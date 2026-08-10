#!/usr/bin/env python3
"""STM32 UART Bootloader Flasher.

GUI tool for programming STM32 devices through the factory ROM bootloader
using the USART protocol described in ST application note AN3155.

Supported firmware formats:
- .bin: uses the start address entered in the GUI
- .hex: addresses are taken from the Intel HEX file
- .elf: flash load addresses are taken from PT_LOAD segments

The default configuration is suitable for STM32F405 through USART3:
USB-UART TX -> PC11, USB-UART RX -> PC10, common GND, BOOT0=1, reset.

Version 1.9 keeps the robust flash flow and adds automatic UART batch capture,
operator-selected log filenames, and nonlinear result analysis:
- configurable 32/64/128/256-byte TX blocks (default 128),
- automatic retries after NACK/timeouts,
- adaptive split to smaller blocks if a frame repeatedly fails,
- short inter-frame settling delays,
- optional immediate read-back of every written block.
On boards where USB-UART DTR is wired to NRST, opening the bootloader port asserts
DTR and immediately releases it, which resets the MCU while BOOT0=1. The tool then
clears stale application UART bytes, synchronizes once at 8E1, and can flash, verify,
or send GO before reopening the application monitor at 8N1.
"""

from __future__ import annotations

import codecs
import os
import queue
import struct
import sys
import threading
import time
import tkinter as tk
from dataclasses import dataclass
from pathlib import Path
from tkinter import filedialog, messagebox, simpledialog, ttk
from typing import Callable, Iterable, Optional

import serial
from serial.tools import list_ports

from auto_log_analysis import (
    AnalysisOutcome,
    BatchLogRecorder,
    CompletedCapture,
    analyze_saved_log,
    save_capture,
    suggested_capture_filename,
)

try:
    from intelhex import IntelHex
except ImportError:  # handled when a HEX file is selected
    IntelHex = None  # type: ignore[assignment]

try:
    from elftools.elf.elffile import ELFFile
except ImportError:  # handled when an ELF file is selected
    ELFFile = None  # type: ignore[assignment]


APP_NAME = "STM32 UART Flasher"
APP_VERSION = "1.10.0"
DEFAULT_FLASH_ADDRESS = 0x08000000
DEFAULT_APPLICATION_BAUD = 921600
DEFAULT_WRITE_BLOCK_SIZE = 128
DEFAULT_WRITE_RETRIES = 10
DEFAULT_INTER_FRAME_DELAY = 0.008
MIN_ADAPTIVE_BLOCK_SIZE = 32
APPLICATION_RX_BUFFER_BYTES = 1024 * 1024
APPLICATION_READ_CHUNK_BYTES = 64 * 1024
SERIAL_UI_PUMP_INTERVAL_MS = 40
SERIAL_UI_MAX_BYTES_PER_PUMP = 512 * 1024


def default_log_directory() -> Path:
    """Return a writable, predictable log folder in source and packaged modes."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent / "captured-logs"
    return Path(__file__).resolve().parent.parent / "captured-logs"

# Danh sách baud phổ biến của pyserial cộng thêm các baud thường gặp trên
# USB-UART/Windows. Combobox vẫn cho phép nhập thủ công nên ứng dụng không bị
# giới hạn bởi danh sách này. Khả năng mở một baud cụ thể phụ thuộc driver và
# phần cứng USB-UART đang sử dụng.
FULL_BAUD_RATES = tuple(
    str(value)
    for value in sorted(
        set(getattr(serial.SerialBase, "BAUDRATES", ()))
        | {
            14400, 28800, 56000, 76800, 128000, 153600, 250000, 256000,
            512000, 768000, 1200000, 1250000, 1333333, 1600000,
            1843200, 2250000, 2750000, 3250000, 3750000,
        }
    )
)


class BootloaderError(RuntimeError):
    """Raised when the STM32 ROM bootloader rejects or times out."""


class CancelledError(RuntimeError):
    """Raised when the user cancels an operation."""


@dataclass(frozen=True)
class FirmwareSegment:
    address: int
    data: bytes

    @property
    def end_address(self) -> int:
        return self.address + len(self.data)


@dataclass(frozen=True)
class FirmwareImage:
    path: Path
    segments: tuple[FirmwareSegment, ...]

    @property
    def total_size(self) -> int:
        return sum(len(segment.data) for segment in self.segments)

    @property
    def first_address(self) -> int:
        return min(segment.address for segment in self.segments)

    @property
    def last_address(self) -> int:
        return max(segment.end_address for segment in self.segments)


@dataclass(frozen=True)
class BootloaderInfo:
    version: int
    commands: frozenset[int]
    chip_id: int

    @property
    def version_text(self) -> str:
        return f"{self.version >> 4}.{self.version & 0x0F}"


class STM32Bootloader:
    ACK = 0x79
    NACK = 0x1F
    SYNC = 0x7F

    CMD_GET = 0x00
    CMD_GET_ID = 0x02
    CMD_READ_MEMORY = 0x11
    CMD_GO = 0x21
    CMD_WRITE_MEMORY = 0x31
    CMD_ERASE = 0x43
    CMD_EXTENDED_ERASE = 0x44

    def __init__(
        self,
        port: serial.Serial,
        log: Callable[[str], None],
        cancel_event: threading.Event,
    ) -> None:
        self.port = port
        self.log = log
        self.cancel_event = cancel_event
        self.info: Optional[BootloaderInfo] = None
        self.inter_frame_delay = DEFAULT_INTER_FRAME_DELAY
        # Diagnostic data captured during the latest synchronization attempt.
        # These fields help distinguish ROM-bootloader ACK traffic from an
        # already-running application or another device driving the UART.
        self.sync_invalid_bytes = bytearray()
        self.sync_unsolicited_bytes = bytearray()
        self.sync_received_ack = False

    def _check_cancelled(self) -> None:
        if self.cancel_event.is_set():
            raise CancelledError("Thao tác đã bị hủy.")

    def _write(self, payload: bytes) -> None:
        self._check_cancelled()
        if not self.port.is_open:
            raise BootloaderError(
                "Cổng COM đã đóng. Đưa BOOT0=1, reset STM32 rồi kết nối lại."
            )
        try:
            # Serial.write() on Windows already waits until the USB-UART driver
            # accepts the bytes. Calling flush()/FlushFileBuffers after every tiny
            # frame causes WinError 22 on some CH340/CP210x driver versions, so it
            # is intentionally not used here.
            written = self.port.write(payload)
        except (serial.SerialException, OSError) as exc:
            raise BootloaderError(
                "Windows mất quyền ghi vào cổng COM/USB-UART. Hãy đóng mọi Serial "
                "Monitor, rút-cắm lại USB-UART, chọn lại COM, giữ BOOT0=1, reset "
                "STM32 và kết nối lại. Chi tiết: " + str(exc)
            ) from exc
        if written != len(payload):
            raise BootloaderError(
                f"Chỉ gửi được {written}/{len(payload)} byte qua UART."
            )

    def _read_exact(self, size: int, timeout: Optional[float] = None) -> bytes:
        self._check_cancelled()
        old_timeout = self.port.timeout
        if timeout is not None:
            self.port.timeout = timeout
        try:
            data = self.port.read(size)
        finally:
            self.port.timeout = old_timeout
        if len(data) != size:
            raise BootloaderError(
                f"UART timeout: cần {size} byte nhưng chỉ nhận {len(data)} byte."
            )
        return data

    def _expect_ack(self, stage: str, timeout: Optional[float] = None) -> None:
        response = self._read_exact(1, timeout=timeout)[0]
        if response == self.ACK:
            return
        if response == self.NACK:
            raise BootloaderError(f"STM32 trả về NACK tại bước: {stage}.")
        raise BootloaderError(
            f"Phản hồi không hợp lệ 0x{response:02X} tại bước: {stage}."
        )

    @staticmethod
    def _xor_checksum(payload: Iterable[int]) -> int:
        checksum = 0
        for value in payload:
            checksum ^= value
        return checksum & 0xFF

    def _collect_rx_window(self, duration: float, max_bytes: int = 256) -> bytes:
        """Collect bytes for a short window without blocking for the full port timeout."""
        old_timeout = self.port.timeout
        deadline = time.monotonic() + max(0.0, duration)
        data = bytearray()
        try:
            self.port.timeout = 0.02
            while time.monotonic() < deadline and len(data) < max_bytes:
                self._check_cancelled()
                waiting = self.port.in_waiting
                chunk = self.port.read(min(max(waiting, 1), max_bytes - len(data)))
                if chunk:
                    data.extend(chunk)
                else:
                    time.sleep(0.003)
        finally:
            self.port.timeout = old_timeout
        return bytes(data)

    @staticmethod
    def _hex_preview(data: bytes, limit: int = 24) -> str:
        preview = data[:limit]
        text = " ".join(f"{value:02X}" for value in preview)
        if len(data) > limit:
            text += f" ... (+{len(data) - limit} byte)"
        return text or "<rỗng>"

    def synchronize(self, attempts: int = 12, interval: float = 0.7) -> None:
        """Synchronize with the ROM bootloader and tolerate stale UART traffic.

        Unlike the previous implementation, this routine does not assume the
        first received byte is the bootloader response. It scans a short receive
        window for ACK 0x79. This matters when PC10 still contains application
        log bytes just before reset or when another device shares the UART.
        """
        self.log(
            "Đang đồng bộ bằng 0x7F. Giữ BOOT0=1, BOOT1=0 và nhấn RESET "
            "ngay khi thấy thông báo này..."
        )
        self.sync_invalid_bytes.clear()
        self.sync_unsolicited_bytes.clear()
        self.sync_received_ack = False

        self.port.reset_output_buffer()
        time.sleep(0.08)

        last_response: Optional[int] = None
        for attempt in range(1, attempts + 1):
            self._check_cancelled()

            # Capture any byte that arrives before SYNC. A silent RX line is
            # expected while the ROM bootloader waits for 0x7F. Continuous data
            # strongly suggests the user application is already running.
            pre_rx = self._collect_rx_window(0.055, max_bytes=64)
            if pre_rx:
                self.sync_unsolicited_bytes.extend(pre_rx)
                if self.ACK in pre_rx:
                    self.sync_received_ack = True
                    self.log(
                        f"Đồng bộ thành công ở lần thử {attempt}; nhận ACK 0x79 "
                        "đến trễ từ lần thử trước."
                    )
                    return

            self._write(bytes([self.SYNC]))
            response = self._collect_rx_window(0.32, max_bytes=128)

            if self.ACK in response:
                self.sync_received_ack = True
                ack_index = response.index(self.ACK)
                leading = response[:ack_index]
                if leading:
                    self.sync_invalid_bytes.extend(leading)
                    self.log(
                        "Đã bỏ qua dữ liệu tồn trước ACK: "
                        + self._hex_preview(leading)
                    )
                self.log(f"Đồng bộ thành công ở lần thử {attempt}; nhận ACK 0x79.")
                return

            if response:
                last_response = response[-1]
                if self.NACK in response:
                    self.log(
                        f"Lần thử {attempt}: nhận NACK 0x1F trong chuỗi "
                        f"[{self._hex_preview(response)}]. Nhấn RESET lại để ROM "
                        "bootloader quay về trạng thái chờ SYNC."
                    )
                else:
                    self.sync_invalid_bytes.extend(response)
                    self.log(
                        f"Lần thử {attempt}: nhận dữ liệu không phải ACK "
                        f"[{self._hex_preview(response)}]. Tool vẫn tiếp tục tìm 0x79."
                    )
            else:
                self.log(
                    f"Lần thử {attempt}/{attempts}: chưa nhận ACK. "
                    "Kiểm tra BOOT0/RESET, USB-UART TX→PC11, RX←PC10 và GND chung."
                )

            if attempt < attempts:
                time.sleep(interval)

        detail = (
            f" Phản hồi cuối: 0x{last_response:02X}."
            if last_response is not None
            else " Không nhận được byte nào từ STM32."
        )
        if self.sync_unsolicited_bytes or self.sync_invalid_bytes:
            sample = bytes(self.sync_unsolicited_bytes + self.sync_invalid_bytes)
            raise BootloaderError(
                "Không nhận được ACK bootloader 0x79." + detail
                + " Đường RX có dữ liệu khác: [" + self._hex_preview(sample) + "]. "
                "Khả năng cao MCU đang chạy firmware ở UART APP 8N1, BOOT0 chưa "
                "được chốt mức 1 tại cạnh RESET, hoặc thiết bị khác đang phát trên "
                "PC10. Hãy thử nút MỞ UART APP; nếu cần gửi GO thì reset lại với "
                "BOOT0=1 rồi kết nối bootloader."
            )
        raise BootloaderError(
            "Không đồng bộ được bootloader sau nhiều lần thử." + detail
            + " Hãy thử STM32CubeProgrammer UART để phân biệt lỗi phần cứng và lỗi ứng dụng."
        )

    def synchronize_clean(self, timeout: float = 2.0) -> None:
        """Legacy v1 synchronization after a DTR-generated reset.

        The original v1 cleared both UART buffers immediately before sending the
        single 0x7F synchronization byte. This is important on this board because
        the application continuously emits 921600-8N1 log data on PC10. After a
        successful DTR reset with BOOT0=1, those stale bytes must be discarded so
        they cannot be mistaken for a ROM-bootloader response.
        """
        self.log(
            "AUTO RESET kiểu v1 đã được thực hiện; xóa dữ liệu UART cũ và "
            "gửi một byte SYNC 0x7F..."
        )
        self.sync_invalid_bytes.clear()
        self.sync_unsolicited_bytes.clear()
        self.sync_received_ack = False
        self.port.reset_input_buffer()
        self.port.reset_output_buffer()
        time.sleep(0.06)
        self._write(bytes([self.SYNC]))
        self._expect_ack("đồng bộ bootloader sau auto reset", timeout=timeout)
        self.sync_received_ack = True
        self.log("Đồng bộ bootloader thành công: ACK 0x79.")

    def _send_command(self, command: int, stage: str) -> None:
        self._write(bytes([command, command ^ 0xFF]))
        self._expect_ack(stage)
        if self.inter_frame_delay > 0:
            time.sleep(self.inter_frame_delay)

    def get_info(self) -> BootloaderInfo:
        self._send_command(self.CMD_GET, "GET command")
        count_minus_one = self._read_exact(1)[0]
        payload = self._read_exact(count_minus_one + 1)
        self._expect_ack("kết thúc GET command")
        if not payload:
            raise BootloaderError("GET command không trả về dữ liệu.")

        version = payload[0]
        commands = frozenset(payload[1:])

        self._send_command(self.CMD_GET_ID, "GET ID command")
        id_count_minus_one = self._read_exact(1)[0]
        chip_id_bytes = self._read_exact(id_count_minus_one + 1)
        self._expect_ack("kết thúc GET ID command")
        chip_id = int.from_bytes(chip_id_bytes, byteorder="big", signed=False)

        info = BootloaderInfo(version=version, commands=commands, chip_id=chip_id)
        self.info = info
        self.log(
            f"Bootloader v{info.version_text}, Chip ID: 0x{info.chip_id:X}, "
            f"lệnh hỗ trợ: {', '.join(f'0x{x:02X}' for x in sorted(commands))}"
        )
        return info

    def _require_command(self, command: int, name: str) -> None:
        if self.info is not None and command not in self.info.commands:
            raise BootloaderError(f"Bootloader không hỗ trợ lệnh {name} (0x{command:02X}).")

    def _send_address(self, address: int, stage: str) -> None:
        address_bytes = struct.pack(">I", address)
        packet = address_bytes + bytes([self._xor_checksum(address_bytes)])
        self._write(packet)
        self._expect_ack(stage)
        if self.inter_frame_delay > 0:
            time.sleep(self.inter_frame_delay)

    def read_memory(self, address: int, length: int) -> bytes:
        if not 1 <= length <= 256:
            raise ValueError("Read Memory chỉ hỗ trợ từ 1 đến 256 byte.")
        self._require_command(self.CMD_READ_MEMORY, "Read Memory")
        self._send_command(self.CMD_READ_MEMORY, "Read Memory command")
        self._send_address(address, "địa chỉ Read Memory")
        n = length - 1
        self._write(bytes([n, n ^ 0xFF]))
        self._expect_ack("độ dài Read Memory")
        data = self._read_exact(length, timeout=3.0)
        if self.inter_frame_delay > 0:
            time.sleep(self.inter_frame_delay)
        return data

    def write_memory(self, address: int, data: bytes) -> None:
        if not 1 <= len(data) <= 256:
            raise ValueError("Write Memory chỉ hỗ trợ từ 1 đến 256 byte.")
        if len(data) % 4 != 0:
            raise ValueError("Kích thước Write Memory phải là bội số của 4.")
        if address % 4 != 0:
            raise ValueError("Địa chỉ ghi phải căn chỉnh 4 byte.")

        self._require_command(self.CMD_WRITE_MEMORY, "Write Memory")
        self._send_command(self.CMD_WRITE_MEMORY, "Write Memory command")
        self._send_address(address, "địa chỉ Write Memory")

        n = len(data) - 1
        checksum = self._xor_checksum(bytes([n]) + data)
        self._write(bytes([n]) + data + bytes([checksum]))
        self._expect_ack(f"ghi dữ liệu tại 0x{address:08X}", timeout=5.0)
        if self.inter_frame_delay > 0:
            time.sleep(self.inter_frame_delay)

    def write_memory_robust(
        self,
        address: int,
        data: bytes,
        retries: int = DEFAULT_WRITE_RETRIES,
        verify_immediately: bool = True,
        min_block_size: int = MIN_ADAPTIVE_BLOCK_SIZE,
    ) -> None:
        """Write one block with retry and adaptive frame splitting.

        A NACK at varying addresses normally indicates a transient UART frame
        error rather than a fixed flash-address problem. The ROM bootloader
        aborts the failed Write Memory command and returns to command-wait
        state, so the same block can safely be sent again. If repeated retries
        fail, the block is split into two aligned halves and each half is
        programmed separately.
        """
        if retries < 1:
            raise ValueError("Số lần retry phải >= 1.")

        last_error: Optional[Exception] = None
        for attempt in range(1, retries + 1):
            self._check_cancelled()
            try:
                # Remove any delayed ACK/NACK left by the previous failed frame.
                self.port.reset_input_buffer()
                if attempt > 1:
                    time.sleep(min(0.25, 0.025 * attempt))

                self.write_memory(address, data)

                if verify_immediately:
                    actual = self.read_memory(address, len(data))
                    if actual != data:
                        mismatch = next(
                            (
                                index
                                for index, (expected, received) in enumerate(zip(data, actual))
                                if expected != received
                            ),
                            0,
                        )
                        raise BootloaderError(
                            f"Đọc lại sai tại 0x{address + mismatch:08X}: "
                            f"ghi=0x{data[mismatch]:02X}, đọc=0x{actual[mismatch]:02X}."
                        )
                return
            except CancelledError:
                raise
            except (BootloaderError, serial.SerialException, OSError) as exc:
                last_error = exc
                self.log(
                    f"Ghi block 0x{address:08X}, {len(data)} byte thất bại "
                    f"lần {attempt}/{retries}: {exc}"
                )
                # A NACK aborts the command. Give the ROM bootloader and USB-UART
                # driver a short recovery window before repeating the full frame.
                try:
                    self.port.reset_input_buffer()
                except Exception:
                    pass

        if len(data) > min_block_size:
            half = max(min_block_size, (len(data) // 2) & ~0x03)
            if half >= len(data):
                half = len(data) - 4
            left = data[:half]
            right = data[half:]
            self.log(
                f"Block {len(data)} byte tại 0x{address:08X} vẫn lỗi sau "
                f"{retries} lần; tự chia thành {len(left)} + {len(right)} byte."
            )
            self.write_memory_robust(
                address,
                left,
                retries=retries,
                verify_immediately=verify_immediately,
                min_block_size=min_block_size,
            )
            self.write_memory_robust(
                address + len(left),
                right,
                retries=retries,
                verify_immediately=verify_immediately,
                min_block_size=min_block_size,
            )
            return

        raise BootloaderError(
            f"Không thể ghi block tại 0x{address:08X} sau {retries} lần. "
            f"Lỗi cuối: {last_error}"
        )

    def mass_erase(self) -> None:
        if self.info is None:
            raise BootloaderError("Chưa đọc thông tin bootloader.")

        self.log("Đang xóa toàn bộ Flash...")
        # Prefer the legacy global erase command when the ROM reports it. It is
        # the shortest valid frame (0x43/0xBC, then 0xFF/0x00) and is reliable
        # on STM32F405 bootloader revisions. Fall back to Extended Erase.
        if self.CMD_ERASE in self.info.commands:
            self.log("Gửi Erase command 0x43/0xBC...")
            self._send_command(self.CMD_ERASE, "Erase command")
            self.log("Gửi global erase 0xFF/0x00...")
            self._write(b"\xFF\x00")
            self._expect_ack("Mass Erase", timeout=45.0)
        elif self.CMD_EXTENDED_ERASE in self.info.commands:
            self.log("Gửi Extended Erase command 0x44/0xBB...")
            self._send_command(self.CMD_EXTENDED_ERASE, "Extended Erase command")
            self.log("Gửi extended global erase 0xFFFF/0x00...")
            # 0xFFFF requests global mass erase; XOR checksum of FF and FF is 00.
            self._write(b"\xFF\xFF\x00")
            self._expect_ack("Extended Mass Erase", timeout=45.0)
        else:
            raise BootloaderError("Bootloader không hỗ trợ lệnh xóa Flash.")
        self.log("Xóa Flash thành công.")

    def go(self, address: int) -> None:
        self._require_command(self.CMD_GO, "Go")
        self.log(f"Yêu cầu STM32 chạy ứng dụng tại 0x{address:08X}...")
        self._send_command(self.CMD_GO, "Go command")
        self._send_address(address, "địa chỉ Go")
        self.log("STM32 đã nhận lệnh Go.")


class FirmwareLoader:
    @staticmethod
    def load(path: str, binary_base_address: int) -> FirmwareImage:
        firmware_path = Path(path)
        if not firmware_path.is_file():
            raise FileNotFoundError(f"Không tìm thấy firmware: {firmware_path}")

        suffix = firmware_path.suffix.lower()
        if suffix == ".bin":
            data = firmware_path.read_bytes()
            if not data:
                raise ValueError("File BIN rỗng.")
            segments = [FirmwareSegment(binary_base_address, data)]
        elif suffix in {".hex", ".ihex"}:
            segments = FirmwareLoader._load_hex(firmware_path)
        elif suffix in {".elf", ".axf"}:
            segments = FirmwareLoader._load_elf(firmware_path)
        else:
            raise ValueError("Chỉ hỗ trợ file .bin, .hex, .ihex, .elf hoặc .axf.")

        merged = FirmwareLoader._merge_segments(segments)
        FirmwareLoader._validate_segments(merged)
        return FirmwareImage(path=firmware_path, segments=tuple(merged))

    @staticmethod
    def _load_hex(path: Path) -> list[FirmwareSegment]:
        if IntelHex is None:
            raise RuntimeError(
                "Thiếu thư viện intelhex. Chạy: pip install -r requirements.txt"
            )
        image = IntelHex(str(path))
        segments: list[FirmwareSegment] = []
        for start, end in image.segments():
            data = bytes(image.tobinarray(start=start, end=end - 1))
            if data:
                segments.append(FirmwareSegment(start, data))
        if not segments:
            raise ValueError("File HEX không có dữ liệu.")
        return segments

    @staticmethod
    def _load_elf(path: Path) -> list[FirmwareSegment]:
        if ELFFile is None:
            raise RuntimeError(
                "Thiếu thư viện pyelftools. Chạy: pip install -r requirements.txt"
            )
        segments: list[FirmwareSegment] = []
        with path.open("rb") as stream:
            elf = ELFFile(stream)
            for segment in elf.iter_segments():
                if segment["p_type"] != "PT_LOAD" or segment["p_filesz"] == 0:
                    continue
                paddr = int(segment["p_paddr"])
                vaddr = int(segment["p_vaddr"])
                address = paddr if 0x08000000 <= paddr < 0x10000000 else vaddr
                if not 0x08000000 <= address < 0x10000000:
                    continue
                data = bytes(segment.data()[: int(segment["p_filesz"])])
                if data:
                    segments.append(FirmwareSegment(address, data))
        if not segments:
            raise ValueError("Không tìm thấy PT_LOAD segment thuộc vùng Flash trong ELF.")
        return segments

    @staticmethod
    def _merge_segments(segments: list[FirmwareSegment]) -> list[FirmwareSegment]:
        ordered = sorted(segments, key=lambda item: item.address)
        if not ordered:
            return []
        result: list[FirmwareSegment] = [ordered[0]]
        for current in ordered[1:]:
            previous = result[-1]
            if current.address < previous.end_address:
                raise ValueError(
                    f"Firmware có segment chồng lấn tại 0x{current.address:08X}."
                )
            if current.address == previous.end_address:
                result[-1] = FirmwareSegment(
                    previous.address, previous.data + current.data
                )
            else:
                result.append(current)
        return result

    @staticmethod
    def _validate_segments(segments: list[FirmwareSegment]) -> None:
        if not segments:
            raise ValueError("Firmware không có dữ liệu để ghi.")
        for segment in segments:
            if segment.address % 4 != 0:
                raise ValueError(
                    f"Segment tại 0x{segment.address:08X} không căn chỉnh 4 byte."
                )
            if segment.address < 0x08000000:
                raise ValueError(
                    f"Địa chỉ 0x{segment.address:08X} không thuộc vùng Flash STM32 thông thường."
                )


class LiveNlPlot(ttk.Frame):
    """Dependency-free line chart of ErrorDeg vs point Index for one NL sweep.

    Redrawn live as DATA lines stream in from the UART app monitor (see
    FlasherApp._feed_plot_line). Pure tk.Canvas -- no matplotlib -- to keep
    the PyInstaller build (STM32_UART_Flasher.spec) light and avoid a new
    packaging dependency for a single chart.
    """

    _MARGIN_LEFT = 46
    _MARGIN_RIGHT = 12
    _MARGIN_TOP = 14
    _MARGIN_BOTTOM = 26
    _Y_MIN = -3.0
    _Y_MAX = 3.0
    _Y_GRID_STEP = 0.5
    _N_POINTS = 360  # 1 deg/point, matches GRID,NominalStepDeg=1.00000 in every log so far.

    def __init__(self, master: tk.Widget) -> None:
        super().__init__(master)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(1, weight=1)

        self.title_var = tk.StringVar(
            value="Chưa có dữ liệu — mở UART app và chạy test để xem đường ErrorDeg theo góc quay."
        )
        ttk.Label(self, textvariable=self.title_var).grid(
            row=0, column=0, sticky="w", pady=(4, 4)
        )

        self.canvas = tk.Canvas(
            self, background="white", highlightthickness=1, highlightbackground="#c0c0c0"
        )
        self.canvas.grid(row=1, column=0, sticky="nsew")
        self.canvas.bind("<Configure>", lambda _evt: self._redraw())

        self._points: list[tuple[int, float]] = []

    def reset(self) -> None:
        """Start a new sweep trace (called on DATA,...,Index=0)."""
        self._points = []
        self.title_var.set("Sweep mới đang chạy...")
        self._redraw()

    def add_point(self, index: int, error_deg: float) -> None:
        self.add_points([(index, error_deg)])

    def add_points(self, points: list[tuple[int, float]]) -> None:
        """Append a UART burst and redraw once, not once per DATA record."""
        if not points:
            return
        for index, error_deg in points:
            if index == 0:
                self._points = []
            self._points.append((index, error_deg))
        index, error_deg = points[-1]
        self.title_var.set(
            f"Điểm {index + 1}/{self._N_POINTS}  ·  ErrorDeg={error_deg:+.3f}°"
        )
        self._redraw()

    def _x(self, index: int, width: int) -> float:
        plot_w = width - self._MARGIN_LEFT - self._MARGIN_RIGHT
        return self._MARGIN_LEFT + (index / max(self._N_POINTS - 1, 1)) * plot_w

    def _y(self, value: float, height: int) -> float:
        plot_h = height - self._MARGIN_TOP - self._MARGIN_BOTTOM
        clamped = max(self._Y_MIN, min(self._Y_MAX, value))
        frac = (clamped - self._Y_MIN) / (self._Y_MAX - self._Y_MIN)
        return self._MARGIN_TOP + (1 - frac) * plot_h

    def _redraw(self) -> None:
        c = self.canvas
        c.delete("all")
        width = c.winfo_width()
        height = c.winfo_height()
        if width < 10 or height < 10:
            return

        y = self._Y_MIN
        while y <= self._Y_MAX + 1e-9:
            yp = self._y(y, height)
            c.create_line(
                self._MARGIN_LEFT, yp, width - self._MARGIN_RIGHT, yp, fill="#e8e8e8"
            )
            c.create_text(
                self._MARGIN_LEFT - 6, yp, text=f"{y:+.1f}°", anchor="e",
                font=("Consolas", 8), fill="#808080",
            )
            y += self._Y_GRID_STEP

        zero_y = self._y(0.0, height)
        c.create_line(
            self._MARGIN_LEFT, zero_y, width - self._MARGIN_RIGHT, zero_y, fill="#a0a0a0"
        )

        for tick in range(0, self._N_POINTS + 1, 45):
            xp = self._x(min(tick, self._N_POINTS - 1), width)
            c.create_line(xp, self._MARGIN_TOP, xp, height - self._MARGIN_BOTTOM, fill="#f2f2f2")
            c.create_text(
                xp, height - self._MARGIN_BOTTOM + 12, text=f"{tick}°", anchor="n",
                font=("Consolas", 8), fill="#808080",
            )

        c.create_rectangle(
            self._MARGIN_LEFT, self._MARGIN_TOP, width - self._MARGIN_RIGHT,
            height - self._MARGIN_BOTTOM, outline="#c0c0c0",
        )

        if len(self._points) >= 2:
            coords: list[float] = []
            for index, error_deg in self._points:
                coords.append(self._x(index, width))
                coords.append(self._y(error_deg, height))
            c.create_line(*coords, fill="#2a78d6", width=2, joinstyle="round", capstyle="round")

        if self._points:
            last_index, last_error = self._points[-1]
            xp = self._x(last_index, width)
            yp = self._y(last_error, height)
            r = 4
            c.create_oval(xp - r, yp - r, xp + r, yp + r, fill="#eb6834", outline="")


class FlasherApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(f"{APP_NAME} v{APP_VERSION}")
        self.geometry("1120x760")
        self.minsize(980, 660)

        # ROM bootloader connection (8E1).
        self.serial_port: Optional[serial.Serial] = None
        self.bootloader: Optional[STM32Bootloader] = None
        self.bootloader_info: Optional[BootloaderInfo] = None

        # Application UART monitor connection (8N1).
        self.app_serial: Optional[serial.Serial] = None
        self.app_monitor_stop_event = threading.Event()
        self.app_monitor_thread: Optional[threading.Thread] = None
        self.log_recorder = BatchLogRecorder()
        self._plot_pending = ""  # separate line buffer feeding LiveNlPlot only
        # Never make the high-rate UART reader wait for Tk. At 921600 baud,
        # one Tk callback and one canvas redraw per chunk/point can starve the
        # reader long enough to overflow the Windows COM receive buffer.
        self._serial_ui_queue: queue.SimpleQueue[tuple[int, str, object]] = queue.SimpleQueue()
        self._serial_ui_decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
        self._serial_ui_epoch = 0
        self._closing = False

        self.cancel_event = threading.Event()
        self.worker: Optional[threading.Thread] = None
        self.is_busy = False

        self.port_var = tk.StringVar()
        self.baud_var = tk.StringVar(value="115200")
        self.app_baud_var = tk.StringVar(value=str(DEFAULT_APPLICATION_BAUD))
        self.file_var = tk.StringVar()
        self.address_var = tk.StringVar(value="0x08000000")
        self.go_address_var = tk.StringVar(value="0x08000000")
        self.verify_var = tk.BooleanVar(value=True)
        self.verify_each_block_var = tk.BooleanVar(value=True)
        self.write_block_size_var = tk.StringVar(value=str(DEFAULT_WRITE_BLOCK_SIZE))
        self.write_retries_var = tk.StringVar(value=str(DEFAULT_WRITE_RETRIES))
        self.run_var = tk.BooleanVar(value=False)
        self.auto_monitor_var = tk.BooleanVar(value=True)
        self.dtr_reset_var = tk.BooleanVar(value=True)
        self.auto_save_log_var = tk.BooleanVar(value=True)
        self.auto_analyze_log_var = tk.BooleanVar(value=True)
        self.ask_log_filename_var = tk.BooleanVar(value=True)
        self.log_directory_var = tk.StringVar(value=str(default_log_directory()))
        self.status_var = tk.StringVar(value="Chưa kết nối")
        self.progress_var = tk.DoubleVar(value=0.0)

        self._build_ui()
        self.refresh_ports()
        self.protocol("WM_DELETE_WINDOW", self.on_close)
        self.after(SERIAL_UI_PUMP_INTERVAL_MS, self._drain_serial_ui_queue)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(7, weight=1)

        title = ttk.Label(root, text=APP_NAME, font=("Segoe UI", 16, "bold"))
        title.grid(row=0, column=0, columnspan=5, sticky="w", pady=(0, 10))

        ttk.Label(root, text="Cổng COM:").grid(row=1, column=0, sticky="w", pady=4)
        self.port_combo = ttk.Combobox(root, textvariable=self.port_var, state="readonly")
        self.port_combo.grid(row=1, column=1, sticky="ew", padx=(8, 8), pady=4)
        ttk.Button(root, text="Làm mới", command=self.refresh_ports).grid(
            row=1, column=2, sticky="ew", pady=4
        )
        self.connect_button = ttk.Button(root, text="Kết nối BL", command=self.toggle_connection)
        self.connect_button.grid(row=1, column=3, sticky="ew", padx=(8, 0), pady=4)
        self.run_button = ttk.Button(
            root,
            text="RECONNECT / RUN APP",
            command=self.start_go_application,
        )
        self.run_button.grid(row=1, column=4, sticky="ew", padx=(8, 0), pady=4)

        ttk.Label(root, text="Baud bootloader:").grid(row=2, column=0, sticky="w", pady=4)
        self.baud_combo = ttk.Combobox(
            root,
            textvariable=self.baud_var,
            values=FULL_BAUD_RATES,
            state="normal",
            width=14,
        )
        self.baud_combo.grid(row=2, column=1, sticky="w", padx=(8, 8), pady=4)
        ttk.Label(root, text="8E1 — ROM BL: tối đa 115200").grid(
            row=2, column=2, sticky="w", pady=4
        )
        ttk.Label(root, text="Địa chỉ GO:").grid(row=2, column=3, sticky="e", pady=4)
        ttk.Entry(root, textvariable=self.go_address_var, width=16).grid(
            row=2, column=4, sticky="ew", padx=(8, 0), pady=4
        )

        ttk.Label(root, text="Baud UART app:").grid(row=3, column=0, sticky="w", pady=4)
        self.app_baud_combo = ttk.Combobox(
            root,
            textvariable=self.app_baud_var,
            values=FULL_BAUD_RATES,
            state="normal",
            width=14,
        )
        self.app_baud_combo.grid(row=3, column=1, sticky="w", padx=(8, 8), pady=4)
        ttk.Label(root, text="8N1 — firmware hiện tại: 921600").grid(
            row=3, column=2, sticky="w", pady=4
        )
        ttk.Checkbutton(
            root,
            text="Mở monitor sau GO",
            variable=self.auto_monitor_var,
        ).grid(row=3, column=3, sticky="e", pady=4)
        ttk.Checkbutton(
            root,
            text="Auto reset kiểu v1 bằng DTR (DTR→NRST)",
            variable=self.dtr_reset_var,
        ).grid(row=3, column=4, sticky="w", padx=(8, 0), pady=4)

        ttk.Separator(root).grid(row=4, column=0, columnspan=5, sticky="ew", pady=10)

        ttk.Label(root, text="Firmware:").grid(row=5, column=0, sticky="w", pady=4)
        ttk.Entry(root, textvariable=self.file_var).grid(
            row=5, column=1, columnspan=3, sticky="ew", padx=(8, 8), pady=4
        )
        ttk.Button(root, text="Chọn file", command=self.select_firmware).grid(
            row=5, column=4, sticky="ew", pady=4
        )

        options = ttk.Frame(root)
        options.grid(row=6, column=0, columnspan=5, sticky="ew", pady=(4, 10))
        options.columnconfigure(1, weight=1)
        ttk.Label(options, text="Địa chỉ BIN:").grid(row=0, column=0, sticky="w")
        ttk.Entry(options, textvariable=self.address_var, width=18).grid(
            row=0, column=1, sticky="w", padx=(8, 20)
        )
        ttk.Label(options, text="Block ghi:").grid(row=0, column=2, sticky="e")
        ttk.Combobox(
            options,
            textvariable=self.write_block_size_var,
            values=("32", "64", "128", "256"),
            state="readonly",
            width=6,
        ).grid(row=0, column=3, sticky="w", padx=(8, 16))
        ttk.Label(options, text="Retry/block:").grid(row=0, column=4, sticky="e")
        ttk.Spinbox(
            options,
            from_=1,
            to=20,
            textvariable=self.write_retries_var,
            width=5,
        ).grid(row=0, column=5, sticky="w", padx=(8, 16))
        ttk.Checkbutton(options, text="Verify từng block", variable=self.verify_each_block_var).grid(
            row=0, column=6, sticky="w", padx=(0, 16)
        )
        ttk.Checkbutton(options, text="Verify toàn bộ", variable=self.verify_var).grid(
            row=0, column=7, sticky="w", padx=(0, 16)
        )
        ttk.Checkbutton(
            options,
            text="GO + monitor sau flash",
            variable=self.run_var,
        ).grid(row=0, column=8, sticky="w")

        ttk.Checkbutton(
            options,
            text="Tự lưu log khi test xong",
            variable=self.auto_save_log_var,
        ).grid(row=1, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Checkbutton(
            options,
            text="Tự phân tích",
            variable=self.auto_analyze_log_var,
        ).grid(row=1, column=2, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Label(options, text="Thư mục log:").grid(
            row=1, column=4, sticky="e", pady=(8, 0)
        )
        options.columnconfigure(5, weight=1)
        ttk.Entry(options, textvariable=self.log_directory_var).grid(
            row=1, column=5, columnspan=3, sticky="ew", padx=(8, 8), pady=(8, 0)
        )
        ttk.Button(options, text="Chọn thư mục", command=self.select_log_directory).grid(
            row=1, column=8, sticky="ew", pady=(8, 0)
        )
        ttk.Checkbutton(
            options,
            text="Hỏi tên file trước khi lưu",
            variable=self.ask_log_filename_var,
        ).grid(row=2, column=0, columnspan=4, sticky="w", pady=(6, 0))

        view_notebook = ttk.Notebook(root)
        view_notebook.grid(row=7, column=0, columnspan=5, sticky="nsew")

        log_frame = ttk.Frame(view_notebook)
        view_notebook.add(log_frame, text="Nhật ký bootloader / UART app")
        log_frame.columnconfigure(0, weight=1)
        log_frame.rowconfigure(0, weight=1)
        self.log_text = tk.Text(log_frame, wrap="word", state="disabled", font=("Consolas", 10))
        self.log_text.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(log_frame, command=self.log_text.yview)
        scrollbar.grid(row=0, column=1, sticky="ns")
        self.log_text.configure(yscrollcommand=scrollbar.set)

        plot_tab = ttk.Frame(view_notebook, padding=(8, 4))
        view_notebook.add(plot_tab, text="Đồ thị NL — ErrorDeg(θ)")
        plot_tab.columnconfigure(0, weight=1)
        plot_tab.rowconfigure(0, weight=1)
        self.error_plot = LiveNlPlot(plot_tab)
        self.error_plot.grid(row=0, column=0, sticky="nsew")

        self.progress = ttk.Progressbar(
            root, variable=self.progress_var, maximum=100.0, mode="determinate"
        )
        self.progress.grid(row=8, column=0, columnspan=5, sticky="ew", pady=(10, 4))

        action_frame = ttk.Frame(root)
        action_frame.grid(row=9, column=0, columnspan=5, sticky="ew", pady=(4, 0))
        action_frame.columnconfigure(1, weight=1)
        ttk.Label(action_frame, textvariable=self.status_var).grid(row=0, column=0, sticky="w")
        self.open_monitor_button = ttk.Button(
            action_frame,
            text="MỞ UART APP",
            command=self.start_application_monitor_only,
        )
        self.open_monitor_button.grid(row=0, column=2, padx=(8, 8))
        self.stop_monitor_button = ttk.Button(
            action_frame,
            text="Dừng UART APP",
            command=self.stop_application_monitor,
            state="disabled",
        )
        self.stop_monitor_button.grid(row=0, column=3, padx=(0, 8))
        self.flash_button = ttk.Button(
            action_frame,
            text="FLASH FIRMWARE",
            command=self.start_flash,
            state="disabled",
        )
        self.flash_button.grid(row=0, column=4, padx=(0, 8))
        self.cancel_button = ttk.Button(
            action_frame,
            text="Hủy",
            command=self.cancel_operation,
            state="disabled",
        )
        self.cancel_button.grid(row=0, column=5)

        note = (
            "STM32F405 USART3: USB-UART TX → PC11, RX ← PC10, GND chung. "
            "BOOT0=1: sau mỗi reset, nhấn RECONNECT / RUN APP; tool tự mở 8E1, "
            "đồng bộ, gửi GO tới địa chỉ đã nhập, rồi mở lại COM ở UART app 8N1. "
            "Nếu nhận byte lạ lặp lại như 0x29, thử MỞ UART APP vì firmware có thể "
            "đã chạy và đang phát log. Muốn flash lại khi monitor đang mở, bấm "
            "ĐÓNG APP → KẾT NỐI BL. Mặc định tool dùng cách mở COM kiểu v1 để "
            "tạo reset qua DTR; nếu board không nối DTR→NRST thì bỏ chọn và nhấn "
            "RESET bằng tay khi tool đang chờ đồng bộ. Khi đường UART không ổn định, "
            "dùng Block ghi=128 hoặc 64 và Retry/block=10; tool sẽ tự chia nhỏ block "
            "nếu gặp NACK ngẫu nhiên."
        )
        ttk.Label(root, text=note, wraplength=940).grid(
            row=10, column=0, columnspan=5, sticky="w", pady=(10, 0)
        )

    def log(self, message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")

        def append() -> None:
            self.log_text.configure(state="normal")
            self.log_text.insert("end", f"[{timestamp}] {message}\n")
            self.log_text.see("end")
            self.log_text.configure(state="disabled")

        self.after(0, append)

    def log_serial_data(self, data: bytes, epoch: Optional[int] = None) -> None:
        """Capture UART bytes immediately; defer all Tk work to one UI pump."""
        if epoch is None:
            epoch = self._serial_ui_epoch
        completed_captures = self.log_recorder.feed(data)
        self._serial_ui_queue.put((epoch, "data", data))
        for capture in completed_captures:
            self._serial_ui_queue.put((epoch, "capture", capture))

    def _drain_serial_ui_queue(self) -> None:
        """Coalesce UART text, plot points, and completed batches on Tk's thread."""
        if self._closing:
            return
        text_chunks: list[str] = []
        captures: list[CompletedCapture] = []
        byte_count = 0
        while byte_count < SERIAL_UI_MAX_BYTES_PER_PUMP:
            try:
                epoch, kind, payload = self._serial_ui_queue.get_nowait()
            except queue.Empty:
                break
            if epoch != self._serial_ui_epoch:
                continue
            if kind == "reset":
                self._serial_ui_decoder = codecs.getincrementaldecoder("utf-8")(
                    errors="replace"
                )
                self._plot_pending = ""
                continue
            if kind == "data":
                raw = payload
                assert isinstance(raw, bytes)
                byte_count += len(raw)
                text_chunks.append(self._serial_ui_decoder.decode(raw, final=False))
            elif kind == "capture":
                assert isinstance(payload, CompletedCapture)
                captures.append(payload)

        if text_chunks:
            text = "".join(text_chunks)
            self.log_text.configure(state="normal")
            self.log_text.insert("end", text)
            self.log_text.see("end")
            self.log_text.configure(state="disabled")

            self._plot_pending += text
            plot_points: list[tuple[int, float]] = []
            while "\n" in self._plot_pending:
                raw_line, self._plot_pending = self._plot_pending.split("\n", 1)
                point = self._parse_plot_line(raw_line.rstrip("\r"))
                if point is not None:
                    plot_points.append(point)
            self.error_plot.add_points(plot_points)

        for capture in captures:
            self._handle_completed_capture(capture)
        self.after(SERIAL_UI_PUMP_INTERVAL_MS, self._drain_serial_ui_queue)

    @staticmethod
    def _parse_plot_line(line: str) -> Optional[tuple[int, float]]:
        if not line.startswith("DATA,"):
            return None
        parts = line.split(",")
        if len(parts) != 12:
            return None
        try:
            return int(parts[7]), float(parts[11])
        except ValueError:
            return None

    def _feed_plot_line(self, line: str) -> None:
        """Parse one DATA,... line and push it to the live NL chart.

        Positional fields per point (matches parse_nl_log.m's documented
        DATA convention): index 7=Index, 11=ErrorDeg (0-based here).
        Example: DATA,5,1,1,JIG1,p03,CW,0,5959,5963,32.75574,-0.00797
        """
        point = self._parse_plot_line(line)
        if point is not None:
            self.error_plot.add_points([point])

    def _handle_completed_capture(self, capture: CompletedCapture) -> None:
        """Snapshot Tk options, then save/analyze without blocking the GUI."""
        if not self.auto_save_log_var.get():
            self.log(
                f"Đã phát hiện test {capture.terminal_status} nhưng tự lưu log đang tắt."
            )
            return

        directory_text = self.log_directory_var.get().strip()
        if not directory_text:
            directory_text = str(default_log_directory())
            self.log_directory_var.set(directory_text)
        output_dir = Path(directory_text).expanduser()
        run_analysis = bool(self.auto_analyze_log_var.get())
        requested_filename: Optional[str] = None
        if self.ask_log_filename_var.get() and capture.terminal_status != "INCOMPLETE":
            suggested_name = suggested_capture_filename(capture)
            requested_filename = simpledialog.askstring(
                "Tên file log",
                (
                    "Nhập tên file cho batch vừa hoàn thành.\n"
                    "Có thể nhập có hoặc không có đuôi .txt.\n"
                    "Bấm Cancel để dùng tên tự động."
                ),
                initialvalue=suggested_name,
                parent=self,
            )
            if not requested_filename or not requested_filename.strip():
                requested_filename = suggested_name

        def task() -> None:
            try:
                log_path = save_capture(capture, output_dir, requested_filename)
                self.log(f"AUTO SAVE: {log_path}")
                if not run_analysis:
                    self.set_status(f"ĐÃ LƯU LOG — {log_path.name}")
                    return

                outcome: AnalysisOutcome = analyze_saved_log(
                    log_path,
                    expected_official_runs=capture.expected_official_runs,
                    terminal_status=capture.terminal_status,
                )
                self.log(f"AUTO ANALYSIS: {outcome.summary}")
                self.log(f"Báo cáo: {outcome.report_path}")
                self.set_status(
                    f"PHÂN TÍCH {'PASS' if outcome.passed else 'FAIL'} — {log_path.name}"
                )
            except Exception as exc:
                self.log(f"AUTO SAVE/ANALYSIS THẤT BẠI: {exc}")
                self.set_status("AUTO SAVE/ANALYSIS THẤT BẠI")
                self.after(
                    0,
                    messagebox.showerror,
                    APP_NAME,
                    "Không thể tự lưu hoặc phân tích log:\n\n" + str(exc),
                )

        # Keep the process alive for this short worker so a completed test is
        # not lost if the operator closes the window immediately afterward.
        threading.Thread(target=task, daemon=False).start()

    def _flush_active_log_capture(self, epoch: Optional[int] = None) -> None:
        if epoch is None:
            epoch = self._serial_ui_epoch
        for capture in self.log_recorder.flush_incomplete():
            self._serial_ui_queue.put((epoch, "capture", capture))

    def _take_pending_captures_for_shutdown(self) -> list[CompletedCapture]:
        captures: list[CompletedCapture] = []
        while True:
            try:
                epoch, kind, payload = self._serial_ui_queue.get_nowait()
            except queue.Empty:
                break
            if (
                epoch == self._serial_ui_epoch
                and kind == "capture"
                and isinstance(payload, CompletedCapture)
            ):
                captures.append(payload)
        return captures

    def set_status(self, status: str) -> None:
        self.after(0, self.status_var.set, status)

    def set_progress(self, percent: float) -> None:
        self.after(0, self.progress_var.set, max(0.0, min(100.0, percent)))

    def refresh_ports(self) -> None:
        ports = sorted(list_ports.comports(), key=lambda item: item.device)
        values = [f"{item.device} — {item.description}" for item in ports]
        self.port_combo["values"] = values
        if values and self.port_var.get() not in values:
            self.port_var.set(values[0])
        elif not values:
            self.port_var.set("")

    def select_firmware(self) -> None:
        path = filedialog.askopenfilename(
            title="Chọn firmware STM32",
            filetypes=(
                ("Firmware STM32", "*.bin *.hex *.ihex *.elf *.axf"),
                ("Binary", "*.bin"),
                ("Intel HEX", "*.hex *.ihex"),
                ("ELF", "*.elf *.axf"),
                ("Tất cả file", "*.*"),
            ),
        )
        if path:
            self.file_var.set(path)

    def select_log_directory(self) -> None:
        initial = self.log_directory_var.get().strip() or str(default_log_directory())
        path = filedialog.askdirectory(title="Chọn thư mục lưu log", initialdir=initial)
        if path:
            self.log_directory_var.set(path)

    def _selected_port_name(self) -> str:
        value = self.port_var.get().strip()
        if not value:
            raise ValueError("Chưa chọn cổng COM.")
        return value.split(" — ", 1)[0]

    @staticmethod
    def _parse_address_text(text: str, label: str) -> int:
        try:
            address = int(text.strip(), 0)
        except ValueError as exc:
            raise ValueError(f"{label} không hợp lệ. Ví dụ: 0x08000000") from exc
        if not 0 <= address <= 0xFFFFFFFF:
            raise ValueError(f"{label} nằm ngoài phạm vi 32 bit.")
        return address

    def _parse_address(self) -> int:
        return self._parse_address_text(self.address_var.get(), "Địa chỉ BIN")

    def _parse_go_address(self) -> int:
        return self._parse_address_text(self.go_address_var.get(), "Địa chỉ GO")

    @staticmethod
    def _parse_baudrate_text(text: str, label: str) -> int:
        normalized = text.strip().replace("_", "").replace(",", "")
        if not normalized:
            raise ValueError(f"Chưa nhập {label}.")
        try:
            baudrate = int(normalized, 10)
        except ValueError as exc:
            raise ValueError(f"{label} không hợp lệ. Ví dụ: 115200 hoặc 921600.") from exc
        if not 50 <= baudrate <= 12_000_000:
            raise ValueError(
                f"{label} phải từ 50 đến 12,000,000. "
                "Giới hạn thực tế phụ thuộc driver và USB-UART."
            )
        return baudrate

    def _parse_baudrate(self) -> int:
        baudrate = self._parse_baudrate_text(self.baud_var.get(), "baud bootloader")
        if baudrate > 115200:
            raise ValueError(
                "Baud ROM bootloader phải không lớn hơn 115200. "
                "Hãy để 115200 8E1; baud 921600 chỉ nhập ở ô UART app 8N1."
            )
        return baudrate

    def _parse_app_baudrate(self) -> int:
        return self._parse_baudrate_text(self.app_baud_var.get(), "baud UART app")

    def _parse_write_block_size(self) -> int:
        try:
            value = int(self.write_block_size_var.get().strip(), 10)
        except ValueError as exc:
            raise ValueError("Block ghi phải là 32, 64, 128 hoặc 256 byte.") from exc
        if value not in {32, 64, 128, 256}:
            raise ValueError("Block ghi phải là 32, 64, 128 hoặc 256 byte.")
        return value

    def _parse_write_retries(self) -> int:
        try:
            value = int(self.write_retries_var.get().strip(), 10)
        except ValueError as exc:
            raise ValueError("Retry/block phải là số nguyên từ 1 đến 20.") from exc
        if not 1 <= value <= 20:
            raise ValueError("Retry/block phải từ 1 đến 20.")
        return value

    @staticmethod
    def _open_serial(
        port_name: str,
        baudrate: int,
        parity: str,
        timeout: float,
        write_timeout: float,
    ) -> serial.Serial:
        # Configure DTR/RTS before opening to minimize unwanted line transitions.
        port = serial.Serial()
        port.port = port_name
        port.baudrate = baudrate
        port.bytesize = serial.EIGHTBITS
        port.parity = parity
        port.stopbits = serial.STOPBITS_ONE
        port.timeout = timeout
        port.write_timeout = write_timeout
        port.xonxoff = False
        port.rtscts = False
        port.dsrdtr = False
        port.dtr = False
        port.rts = False
        port.open()
        return port

    @staticmethod
    def _configure_application_rx_buffer(port: serial.Serial) -> bool:
        """Request a large driver RX buffer when the platform supports it."""
        try:
            port.set_buffer_size(
                rx_size=APPLICATION_RX_BUFFER_BYTES,
                tx_size=64 * 1024,
            )
            return True
        except (AttributeError, NotImplementedError, serial.SerialException, OSError):
            # pyserial exposes set_buffer_size only on selected backends. The
            # queue-based reader still works when the driver ignores this hint.
            return False

    @staticmethod
    def _open_serial_legacy_v1_reset(
        port_name: str,
        baudrate: int,
        parity: str,
        timeout: float,
        write_timeout: float,
    ) -> serial.Serial:
        """Open COM exactly like v1 so the DTR transition can reset the board.

        In v1, serial.Serial(...) opened the handle with pyserial's default DTR
        assertion, then the code immediately assigned dtr=False/rts=False. On the
        company board this transition appears to be wired to NRST, so it produces
        the reset that places STM32F405 in ROM bootloader when BOOT0=1. v1.6 set
        DTR low *before* opening the port and therefore removed this transition.
        """
        port = serial.Serial(
            port=port_name,
            baudrate=baudrate,
            bytesize=serial.EIGHTBITS,
            parity=parity,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
            write_timeout=write_timeout,
            xonxoff=False,
            rtscts=False,
            dsrdtr=False,
        )
        # Reproduce v1 exactly: port is already open, then release DTR/RTS.
        time.sleep(0.03)
        port.dtr = False
        port.rts = False
        # Allow reset release, BOOT0 sampling, and ROM bootloader startup.
        time.sleep(0.35)
        return port

    def _pulse_dtr_reset(self, port: serial.Serial) -> None:
        self.log("Tạo xung DTR để reset board (DTR phải được nối tới NRST)...")
        # Most TTL USB-UART boards expose DTR as active-low. pyserial dtr=True
        # asserts the line, typically pulling it low. The option is disabled by
        # default because polarity and board wiring can differ.
        port.dtr = False
        time.sleep(0.05)
        port.dtr = True
        time.sleep(0.12)
        port.dtr = False
        time.sleep(0.35)
        port.reset_input_buffer()

    def toggle_connection(self) -> None:
        if self.serial_port is not None and self.serial_port.is_open:
            self.disconnect_bootloader()
        else:
            self.connect()

    def connect(self) -> None:
        if self.worker and self.worker.is_alive():
            return
        try:
            port_name = self._selected_port_name()
            baudrate = self._parse_baudrate()
            dtr_reset = bool(self.dtr_reset_var.get())
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc))
            return

        monitor_was_active = self.app_serial is not None and self.app_serial.is_open
        if monitor_was_active:
            self.log(
                "Đang đóng UART APP 8N1 và giải phóng cổng COM để chuyển sang "
                "ROM bootloader 8E1..."
            )
        self._close_app_serial_safely()
        # Một số driver USB-UART trên Windows cần một khoảng nghỉ ngắn sau khi
        # đóng handle 8N1 trước khi mở lại cùng COM ở 8E1.
        time.sleep(0.20)
        self.cancel_event.clear()
        self._set_busy(True)
        self.set_status("Đang chờ BOOT0=1 + RESET để kết nối bootloader...")

        def task() -> None:
            port: Optional[serial.Serial] = None
            try:
                self.log(f"Mở {port_name} tại {baudrate} baud, 8E1...")
                if not dtr_reset:
                    self.log(
                        "Auto reset DTR đang tắt: giữ BOOT0=1 và nhấn RESET bằng tay "
                        "ngay khi tool bắt đầu đồng bộ."
                    )
                if dtr_reset:
                    self.log(
                        "Dùng AUTO RESET kiểu app v1: mở COM rồi nhả DTR/RTS để "
                        "reset MCU. BOOT0 phải đang ở mức 1."
                    )
                    port = self._open_serial_legacy_v1_reset(
                        port_name,
                        baudrate,
                        serial.PARITY_EVEN,
                        timeout=2.0,
                        write_timeout=2.0,
                    )
                else:
                    port = self._open_serial(
                        port_name,
                        baudrate,
                        serial.PARITY_EVEN,
                        timeout=2.0,
                        write_timeout=2.0,
                    )
                bootloader = STM32Bootloader(port, self.log, self.cancel_event)
                if dtr_reset:
                    bootloader.synchronize_clean(timeout=2.5)
                else:
                    bootloader.synchronize()
                info = bootloader.get_info()
                self.serial_port = port
                self.bootloader = bootloader
                self.bootloader_info = info
                self.after(0, self._connected_ui)
            except Exception as exc:
                self.log(f"LỖI KẾT NỐI: {exc}")
                if port is not None:
                    try:
                        if port.is_open:
                            port.close()
                    except Exception:
                        pass
                self._close_bootloader_safely()
                self.after(0, self._disconnected_ui)
                self.after(0, messagebox.showerror, APP_NAME, str(exc))
            finally:
                self.after(0, self._set_busy, False)

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    def disconnect_bootloader(self) -> None:
        self.cancel_event.set()
        self._close_bootloader_safely()
        self._disconnected_ui()
        self.log("Đã ngắt kết nối bootloader.")

    def _close_bootloader_safely(self) -> None:
        port = self.serial_port
        self.serial_port = None
        self.bootloader = None
        self.bootloader_info = None
        if port is not None:
            try:
                if port.is_open:
                    port.close()
            except Exception:
                pass

    def _close_app_serial_safely(self) -> None:
        self.app_monitor_stop_event.set()
        self._flush_active_log_capture()
        port = self.app_serial
        self.app_serial = None
        if port is not None:
            try:
                if port.is_open:
                    port.close()
            except Exception:
                pass

    def _connected_ui(self) -> None:
        self.connect_button.configure(text="Ngắt BL")
        if self.bootloader_info:
            self.status_var.set(
                f"Đã kết nối BL — Chip ID 0x{self.bootloader_info.chip_id:X}, "
                f"v{self.bootloader_info.version_text}"
            )
        else:
            self.status_var.set("Đã kết nối bootloader")
        self._update_button_states()

    def _disconnected_ui(self) -> None:
        self.connect_button.configure(text="Kết nối BL")
        if self.app_serial is None:
            self.status_var.set("Chưa kết nối")
        self._update_button_states()

    def _set_busy(self, busy: bool) -> None:
        self.is_busy = busy
        self._update_button_states()

    def _update_button_states(self) -> None:
        boot_connected = (
            self.serial_port is not None
            and self.serial_port.is_open
            and self.bootloader is not None
        )
        monitor_active = self.app_serial is not None and self.app_serial.is_open

        if self.is_busy:
            self.connect_button.configure(state="disabled")
            self.run_button.configure(state="disabled")
            self.flash_button.configure(state="disabled")
            self.open_monitor_button.configure(state="disabled")
            self.stop_monitor_button.configure(state="disabled")
            self.cancel_button.configure(state="normal")
            return

        # Cho phép bấm Kết nối BL ngay cả khi UART APP đang mở. connect() sẽ tự
        # đóng monitor, giải phóng COM và mở lại cổng ở 8E1. Đây là luồng cần
        # thiết để flash lại firmware sau khi đã xem log ứng dụng.
        self.connect_button.configure(state="normal")
        if boot_connected:
            self.connect_button.configure(text="Ngắt BL")
        elif monitor_active:
            self.connect_button.configure(text="ĐÓNG APP → KẾT NỐI BL")
        else:
            self.connect_button.configure(text="Kết nối BL")

        self.run_button.configure(state="normal")
        self.open_monitor_button.configure(state="disabled" if monitor_active else "normal")
        self.flash_button.configure(state="normal" if boot_connected else "disabled")
        self.stop_monitor_button.configure(state="normal" if monitor_active else "disabled")
        self.cancel_button.configure(state="disabled")

    def cancel_operation(self) -> None:
        self.cancel_event.set()
        self.log("Đã yêu cầu hủy thao tác...")

    def _inspect_application_vector(
        self,
        bootloader: STM32Bootloader,
        address: int,
    ) -> tuple[int, int]:
        vector = bootloader.read_memory(address, 8)
        initial_msp, reset_handler = struct.unpack("<II", vector)
        self.log(
            f"Vector table tại 0x{address:08X}: MSP=0x{initial_msp:08X}, "
            f"Reset_Handler=0x{reset_handler:08X}."
        )
        if initial_msp in {0x00000000, 0xFFFFFFFF} or reset_handler in {
            0x00000000,
            0xFFFFFFFF,
        }:
            raise BootloaderError(
                "Vector table rỗng/không hợp lệ. Firmware có thể chưa được ghi tại "
                f"0x{address:08X}."
            )
        if (reset_handler & 1) == 0:
            self.log(
                "CẢNH BÁO: bit Thumb của Reset_Handler bằng 0. Firmware có thể không chạy đúng."
            )
        return initial_msp, reset_handler

    def _open_application_monitor(self, port_name: str, baudrate: int) -> None:
        self.app_monitor_stop_event.clear()
        self.log_recorder.reset_session()
        self._serial_ui_epoch += 1
        monitor_epoch = self._serial_ui_epoch
        self._serial_ui_queue.put((monitor_epoch, "reset", b""))
        last_error: Optional[Exception] = None
        app_port: Optional[serial.Serial] = None

        # Windows/USB-UART drivers can need a short time after closing the 8E1
        # bootloader handle before reopening the same COM with 8N1.
        for attempt in range(1, 9):
            try:
                app_port = self._open_serial(
                    port_name,
                    baudrate,
                    serial.PARITY_NONE,
                    timeout=0.08,
                    write_timeout=1.0,
                )
                break
            except (serial.SerialException, OSError) as exc:
                last_error = exc
                self.log(
                    f"Mở UART app lần {attempt}/8 chưa thành công; thử lại... ({exc})"
                )
                time.sleep(0.20)

        if app_port is None:
            raise BootloaderError(
                "Firmware đã nhận GO nhưng không mở lại được UART app. "
                f"Chi tiết: {last_error}"
            )

        large_rx_buffer = self._configure_application_rx_buffer(app_port)
        self.app_serial = app_port
        self.log(
            "UART RX buffer: "
            + (f"requested {APPLICATION_RX_BUFFER_BYTES} bytes."
               if large_rx_buffer else "driver default (large-buffer request unsupported).")
        )
        self.log(f"Đã mở UART APP {port_name} tại {baudrate} baud, 8N1.")
        self.set_status(f"APP ĐANG CHẠY — UART {baudrate} 8N1")
        self.after(0, self._update_button_states)

        def monitor() -> None:
            local_port = app_port
            try:
                while not self.app_monitor_stop_event.is_set():
                    if not local_port.is_open:
                        break
                    waiting = local_port.in_waiting
                    read_size = min(max(waiting, 1), APPLICATION_READ_CHUNK_BYTES)
                    data = local_port.read(read_size)
                    if data:
                        self.log_serial_data(data, monitor_epoch)
                    else:
                        time.sleep(0.001)
            except (serial.SerialException, OSError) as exc:
                if not self.app_monitor_stop_event.is_set():
                    self.log(f"UART APP bị ngắt: {exc}")
                    self.set_status("UART APP đã ngắt")
            finally:
                self._flush_active_log_capture(monitor_epoch)
                try:
                    if local_port.is_open:
                        local_port.close()
                except Exception:
                    pass
                # Do not close a newer monitor that may already use the same
                # self.app_serial slot after a quick RECONNECT operation.
                if self.app_serial is local_port:
                    self.app_serial = None
                self.after(0, self._update_button_states)

        self.app_monitor_thread = threading.Thread(target=monitor, daemon=True)
        self.app_monitor_thread.start()

    def start_application_monitor_only(self) -> None:
        """Open the application UART directly without sending a bootloader GO command."""
        if self.worker and self.worker.is_alive():
            return
        try:
            port_name = self._selected_port_name()
            app_baud = self._parse_app_baudrate()
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc))
            return

        self.cancel_event.clear()
        self._set_busy(True)
        self.set_status("Đang mở UART APP...")

        def task() -> None:
            try:
                self._close_bootloader_safely()
                self.after(0, self._disconnected_ui)
                self._close_app_serial_safely()
                time.sleep(0.10)
                self._open_application_monitor(port_name, app_baud)
                self.log(
                    "Đã mở trực tiếp UART APP, không gửi SYNC 0x7F và không gửi GO. "
                    "Dùng chế độ này khi firmware đã chạy hoặc khi bootloader trả byte lạ "
                    "do PC10 đang có log ứng dụng."
                )
            except Exception as exc:
                self.log(f"MỞ UART APP THẤT BẠI: {exc}")
                self.set_status("MỞ UART APP THẤT BẠI")
                self.after(0, messagebox.showerror, APP_NAME, str(exc))
            finally:
                self.after(0, self._set_busy, False)

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    def stop_application_monitor(self) -> None:
        active = self.app_serial is not None
        self._close_app_serial_safely()
        if active:
            self.log("Đã đóng UART APP.")
        if self.bootloader is None:
            self.status_var.set("Chưa kết nối")
        self._update_button_states()

    def start_go_application(self) -> None:
        """Reconnect to ROM bootloader, send GO, then reopen as app UART.

        This button is designed for BOOT0 permanently held high. After each reset,
        the ROM bootloader waits for a host command. The user can click this button
        and, if needed, press RESET during the synchronization retry window.
        """
        if self.worker and self.worker.is_alive():
            return
        try:
            port_name = self._selected_port_name()
            boot_baud = self._parse_baudrate()
            app_baud = self._parse_app_baudrate()
            go_address = self._parse_go_address()
            dtr_reset = bool(self.dtr_reset_var.get())
            auto_monitor = bool(self.auto_monitor_var.get())
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc))
            return

        # If a monitor is still open after the board reset, close it first so the
        # same COM can be reopened at bootloader 8E1.
        self._close_app_serial_safely()
        self.cancel_event.clear()
        self._set_busy(True)
        self.set_status("Đang RECONNECT và gửi GO...")

        def task() -> None:
            temporary_port: Optional[serial.Serial] = None
            bootloader: Optional[STM32Bootloader] = None
            used_existing = False
            try:
                if (
                    self.bootloader is not None
                    and self.serial_port is not None
                    and self.serial_port.is_open
                ):
                    bootloader = self.bootloader
                    used_existing = True
                    self.log("Dùng kết nối bootloader hiện có để gửi GO.")
                else:
                    self.log(
                        f"RECONNECT: mở {port_name} tại {boot_baud} baud, 8E1. "
                        + (
                            "Tool sẽ auto reset theo cơ chế DTR của v1."
                            if dtr_reset
                            else "Board đang chạy app thì nhấn RESET trong thời gian đồng bộ."
                        )
                    )
                    if dtr_reset:
                        self.log(
                            "RECONNECT dùng AUTO RESET kiểu v1: mở COM và nhả DTR/RTS "
                            "để reset MCU vào ROM bootloader."
                        )
                        temporary_port = self._open_serial_legacy_v1_reset(
                            port_name,
                            boot_baud,
                            serial.PARITY_EVEN,
                            timeout=2.0,
                            write_timeout=2.0,
                        )
                    else:
                        temporary_port = self._open_serial(
                            port_name,
                            boot_baud,
                            serial.PARITY_EVEN,
                            timeout=2.0,
                            write_timeout=2.0,
                        )
                    bootloader = STM32Bootloader(
                        temporary_port,
                        self.log,
                        self.cancel_event,
                    )
                    try:
                        if dtr_reset:
                            bootloader.synchronize_clean(timeout=2.5)
                        else:
                            bootloader.synchronize(attempts=15, interval=0.60)
                    except BootloaderError as sync_exc:
                        # If bytes are present but none is ACK 0x79, the line is
                        # very likely carrying application traffic (for this
                        # board normally 921600 8N1) instead of ROM-bootloader
                        # traffic. Close 8E1 and reopen the same COM as the app
                        # monitor so one button works in both states.
                        if (
                            auto_monitor
                            and (
                                bootloader.sync_unsolicited_bytes
                                or bootloader.sync_invalid_bytes
                            )
                        ):
                            sample = bytes(
                                bootloader.sync_unsolicited_bytes
                                + bootloader.sync_invalid_bytes
                            )
                            self.log(
                                "Không thấy ACK 0x79 nhưng có dữ liệu UART ["
                                + bootloader._hex_preview(sample)
                                + "]. Tự chuyển sang UART APP 8N1; không gửi GO "
                                "vì MCU không ở trạng thái ROM bootloader."
                            )
                            try:
                                temporary_port.close()
                            finally:
                                temporary_port = None
                            time.sleep(0.12)
                            self._open_application_monitor(port_name, app_baud)
                            self.log(
                                "Đã mở UART APP. Nếu log hiển thị đúng, firmware "
                                "đã chạy sẵn. Nếu cửa sổ im lặng, kiểm tra BOOT0 "
                                "và nhấn RESET để vào bootloader rồi thử lại."
                            )
                            self.set_status(
                                f"UART APP ĐÃ MỞ — {app_baud} 8N1 (GO chưa gửi)"
                            )
                            return
                        raise sync_exc
                    bootloader.get_info()

                if bootloader is None:
                    raise BootloaderError("Không tạo được kết nối bootloader.")

                self._inspect_application_vector(bootloader, go_address)
                bootloader.go(go_address)
                self.log(
                    f"GO 0x{go_address:08X} thành công. Bootloader đã chuyển sang Reset_Handler."
                )

                if used_existing:
                    self._close_bootloader_safely()
                elif temporary_port is not None:
                    try:
                        temporary_port.close()
                    finally:
                        temporary_port = None

                self.after(0, self._disconnected_ui)
                time.sleep(0.12)

                if auto_monitor:
                    try:
                        self._open_application_monitor(port_name, app_baud)
                    except Exception as monitor_exc:
                        # GO has already succeeded; monitor failure does not mean
                        # the application failed to start.
                        self.log(str(monitor_exc))
                        self.set_status("APP ĐÃ NHẬN GO — chưa mở được UART monitor")
                        self.after(
                            0,
                            messagebox.showwarning,
                            APP_NAME,
                            "STM32 đã nhận GO và firmware đã được khởi chạy, nhưng "
                            "không mở lại được UART app.\n\n" + str(monitor_exc),
                        )
                else:
                    self.set_status("APP ĐÃ NHẬN GO")
                    self.after(
                        0,
                        messagebox.showinfo,
                        APP_NAME,
                        f"Đã gửi GO 0x{go_address:08X}. Firmware đang chạy.",
                    )
            except CancelledError as exc:
                self.log(str(exc))
                self.set_status("Đã hủy")
            except Exception as exc:
                text = str(exc)
                self.log(f"RUN APP THẤT BẠI: {text}")
                self.set_status("RUN APP THẤT BẠI")
                self.after(
                    0,
                    messagebox.showerror,
                    APP_NAME,
                    text
                    + "\n\nVới BOOT0=1: reset board rồi nhấn RECONNECT / RUN APP. "
                    "Bạn cũng có thể nhấn nút trước, sau đó nhấn RESET trong cửa sổ đồng bộ.",
                )
            finally:
                if temporary_port is not None:
                    try:
                        if temporary_port.is_open:
                            temporary_port.close()
                    except Exception:
                        pass
                self.after(0, self._set_busy, False)

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    @staticmethod
    def _padded_chunks(
        segment: FirmwareSegment, block_size: int
    ) -> Iterable[tuple[int, bytes, int]]:
        offset = 0
        while offset < len(segment.data):
            raw = segment.data[offset : offset + block_size]
            original_length = len(raw)
            if len(raw) % 4:
                raw += b"\xFF" * (4 - len(raw) % 4)
            yield segment.address + offset, raw, original_length
            offset += original_length

    def start_flash(self) -> None:
        if self.worker and self.worker.is_alive():
            return
        if self.bootloader is None or self.serial_port is None or not self.serial_port.is_open:
            messagebox.showerror(APP_NAME, "Chưa kết nối STM32 bootloader.")
            return

        try:
            image = FirmwareLoader.load(self.file_var.get().strip(), self._parse_address())
            go_address = self._parse_go_address()
            app_baud = self._parse_app_baudrate()
            write_block_size = self._parse_write_block_size()
            write_retries = self._parse_write_retries()
            port_name = self._selected_port_name()
        except Exception as exc:
            messagebox.showerror(APP_NAME, str(exc))
            return

        range_text = f"0x{image.first_address:08X}–0x{image.last_address - 1:08X}"
        proceed = messagebox.askyesno(
            APP_NAME,
            f"Firmware: {image.path.name}\n"
            f"Kích thước: {image.total_size:,} byte\n"
            f"Vùng địa chỉ: {range_text}\n\n"
            "Ứng dụng sẽ MASS ERASE toàn bộ Flash rồi ghi firmware. Tiếp tục?",
        )
        if not proceed:
            return

        verify_after_write = bool(self.verify_var.get())
        verify_each_block = bool(self.verify_each_block_var.get())
        run_after_flash = bool(self.run_var.get())
        auto_monitor = bool(self.auto_monitor_var.get())

        self.cancel_event.clear()
        self._set_busy(True)
        self.set_progress(0)

        def task() -> None:
            go_succeeded = False
            try:
                bootloader = self.bootloader
                if bootloader is None:
                    raise BootloaderError("Mất kết nối bootloader.")

                self.log(
                    f"Nạp {image.path.name}: {image.total_size:,} byte, "
                    f"{len(image.segments)} segment, vùng {range_text}. "
                    f"Block={write_block_size} byte, retry={write_retries}, "
                    f"verify từng block={'ON' if verify_each_block else 'OFF'}."
                )
                self.log("Kiểm tra lại cổng COM và trạng thái bootloader trước khi xóa...")
                bootloader.get_info()
                time.sleep(0.05)
                bootloader.mass_erase()
                # ACK của Mass Erase có nghĩa là thao tác đã hoàn tất, nhưng một
                # khoảng nghỉ ngắn giúp ổn định các USB-UART/driver Windows cũ.
                time.sleep(0.20)

                processed = 0
                for segment in image.segments:
                    self.log(
                        f"Ghi segment 0x{segment.address:08X}, {len(segment.data):,} byte..."
                    )
                    for address, padded_data, original_length in self._padded_chunks(
                        segment, write_block_size
                    ):
                        if self.cancel_event.is_set():
                            raise CancelledError("Thao tác đã bị hủy.")
                        bootloader.write_memory_robust(
                            address,
                            padded_data,
                            retries=write_retries,
                            verify_immediately=verify_each_block,
                        )
                        processed += original_length
                        self.set_progress(processed * 70.0 / image.total_size)

                self.log("Ghi firmware hoàn tất.")

                if verify_after_write:
                    self.log("Đang verify bằng cách đọc lại Flash...")
                    verified = 0
                    for segment in image.segments:
                        offset = 0
                        while offset < len(segment.data):
                            if self.cancel_event.is_set():
                                raise CancelledError("Thao tác đã bị hủy.")
                            expected = segment.data[offset : offset + 256]
                            address = segment.address + offset
                            actual = bootloader.read_memory(address, len(expected))
                            if actual != expected:
                                mismatch = next(
                                    (
                                        index
                                        for index, (left, right) in enumerate(zip(expected, actual))
                                        if left != right
                                    ),
                                    0,
                                )
                                fail_address = address + mismatch
                                raise BootloaderError(
                                    f"Verify sai tại 0x{fail_address:08X}: "
                                    f"file=0x{expected[mismatch]:02X}, "
                                    f"flash=0x{actual[mismatch]:02X}."
                                )
                            offset += len(expected)
                            verified += len(expected)
                            self.set_progress(70.0 + verified * 30.0 / image.total_size)
                    self.log("VERIFY THÀNH CÔNG.")
                else:
                    self.set_progress(100.0)

                if run_after_flash:
                    self._inspect_application_vector(bootloader, go_address)
                    bootloader.go(go_address)
                    go_succeeded = True
                    self.log(
                        f"Đã gửi GO 0x{go_address:08X}. Với BOOT0=1, sau mỗi reset "
                        "hãy nhấn RECONNECT / RUN APP."
                    )
                    self._close_bootloader_safely()
                    self.after(0, self._disconnected_ui)
                    time.sleep(0.12)
                    if auto_monitor:
                        try:
                            self._open_application_monitor(port_name, app_baud)
                        except Exception as monitor_exc:
                            self.log(str(monitor_exc))
                            self.set_status("FLASH OK + GO OK — monitor chưa mở")

                self.set_progress(100.0)
                if go_succeeded:
                    self.set_status(
                        f"FLASH OK — APP ĐANG CHẠY UART {app_baud} 8N1"
                        if self.app_serial is not None
                        else "FLASH OK — APP ĐÃ NHẬN GO"
                    )
                else:
                    self.set_status("FLASH THÀNH CÔNG — chờ GO")
                self.log("FLASH THÀNH CÔNG.")

                message = "Flash firmware thành công."
                if go_succeeded:
                    message += f"\n\nĐã gửi GO 0x{go_address:08X}; firmware đã được khởi chạy."
                    if auto_monitor:
                        message += f"\nUART app: {app_baud} 8N1."
                else:
                    message += (
                        "\n\nBOOT0 đang bằng 1: nhấn RECONNECT / RUN APP để gửi "
                        f"GO 0x{go_address:08X}."
                    )
                self.after(0, messagebox.showinfo, APP_NAME, message)
            except CancelledError as exc:
                self.log(str(exc))
                self.set_status("Đã hủy")
            except Exception as exc:
                text = str(exc)
                self.log(f"FLASH THẤT BẠI: {text}")
                self.set_status("FLASH THẤT BẠI")
                lower = text.lower()
                if (
                    "writefile failed" in lower
                    or "mất quyền ghi" in lower
                    or "cổng com đã đóng" in lower
                    or "device does not recognize" in lower
                ):
                    self.log(
                        "Cổng COM đã được đóng để phục hồi. Rút-cắm USB-UART, "
                        "BOOT0=1, reset STM32 rồi nhấn Kết nối BL lại."
                    )
                    self._close_bootloader_safely()
                    self.after(0, self._disconnected_ui)
                self.after(0, messagebox.showerror, APP_NAME, text)
            finally:
                self.after(0, self._set_busy, False)

        self.worker = threading.Thread(target=task, daemon=True)
        self.worker.start()

    def on_close(self) -> None:
        self._closing = True
        self.cancel_event.set()
        # Stop the producer before draining the queue. A completed capture may
        # already be queued but not yet handled by Tk; preserve that case as
        # well as an interrupted active batch.
        self._close_app_serial_safely()
        monitor_thread = self.app_monitor_thread
        if monitor_thread is not None and monitor_thread.is_alive():
            monitor_thread.join(timeout=0.5)
        captures = self._take_pending_captures_for_shutdown()
        if self.auto_save_log_var.get():
            directory_text = self.log_directory_var.get().strip()
            output_dir = Path(directory_text or str(default_log_directory())).expanduser()
            for capture in captures:
                try:
                    save_capture(capture, output_dir)
                except Exception:
                    # Shutdown must continue even if the chosen drive vanished.
                    pass
        self._close_bootloader_safely()
        self.destroy()


def main() -> None:
    app = FlasherApp()
    app.mainloop()


if __name__ == "__main__":
    main()

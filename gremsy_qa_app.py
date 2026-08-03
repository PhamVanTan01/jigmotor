
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox, filedialog
import serial
import serial.tools.list_ports
import json
import os
import pandas as pd
from datetime import datetime
import sys
import openpyxl

# --- CẤU HÌNH ĐƯỜNG DẪN AN TOÀN CHO PYINSTALLER ---
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DEFAULT_EXCEL_PATH = os.path.join(BASE_DIR, 'Gremsy_Motor_QA_Log.xlsx')
BAUD_RATE = 921600

ERROR_DICT = {
    "UNKNOWN": "Lỗi chưa xác định",
    "OK": "Không có lỗi",
    "E501": "Lỗi lost phase",
    "E502": "Lỗi ngược phase",
    "E503": "Lỗi giá trị điện trở sai lệch",
    "E504": "Lỗi chưa xác định (Exception)",
    "E505": "Lỗi non-linear",
    "E506": "Lỗi power min",
    "E507": "Lỗi database"
}

class GremsyQAApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Gremsy Motor QA Jig Tester")
        self.root.geometry("960x860")
        self.root.minsize(780, 720)

        self.serial_conn = None
        self.is_running = False
        self.rx_buffer = ""

        self.excel_file_path = DEFAULT_EXCEL_PATH

        self.build_ui()
        self.init_excel()

    def init_excel(self):
        columns = ['Timestamp', 'JigID', 'Checked By', 'Liner', 'Product Detail',
                   'ResA', 'ResB', 'ResC', 'ResErr(%)', 'NLLow', 'NLHigh',
                   'NLAngle', 'PwrMin(%)', 'Error', 'Status']

        try:
            if not os.path.exists(self.excel_file_path):
                df = pd.DataFrame(columns=columns)
                df.to_excel(self.excel_file_path, index=False)
            else:
                df = pd.read_excel(self.excel_file_path)

                # Thêm cột mới nếu file Excel cũ chưa có, giữ nguyên dữ liệu hiện tại.
                for col in columns:
                    if col not in df.columns:
                        df[col] = ""

                # Sắp xếp cột chính theo format chuẩn, giữ lại mọi cột phụ nếu có.
                extra_cols = [col for col in df.columns if col not in columns]
                df = df[columns + extra_cols]
                df.to_excel(self.excel_file_path, index=False)

            self.apply_excel_protection()

        except Exception as e:
            messagebox.showerror(
                "Lỗi tạo/cập nhật file",
                f"Không thể tạo hoặc cập nhật file Excel tại:\n{self.excel_file_path}\nChi tiết: {e}"
            )

    def apply_excel_protection(self):
        try:
            wb = openpyxl.load_workbook(self.excel_file_path)
            ws = wb.active
            for col in ws.columns:
                max_length = 0
                column_letter = col[0].column_letter
                for cell in col:
                    try:
                        if cell.value:
                            cell_length = len(str(cell.value))
                            if cell_length > max_length:
                                max_length = cell_length
                    except:
                        pass
                adjusted_width = max_length + 2
                ws.column_dimensions[column_letter].width = adjusted_width

            ws.protection.sheet = True
            ws.protection.password = "GremsyQA@2026"
            wb.save(self.excel_file_path)
            wb.close()
        except Exception as e:
            self.root.after(0, lambda: self.log_message(f"⚠️ LỖI BẢO MẬT/CĂN CHỈNH EXCEL: {e}"))

    def scan_ports(self):
        ports = serial.tools.list_ports.comports()
        return [port for port, desc, hwid in sorted(ports)]

    def refresh_ports(self):
        ports = self.scan_ports()
        self.cb_ports['values'] = ports
        if ports:
            self.cb_ports.current(0)
        else:
            self.cb_ports.set("Không tìm thấy COM")

    def choose_save_location(self):
        new_path = filedialog.asksaveasfilename(
            title="Chọn nơi lưu file Excel",
            defaultextension=".xlsx",
            initialfile="Gremsy_Motor_QA_Log.xlsx",
            filetypes=[("Excel files", "*.xlsx"), ("All files", "*.*")]
        )
        if new_path:
            self.excel_file_path = new_path
            self.path_var.set(self.excel_file_path)
            self.init_excel()
            self.log_message(f"Cập nhật nơi lưu file: {self.excel_file_path}")

    def build_ui(self):
        # Khung cấu hình File Excel
        file_frame = tk.LabelFrame(self.root, text="Cấu hình Lưu File", padx=10, pady=5)
        file_frame.pack(fill="x", padx=10, pady=5)

        self.path_var = tk.StringVar(value=self.excel_file_path)
        self.entry_path = tk.Entry(file_frame, textvariable=self.path_var, state='readonly', width=60, font=("Arial", 9))
        self.entry_path.grid(row=0, column=0, padx=5, pady=5)

        self.btn_browse = tk.Button(file_frame, text="Chọn nơi lưu...", command=self.choose_save_location)
        self.btn_browse.grid(row=0, column=1, padx=5)

        # Khung cấu hình kết nối
        conn_frame = tk.LabelFrame(self.root, text="Cấu hình Kết nối", padx=10, pady=5)
        conn_frame.pack(fill="x", padx=10, pady=5)

        tk.Label(conn_frame, text="Chọn Cổng COM:", font=("Arial", 10, "bold")).grid(row=0, column=0, sticky="w", pady=5)
        self.cb_ports = ttk.Combobox(conn_frame, state="readonly", font=("Arial", 10), width=15)
        self.cb_ports.grid(row=0, column=1, padx=10)
        self.btn_refresh = tk.Button(conn_frame, text="Làm mới (Refresh)", command=self.refresh_ports)
        self.btn_refresh.grid(row=0, column=2, padx=5)
        self.refresh_ports()

        # Khung thông tin tester nhập (thêm trường Liner)
        input_frame = tk.LabelFrame(self.root, text="Thông tin Tester nhập", padx=10, pady=10)
        input_frame.pack(fill="x", padx=10, pady=5)

        tk.Label(input_frame, text="Checked By (Tên NV):", font=("Arial", 10, "bold")).grid(row=0, column=0, sticky="w", pady=5)
        self.checked_by_var = tk.StringVar()
        self.entry_checked_by = tk.Entry(input_frame, textvariable=self.checked_by_var, font=("Arial", 10), width=30)
        self.entry_checked_by.grid(row=0, column=1, padx=10)

        tk.Label(input_frame, text="Product Detail (Chi tiết SP):", font=("Arial", 10, "bold")).grid(row=1, column=0, sticky="w", pady=5)
        self.product_detail_var = tk.StringVar()
        self.entry_product_detail = tk.Entry(input_frame, textvariable=self.product_detail_var, font=("Arial", 10), width=30)
        self.entry_product_detail.grid(row=1, column=1, padx=10)

        # Thêm trường Liner
        tk.Label(input_frame, text="Lệnh sản xuất :", font=("Arial", 10, "bold")).grid(row=2, column=0, sticky="w", pady=5)
        self.liner_var = tk.StringVar()
        self.entry_liner = tk.Entry(input_frame, textvariable=self.liner_var, font=("Arial", 10), width=30)
        self.entry_liner.grid(row=2, column=1, padx=10)

        # Nút điều khiển
        btn_frame = tk.Frame(self.root)
        btn_frame.pack(fill="x", padx=10, pady=5)
        self.btn_connect = tk.Button(btn_frame, text="Kết nối Mạch & Sẵn sàng", bg="#4CAF50", fg="white", font=("Arial", 10, "bold"), command=self.toggle_connection)
        self.btn_connect.pack(fill="x", ipady=5)

        # Khung hiển thị kết quả
        status_frame = tk.LabelFrame(self.root, text="Kết quả Test Mới Nhất", padx=10, pady=10)
        status_frame.pack(fill="x", padx=10, pady=5)
        self.lbl_status = tk.Label(status_frame, text="CHỜ KẾT NỐI...", font=("Arial", 16, "bold"), fg="gray")
        self.lbl_status.pack()

        # Khung log hệ thống
        log_frame = tk.LabelFrame(self.root, text="Log Hệ Thống (Không thể xóa/sửa)", padx=10, pady=10)
        log_frame.pack(fill="both", expand=True, padx=10, pady=5)
        self.txt_log = scrolledtext.ScrolledText(log_frame, wrap=tk.WORD, font=("Consolas", 9), state=tk.DISABLED)
        self.txt_log.pack(fill="both", expand=True)

    def log_message(self, message):
        self.txt_log.config(state=tk.NORMAL)
        self.txt_log.insert(tk.END, message + "\n")
        self.txt_log.see(tk.END)
        self.txt_log.config(state=tk.DISABLED)

    def clean_serial_payload(self, line):
        text = line.strip()
        if text.startswith("MCU:"):
            text = text[4:].strip()

        markers = ["QA_RESULT:", "AUTO_TEST_START:"]
        for marker in markers:
            marker_index = text.find(marker)
            if marker_index >= 0:
                return text[marker_index:]
        return text

    def toggle_connection(self):
        if not self.is_running:
            selected_port = self.cb_ports.get()
            if not selected_port or selected_port == "Không tìm thấy COM":
                messagebox.showwarning("Lỗi COM", "Vui lòng chọn một cổng COM hợp lệ!")
                return

            if not self.checked_by_var.get().strip() or not self.product_detail_var.get().strip() or not self.liner_var.get().strip():
                messagebox.showwarning("Thiếu thông tin", "Vui lòng nhập đầy đủ 'Checked By', 'Product Detail' và 'Lệnh sx' trước khi kết nối!")
                return

            try:
                with open(self.excel_file_path, 'a'): pass
            except PermissionError:
                messagebox.showerror("Lỗi File", f"File Excel đang được mở bởi chương trình khác.\nVui lòng đóng file: {self.excel_file_path}")
                return

            try:
                self.serial_conn = serial.Serial()
                self.serial_conn.port = selected_port
                self.serial_conn.baudrate = BAUD_RATE
                self.serial_conn.timeout = 0.1
                self.serial_conn.setDTR(False)
                self.serial_conn.setRTS(False)
                self.serial_conn.open()
                self.rx_buffer = ""
                self.is_running = True

                self.cb_ports.config(state=tk.DISABLED)
                self.btn_refresh.config(state=tk.DISABLED)
                self.entry_checked_by.config(state=tk.DISABLED)
                self.entry_product_detail.config(state=tk.DISABLED)
                self.entry_liner.config(state=tk.DISABLED)
                self.btn_browse.config(state=tk.DISABLED)

                self.btn_connect.config(text="Đang kết nối... Nhấn để Ngắt", bg="#f44336")
                self.log_message(f"=== ĐÃ KẾT NỐI {selected_port}: MẠCH SẴN SÀNG ===")
                self.lbl_status.config(text="ĐANG CHỜ BẤM NÚT TRÊN JIG...", fg="blue")

                self.read_serial()
            except Exception as e:
                messagebox.showerror("Lỗi Serial", f"Không thể mở {selected_port}.\n{e}")
        else:
            self.is_running = False
            if self.serial_conn and self.serial_conn.is_open:
                self.serial_conn.close()

            self.cb_ports.config(state="readonly")
            self.btn_refresh.config(state=tk.NORMAL)
            self.entry_checked_by.config(state=tk.NORMAL)
            self.entry_product_detail.config(state=tk.NORMAL)
            self.entry_liner.config(state=tk.NORMAL)
            self.btn_browse.config(state=tk.NORMAL)

            self.btn_connect.config(text="Kết nối Mạch & Sẵn sàng", bg="#4CAF50")
            self.log_message("=== ĐÃ NGẮT KẾT NỐI ===")
            self.lbl_status.config(text="CHƯA KẾT NỐI", fg="gray")
    def read_serial(self):
        if self.is_running and self.serial_conn and self.serial_conn.is_open:
            try:
                waiting = self.serial_conn.in_waiting

                if waiting > 0:
                    raw = self.serial_conn.read(waiting)
                    text = raw.decode('utf-8', errors='ignore')

                    # Gom dữ liệu serial vào buffer.
                    # Không parse ngay từng mảnh, vì JSON có thể chưa nhận đủ.
                    self.rx_buffer += text

                    # Chỉ xử lý khi đã nhận đủ 1 dòng kết thúc bằng '\n'
                    while '\n' in self.rx_buffer:
                        line, self.rx_buffer = self.rx_buffer.split('\n', 1)
                        line = line.strip('\r').strip()

                        if line:
                            self.handle_serial_line(line)

                # Chống buffer phình to nếu có dữ liệu rác không có xuống dòng
                if len(self.rx_buffer) > 4096:
                    self.log_message("⚠️ RX BUFFER QUÁ DÀI, ĐÃ XÓA BUFFER SERIAL RÁC")
                    self.rx_buffer = ""

            except Exception as e:
                self.log_message(f"LỖI ĐỌC SERIAL: {e}")
                self.toggle_connection()

            self.root.after(50, self.read_serial)


    def handle_serial_line(self, line):
        line = self.clean_serial_payload(line)

        if line.startswith("AUTO_TEST_START:"):
            self.log_message(f"MCU: {line}")
            return

        if line.startswith("QA_RESULT:"):
            json_str = line[len("QA_RESULT:"):].strip()

            # Chỉ parse JSON khi đã có đủ dấu mở và đóng
            if not json_str.startswith("{") or not json_str.endswith("}"):
                self.log_message(f"⚠️ BỎ QUA QA_RESULT CHƯA ĐỦ DÒNG: {json_str}")
                return

            self.process_json_result(json_str)

        elif line != "":
            self.log_message(f"MCU: {line}")
    # ---------- CÁC HÀM XỬ LÝ THIẾU THÔNG TIN VÀ LƯU DỮ LIỆU MỚI ----------
    def show_missing_info_dialog(self, missing_fields, current_values, callback):
        """
        Hiển thị dialog yêu cầu nhập các trường còn thiếu.
        missing_fields: list các tên trường cần nhập (vd: ['Checked By', 'Product Detail'])
        current_values: dict các giá trị hiện có của row_data (để pre-fill nếu có)
        callback: hàm được gọi với dict các giá trị đã nhập (cập nhật vào row_data)
        """
        dialog = tk.Toplevel(self.root)
        dialog.title("Nhập thông tin còn thiếu")
        dialog.geometry("400x250")
        dialog.transient(self.root)
        dialog.grab_set()

        entries = {}
        row = 0
        for field in missing_fields:
            tk.Label(dialog, text=f"{field}:", font=("Arial", 10, "bold")).grid(row=row, column=0, padx=10, pady=10, sticky="e")
            var = tk.StringVar()
            # Nếu current_values đã có giá trị cho field này (có thể do nhập một phần trước đó) thì hiển thị
            if field in current_values and current_values[field]:
                var.set(current_values[field])
            entry = tk.Entry(dialog, textvariable=var, width=30)
            entry.grid(row=row, column=1, padx=10, pady=10)
            entries[field] = var
            row += 1

        def on_save():
            new_values = {}
            for field, var in entries.items():
                val = var.get().strip()
                if not val:
                    messagebox.showwarning("Cảnh báo", f"Trường '{field}' không được để trống!")
                    return
                new_values[field] = val
            dialog.destroy()
            callback(new_values)

        btn_save = tk.Button(dialog, text="Lưu & Tiếp tục", command=on_save, bg="#4CAF50", fg="white", width=15)
        btn_save.grid(row=row, column=0, columnspan=2, pady=20)

    def ensure_and_save(self, row_data, error_detail):
        """
        Kiểm tra các trường bắt buộc trong row_data: 'Checked By', 'Product Detail', 'Liner'
        Nếu thiếu, hiển thị dialog yêu cầu nhập và cập nhật vào row_data.
        Sau khi đủ, tiến hành lưu vào Excel và cập nhật giao diện.
        error_detail: chuỗi mô tả lỗi dùng để hiển thị trên log và label.
        """
        required_fields = ['Checked By', 'Product Detail', 'Liner']
        missing = [f for f in required_fields if not row_data.get(f, '').strip()]

        if missing:
            # Hiển thị dialog yêu cầu nhập các trường thiếu, truyền current_values là row_data hiện tại
            def after_fill(filled_values):
                # Cập nhật row_data với các giá trị vừa nhập
                for field, value in filled_values.items():
                    row_data[field] = value
                # Gọi lại chính nó để kiểm tra (lúc này đã đủ)
                self.ensure_and_save(row_data, error_detail)
            self.show_missing_info_dialog(missing, row_data, after_fill)
        else:
            # Đã có đủ thông tin, tiến hành lưu vào Excel
            try:
                # Lưu vào Excel
                df = pd.read_excel(self.excel_file_path)
                df = pd.concat([df, pd.DataFrame([row_data])], ignore_index=True)
                df.to_excel(self.excel_file_path, index=False)
                self.apply_excel_protection()

                # Cập nhật giao diện: đồng bộ các biến trên form với giá trị đã lưu
                self.checked_by_var.set(row_data['Checked By'])
                self.product_detail_var.set(row_data['Product Detail'])
                self.liner_var.set(row_data['Liner'])

                # Hiển thị kết quả test
                status = row_data.get('Status', 'N/A')
                jig_id = row_data.get('JigID', 'N/A')
                if status == 'pass':
                    self.lbl_status.config(text=f"PASS - {jig_id}", fg="green")
                    self.log_message(f"✅ ĐÃ LƯU THÀNH CÔNG: PASS ({jig_id})")
                else:
                    self.lbl_status.config(text=f"FAIL - {error_detail}", fg="red")
                    self.log_message(f"❌ ĐÃ LƯU THẤT BẠI: FAIL ({jig_id}) - {error_detail}")

                # Mở khóa các ô nhập để chuẩn bị cho test tiếp theo
                self.entry_checked_by.config(state=tk.NORMAL)
                self.entry_product_detail.config(state=tk.NORMAL)
                self.entry_liner.config(state=tk.NORMAL)
                # Giữ nguyên Checked By, Product Detail và Liner cho lần test tiếp theo
                 # Xóa Product Detail và Liner (giữ lại Checked By)
                self.product_detail_var.set("")
                self.liner_var.set("")
                # self.entry_product_detail.focus_set()
            except Exception as e:
                self.log_message(f"LỖI LƯU EXCEL: {e}")
                messagebox.showerror("Lỗi lưu file", f"Không thể lưu dữ liệu vào Excel:\n{e}")

    def process_json_result(self, json_str):
        try:
            data = json.loads(json_str)
            error_code = data.get('Error', 'UNKNOWN')
            error_detail = ERROR_DICT.get(error_code, "Mã lỗi không xác định")
            status = data.get('Status', 'N/A')
            jig_id = data.get('JigID', 'N/A')

            # Tạo một dictionary chứa toàn bộ dòng dữ liệu cần lưu (theo thứ tự cột mới)
            row_data = {
                'Timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                'JigID': jig_id,
                'Checked By': self.checked_by_var.get().strip(),
                'Liner': self.liner_var.get().strip(),
                'Product Detail': self.product_detail_var.get().strip(),
                'ResA': data.get('ResA', 0) / 100.0,
                'ResB': data.get('ResB', 0) / 100.0,
                'ResC': data.get('ResC', 0) / 100.0,
                'ResErr(%)': data.get('ResErr', 0) / 100.0,
                'NLLow': data.get('NLLow', 0) / 100.0,
                'NLHigh': data.get('NLHigh', 0) / 100.0,
                'NLAngle': data.get('NLAngle', 0) / 100.0,
                'PwrMin(%)': data.get('PwrMin', 0) / 100.0,
                'Error': error_code,
                'Status': status,
            }

            # Gọi hàm kiểm tra và lưu (nếu thiếu thông tin sẽ tự động hiện dialog)
            self.ensure_and_save(row_data, error_detail)

        except Exception as e:
            self.log_message(f"LỖI XỬ LÝ DỮ LIỆU JSON: {e}")
            self.log_message(f"RAW JSON LỖI: {json_str}")

if __name__ == "__main__":
    root = tk.Tk()
    app = GremsyQAApp(root)
    root.mainloop()

# -*- mode: python ; coding: utf-8 -*-

import os
import re
import shutil
import sys
from pathlib import Path


def configure_tcl_for_pyinstaller():
    """Repair a Python installer whose Tcl DLL and init.tcl exact gate disagree.

    Python 3.14 on the jig PC ships Tcl/Tk 8.6.15 DLLs and 8.6.15 scripts, but
    ``package require -exact`` fails before PyInstaller can inspect tkinter.
    Source execution is unaffected until a Tcl interpreter is created. Build
    a private script copy and relax only that bootstrap equality gate; never
    edit the installed Python runtime.
    """
    try:
        import tkinter
        tkinter.Tcl()
        return
    except Exception:
        pass

    tcl_source = Path(sys.base_prefix) / 'tcl' / 'tcl8.6'
    tk_source = Path(sys.base_prefix) / 'tcl' / 'tk8.6'
    patched_tcl = Path(SPECPATH) / 'build' / 'pyinstaller-tcl8.6'
    if not (tcl_source / 'init.tcl').is_file() or not tk_source.is_dir():
        raise RuntimeError('Tcl/Tk runtime is incomplete; repair Python before packaging')
    shutil.copytree(tcl_source, patched_tcl, dirs_exist_ok=True)
    init_path = patched_tcl / 'init.tcl'
    init_text = init_path.read_text(encoding='utf-8')
    init_text, replacements = re.subn(
        r'package require -exact Tcl [0-9.]+',
        'package require Tcl 8.6',
        init_text,
        count=1,
    )
    if replacements != 1:
        raise RuntimeError('Could not locate the Tcl exact-version bootstrap gate')
    init_path.write_text(init_text, encoding='utf-8', newline='\n')
    os.environ['TCL_LIBRARY'] = str(patched_tcl)
    os.environ['TK_LIBRARY'] = str(tk_source)


configure_tcl_for_pyinstaller()


a = Analysis(
    ['stm32_uart_flasher.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=['auto_log_analysis', 'analyze_motor_logs'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='STM32_UART_Flasher',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

"""
Raw COM5 reader using Win32 API - bypasses SetCommState issue.
Opens port, sets only timeouts (not baud/parity), reads raw bytes.
"""
import ctypes
from ctypes import wintypes
import time
import sys

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_ATTRIBUTE_NORMAL = 0x80
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

# Open COM5
handle = kernel32.CreateFileW(
    r'\\.\COM5',
    GENERIC_READ | GENERIC_WRITE,
    0, None,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    None
)

if handle == INVALID_HANDLE_VALUE:
    err = ctypes.get_last_error()
    print(f"FAIL: CreateFileW error {err}")
    sys.exit(1)

print(f"OK: Port opened, handle={handle}")

# Try SetCommState with current settings (don't change baud)
class DCB(ctypes.Structure):
    _fields_ = [
        ("DCBlength", wintypes.DWORD),
        ("BaudRate", wintypes.DWORD),
        ("fBinary", wintypes.DWORD, 1),
        ("fParity", wintypes.DWORD, 1),
        ("fOutxCtsFlow", wintypes.DWORD, 1),
        ("fOutxDsrFlow", wintypes.DWORD, 1),
        ("fDtrControl", wintypes.DWORD, 2),
        ("fDsrSensitivity", wintypes.DWORD, 1),
        ("fTXContinueOnXoff", wintypes.DWORD, 1),
        ("fOutX", wintypes.DWORD, 1),
        ("fInX", wintypes.DWORD, 1),
        ("fErrorChar", wintypes.DWORD, 1),
        ("fNull", wintypes.DWORD, 1),
        ("fRtsControl", wintypes.DWORD, 2),
        ("fAbortOnError", wintypes.DWORD, 1),
        ("fDummy2", wintypes.DWORD, 17),
        ("wReserved", wintypes.WORD),
        ("XonLim", wintypes.WORD),
        ("XoffLim", wintypes.WORD),
        ("ByteSize", wintypes.BYTE),
        ("Parity", wintypes.BYTE),
        ("StopBits", wintypes.BYTE),
        ("XonChar", ctypes.c_char),
        ("XoffChar", ctypes.c_char),
        ("ErrorChar", ctypes.c_char),
        ("EofChar", ctypes.c_char),
        ("EvtChar", ctypes.c_char),
        ("wReserved1", wintypes.WORD),
    ]

# Get current DCB
dcb = DCB()
dcb.DCBlength = ctypes.sizeof(DCB)

if kernel32.GetCommState(handle, ctypes.byref(dcb)):
    print(f"Current DCB: Baud={dcb.BaudRate}, ByteSize={dcb.ByteSize}, Parity={dcb.Parity}, StopBits={dcb.StopBits}")
    
    # Try to set specific baud rates
    for baud in [9600, 115200]:
        dcb.BaudRate = baud
        dcb.ByteSize = 8
        dcb.Parity = 0  # NOPARITY
        dcb.StopBits = 0  # ONESTOPBIT
        dcb.fBinary = 1
        dcb.fDtrControl = 1  # DTR_CONTROL_ENABLE
        dcb.fRtsControl = 1  # RTS_CONTROL_ENABLE
        
        result = kernel32.SetCommState(handle, ctypes.byref(dcb))
        if result:
            print(f"OK: SetCommState succeeded at {baud} baud!")
        else:
            err = ctypes.get_last_error()
            print(f"FAIL: SetCommState at {baud} error {err}")
else:
    err = ctypes.get_last_error()
    print(f"FAIL: GetCommState error {err}")

# Set timeouts
class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [
        ("ReadIntervalTimeout", wintypes.DWORD),
        ("ReadTotalTimeoutMultiplier", wintypes.DWORD),
        ("ReadTotalTimeoutConstant", wintypes.DWORD),
        ("WriteTotalTimeoutMultiplier", wintypes.DWORD),
        ("WriteTotalTimeoutConstant", wintypes.DWORD),
    ]

timeouts = COMMTIMEOUTS()
timeouts.ReadIntervalTimeout = 50
timeouts.ReadTotalTimeoutMultiplier = 0
timeouts.ReadTotalTimeoutConstant = 2000  # 2 sec timeout
timeouts.WriteTotalTimeoutMultiplier = 0
timeouts.WriteTotalTimeoutConstant = 1000

if kernel32.SetCommTimeouts(handle, ctypes.byref(timeouts)):
    print("OK: Timeouts set")
else:
    print(f"FAIL: SetCommTimeouts error {ctypes.get_last_error()}")

# Toggle DTR to reset Arduino
kernel32.EscapeCommFunction(handle, 6)  # CLRDTR
time.sleep(0.1)
kernel32.EscapeCommFunction(handle, 5)  # SETDTR
print("DTR toggled (Arduino reset)")
time.sleep(2)  # Wait for Arduino to boot

# Purge buffers
kernel32.PurgeComm(handle, 0x000F)  # PURGE_TXABORT|TXCLEAR|RXABORT|RXCLEAR

# Read data
buf = ctypes.create_string_buffer(4096)
bytes_read = wintypes.DWORD()

print("\nReading data (5 attempts, 2 sec each)...")
for i in range(5):
    result = kernel32.ReadFile(handle, buf, 4096, ctypes.byref(bytes_read), None)
    n = bytes_read.value
    if n > 0:
        raw = buf.raw[:n]
        print(f"\n=== Read #{i+1}: {n} bytes ===")
        # Try decode as ASCII
        try:
            text = raw.decode('ascii', errors='replace')
            print(text)
        except:
            print(f"Raw hex: {raw.hex()}")
    else:
        print(f"Read #{i+1}: 0 bytes (timeout)")

# Close handle
kernel32.CloseHandle(handle)
print("\nDone.")

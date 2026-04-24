"""Attempt to communicate with COM3 using raw Win32 API."""
import ctypes
import ctypes.wintypes as wt
import time
import struct

kernel32 = ctypes.windll.kernel32

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_ATTRIBUTE_NORMAL = 0x80
INVALID_HANDLE_VALUE = -1

# Open COM3 directly via Win32
port = r"\\.\COM3"
print(f"Opening {port} via Win32 CreateFile...")

handle = kernel32.CreateFileW(
    port,
    GENERIC_READ | GENERIC_WRITE,
    0,  # no sharing
    None,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    None
)

if handle == INVALID_HANDLE_VALUE or handle == ctypes.c_void_p(-1).value:
    err = kernel32.GetLastError()
    print(f"CreateFile failed, error code: {err}")
    
    # Try read-only
    print(f"\nTrying read-only...")
    handle = kernel32.CreateFileW(
        port,
        GENERIC_READ,
        0,
        None,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        None
    )
    if handle == INVALID_HANDLE_VALUE or handle == ctypes.c_void_p(-1).value:
        err = kernel32.GetLastError()
        print(f"Read-only also failed, error: {err}")
        exit(1)

print(f"Handle opened: {handle}")

# Set up DCB (baud rate etc)
class DCB(ctypes.Structure):
    _fields_ = [
        ("DCBlength", wt.DWORD),
        ("BaudRate", wt.DWORD),
        ("fBinary", wt.DWORD),  # bit fields packed
        ("wReserved", wt.WORD),
        ("XonLim", wt.WORD),
        ("XoffLim", wt.WORD),
        ("ByteSize", wt.BYTE),
        ("Parity", wt.BYTE),
        ("StopBits", wt.BYTE),
        ("XonChar", ctypes.c_char),
        ("XoffChar", ctypes.c_char),
        ("ErrorChar", ctypes.c_char),
        ("EofChar", ctypes.c_char),
        ("EvtChar", ctypes.c_char),
        ("wReserved1", wt.WORD),
    ]

class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [
        ("ReadIntervalTimeout", wt.DWORD),
        ("ReadTotalTimeoutMultiplier", wt.DWORD),
        ("ReadTotalTimeoutConstant", wt.DWORD),
        ("WriteTotalTimeoutMultiplier", wt.DWORD),
        ("WriteTotalTimeoutConstant", wt.DWORD),
    ]

# Try setting timeouts
timeouts = COMMTIMEOUTS()
timeouts.ReadIntervalTimeout = 50
timeouts.ReadTotalTimeoutMultiplier = 10
timeouts.ReadTotalTimeoutConstant = 3000
timeouts.WriteTotalTimeoutMultiplier = 10
timeouts.WriteTotalTimeoutConstant = 3000

result = kernel32.SetCommTimeouts(handle, ctypes.byref(timeouts))
print(f"SetCommTimeouts: {'OK' if result else f'FAIL (err={kernel32.GetLastError()})'}")

# Try to purge and read
PURGE_RXCLEAR = 0x0008
kernel32.PurgeComm(handle, PURGE_RXCLEAR)

# Set DTR
EscapeCommFunction = kernel32.EscapeCommFunction
SETDTR = 5
result = EscapeCommFunction(handle, SETDTR)
print(f"Set DTR: {'OK' if result else f'FAIL (err={kernel32.GetLastError()})'}")

print(f"\nWaiting 3s for Arduino reset...")
time.sleep(3)

# Read data
buf = ctypes.create_string_buffer(4096)
bytes_read = wt.DWORD(0)

print(f"\nReading data...")
for attempt in range(10):
    result = kernel32.ReadFile(handle, buf, 4096, ctypes.byref(bytes_read), None)
    if result and bytes_read.value > 0:
        raw = buf.raw[:bytes_read.value]
        print(f"\n  Read {bytes_read.value} bytes:")
        # Try text decode
        try:
            text = raw.decode('utf-8', errors='replace')
            for line in text.split('\n'):
                line = line.strip()
                if line:
                    print(f"    TEXT: {line}")
        except:
            pass
        # Also show hex
        print(f"    HEX:  {raw[:100].hex()}")
    else:
        err = kernel32.GetLastError()
        print(f"  Attempt {attempt}: no data (result={result}, err={err})")
    time.sleep(0.5)

kernel32.CloseHandle(handle)
print("\nDone.")

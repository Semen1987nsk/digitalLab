"""
Last resort COM3 fix attempt:
1. Try BuildCommDCB API (different path to SetCommState)
2. Try DeviceIoControl directly with IOCTL_SERIAL_SET_BAUD_RATE
"""
import ctypes
from ctypes import wintypes
import struct
import time

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

PORT = r'\\.\COM3'

h = kernel32.CreateFileW(PORT, 0xC0000000, 0, None, 3, 0x80, None)
if h == ctypes.c_void_p(-1).value:
    print(f"Cannot open: {ctypes.get_last_error()}")
    exit()
print(f"Opened COM3, handle={h}")

# Method 1: BuildCommDCBW + SetCommState
print("\n=== Method 1: BuildCommDCBW ===")
class DCB(ctypes.Structure):
    _fields_ = [
        ("DCBlength", wintypes.DWORD),
        ("BaudRate", wintypes.DWORD),
        ("flags", wintypes.DWORD),
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

dcb = DCB()
dcb.DCBlength = ctypes.sizeof(DCB)

# BuildCommDCBW builds a DCB from a device-control string
for baud_str in ["9600,n,8,1", "115200,n,8,1"]:
    dcb2 = DCB()
    dcb2.DCBlength = ctypes.sizeof(DCB)
    r = kernel32.BuildCommDCBW(baud_str, ctypes.byref(dcb2))
    if r:
        print(f"  BuildCommDCB('{baud_str}'): OK, Baud={dcb2.BaudRate} ByteSize={dcb2.ByteSize}")
        r2 = kernel32.SetCommState(h, ctypes.byref(dcb2))
        err = ctypes.get_last_error()
        print(f"  SetCommState: {'OK' if r2 else f'FAIL err={err}'}")
    else:
        print(f"  BuildCommDCB('{baud_str}'): FAIL err={ctypes.get_last_error()}")

# Method 2: DeviceIoControl with IOCTL_SERIAL_SET_BAUD_RATE
print("\n=== Method 2: DeviceIoControl IOCTL_SERIAL_SET_BAUD_RATE ===")
# IOCTL_SERIAL_SET_BAUD_RATE = CTL_CODE(FILE_DEVICE_SERIAL_PORT, 1, METHOD_BUFFERED, FILE_ANY_ACCESS)
# FILE_DEVICE_SERIAL_PORT = 0x1B
# CTL_CODE(0x1B, 1, 0, 0) = (0x1B << 16) | (0 << 14) | (1 << 2) | 0 = 0x001B0004
IOCTL_SERIAL_SET_BAUD_RATE = 0x001B0004
IOCTL_SERIAL_SET_LINE_CONTROL = 0x001B000C
IOCTL_SERIAL_GET_BAUD_RATE = 0x001B0050
IOCTL_SERIAL_GET_LINE_CONTROL = 0x001B0054

# Get current baud rate
baud_buf = ctypes.create_string_buffer(4)
bytes_returned = wintypes.DWORD()
r = kernel32.DeviceIoControl(h, IOCTL_SERIAL_GET_BAUD_RATE, None, 0, baud_buf, 4, ctypes.byref(bytes_returned), None)
if r:
    current_baud = struct.unpack('<I', baud_buf.raw[:4])[0]
    print(f"  Current baud: {current_baud}")
else:
    print(f"  GET_BAUD_RATE failed: {ctypes.get_last_error()}")

# Try to set baud rate via IOCTL
for baud in [9600, 115200]:
    baud_data = struct.pack('<I', baud)
    r = kernel32.DeviceIoControl(h, IOCTL_SERIAL_SET_BAUD_RATE, baud_data, 4, None, 0, ctypes.byref(bytes_returned), None)
    err = ctypes.get_last_error()
    print(f"  SET_BAUD_RATE({baud}): {'OK' if r else f'FAIL err={err}'}")

# Try set line control (8N1)
# SERIAL_LINE_CONTROL: StopBits=STOP_BIT_1(0), Parity=NO_PARITY(0), WordLength=8
line_ctrl = struct.pack('<BBB', 0, 0, 8)  # StopBits, Parity, WordLength
r = kernel32.DeviceIoControl(h, IOCTL_SERIAL_SET_LINE_CONTROL, line_ctrl, 3, None, 0, ctypes.byref(bytes_returned), None)
err = ctypes.get_last_error()
print(f"  SET_LINE_CONTROL(8N1): {'OK' if r else f'FAIL err={err}'}")

# If any IOCTL worked, try reading
print("\n=== Reading data after IOCTL ===")

class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [("RI",wintypes.DWORD),("RTM",wintypes.DWORD),("RTC",wintypes.DWORD),("WTM",wintypes.DWORD),("WTC",wintypes.DWORD)]
t = COMMTIMEOUTS(50, 0, 2000, 0, 1000)
kernel32.SetCommTimeouts(h, ctypes.byref(t))

# Reset Arduino
kernel32.EscapeCommFunction(h, 6)
time.sleep(0.1)
kernel32.EscapeCommFunction(h, 5)
time.sleep(2.5)
kernel32.PurgeComm(h, 0xF)

buf = ctypes.create_string_buffer(2048)
br = wintypes.DWORD()
for i in range(3):
    kernel32.ReadFile(h, buf, 2048, ctypes.byref(br), None)
    n = br.value
    if n > 0:
        print(f"  Read {n} bytes: {buf.raw[:min(n,100)]}")
    else:
        print(f"  Read {i+1}: 0 bytes")

kernel32.CloseHandle(h)
print("\nDone.")

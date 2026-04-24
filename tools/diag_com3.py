"""
Arduino UNO COM3 diagnostic tool.
Tries multiple approaches to communicate with the Arduino.
"""
import ctypes
from ctypes import wintypes
import time
import sys

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

PORT = r'\\.\COM3'
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000

print("=" * 60)
print("  Arduino UNO COM3 Diagnostic Tool")
print("=" * 60)

# Open port
h = kernel32.CreateFileW(PORT, GENERIC_READ | GENERIC_WRITE, 0, None, 3, 0x80, None)
if h == ctypes.c_void_p(-1).value:
    print(f"FAIL: Cannot open {PORT}, error {ctypes.get_last_error()}")
    sys.exit(1)
print(f"[OK] Port opened, handle={h}")

# Set timeouts
class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [
        ("ReadIntervalTimeout", wintypes.DWORD),
        ("ReadTotalTimeoutMultiplier", wintypes.DWORD),
        ("ReadTotalTimeoutConstant", wintypes.DWORD),
        ("WriteTotalTimeoutMultiplier", wintypes.DWORD),
        ("WriteTotalTimeoutConstant", wintypes.DWORD),
    ]

t = COMMTIMEOUTS(50, 0, 3000, 0, 1000)
r = kernel32.SetCommTimeouts(h, ctypes.byref(t))
print(f"[{'OK' if r else 'FAIL'}] SetCommTimeouts")

# Check comm properties
class COMMPROP(ctypes.Structure):
    _fields_ = [
        ("wPacketLength", wintypes.WORD),
        ("wPacketVersion", wintypes.WORD),
        ("dwServiceMask", wintypes.DWORD),
        ("dwReserved1", wintypes.DWORD),
        ("dwMaxTxQueue", wintypes.DWORD),
        ("dwMaxRxQueue", wintypes.DWORD),
        ("dwMaxBaud", wintypes.DWORD),
        ("dwProvSubType", wintypes.DWORD),
        ("dwProvCapabilities", wintypes.DWORD),
        ("dwSettableParams", wintypes.DWORD),
        ("dwSettableBaud", wintypes.DWORD),
        ("wSettableData", wintypes.WORD),
        ("wSettableStopParity", wintypes.WORD),
        ("dwCurrentTxQueue", wintypes.DWORD),
        ("dwCurrentRxQueue", wintypes.DWORD),
        ("dwProvSpec1", wintypes.DWORD),
        ("dwProvSpec2", wintypes.DWORD),
        ("wcProvChar", wintypes.WCHAR * 1),
    ]

prop = COMMPROP()
r = kernel32.GetCommProperties(h, ctypes.byref(prop))
if r:
    print(f"[OK] CommProperties: MaxBaud={prop.dwMaxBaud}, ProvSubType={prop.dwProvSubType}")
    print(f"     SettableBaud=0x{prop.dwSettableBaud:08X}, SettableData=0x{prop.wSettableData:04X}")
    print(f"     ProvCapabilities=0x{prop.dwProvCapabilities:08X}")
else:
    print(f"[FAIL] GetCommProperties error {ctypes.get_last_error()}")

# Try toggling DTR/RTS to reset
print("\n--- Resetting Arduino via DTR ---")
kernel32.EscapeCommFunction(h, 6)  # CLRDTR
time.sleep(0.25)
kernel32.EscapeCommFunction(h, 5)  # SETDTR
print("DTR toggled, waiting 2.5s for bootloader...")
time.sleep(2.5)

# Purge
kernel32.PurgeComm(h, 0xF)

# Read attempts
buf = ctypes.create_string_buffer(4096)
br = wintypes.DWORD()

print("\n--- Reading data (3x 3 sec) ---")
for i in range(3):
    kernel32.ReadFile(h, buf, 4096, ctypes.byref(br), None)
    n = br.value
    if n > 0:
        raw = buf.raw[:n]
        print(f"[READ {i+1}] {n} bytes:")
        try:
            print(f"  ASCII: {raw.decode('ascii', errors='replace')[:200]}")
        except:
            pass
        print(f"  HEX: {raw[:50].hex()}")
    else:
        print(f"[READ {i+1}] 0 bytes (timeout)")

# Try writing STK500v1 sync command (0x30 0x20) - the bootloader expects this
print("\n--- Trying STK500v1 sync ---")
# Reset again
kernel32.EscapeCommFunction(h, 6)  # CLRDTR
time.sleep(0.25)
kernel32.EscapeCommFunction(h, 5)  # SETDTR
time.sleep(0.5)  # Short delay to catch bootloader

sync_cmd = bytes([0x30, 0x20])  # Cmnd_STK_GET_SYNC + Sync_CRC_EOP
written = wintypes.DWORD()
for attempt in range(5):
    kernel32.WriteFile(h, sync_cmd, len(sync_cmd), ctypes.byref(written), None)
    time.sleep(0.1)
    kernel32.ReadFile(h, buf, 256, ctypes.byref(br), None)
    n = br.value
    if n > 0:
        print(f"  Sync attempt {attempt+1}: Got {n} bytes: {buf.raw[:n].hex()}")
        if buf.raw[0:1] == b'\x14' and buf.raw[1:2] == b'\x10':
            print("  >>> STK500 RESPONSE DETECTED! Bootloader is alive!")
            break
    else:
        print(f"  Sync attempt {attempt+1}: no response")

kernel32.CloseHandle(h)
print("\nDone.")

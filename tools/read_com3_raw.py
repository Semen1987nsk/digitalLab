"""Read COM3 raw - open handle, skip SetCommState, just read."""
import ctypes
import ctypes.wintypes as wt
import time

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
INVALID_HANDLE_VALUE = wt.HANDLE(-1).value

print("=== RAW COM3 Reader (no SetCommState) ===\n")

handle = kernel32.CreateFileW(
    r"\\.\COM3",
    GENERIC_READ | GENERIC_WRITE,
    0, None, OPEN_EXISTING, 0, None
)
if handle == INVALID_HANDLE_VALUE:
    print(f"CreateFile FAILED: {ctypes.get_last_error()}")
    exit(1)
print(f"Handle: {handle}")

# Set only timeouts (this usually works even when SetCommState fails)
class COMMTIMEOUTS(ctypes.Structure):
    _fields_ = [
        ("ReadIntervalTimeout", wt.DWORD),
        ("ReadTotalTimeoutMultiplier", wt.DWORD),
        ("ReadTotalTimeoutConstant", wt.DWORD),
        ("WriteTotalTimeoutMultiplier", wt.DWORD),
        ("WriteTotalTimeoutConstant", wt.DWORD),
    ]

to = COMMTIMEOUTS(50, 0, 2000, 0, 1000)
r = kernel32.SetCommTimeouts(handle, ctypes.byref(to))
print(f"SetCommTimeouts: {'OK' if r else f'FAIL err={ctypes.get_last_error()}'}")

# Toggle DTR to reset Arduino
kernel32.EscapeCommFunction(handle, 6)  # CLRDTR
time.sleep(0.1)
kernel32.EscapeCommFunction(handle, 5)  # SETDTR
print("DTR toggled, waiting 3s for Arduino boot...")
time.sleep(3)

# Purge buffers
kernel32.PurgeComm(handle, 0x000F)

# Read raw data
buf = ctypes.create_string_buffer(4096)
bytesRead = wt.DWORD(0)
total = b""

print("\nReading...\n")
for i in range(8):
    ok = kernel32.ReadFile(handle, buf, 4096, ctypes.byref(bytesRead), None)
    n = bytesRead.value
    if n > 0:
        chunk = buf.raw[:n]
        total += chunk
        # Try decode as text
        text = chunk.decode('utf-8', errors='replace').strip()
        if text:
            for line in text.split('\n'):
                print(f"  [{i}] {line.strip()}")
        else:
            print(f"  [{i}] {n} bytes (binary): {chunk[:60].hex()}")
    else:
        err = ctypes.get_last_error()
        print(f"  [{i}] no data (ok={ok}, err={err})")
    time.sleep(0.3)

kernel32.CloseHandle(handle)

print(f"\n=== Total: {len(total)} bytes ===")
if total:
    print(f"HEX: {total[:200].hex()}")
    print(f"TXT: {total[:200].decode('utf-8', errors='replace')}")
else:
    print("No data received. Possible issues:")
    print("  1. Arduino has no sketch loaded (blank)")
    print("  2. Sketch doesn't print to Serial")  
    print("  3. Wrong baud rate (port default != sketch baud)")
    print("  4. USB cable is charge-only (no data)")
    print("  5. ATmega16U2 firmware issue")

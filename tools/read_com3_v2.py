"""Read COM3 (Arduino Mega 2560) - multiple approaches."""
import ctypes
import ctypes.wintypes as wt
import time
import sys

kernel32 = ctypes.windll.kernel32

GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
FILE_ATTRIBUTE_NORMAL = 0x80

def try_read_com3():
    port = r"\\.\COM3"
    print(f"=== Opening {port} via Win32 ===")
    
    handle = kernel32.CreateFileW(
        port,
        GENERIC_READ | GENERIC_WRITE,
        0, None, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, None
    )
    
    err = ctypes.get_last_error()
    if handle == -1 or handle == 0xFFFFFFFF:
        print(f"FAIL: CreateFile error {err}")
        # Try read-only
        handle = kernel32.CreateFileW(
            port, GENERIC_READ, 0, None, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, None
        )
        if handle == -1 or handle == 0xFFFFFFFF:
            print(f"FAIL read-only too, error {ctypes.get_last_error()}")
            return
    
    print(f"OK: handle = {handle}")
    
    # Set timeouts (critical to avoid hanging!)
    class COMMTIMEOUTS(ctypes.Structure):
        _fields_ = [
            ("ReadIntervalTimeout", wt.DWORD),
            ("ReadTotalTimeoutMultiplier", wt.DWORD),
            ("ReadTotalTimeoutConstant", wt.DWORD),
            ("WriteTotalTimeoutMultiplier", wt.DWORD),
            ("WriteTotalTimeoutConstant", wt.DWORD),
        ]
    
    timeouts = COMMTIMEOUTS()
    timeouts.ReadIntervalTimeout = 50
    timeouts.ReadTotalTimeoutMultiplier = 0
    timeouts.ReadTotalTimeoutConstant = 2000  # 2 sec max wait
    timeouts.WriteTotalTimeoutMultiplier = 0
    timeouts.WriteTotalTimeoutConstant = 1000
    
    r = kernel32.SetCommTimeouts(handle, ctypes.byref(timeouts))
    print(f"SetCommTimeouts: {'OK' if r else 'FAIL'}")
    
    # Set baud rate via BuildCommDCBW + SetCommState
    class DCB(ctypes.Structure):
        _fields_ = [
            ("DCBlength", wt.DWORD),
            ("BaudRate", wt.DWORD),
            ("flags", wt.DWORD),
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
    
    for baud in [9600, 115200, 57600]:
        print(f"\n--- Trying {baud} baud ---")
        
        dcb = DCB()
        dcb.DCBlength = ctypes.sizeof(DCB)
        kernel32.GetCommState(handle, ctypes.byref(dcb))
        dcb.BaudRate = baud
        dcb.ByteSize = 8
        dcb.Parity = 0   # NOPARITY
        dcb.StopBits = 0  # ONESTOPBIT
        dcb.flags = 1     # fBinary = 1
        
        r = kernel32.SetCommState(handle, ctypes.byref(dcb))
        if not r:
            print(f"  SetCommState FAIL (err={ctypes.get_last_error()})")
            continue
        
        # Toggle DTR to reset Arduino
        kernel32.EscapeCommFunction(handle, 6)  # CLRDTR
        time.sleep(0.1)
        kernel32.EscapeCommFunction(handle, 5)  # SETDTR
        time.sleep(2.5)  # Wait for Arduino bootloader
        
        # Purge
        kernel32.PurgeComm(handle, 0x000F)
        
        # Read
        buf = ctypes.create_string_buffer(4096)
        bytes_read = wt.DWORD(0)
        all_data = b""
        
        for i in range(5):
            r = kernel32.ReadFile(handle, buf, 4096, ctypes.byref(bytes_read), None)
            if bytes_read.value > 0:
                chunk = buf.raw[:bytes_read.value]
                all_data += chunk
                try:
                    text = chunk.decode('utf-8', errors='replace')
                    for line in text.strip().split('\n'):
                        if line.strip():
                            print(f"  [{i}] {line.strip()}")
                except:
                    print(f"  [{i}] HEX: {chunk[:80].hex()}")
            else:
                print(f"  [{i}] (no data)")
            time.sleep(0.3)
        
        if all_data:
            print(f"\n  TOTAL: {len(all_data)} bytes at {baud} baud")
            print(f"  First 200 chars: {all_data[:200]}")
            # Don't try other bauds
            break
        else:
            print(f"  No data at {baud}")
    
    kernel32.CloseHandle(handle)
    print("\nDone.")

if __name__ == "__main__":
    try_read_com3()

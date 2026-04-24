"""Quick script to read data from multisensor on COM3 (Arduino Mega 2560)."""
import serial
import time
import sys

PORT = "COM3"
BAUDS = [9600, 115200, 57600, 38400, 19200, 4800]

def try_baud(baud, duration=4):
    """Try reading at a specific baud rate."""
    print(f"\n{'='*60}")
    print(f"Trying {PORT} @ {baud} baud...")
    print(f"{'='*60}")
    try:
        ser = serial.Serial(PORT, baud, timeout=2, dsrdtr=True, rtscts=False)
        time.sleep(2.5)  # Wait for Arduino reset after DTR
        
        # Flush any garbage
        ser.reset_input_buffer()
        
        start = time.time()
        lines_read = 0
        raw_bytes = b""
        
        while time.time() - start < duration:
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                raw_bytes += data
                try:
                    text = data.decode('utf-8', errors='replace')
                    for line in text.split('\n'):
                        line = line.strip()
                        if line:
                            print(f"  [{lines_read}] {line}")
                            lines_read += 1
                except:
                    print(f"  [RAW] {data.hex()}")
            else:
                time.sleep(0.05)
        
        ser.close()
        
        if lines_read == 0 and raw_bytes:
            print(f"  Raw bytes ({len(raw_bytes)}): {raw_bytes[:200].hex()}")
        elif lines_read == 0:
            print(f"  No data received at {baud} baud")
        
        return lines_read > 0
        
    except serial.SerialException as e:
        print(f"  Error: {e}")
        return False
    except Exception as e:
        print(f"  Error: {e}")
        return False

if __name__ == "__main__":
    print(f"Multisensor Reader — Scanning {PORT}")
    print(f"Device: Arduino Mega 2560 (VID:2341 PID:0043)")
    
    for baud in BAUDS:
        found = try_baud(baud)
        if found:
            print(f"\n*** SUCCESS at {baud} baud! ***")
            # Read more data at this baud rate
            print(f"\nReading more data at {baud}...")
            try_baud(baud, duration=8)
            break
    else:
        print("\nNo readable data at any baud rate.")

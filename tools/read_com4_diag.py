"""Read raw data from COM4 (FTDI distance sensor V802) to diagnose 0 Hz issue."""
import serial
import time

PORT = 'COM4'
BAUD = 9600
DURATION = 8

try:
    s = serial.Serial(PORT, BAUD, timeout=2)
    print(f'Port {PORT} opened at {BAUD} baud. Reading for {DURATION}s...')
    start = time.time()
    count = 0
    while time.time() - start < DURATION:
        line = s.readline()
        if line:
            count += 1
            raw = line.rstrip()
            try:
                decoded = raw.decode('utf-8', errors='replace')
            except:
                decoded = str(raw)
            print(f'  [{count:3d}] len={len(raw):3d}  hex={raw[:20].hex()}  text="{decoded}"')
        else:
            print(f'  (timeout - no data within 2s)')
    print(f'\nTotal lines received: {count}')
    s.close()
except Exception as e:
    print(f'Error: {e}')

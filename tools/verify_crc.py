"""Verify CRC8 from Arduino firmware output."""
import serial
import time

def crc8_maxim(data: bytes) -> int:
    crc = 0x00
    for b in data:
        for _ in range(8):
            if (crc ^ b) & 0x01:
                crc = (crc >> 1) ^ 0x8C
            else:
                crc >>= 1
            b >>= 1
    return crc

def main():
    print("Opening COM3...")
    ser = serial.Serial('COM3', 115200, timeout=2)
    ser.dtr = True
    time.sleep(3)
    ser.reset_input_buffer()
    time.sleep(1.5)

    ok = 0
    fail = 0
    lines_checked = 0

    raw = ser.read(ser.in_waiting or 1024).decode('ascii', errors='replace')
    for line in raw.split('\n'):
        line = line.strip()
        if not line.startswith('V:') or '*' not in line:
            continue
        idx = line.rfind('*')
        data_part = line[:idx]
        crc_hex = line[idx+1:]
        try:
            expected = int(crc_hex, 16)
        except ValueError:
            continue

        computed = crc8_maxim(data_part.encode('ascii'))
        match = "OK" if computed == expected else "FAIL"
        if computed == expected:
            ok += 1
        else:
            fail += 1
        lines_checked += 1
        print(f"  [{match}] CRC={crc_hex} computed={computed:02X} | ...{data_part[-30:]}")
        if lines_checked >= 8:
            break

    ser.close()
    print(f"\nResult: {ok} OK, {fail} FAIL out of {lines_checked} lines")
    if fail == 0 and ok > 0:
        print("CRC8 VERIFICATION PASSED!")
    elif fail > 0:
        print("CRC8 MISMATCH DETECTED!")

if __name__ == '__main__':
    main()

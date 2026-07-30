#!/usr/bin/env python3
"""Load firmware.bin to RiscV WebSoC via UART.
Protocol: sw<8-hex-addr><8-hex-data>\r
"""
import serial, sys, time, struct

PORT = '/dev/ttyACM0'
BAUD = 115200
BASE_ADDR = 0x10000  # instruction RAM base

def load(firmware_bin, port=PORT, baud=BAUD, base=BASE_ADDR):
    with open(firmware_bin, 'rb') as f:
        data = f.read()

    # Pad to 4-byte boundary
    while len(data) % 4:
        data += b'\x00'

    ser = serial.Serial(port, baud, timeout=1)
    print(f"Loading {len(data)} bytes ({len(data)//4} words) to 0x{base:08X}...")

    for i in range(0, len(data), 4):
        word = struct.unpack('<I', data[i:i+4])[0]
        addr = base + i
        cmd = f"sw{addr:08X}{word:08X}\r"
        ser.write(cmd.encode())
        time.sleep(0.0005)  # ~4 bits at 115200

        if (i // 4) % 100 == 0:
            print(f"  {i//4}/{len(data)//4} words...")

    ser.close()
    print(f"Done! {len(data)//4} words loaded.")

if __name__ == '__main__':
    fw = sys.argv[1] if len(sys.argv) > 1 else '/home/minkey/work/RiscV_WebSoC_v1/RiscV_WebSoC/c_build/out/firmware.bin'
    load(fw)

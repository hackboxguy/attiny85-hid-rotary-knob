# ATtiny85 HID Rotary Knob

Turn a Digispark ATtiny85 USB dongle into a USB volume control knob for PCs.

Rotate the knob to adjust volume, press to mute. Works as a standard USB HID
Consumer Control device - no drivers needed on any OS.

![Volume Control Knob](doc/images/volume-control-knob.jpg)

## Hardware Required

- [Digispark ATtiny85 USB development board](http://digistump.com/products/1)
- [KY-040 Rotary Encoder module](https://www.amazon.de/-/en/AZDelivery-KY-040-Encoder-Compatible-Arduino/dp/B07CMSHWV6)

![Required Items](doc/images/required-items.jpg)

## Wiring

![Connection Diagram](doc/images/connection-diagram.jpg)

```
                     +-\/-+
ENC_A (CLK)    PB5  1|    |8  Vcc
USB D-         PB3  2|    |7  PB2    ENC_B (DT)
USB D+         PB4  3|    |6  PB1
               GND  4|    |5  PB0    ENC_SW (SW)
                     +----+
```

| Rotary Encoder | Digispark ATtiny85 |
|----------------|:------------------:|
| CLK            | P5                 |
| DT             | P2                 |
| SW             | P0                 |
| +              | 5V                 |
| GND            | GND                |

## Building from Source

### Prerequisites

```bash
sudo apt install gcc-avr avr-libc binutils-avr
```

### Compile

```bash
make hex
```

This produces `main.hex` and copies it to `hex/attiny85-volume-control-hid.hex`.

## Flashing

### Option A: Micronucleus (for boards with bootloader)

1. Clone and build the micronucleus command-line tool:
   ```bash
   sudo apt install libusb-dev
   git clone https://github.com/micronucleus/micronucleus.git
   cd micronucleus/commandline
   make
   ```

2. (Optional) Update to the latest micronucleus bootloader v2.6:
   ```bash
   sudo ./micronucleus --run ../firmware/upgrades/upgrade-t85_default.hex
   # Insert Digispark when prompted, then remove after flashing
   ```

3. Flash the volume control firmware:
   ```bash
   sudo ./micronucleus --run /path/to/hex/attiny85-volume-control-hid.hex
   # Insert Digispark when prompted
   ```

4. Rotate or press the knob to control your PC's volume.

### Option B: ISP Programmer (avrdude + usbasp)

```bash
make flash               # flash firmware only
make fuse                # program fuse bits
make program             # flash firmware + fuse bits
```

Override the programmer if needed:
```bash
make flash PROGRAMMER="-c usbasp"
```

## Troubleshooting

1. Run `dmesg` after plugging in the Digispark. If you see `device descriptor read/64, error -71`:
2. Re-flash the micronucleus bootloader via ISP:
   ```bash
   sudo avrdude -c usbasp -p t85 \
     -U flash:w:upgrade-t85_default.hex \
     -U lfuse:w:0xe1:m -U hfuse:w:0x5d:m -U efuse:w:0xfe:m
   ```
3. Then retry the micronucleus flashing steps above.

## Credits

Based on [tinyKnob](https://github.com/wagiminator/ATtiny85-TinyKnob) by Stefan Wagner (2020).
Uses the [V-USB](https://www.obdev.at/products/vusb/) software USB stack.

## License

Firmware source: [CC BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/)
V-USB library: GNU GPL v2 / v3 (see `usbdrv/License.txt`)

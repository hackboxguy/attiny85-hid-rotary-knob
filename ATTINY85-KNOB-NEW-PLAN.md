# ATtiny85 HID Rotary Knob - Restructuring & Improvement Plan

## Overview

Restructure and improve the Digispark ATtiny85 USB HID volume-control-knob firmware
from the original monorepo (`brbox/sources/firmware/attiny85-hid-rotary/`) into a
clean, standalone repository with bug fixes and code quality improvements.

Original source: https://github.com/wagiminator/ATtiny85-TinyKnob
License: CC BY-SA 3.0

## Decision Log

- **Build system:** Clean Makefile (no CMake, no PlatformIO)
- **USB stack:** V-USB (vendored copy) - the only software USB stack for ATtiny85;
  unmaintained upstream (last commit 2020) but stable and battle-tested.
  No modern alternative exists for this chip.
- **Framework:** Bare-metal C (no Arduino) - more reliable than the abandoned
  Digispark/Trinket Arduino HID libraries
- **Future path:** If hardware modernization is desired later, CH552E
  (native USB, ~$0.50) or RP2040 (TinyUSB) are the natural successors.
  See: https://github.com/wagiminator/CH552-USB-Knob

---

## 1. Proposed Directory Structure

```
attiny85-hid-rotary-knob/
├── README.md                       # Comprehensive project docs (merged from old README.md + readme.txt)
├── LICENSE                         # Multi-license (CC BY-SA 3.0 / GPL / MIT)
├── .gitignore                      # Ignore *.o, *.elf, *.hex (build artifacts)
├── Makefile                        # Clean, well-documented build system
├── src/
│   ├── main.c                      # Refactored firmware (encoder + USB HID logic)
│   └── usbconfig.h                 # V-USB configuration for ATtiny85/Digispark
├── usbdrv/                         # V-USB library (vendored copy, v2012-01-09)
│   ├── usbdrv.c
│   ├── usbdrv.h
│   ├── usbdrvasm.S
│   ├── usbdrvasm.asm
│   ├── usbdrvasm12.inc
│   ├── usbdrvasm128.inc
│   ├── usbdrvasm15.inc
│   ├── usbdrvasm16.inc
│   ├── usbdrvasm165.inc
│   ├── usbdrvasm18-crc.inc
│   ├── usbdrvasm20.inc
│   ├── asmcommon.inc
│   ├── oddebug.c
│   ├── oddebug.h
│   ├── osccal.h
│   ├── usbportability.h
│   ├── usbconfig-prototype.h
│   ├── License.txt
│   ├── CommercialLicense.txt
│   ├── Changelog.txt
│   ├── Readme.txt
│   ├── USB-IDs-for-free.txt
│   └── USB-ID-FAQ.txt
├── hex/
│   └── attiny85-volume-control-hid.hex   # Pre-built firmware binary
└── doc/
    └── images/
        ├── volume-control-knob.jpg
        ├── required-items.jpg
        └── connection-diagram.jpg
```

### Rationale

- **`src/`** separates project source from the vendored library, making it clear what
  is "ours" vs third-party.
- **`usbdrv/`** stays at root level (not under `lib/`) because V-USB's build expects
  `#include "usbdrv.h"` and keeping it at root simplifies include paths for the
  Makefile without requiring `-I` gymnastics. This matches the canonical V-USB project
  layout used in upstream examples.
- **`hex/`** renamed from `hexfiles/` for brevity.
- **`doc/images/`** keeps documentation assets organized and out of the root.
- No CMake: for a project with 1 source file + V-USB library targeting a single MCU,
  a clean Makefile is the right tool. CMake would require a custom AVR toolchain file
  and adds complexity with zero benefit here.

---

## 2. Build System (Makefile) Improvements

### Current issues
- Header comment says "hid-mouse example" (copy-paste leftover)
- `AVRDUDE` programmer path hardcoded to `/dev/ttyACM0`
- No `.PHONY` declarations
- Include paths need updating for new directory structure

### New Makefile plan

```makefile
# Project: ATtiny85 HID Volume Control Knob
# Hardware: Digispark ATtiny85
# USB Stack: V-USB (https://www.obdev.at/products/vusb/)

# --- Configuration ---
DEVICE     = attiny85
F_CPU      = 16500000
FUSE_L     = 0xE1
FUSE_H     = 0x5D  # RSTDISBL programmed: PB5 is GPIO

# Programmer: override on command line if needed
#   e.g.: make flash PROGRAMMER="-c usbasp"
SERIAL_PORT ?= /dev/ttyACM0
PROGRAMMER  ?= -c stk500v1 -b 19200 -P $(SERIAL_PORT)
AVRDUDE     = avrdude $(PROGRAMMER) -p $(DEVICE)

# --- Toolchain ---
CC       = avr-gcc
OBJCOPY  = avr-objcopy
SIZE     = avr-size

CFLAGS   = -Wall -Os -DF_CPU=$(F_CPU) -mmcu=$(DEVICE) -Iusbdrv -Isrc -DDEBUG_LEVEL=0
LDFLAGS  = -mmcu=$(DEVICE)

# --- Sources ---
OBJECTS  = src/main.o usbdrv/usbdrv.o usbdrv/usbdrvasm.o usbdrv/oddebug.o

# --- Targets ---
.PHONY: all hex flash fuse program clean help

all: hex

help:
	@echo "Available targets:"
	@echo "  make hex      - Build firmware (main.hex)"
	@echo "  make flash    - Flash firmware via micronucleus or avrdude"
	@echo "  make fuse     - Program fuse bits (requires ISP programmer)"
	@echo "  make program  - Flash fuses + firmware"
	@echo "  make clean    - Remove build artifacts"

hex: main.hex

main.elf: $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

main.hex: main.elf
	$(OBJCOPY) -j .text -j .data -O ihex $< $@
	$(SIZE) $@
	@cp $@ hex/attiny85-volume-control-hid.hex

# Pattern rules
src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

usbdrv/%.o: usbdrv/%.c
	$(CC) $(CFLAGS) -c $< -o $@

usbdrv/%.o: usbdrv/%.S
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

flash: main.hex
	$(AVRDUDE) -U flash:w:main.hex:i

fuse:
	$(AVRDUDE) -U hfuse:w:$(FUSE_H):m -U lfuse:w:$(FUSE_L):m

program: flash fuse

clean:
	rm -f main.hex main.elf src/*.o usbdrv/*.o
```

### Key improvements
- Proper header and project description
- Configurable `SERIAL_PORT` and `PROGRAMMER` via env/command-line overrides
- `.PHONY` targets declared
- Pattern rules for `src/` and `usbdrv/` directories
- Auto-copies built hex to `hex/` directory
- `help` as default target (prevents accidental builds from bare `make`)

---

## 3. Firmware Improvements (src/main.c)

### 3.1 CRITICAL: Non-blocking encoder reading

**Problem:** The current `checkEncoder()` blocks in a `while` loop ([main.c:75]):
```c
while (!(PINB & ENC_A)) _delay_ms(5);
```
This starves `usbPoll()` which must be called every 50ms. A slow encoder turn can
cause the USB host to drop the device.

**Fix:** Replace with edge-detection state machine:
```c
static void checkEncoder(void) {
    static uint8_t lastA = 1;
    static uint8_t debounceCount = 0;

    currentKey = 0;
    uint8_t a = (PINB & ENC_A) ? 1 : 0;

    // Detect falling edge on A (CLK)
    if (lastA && !a) {
        if (PINB & ENC_B)
            currentKey = VOLUMEUP;
        else
            currentKey = VOLUMEDOWN;
    }
    lastA = a;

    // Debounced mute button (switch on PB0)
    if (!(PINB & ENC_SW)) {
        if (debounceCount < DEBOUNCE_THRESHOLD)
            debounceCount++;
        if (debounceCount == DEBOUNCE_THRESHOLD && !isSwitchPressed) {
            currentKey = VOLUMEMUTE;
            isSwitchPressed = 1;
        }
    } else {
        debounceCount = 0;
        isSwitchPressed = 0;
    }
}
```
- Zero blocking delays
- USB polling is never starved
- Button gets proper debounce via threshold counting

### 3.2 Remove dead code

- Delete the commented-out `calibrateOscillator()` (lines 106-129)
- Delete the unused `#define abs(x)` macro (line 131)

### 3.3 Fix calibrateOscillator() indentation

The active function has broken indentation where the neighborhood search code
appears to be inside the `do-while` loop but is actually after it. Fix to use
consistent formatting.

### 3.4 USB descriptor corrections

In `usbconfig.h`:
- Change `USB_CFG_INTERFACE_SUBCLASS` from `0x01` to `0x00` (No Subclass -
  Boot Interface is wrong for Consumer Control)
- Change `USB_CFG_INTERFACE_PROTOCOL` from `0x01` to `0x00` (No Protocol -
  Keyboard protocol is wrong for Consumer Control)
- Rename `USB_CFG_DEVICE_NAME` from `DigiKey` (a trademark of a major electronics
  distributor) to `VolKnob` or similar

---

## 4. Files to Cherry-Pick from Original

| Source (attiny85-hid-rotary/)           | Destination (attiny85-hid-rotary-knob/)       | Action        |
|-----------------------------------------|-----------------------------------------------|---------------|
| `main.c`                               | `src/main.c`                                  | Copy + modify |
| `usbconfig.h`                          | `src/usbconfig.h`                             | Copy + modify |
| `usbdrv/*` (entire directory)          | `usbdrv/`                                     | Copy as-is    |
| `hexfiles/*.hex`                       | `hex/attiny85-volume-control-hid.hex`         | Copy as-is    |
| `images/*`                             | `doc/images/`                                 | Copy as-is    |
| `README.md` + `readme.txt`            | `README.md` (merge)                           | Rewrite       |
| (new)                                  | `.gitignore`                                  | Create        |
| (new)                                  | `Makefile`                                    | Rewrite       |

---

## 5. New .gitignore

```
# Build artifacts
*.o
*.elf
*.hex
!hex/*.hex

# Editor files
*.swp
*~
.vscode/
```

---

## 6. README.md Rewrite Plan

Merge content from both `README.md` and `readme.txt` into a single comprehensive README:

1. **Project title & description** - what it does, one-liner
2. **Photo** of assembled hardware
3. **Hardware requirements** - Digispark ATtiny85, KY-040 rotary encoder
4. **Wiring diagram** - table + image
5. **Pin assignment** (ATtiny85 pinout ASCII art from main.c comment)
6. **Building from source** - `make hex` (prerequisites: `avr-gcc`, `avr-libc`)
7. **Flashing**
   - Option A: micronucleus (for boards with bootloader)
   - Option B: ISP programmer (avrdude + usbasp)
8. **Troubleshooting** - the `dmesg` error -71 recovery steps
9. **Credits & License**

---

## 7. Implementation Order

| Step | Task                                                  | Depends on |
|------|-------------------------------------------------------|------------|
| 1    | Create directory structure (`src/`, `usbdrv/`, `hex/`, `doc/images/`) | - |
| 2    | Copy `usbdrv/` as-is from original                   | Step 1     |
| 3    | Copy images to `doc/images/`                          | Step 1     |
| 4    | Copy pre-built hex to `hex/`                          | Step 1     |
| 5    | Copy & refactor `main.c` into `src/main.c`           | Step 1     |
| 6    | Copy & fix `usbconfig.h` into `src/usbconfig.h`      | Step 1     |
| 7    | Write new `Makefile`                                  | Steps 5,6  |
| 8    | Create `.gitignore`                                   | -          |
| 9    | Rewrite `README.md`                                   | All above  |
| 10   | Verify build with `make hex`                          | Steps 1-8  |
| 11   | Commit & push                                         | Step 10    |

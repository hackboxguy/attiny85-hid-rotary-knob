# Project: ATtiny85 HID Volume Control Knob
# Hardware: Digispark ATtiny85
# USB Stack: V-USB (https://www.obdev.at/products/vusb/)

# --- Configuration ---
DEVICE     = attiny85
F_CPU      = 16500000
FUSE_L     = 0xE1
FUSE_H     = 0xDD

# Programmer: override on command line if needed
#   e.g.: make flash PROGRAMMER="-c usbasp"
SERIAL_PORT ?= /dev/ttyACM0
PROGRAMMER  ?= -c stk500v1 -b 19200 -P $(SERIAL_PORT)
AVRDUDE     = avrdude $(PROGRAMMER) -p $(DEVICE)

# --- Toolchain ---
CC      = avr-gcc
OBJCOPY = avr-objcopy
SIZE    = avr-size

CFLAGS  = -Wall -Os -DF_CPU=$(F_CPU) -mmcu=$(DEVICE) -Iusbdrv -Isrc -DDEBUG_LEVEL=0
LDFLAGS = -mmcu=$(DEVICE)

# --- Sources ---
OBJECTS = src/main.o usbdrv/usbdrv.o usbdrv/usbdrvasm.o usbdrv/oddebug.o

# --- Targets ---
.PHONY: all hex flash fuse program clean help

all: hex

help:
	@echo "Available targets:"
	@echo "  make hex      - Build firmware (main.hex)"
	@echo "  make flash    - Flash firmware via avrdude"
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

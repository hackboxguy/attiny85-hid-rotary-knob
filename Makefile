# Project: ATtiny85 HID Volume Control Knob
# Hardware: Digispark ATtiny85
# USB Stack: V-USB (https://www.obdev.at/products/vusb/)

# --- Configuration ---
DEVICE     = attiny85
F_CPU      = 16500000
FUSE_L     = 0xE1
FUSE_H     = 0x5D  # RSTDISBL programmed: PB5 is GPIO (disables ISP permanently)

# ISP Programmer: override on command line if needed
#   e.g.: make flash PROGRAMMER="-c usbasp"
SERIAL_PORT ?= /dev/ttyACM0
PROGRAMMER  ?= -c stk500v1 -b 19200 -P $(SERIAL_PORT)
AVRDUDE     = avrdude $(PROGRAMMER) -p $(DEVICE)

# Use SUDO='' to skip sudo (e.g., if udev rules grant USB access)
SUDO       ?= sudo

# --- AVR Toolchain (firmware) ---
CC      = avr-gcc
OBJCOPY = avr-objcopy
SIZE    = avr-size

CFLAGS  = -Wall -Os -DF_CPU=$(F_CPU) -mmcu=$(DEVICE) -Iusbdrv -Isrc -DDEBUG_LEVEL=0
LDFLAGS = -mmcu=$(DEVICE)

# --- Host Toolchain (micronucleus uploader) ---
HOSTCC     = gcc
HOSTCFLAGS = -Wall -DUSE_HOSTCC
HOSTLFLAGS = $(shell pkg-config --libs --cflags libusb-1.0)

# --- Sources ---
OBJECTS = src/main.o usbdrv/usbdrv.o usbdrv/usbdrvasm.o usbdrv/oddebug.o

MNUC_DIR = tools/micronucleus
MNUC_SRC = $(MNUC_DIR)/littleWire_util.c $(MNUC_DIR)/micronucleus_lib.c $(MNUC_DIR)/micronucleus.c
MNUC_BIN = $(MNUC_DIR)/micronucleus

# --- Targets ---
.PHONY: all hex micronucleus upload flash fuse program clean help

all: hex micronucleus

help:
	@echo "Available targets:"
	@echo "  make all         - Build firmware + micronucleus uploader"
	@echo "  make hex         - Build firmware only (main.hex)"
	@echo "  make micronucleus - Build micronucleus uploader tool"
	@echo "  make upload      - Build all, then flash via micronucleus"
	@echo "  make flash       - Flash firmware via avrdude (ISP programmer)"
	@echo "  make fuse        - Program fuse bits (requires ISP programmer)"
	@echo "  make program     - Flash fuses + firmware via avrdude"
	@echo "  make clean       - Remove build artifacts"

# --- Firmware ---
hex: main.hex

main.elf: $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

main.hex: main.elf
	$(OBJCOPY) -j .text -j .data -O ihex $< $@
	$(SIZE) main.elf
	@cp $@ hex/attiny85-volume-control-hid.hex

src/%.o: src/%.c
	$(CC) $(CFLAGS) -c $< -o $@

usbdrv/%.o: usbdrv/%.c
	$(CC) $(CFLAGS) -c $< -o $@

usbdrv/%.o: usbdrv/%.S
	$(CC) $(CFLAGS) -x assembler-with-cpp -c $< -o $@

# --- Micronucleus uploader ---
micronucleus: $(MNUC_BIN)

$(MNUC_BIN): $(MNUC_SRC)
	$(HOSTCC) $(HOSTCFLAGS) -o $@ $^ $(HOSTLFLAGS)

# --- Flash targets ---
upload: hex micronucleus
	@echo ">>> Plug in Digispark ATtiny85 now..."
	@echo "    (To skip sudo: make upload SUDO='')"
	$(SUDO) $(MNUC_BIN) --run main.hex

flash: main.hex
	$(AVRDUDE) -U flash:w:main.hex:i

fuse:
	@echo "WARNING: This disables RESET on PB5 (needed for encoder CLK)."
	@echo "         ISP programming will no longer work after this."
	@echo "         A high-voltage programmer is required to recover."
	@echo "         Press Ctrl+C within 5s to abort..."
	@sleep 5
	$(AVRDUDE) -U hfuse:w:$(FUSE_H):m -U lfuse:w:$(FUSE_L):m

program: flash fuse

# --- Cleanup ---
clean:
	rm -f main.hex main.elf src/*.o usbdrv/*.o $(MNUC_BIN)

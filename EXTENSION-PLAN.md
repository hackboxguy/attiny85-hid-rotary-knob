# ATtiny85 HID Rotary Knob - Extension Plan

Future feature ideas for the ATtiny85 USB rotary encoder dongle.
All extensions target the same Digispark ATtiny85 + KY-040 hardware.

## Pin Map Reference

```
                     +-\/-+
ENC_A (CLK)    PB5  1|    |8  Vcc
USB D-         PB3  2|    |7  PB2    ENC_B (DT)
USB D+         PB4  3|    |6  PB1    (onboard LED / FREE)
               GND  4|    |5  PB0    ENC_SW (SW)
                     +----+
```

- PB3, PB4: reserved for V-USB (cannot be reassigned)
- PB1: onboard LED, available as GPIO
- PB5: RESET pin repurposed as GPIO (RSTDISBL fuse programmed by Digispark)
- Available for extensions: **PB1** (currently unused)

Flash budget: 8192 bytes total, **~2048** bytes used by micronucleus bootloader,
**~2036** bytes used by current firmware = **~4100 bytes free**.

---

## Extension 1: Multi-Mode Knob

Switch the knob between different control modes using a long-press (>1 second).

### Modes

| Mode | Rotate         | Short Press    | LED (PB1)     |
|------|----------------|----------------|---------------|
| 0    | Volume Up/Down | Mute           | Off           |
| 1    | Media Prev/Next| Play/Pause     | Slow blink    |
| 2    | Brightness +/- | (none)         | Fast blink    |
| 3    | Scroll Up/Down | Middle Click   | Solid on      |

### Implementation Notes

- Long-press detection: hold button >1s (count main loop iterations, ~20000 cycles at ~50us/loop)
- Store active mode in EEPROM so it survives power cycles (`eeprom_read_byte` / `eeprom_update_byte`)
- LED blink patterns driven from main loop counter (no timer needed)
- Brightness control uses HID Consumer Control usages 0x006F (Brightness Increment) and 0x0070 (Brightness Decrement)
- Media controls: 0x00B5 (Scan Next Track), 0x00B6 (Scan Previous Track), 0x00CD (Play/Pause)
- Scroll/middle-click requires a second HID interface (Mouse) — see composite device notes below
- Estimated additional flash: ~300-500 bytes (without scroll mode)

---

## Extension 2: Speed-Sensitive Rotation

Adjust step size based on rotation speed. Slow rotation = fine control (1 step),
fast rotation = coarse control (multiple steps or repeated reports).

### Implementation Notes

- Track time between encoder edges using a free-running counter (Timer0 or main loop counter)
- If interval < threshold (~20ms), send multiple volume steps per detent
- Simple approach: count edges within a time window, scale report rate accordingly
- No additional flash cost beyond ~50-80 bytes
- Must still call `usbPoll()` frequently — send repeated reports across multiple loop iterations, not in a blocking burst

---

## Extension 3: Double-Click Detection

Map double-click (two presses within ~400ms) to a different action than single-click.

### Implementation Notes

- After first press-release, start a timeout counter
- If second press arrives before timeout: trigger double-click action (e.g., Play/Pause)
- If timeout expires: trigger single-click action (e.g., Mute)
- Trade-off: single-click response is delayed by the timeout window
- Estimated additional flash: ~60-100 bytes

---

## Extension 4: Presentation Remote Mode

Use the knob as a wireless-free presentation remote: rotate for next/prev slide,
press for blank screen or laser toggle.

### HID Usages

| Action         | Usage Page| Usage Code | Description          |
|----------------|-----------|------------|----------------------|
| Next slide     | 0x0C      | 0x009C     | Channel Increment    |
| Previous slide | 0x0C      | 0x009D     | Channel Decrement    |

Alternative approach using HID Keyboard interface:
- Next slide: Right Arrow or Page Down
- Previous slide: Left Arrow or Page Up
- Requires a second HID interface (Keyboard) — see composite device notes

---

## Extension 5: Undo/Redo Developer Knob

Rotate CW for Redo (Ctrl+Y), rotate CCW for Undo (Ctrl+Z).
Press for Save (Ctrl+S).

### Implementation Notes

- Requires HID Keyboard interface (modifier + key reports)
- Must be a separate HID interface from Consumer Control
- See composite device notes below for V-USB multi-interface approach
- Estimated additional flash for keyboard interface: ~200-300 bytes

---

## Extension 6: RGB NeoPixel Mode Indicator

Replace the onboard LED on PB1 with a WS2812B (NeoPixel) for color-coded mode indication.

### Implementation Notes

- WS2812B protocol: 800kHz bit-banged signal on PB1
- Each mode gets a distinct color (e.g., green=volume, blue=media, yellow=brightness, white=scroll)
- Timing-critical: must disable interrupts during NeoPixel data transmission (~30us for 1 LED)
- V-USB tolerates brief interrupt blackouts (<50us) between USB frames
- Library: bit-bang in inline assembly (~80 bytes), no external library needed
- Power: single WS2812B draws up to 60mA at full white — Digispark 5V regulator can handle this

---

## Extension 7: MS Teams Microphone Mute Button

Map the encoder button press to toggle microphone mute in Microsoft Teams.

### Approach A: HID System Microphone Mute (Recommended)

Use **HID Usage 0xA9 (System Microphone Mute)** from the Generic Desktop Page (0x01),
defined in [HID Usage Tables Request HUTRR110](https://www.usb.org/sites/default/files/hutrr110-system-microphone-mute.pdf).

This is a **hardware-level** mute that works as a system-wide microphone toggle,
natively supported on:
- Windows 10 21H2+ and Windows 11 (shows system mic mute OSD)
- Linux 5.17+ (maps to `KEY_MICMUTE` input event)

#### HID Report Descriptor Addition

```c
// Generic Desktop Page - System Microphone Mute
0x05, 0x01,        // USAGE_PAGE (Generic Desktop)
0x09, 0xA9,        // USAGE (System Microphone Mute)
0xa1, 0x01,        // COLLECTION (Application)
0x85, 0x02,        //   REPORT_ID (2)
0x09, 0xA9,        //   USAGE (System Microphone Mute)
0x15, 0x00,        //   LOGICAL_MINIMUM (0)
0x25, 0x01,        //   LOGICAL_MAXIMUM (1)
0x75, 0x01,        //   REPORT_SIZE (1)
0x95, 0x01,        //   REPORT_COUNT (1)
0x81, 0x06,        //   INPUT (Data,Var,Rel)  // Relative = toggle
0x75, 0x07,        //   REPORT_SIZE (7)       // Padding
0x95, 0x01,        //   REPORT_COUNT (1)
0x81, 0x01,        //   INPUT (Const)
0xc0               // END_COLLECTION
```

- Uses Report ID 2 (separate from volume Report ID 1)
- Single bit, relative input = each press toggles mute state
- No driver or application-specific support needed
- Estimated additional flash: ~50 bytes (descriptor + report logic)

### Approach B: Keyboard Shortcut Fallback

Send **Ctrl+Shift+M** as a HID Keyboard report (the Teams keyboard shortcut).

- Requires a Keyboard HID interface (composite device)
- Only works when Teams window is focused
- Works on older Windows versions without HUTRR110 support
- Less elegant but more compatible with older systems

### Recommendation

Use Approach A (System Microphone Mute) as primary. It works system-wide,
requires no composite device complexity, and fits within the existing single-interface
HID descriptor by adding a second Report ID.

---

## Extension 8: I2C-Tiny-USB Composite Device

Combine the HID rotary knob with a [harbaum/I2C-Tiny-USB](https://github.com/harbaum/I2C-Tiny-USB)
compatible USB-to-I2C bridge. This enables connecting an SSD1306 OLED display (or any I2C
peripheral) to provide a display output on headless Linux PCs (e.g., OpenWrt pocket routers).

### What is I2C-Tiny-USB?

- V-USB based USB-to-I2C adapter by Till Harbaum
- Shows up as `/dev/i2c-N` on Linux (in-tree kernel driver: `i2c-tiny-usb`)
- Uses USB vendor-specific class (0xFF) with control transfers
- VID=0x0403, PID=0xc631 (or custom)
- Bit-banged I2C on two GPIO pins
- Original pinout: PB1 (SDA), PB5 (SCL)

### Pin Conflict

The I2C bus needs two pins. The standard i2c-tiny-usb assignment is:

| Function | Pin | Current Use     |
|----------|-----|-----------------|
| SCL      | PB5 | Encoder A (CLK) |
| SDA      | PB1 | Free (LED)      |

**PB5 is shared** between encoder CLK and I2C SCL. With only 3 free GPIO pins
(PB0, PB1, PB2) after USB, we cannot have encoder (2 pins) + button (1 pin) +
I2C (2 pins) simultaneously.

### Configuration Options

| Config | Encoder | Button | I2C | LED | Pins Used                           |
|--------|---------|--------|-----|-----|-------------------------------------|
| A      | Yes     | Yes    | No  | PB1 | PB0(SW) PB2(B) PB5(A)               |
| B      | Yes     | No     | Yes | No  | PB0(A) PB2(B) PB1(SDA) PB5(SCL)     |
| C      | No      | Yes    | Yes | No  | PB0(SW) PB1(SDA) PB5(SCL) PB2(free) |

- **Config A** = current firmware (volume knob, no I2C)
- **Config B** = knob + display (no mute button) — encoder remapped to PB0+PB2
- **Config C** = button + display (no rotation) — useful as a simple toggle + status display

Config B is the most useful composite: rotate for volume, display shows current
volume level or system status via I2C from the host.

### V-USB Composite Device Architecture

V-USB supports composite devices through multiple interfaces in a single
configuration descriptor:

```
USB Device
└── Configuration 1
    ├── Interface 0: HID (Consumer Control)
    │   └── Endpoint 1 IN (interrupt, 8 bytes)
    └── Interface 1: Vendor-Specific (I2C-Tiny-USB)
        └── Endpoint 0 (control transfers only)
```

- HID interface uses interrupt endpoint 1 (existing)
- I2C-Tiny-USB uses only control transfers (EP0) — no additional endpoint needed
- V-USB supports custom `usbFunctionSetup()` routing based on interface number
- Must provide custom USB configuration descriptor (cannot use V-USB's auto-generated one)

#### Key Implementation Details

1. **Custom configuration descriptor**: define full config descriptor in PROGMEM
   including both interface descriptors, HID descriptor, and endpoint descriptor
2. **Request routing**: in `usbFunctionSetup()`, check `wIndex` (interface number)
   to dispatch HID requests vs I2C-Tiny-USB vendor requests
3. **I2C bit-bang**: implement `i2c_start()`, `i2c_stop()`, `i2c_read()`, `i2c_write()`
   using PB1/PB5 with appropriate timing (~100kHz)
4. **I2C-Tiny-USB protocol**: handle vendor requests for I2C_IO, I2C_STATUS,
   I2C_FUNC via `usbFunctionSetup()` and `usbFunctionRead()`/`usbFunctionWrite()`
5. **Linux driver**: no user-space driver needed — the in-tree `i2c-tiny-usb`
   kernel module handles everything. Just `modprobe i2c-tiny-usb`.

#### Flash Estimate

| Component                | Bytes (approx) |
|--------------------------|----------------|
| Current firmware         | 2036           |
| Custom config descriptor | 200            |
| I2C bit-bang routines    | 300            |
| I2C-Tiny-USB protocol    | 400            |
| Request routing          | 100            |
| **Total**                | **~3100**      |

Fits within the ~6100 bytes available (8192 - 2048 bootloader).

### Use Case: Headless Linux PC with SSD1306 Display

```
┌──────────────────┐    USB     ┌─────────────────────┐
│  OpenWrt Router   │◄─────────►│  ATtiny85 Composite │
│  (headless)       │           │  ┌───────┐ ┌───────┐│
│                   │           │  │  HID  │ │ I2C   ││
│  /dev/i2c-N ──────┤           │  │ Knob  │ │Bridge ││
│                   │           │  └───┬───┘ └───┬───┘│
└───────────────────┘           └──────┼─────────┼────┘
                                       │         │
                                 ┌─────┘    ┌────┘
                                 │          │ I2C (PB1/PB5)
                             ┌───┴───┐  ┌───┴────┐
                             │KY-040 │  │SSD1306 │
                             │Encoder│  │ OLED   │
                             └───────┘  └────────┘
```

Host-side workflow:
1. `modprobe i2c-tiny-usb` (or auto-loaded by udev)
2. `i2cdetect -y N` shows SSD1306 at address 0x3C
3. Use any SSD1306 library (Python `luma.oled`, C `ssd1306_linux`, etc.) to draw to display
4. Rotary encoder events arrive as standard HID input (evdev)
5. User-space daemon reads encoder events and updates display content

---

## Implementation Priority

| Priority | Extension                  | Complexity | Flash Cost|
|----------|----------------------------|-----------|------------|
| 1        | MS Teams Mic Mute (Ext 7A) | Low       | ~50 bytes  |
| 2        | Multi-Mode Knob (Ext 1)    | Medium    | ~400 bytes |
| 3        | Speed-Sensitive (Ext 2)    | Low       | ~80 bytes  |
| 4        | Double-Click (Ext 3)       | Low       | ~100 bytes |
| 5        | I2C Composite (Ext 8)      | High      | ~1100 bytes|
| 6        | Presentation Remote (Ext 4)| Medium    | ~200 bytes |
| 7        | Undo/Redo Knob (Ext 5)     | Medium    | ~300 bytes |
| 8        | NeoPixel Indicator (Ext 6) | Low       | ~80 bytes  |

Extensions 1-4 and 7A can be implemented independently on the current hardware
with no wiring changes. Extensions 5 and 7B require a Keyboard HID interface
(composite device). Extension 8 requires hardware re-wiring (encoder to PB0+PB2)
and a full composite device with vendor-specific interface.

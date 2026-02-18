// ATtiny85 HID Volume Control Knob
//
// USB volume control for ATtiny45/85 using rotary encoder
// and V-USB interface based on several examples from
// https://www.obdev.at/products/vusb/projects.html
//
// Connection between Digispark-ATtiny85 and rotary encoder:
//                         +-\/-+
// ENC_A(CLK)A0 (D5) PB5  1|    |8  Vcc
// USB-  --- A3 (D3) PB3  2|    |7  PB2 (D2) A1 --- ENC_B(DT)
// USB+  --- A2 (D4) PB4  3|    |6  PB1 (D1) ------
//                   GND  4|    |5  PB0 (D0) ------ ENC_SW(SW)
//                         +----+
//
// Based on tinyKnob by Stefan Wagner (2020)
// Project Files: https://github.com/wagiminator/ATtiny85-TinyKnob
// License: http://creativecommons.org/licenses/by-sa/3.0/

#ifndef F_CPU
#define F_CPU 16500000 // 16.5 MHz
#endif

#include <avr/io.h>
#include <avr/wdt.h>
#include <avr/interrupt.h>
#include <avr/pgmspace.h>
#include <util/delay.h>
#include "usbdrv.h"

// Rotary encoder pins
#define ENC_SW  0b00000001 // PB0 ==> (SW)
#define ENC_B   0b00000100 // PB2 ==> (DT)
#define ENC_A   0b00100000 // PB5 ==> (CLK)

// HID Consumer Control usage codes
#define VOLUMEMUTE  0xE2
#define VOLUMEUP    0xE9
#define VOLUMEDOWN  0xEA

// Debounce threshold (number of poll cycles the button must be held)
// Main loop runs ~50us/iteration, so 50 cycles ≈ 2.5ms press + 2.5ms release
#define DEBOUNCE_THRESHOLD 50

// USB HID report descriptor (Consumer Control)
PROGMEM const char usbHidReportDescriptor[USB_CFG_HID_REPORT_DESCRIPTOR_LENGTH] = {
  0x05, 0x0c,           // USAGE_PAGE (Consumer Devices)
  0x09, 0x01,           // USAGE (Consumer Control)
  0xa1, 0x01,           // COLLECTION (Application)
  0x85, 0x01,           //   REPORT_ID (1)
  0x19, 0x00,           //   USAGE_MINIMUM (Unassigned)
  0x2a, 0x3c, 0x02,     //   USAGE_MAXIMUM (AC Format)
  0x15, 0x00,           //   LOGICAL_MINIMUM (0)
  0x26, 0x3c, 0x02,     //   LOGICAL_MAXIMUM (572)
  0x95, 0x01,           //   REPORT_COUNT (1)
  0x75, 0x10,           //   REPORT_SIZE (16)
  0x81, 0x00,           //   INPUT (Data,Var,Abs)
  0xc0                  // END_COLLECTION
};

static uchar reportBuffer[3] = {1, 0, 0}; // report ID 1 + 16-bit usage code
static uchar idleRate;
static uchar currentKey;
static uchar isSwitchPressed = 0;

// Non-blocking encoder check with debounced button
static void checkEncoder(void) {
  static uint8_t lastA = 1;
  static uint8_t debounceCount = 0;

  currentKey = 0;
  uint8_t a = (PINB & ENC_A) ? 1 : 0;

  // Detect falling edge on A (CLK) for rotation
  if (lastA && !a) {
    if (PINB & ENC_B)
      currentKey = VOLUMEUP;
    else
      currentKey = VOLUMEDOWN;
  }
  lastA = a;

  // Debounced mute button (switch on PB0)
  // Counter increments while pressed, decrements while released.
  // This debounces both press and release edges.
  if (!(PINB & ENC_SW)) {
    if (debounceCount < DEBOUNCE_THRESHOLD)
      debounceCount++;
    if (debounceCount == DEBOUNCE_THRESHOLD && !isSwitchPressed) {
      currentKey = VOLUMEMUTE;
      isSwitchPressed = 1;
    }
  } else {
    if (debounceCount > 0)
      debounceCount--;
    if (debounceCount == 0)
      isSwitchPressed = 0;
  }
}

uchar usbFunctionSetup(uchar data[8]) {
  usbRequest_t *rq = (void *)data;
  usbMsgPtr = reportBuffer;
  if ((rq->bmRequestType & USBRQ_TYPE_MASK) == USBRQ_TYPE_CLASS) {
    if (rq->bRequest == USBRQ_HID_GET_REPORT) {
      return sizeof(reportBuffer);
    } else if (rq->bRequest == USBRQ_HID_GET_IDLE) {
      usbMsgPtr = &idleRate;
      return 1;
    } else if (rq->bRequest == USBRQ_HID_SET_IDLE) {
      idleRate = rq->wValue.bytes[1];
    }
  }
  return 0;
}

// Calibrate internal RC oscillator against USB frame timing
void calibrateOscillator(void) {
  uchar step = 128;
  uchar trialValue = 0, optimumValue;
  int x, optimumDev;
  int targetValue = (unsigned)(1499 * (double)F_CPU / 10.5e6 + 0.5);

  // Binary search for approximate OSCCAL value
  do {
    OSCCAL = trialValue + step;
    x = usbMeasureFrameLength();
    if (x < targetValue)
      trialValue += step;
    step >>= 1;
  } while (step > 0);

  // Neighborhood search for optimum value
  optimumValue = trialValue;
  optimumDev = x;
  for (OSCCAL = trialValue - 1; OSCCAL <= trialValue + 1; OSCCAL++) {
    x = usbMeasureFrameLength() - targetValue;
    if (x < 0)
      x = -x;
    if (x < optimumDev) {
      optimumDev = x;
      optimumValue = OSCCAL;
    }
  }
  OSCCAL = optimumValue;
}

void usbEventResetReady(void) {
  calibrateOscillator();
}

int main(void) {
  usbInit();
  usbDeviceDisconnect();
  uchar i = 0;
  while (--i) {
    wdt_reset();
    _delay_ms(1);
  }
  usbDeviceConnect();
  wdt_enable(WDTO_2S);

  // Enable internal pull-ups for rotary encoder pins
  PORTB |= ENC_A | ENC_B | ENC_SW;

  sei();

  while (1) {
    wdt_reset();
    usbPoll();
    checkEncoder();
    if (usbInterruptIsReady() && (reportBuffer[1] != currentKey)) {
      reportBuffer[1] = currentKey;
      usbSetInterrupt(reportBuffer, sizeof(reportBuffer));
    }
  }
  return 0;
}

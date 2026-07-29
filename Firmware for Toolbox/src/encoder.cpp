#include <Arduino.h>
#include "encoder.h"

#define ENCODER_PIN_A 15
#define ENCODER_PIN_B 16

static volatile int32_t encoderPos = 0;
static bool lastCLKState;

void IRAM_ATTR onEncoderChange() {
  bool currentCLK = digitalRead(ENCODER_PIN_A);

  if (currentCLK != lastCLKState) {
    if (digitalRead(ENCODER_PIN_B) != currentCLK) {
      encoderPos++;
    } else {
      encoderPos--;
    }
  }
  lastCLKState = currentCLK;
}

void encoder_init() {
  pinMode(ENCODER_PIN_A, INPUT_PULLUP);
  pinMode(ENCODER_PIN_B, INPUT_PULLUP);

  lastCLKState = digitalRead(ENCODER_PIN_A);

  attachInterrupt(digitalPinToInterrupt(ENCODER_PIN_A), onEncoderChange, RISING);

  Serial.println("Encoder initialized (GPIO15=A, GPIO16=B).");
}

int32_t encoder_getPosition() {
  noInterrupts();
  int32_t val = encoderPos;
  interrupts();
  return val/2;
}

void encoder_setPosition(int32_t pos) {
  noInterrupts();
  encoderPos = pos;
  interrupts();
}

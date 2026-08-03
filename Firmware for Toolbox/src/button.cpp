#include <Arduino.h>
#include "button.h"

#define BUTTON_PIN 6

static bool lastState = HIGH;
static bool releasedFlag = false;
static unsigned long pressStartTime = 0;
static unsigned long releaseTime = 0;
static uint32_t pressCount = 0;

void button_init() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  // currentState uses active-LOW semantics: true when pressed.
  lastState = button_isPressed();
  Serial.println("Button initialized (GPIO6).");
}

bool button_isPressed() {
  return !digitalRead(BUTTON_PIN); // active LOW
}

bool button_wasReleased() {
  bool flag = releasedFlag;
  releasedFlag = false;
  return flag;
}

unsigned long button_getPressDuration() {
  if (releaseTime > pressStartTime) {
    return releaseTime - pressStartTime;
  }
  return 0;
}

uint32_t button_getPressCount() {
  return pressCount;
}

void button_update() {
  bool currentState = !digitalRead(BUTTON_PIN); // active LOW

  if (!lastState && currentState) {
    pressStartTime = millis();
    pressCount++;
    char buf[32];
    snprintf(buf, sizeof(buf), "Button pressed (count=%lu)", pressCount);
    Serial.println(buf);
  } else if (lastState && !currentState) {
    releaseTime = millis();
    unsigned long duration = releaseTime - pressStartTime;
    Serial.printf("Button released. Press duration: %lu ms\r\n", duration);
    releasedFlag = true;
  }

  lastState = currentState;
}

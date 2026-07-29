#include <Arduino.h>
#include "oled_a.h"
#include "oled_b.h"
#include "button.h"
#include "encoder.h"
#include "wifi.h"
#include "sd_card.h"
#include "inventory.h"

void setup() {
  Serial.begin(115200);
  delay(100);

  oledA_init();
  oledB_init();
  button_init();
  encoder_init();
  wifi_init();
  sdCard_init();
  inventory_init();
}

void loop() {
  button_update();

  static unsigned long lastOledUpdate = 0;
  if (millis() - lastOledUpdate >= 250) {
    lastOledUpdate = millis();

    const char *debugLinesA[8];
    uint8_t debugCountA = 0;
    char buf[32];

    snprintf(buf, sizeof(buf), "Btn: %lu", button_getPressCount());
    debugLinesA[debugCountA++] = buf;

    snprintf(buf, sizeof(buf), "Enc: %ld", encoder_getPosition());
    debugLinesA[debugCountA++] = buf;

    oledA_showStatus("TOOLBOX", debugLinesA, debugCountA);

    const char *debugLinesB[8];
    uint8_t debugCountB = 0;

    if (sdCard_isPresent()) {
      snprintf(buf, sizeof(buf), "SD: %lu files", sdCard_fileCount());
    } else {
      strcpy(buf, "SD: not found");
    }
    debugLinesB[debugCountB++] = buf;

    oledB_showStatus("TOOLBOX", debugLinesB, debugCountB);
  }
}

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "oled_b.h"

#define OLED_B_SDA 4
#define OLED_B_SCL 5
TwoWire oledB_wire(1);
Adafruit_SSD1306 oled_b(128, 64, &oledB_wire, -1, false);

static char messageBuf[64];
static unsigned long messageTime = 0;
#define MESSAGE_DURATION 5000

void oledB_showMessage(const char* msg) {
  strncpy(messageBuf, msg, sizeof(messageBuf) - 1);
  messageBuf[sizeof(messageBuf) - 1] = '\0';
  messageTime = millis();
}

bool oledB_hasActiveMessage() {
  return messageBuf[0] != '\0' && (millis() - messageTime) < MESSAGE_DURATION;
}

void oledB_init() {
  oledB_wire.begin(OLED_B_SDA, OLED_B_SCL, 400000);
  delay(100);

  uint8_t addr = 0x3C;
  bool found = false;
  for (uint8_t testAddr : {0x3C, 0x3D}) {
    oledB_wire.beginTransmission(testAddr);
    if (oledB_wire.endTransmission() == 0) {
      addr = testAddr;
      found = true;
      break;
    }
  }
  if (!found) {
    Serial.println("ERROR: OLED B not found at 0x3C or 0x3D");
    while (1) { Serial.println("OLED B FAILED"); delay(1000); }
  }

  oled_b.begin(SSD1306_SWITCHCAPVCC, addr);
  oled_b.clearDisplay();
  oled_b.setTextSize(1);
  oled_b.setTextColor(SSD1306_WHITE);
  oled_b.setCursor(0, 0);
  oled_b.println("OLED B");
  oled_b.printf("SDA=%d SCL=%d\r\n", OLED_B_SDA, OLED_B_SCL);
  oled_b.printf("Addr=0x%02X\r\n", addr);
  oled_b.println("OK");
  oled_b.display();

  Serial.println("OLED B initialized.");
}

void oledB_showStatus(const char *title, const char **debugLines, uint8_t debugCount) {
  if (oledB_hasActiveMessage()) {
    oled_b.clearDisplay();
    oled_b.setTextSize(1);
    oled_b.setCursor(2, 5);
    oled_b.println("OLED B - Message");
    int y = 18;
    const char* msgLines[6];
    uint8_t lineCount = 0;
    const char* p = messageBuf;
    while (*p && lineCount < 6) {
      msgLines[lineCount++] = p;
      p++;
      while (*p && *p != '\n' && *p != '\r') p++;
      if (*p == '\n' || *p == '\r') p += (*p == '\n') ? 1 : 2;
    }
    for (uint8_t i = 0; i < lineCount && y < 58; i++) {
      oled_b.setCursor(2, y);
      oled_b.println(msgLines[i]);
      y += 9;
    }
    oled_b.display();
    return;
  }

  oled_b.clearDisplay();
  oled_b.setTextSize(2);
  oled_b.setCursor(10, 10);
  oled_b.print(title);

  int y = 35;
  oled_b.setTextSize(1);
  oled_b.setCursor(5, y);
  oled_b.println("OLED B - Secondary");
  y += 10;

  char buf[24];
  snprintf(buf, sizeof(buf), "Uptime: %lus", (unsigned long)(millis() / 1000));
  oled_b.setCursor(5, y);
  oled_b.println(buf);
  y += 10;

  for (uint8_t i = 0; i < debugCount && y < 60; i++) {
    if (debugLines[i] == nullptr) continue;
    oled_b.setCursor(5, y);
    oled_b.println(debugLines[i]);
    y += 10;
  }

  oled_b.display();
}

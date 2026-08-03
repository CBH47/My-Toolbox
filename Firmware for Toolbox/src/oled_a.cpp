#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "oled_a.h"

#define OLED_A_SDA 8
#define OLED_A_SCL 9
TwoWire oledA_wire(0);
Adafruit_SSD1306 oled_a(128, 64, &oledA_wire, -1, false);

static char messageBuf[64];
static unsigned long messageTime = 0;
#define MESSAGE_DURATION 5000

void oledA_showMessage(const char* msg) {
  strncpy(messageBuf, msg, sizeof(messageBuf) - 1);
  messageBuf[sizeof(messageBuf) - 1] = '\0';
  messageTime = millis();

  oled_a.clearDisplay();
  oled_a.setTextSize(1);
  oled_a.setTextColor(SSD1306_WHITE);
  oled_a.setCursor(2, 5);
  oled_a.println("OLED A - Message");

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
    oled_a.setCursor(2, y);
    oled_a.println(msgLines[i]);
    y += 9;
  }
  oled_a.display();
}

bool oledA_hasActiveMessage() {
  return messageBuf[0] != '\0' && (millis() - messageTime) < MESSAGE_DURATION;
}

void oledA_init() {
  oledA_wire.begin(OLED_A_SDA, OLED_A_SCL, 400000);
  delay(100);

  uint8_t addr = 0x3C;
  bool found = false;
  for (uint8_t testAddr : {0x3C, 0x3D}) {
    oledA_wire.beginTransmission(testAddr);
    if (oledA_wire.endTransmission() == 0) {
      addr = testAddr;
      found = true;
      break;
    }
  }
  if (!found) {
    Serial.println("ERROR: OLED A not found at 0x3C or 0x3D");
    while (1) { Serial.println("OLED A FAILED"); delay(1000); }
  }

  oled_a.begin(SSD1306_SWITCHCAPVCC, addr);
  oled_a.clearDisplay();
  oled_a.setTextSize(1);
  oled_a.setTextColor(SSD1306_WHITE);
  oled_a.setCursor(0, 0);
  oled_a.println("OLED A");
  oled_a.printf("SDA=%d SCL=%d\r\n", OLED_A_SDA, OLED_A_SCL);
  oled_a.printf("Addr=0x%02X\r\n", addr);
  oled_a.println("OK");
  oled_a.display();

  Serial.println("OLED A initialized.");
}

void oledA_showStatus(const char *title, const char **debugLines, uint8_t debugCount) {
  if (oledA_hasActiveMessage()) {
    oled_a.clearDisplay();
    oled_a.setTextSize(1);
    oled_a.setTextColor(SSD1306_WHITE);
    oled_a.setCursor(2, 5);
    oled_a.println("OLED A - Message");
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
      oled_a.setCursor(2, y);
      oled_a.println(msgLines[i]);
      y += 9;
    }
    oled_a.display();
    return;
  }

  oled_a.clearDisplay();
  oled_a.setTextColor(SSD1306_WHITE);

  if (title && title[0] != '\0') {
    oled_a.setTextSize(2);
    oled_a.setCursor(10, 10);
    oled_a.print(title);
  }

  int y = title && title[0] != '\0' ? 35 : 5;
  for (uint8_t i = 0; i < debugCount && y < 60; i++) {
    if (debugLines[i] == nullptr) continue;
    oled_a.setTextSize(1);
    oled_a.setCursor(5, y);
    oled_a.println(debugLines[i]);
    y += 10;
  }

  oled_a.display();
}

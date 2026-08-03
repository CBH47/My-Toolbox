#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "oled_b.h"
#include "inventory.h"
#include "button.h"

#define OLED_B_SDA 4
#define OLED_B_SCL 5
TwoWire oledB_wire(1);
Adafruit_SSD1306 oled_b(128, 64, &oledB_wire, -1, false);

static char messageBuf[64];
static unsigned long messageTime = 0;
#define MESSAGE_DURATION 5000

// Navigation state
static Folder* navCurrentFolder = nullptr;
static int32_t navEncoderPos = 0;
static std::vector<Folder*> navFolderStack;
static std::vector<int32_t> navPositionStack;
static unsigned long lastButtonPressTime = 0;
#define BUTTON_DEBOUNCE_MS 300

// Hover tracking
static const Component* hoveredComponent = nullptr;
static const Folder* hoveredFolder = nullptr;

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

static void oledB_renderNavigationLine(int lineY, const char* text, bool highlight) {
  if (highlight) {
    oled_b.fillRect(0, lineY, 128, 9, SSD1306_WHITE);
    oled_b.setTextColor(SSD1306_BLACK);
  } else {
    oled_b.fillRect(0, lineY, 128, 9, SSD1306_BLACK);
    oled_b.setTextColor(SSD1306_WHITE);
  }
  oled_b.setCursor(4, lineY);
  oled_b.print(text);
}

void oledB_updateNavigation(Folder* rootFolder, int32_t encDelta) {
  if (oledB_hasActiveMessage()) return;

  if (!navCurrentFolder) {
    navCurrentFolder = rootFolder;
    navEncoderPos = 0;
    navFolderStack.clear();
    navPositionStack.clear();
  }

  navEncoderPos += static_cast<int>(encDelta);

  int totalItems = static_cast<int>(navCurrentFolder->subfolders.size()) + static_cast<int>(navCurrentFolder->components.size());
  bool hasBack = (navCurrentFolder != rootFolder);
  int listSize = hasBack ? totalItems + 1 : totalItems;

  if (listSize > 0) {
    if (navEncoderPos < 0) navEncoderPos = 0;
    if (navEncoderPos >= listSize) navEncoderPos = listSize - 1;
  } else {
    navEncoderPos = 0;
  }

  unsigned long now = millis();
  if (button_wasReleased() && (now - lastButtonPressTime) > BUTTON_DEBOUNCE_MS) {
    lastButtonPressTime = now;

    if (hasBack && navEncoderPos == 0) {
      if (!navFolderStack.empty() && !navPositionStack.empty()) {
        navCurrentFolder = navFolderStack.back();
        navFolderStack.pop_back();
        navEncoderPos = navPositionStack.back();
        navPositionStack.pop_back();
      } else {
        navCurrentFolder = inventory_getRoot();
        navEncoderPos = 0;
      }
    } else {
      int itemIdx = navEncoderPos - (hasBack ? 1 : 0);
      if (itemIdx >= 0 && itemIdx < static_cast<int>(navCurrentFolder->subfolders.size())) {
        navFolderStack.push_back(navCurrentFolder);
        navPositionStack.push_back(navEncoderPos);
        navCurrentFolder = navCurrentFolder->subfolders[itemIdx];
        navEncoderPos = 0;
      }
    }

    totalItems = static_cast<int>(navCurrentFolder->subfolders.size()) + static_cast<int>(navCurrentFolder->components.size());
    hasBack = (navCurrentFolder != rootFolder);
    listSize = hasBack ? totalItems + 1 : totalItems;
    if (listSize > 0) {
      if (navEncoderPos < 0) navEncoderPos = 0;
      if (navEncoderPos >= listSize) navEncoderPos = listSize - 1;
    } else {
      navEncoderPos = 0;
    }
  }

  if (listSize <= 0) {
    oled_b.clearDisplay();
    oled_b.setTextSize(1);
    oled_b.setTextColor(SSD1306_WHITE);
    oled_b.setCursor(4, 8);
    oled_b.print(navCurrentFolder->name);
    oled_b.setCursor(4, 20);
    oled_b.println("(empty)");
    if (hasBack) {
      oledB_renderNavigationLine(54, "< Back", false);
    }
    oled_b.display();
    return;
  }

  int visibleLines = 6;
  int scrollOffset = 0;

  if (navEncoderPos >= visibleLines) {
    scrollOffset = navEncoderPos - visibleLines + 1;
  }

  int startLine = 0;

  oled_b.clearDisplay();
  hoveredComponent = nullptr;
  hoveredFolder = nullptr;

  for (int vis = 0; vis < visibleLines && (scrollOffset + vis) < listSize; vis++) {
    int globalIdx = scrollOffset + vis;
    bool isHighlighted = (globalIdx == navEncoderPos);
    int y = startLine + vis * 9;

    if (hasBack && globalIdx == 0) {
      oledB_renderNavigationLine(y, "< Back", isHighlighted);
      continue;
    }

    int itemIdx = globalIdx - (hasBack ? 1 : 0);

    if (itemIdx < static_cast<int>(navCurrentFolder->subfolders.size())) {
      if (isHighlighted) {
        hoveredFolder = navCurrentFolder->subfolders[itemIdx];
      }
      char buf[22];
      snprintf(buf, sizeof(buf), "D %s", navCurrentFolder->subfolders[itemIdx]->name.c_str());
      oledB_renderNavigationLine(y, buf, isHighlighted);
    } else {
      int compIdx = itemIdx - static_cast<int>(navCurrentFolder->subfolders.size());
      if (isHighlighted) {
        hoveredComponent = &navCurrentFolder->components[compIdx];
      }
      char buf[22];
      snprintf(buf, sizeof(buf), "  %s", navCurrentFolder->components[compIdx].name.c_str());
      oledB_renderNavigationLine(y, buf, isHighlighted);
    }
  }

  oled_b.display();
}

const Component* oledB_getHoveredComponent() {
  return hoveredComponent;
}

const Folder* oledB_getHoveredFolder() {
  return hoveredFolder;
}

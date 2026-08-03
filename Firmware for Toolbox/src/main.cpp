#include <Arduino.h>
#include "oled_a.h"
#include "oled_b.h"
#include "button.h"
#include "encoder.h"
#include "wifi.h"
#include "sd_card.h"
#include "inventory.h"

static void showComponentDetailsOnOledA(const Component* comp) {
  if (comp) {
    char buf[48];
    snprintf(buf, sizeof(buf), "Name: %s", comp->name.c_str());
    char qtyBuf[32];
    snprintf(qtyBuf, sizeof(qtyBuf), "Qty: %d", comp->quantity);
    char priceBuf[32];
    snprintf(priceBuf, sizeof(priceBuf), "$%.2f", comp->price);
    char posBuf[32];
    snprintf(posBuf, sizeof(posBuf), "X:%d Y:%d", comp->x, comp->y);
    const char *linesA[4] = {buf, qtyBuf, priceBuf, posBuf};
    oledA_showStatus("", linesA, 4);
  } else {
    const char *linesA[1] = {"No component selected"};
    oledA_showStatus("", linesA, 1);
  }
}

static void showNoSelectionOnOledA() {
  const char *linesA[1] = {"No component selected"};
  oledA_showStatus("", linesA, 1);
}

static void showFolderContentsOnOledA(const Folder* folder) {
  if (!folder) {
    return;
  }

  static char line1[48];
  static char line2[48];
  static char line3[48];
  static char line4[48];
  static char line5[48];
  static char line6[48];

  snprintf(line1, sizeof(line1), "Folder: %s", folder->name.c_str());
  snprintf(line2, sizeof(line2), "Subfolders: %d", static_cast<int>(folder->subfolders.size()));
  snprintf(line3, sizeof(line3), "Components: %d", static_cast<int>(folder->components.size()));

  const int maxPreview = 3;
  int previewLine = 0;
  char* previewLines[maxPreview] = {line4, line5, line6};

  for (size_t i = 0; i < folder->subfolders.size() && previewLine < maxPreview; i++) {
    snprintf(previewLines[previewLine], 48, "D: %s", folder->subfolders[i]->name.c_str());
    previewLine++;
  }

  for (size_t i = 0; i < folder->components.size() && previewLine < maxPreview; i++) {
    snprintf(previewLines[previewLine], 48, "C: %s", folder->components[i].name.c_str());
    previewLine++;
  }

  while (previewLine < maxPreview) {
    snprintf(previewLines[previewLine], 48, "-");
    previewLine++;
  }

  const char *linesA[6] = {line1, line2, line3, line4, line5, line6};
  oledA_showStatus("", linesA, 6);
}

void setup() {
  Serial.begin(115200);
  delay(100);

  oledA_init();
  oledB_init();
  button_init();
  encoder_init();
  sdCard_init();
  inventory_init();
  wifi_init();

  // Replace OLED A init/debug splash immediately with the normal details view.
  showNoSelectionOnOledA();
}

void loop() {
  button_update();

  static int32_t lastEncPos = 0;
  int32_t currentEncPos = encoder_getPosition();
  int32_t encDelta = currentEncPos - lastEncPos;

  static bool hasSelectedComponent = false;
  static Component selectedComponentSnapshot;

  static unsigned long lastOledUpdate = 0;
  if (millis() - lastOledUpdate >= 100) {
    lastOledUpdate = millis();

    Folder* root = inventory_getRoot();
    if (root) {
      oledB_updateNavigation(root, encDelta);
    }

    const Folder* hoveredFolder = oledB_getHoveredFolder();
    const Component* hovered = oledB_getHoveredComponent();
    if (hovered) {
      selectedComponentSnapshot = *hovered;
      hasSelectedComponent = true;
    }

    if (hoveredFolder) {
      showFolderContentsOnOledA(hoveredFolder);
    } else {
      showComponentDetailsOnOledA(hovered ? hovered : (hasSelectedComponent ? &selectedComponentSnapshot : nullptr));
    }

    if (encDelta != 0) {
      lastEncPos = currentEncPos;
    }
  }
}

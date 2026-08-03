#ifndef OLED_B_H
#define OLED_B_H

#include "inventory.h"

void oledB_init();
void oledB_showMessage(const char* msg);
bool oledB_hasActiveMessage();
void oledB_showStatus(const char *title, const char **debugLines, uint8_t debugCount);
void oledB_updateNavigation(Folder *rootFolder, int32_t encDelta);
const Component* oledB_getHoveredComponent();
const Folder* oledB_getHoveredFolder();

#endif

#ifndef OLED_B_H
#define OLED_B_H

void oledB_init();
void oledB_showMessage(const char* msg);
bool oledB_hasActiveMessage();
void oledB_showStatus(const char *title, const char **debugLines, uint8_t debugCount);

#endif

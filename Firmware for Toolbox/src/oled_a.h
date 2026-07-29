#ifndef OLED_A_H
#define OLED_A_H

void oledA_init();
void oledA_showMessage(const char* msg);
bool oledA_hasActiveMessage();
void oledA_showStatus(const char *title, const char **debugLines, uint8_t debugCount);

#endif

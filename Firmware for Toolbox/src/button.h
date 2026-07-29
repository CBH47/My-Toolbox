#ifndef BUTTON_H
#define BUTTON_H

void button_init();
void button_update();
bool button_isPressed();
bool button_wasReleased();
unsigned long button_getPressDuration();
uint32_t button_getPressCount();

#endif

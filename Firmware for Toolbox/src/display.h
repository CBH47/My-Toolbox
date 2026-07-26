#pragma once

#include "config.h"

extern TwoWire I2CBus1;
extern TwoWire I2CBus2;

extern Adafruit_SSD1306 displayA;
extern Adafruit_SSD1306 displayB;
extern GFXcanvas1 canvas;

#define CANVAS_WIDTH 256
#define CANVAS_HEIGHT 400

void initDisplays();
GFXcanvas1* getCanvas();
void pushToDisplays(int scrollOffset = 0);
void updateDisplay();
void drawText(const char* text, int x, int y);
void drawLine(int x0, int y0, int x1, int y1);

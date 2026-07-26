#include "display.h"

TwoWire I2CBus1 = TwoWire(0);
TwoWire I2CBus2 = TwoWire(1);

Adafruit_SSD1306 displayA(SCREEN_WIDTH, SCREEN_HEIGHT, &I2CBus1, -1);
Adafruit_SSD1306 displayB(SCREEN_WIDTH, SCREEN_HEIGHT, &I2CBus2, -1);
GFXcanvas1 canvas(CANVAS_WIDTH, CANVAS_HEIGHT);

void initDisplays() {
    I2CBus1.begin(OLED1_SDA, OLED1_SCL);
    I2CBus2.begin(OLED2_SDA, OLED2_SCL);

    if (!displayA.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
        Serial.println("OLED 1 not found");
        while (1);
    }

    if (!displayB.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
        Serial.println("OLED 2 not found");
        while (1);
    }

    displayA.clearDisplay();
    displayB.clearDisplay();
    canvas.fillScreen(0);

    Serial.println("Dual OLEDs initialized");
}

GFXcanvas1* getCanvas() {
    return &canvas;
}

void pushToDisplays(int scrollOffset) {
    memset(displayA.getBuffer(), 0, SCREEN_WIDTH * (SCREEN_HEIGHT + 7) / 8);
    memset(displayB.getBuffer(), 0, SCREEN_WIDTH * (SCREEN_HEIGHT + 7) / 8);

    uint8_t* bufA = displayA.getBuffer();
    uint8_t* bufB = displayB.getBuffer();

    for (int page = 0; page < SCREEN_HEIGHT / 8; page++) {
        int canvasPageStart = page * 8 + scrollOffset;

        for (int col = 0; col < SCREEN_WIDTH; col++) {
            uint8_t byteA = 0;
            uint8_t byteB = 0;

            for (int rowInPage = 0; rowInPage < 8; rowInPage++) {
                int canvasY = canvasPageStart + rowInPage;
                if (canvasY >= CANVAS_HEIGHT) break;

                if (canvas.getPixel(SEAM + col, canvasY)) {
                    byteA |= (1 << rowInPage);
                }

                if (canvas.getPixel(col, canvasY)) {
                    byteB |= (1 << rowInPage);
                }
            }

            bufA[col + page * SCREEN_WIDTH] = byteA;
            bufB[col + page * SCREEN_WIDTH] = byteB;
        }
    }

    displayA.display();
    displayB.display();
}

void drawText(const char* text, int x, int y) {
    canvas.setCursor(x, y);
    canvas.print(text);
}

void drawLine(int x0, int y0, int x1, int y1) {
    canvas.drawLine(x0, y0, x1, y1, SSD1306_WHITE);
}

void updateDisplay() {
    static int scrollOffset = 0;
    static long lastPosition = 0;

    extern ESP32Encoder encoder;

    long currentPosition = encoder.getCount() * -1;

    if (currentPosition != lastPosition) {
        int delta = currentPosition - lastPosition;
        scrollOffset += delta * 2;

        int maxScroll = CANVAS_HEIGHT - SCREEN_HEIGHT;
        if (scrollOffset < 0) scrollOffset = 0;
        if (scrollOffset > maxScroll) scrollOffset = maxScroll;

        pushToDisplays(scrollOffset);
        lastPosition = currentPosition;
    }
}

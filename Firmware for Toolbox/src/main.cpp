#include "config.h"
#include "display.h"
#include "bluetooth.h"

ESP32Encoder encoder;

const char* scrollText[] = {
    "The quick brown fox jumps over the lazy dog",
    "",
    "Pack my box with five dozen liquor jugs",
    "",
    "How vexingly quick daft zebras jump",
    "",
    "Sphinx of black quartz, judge my vow",
    "",
    "Two driven jocks help fax my big quiz",
    "",
    "The five boxing wizards jump quickly",
    "",
    "Jackdaws love my big sphinx of quartz",
    "",
    "We promptly judged antique ivory buckles",
    "",
    "The job requires extra pluck and zeal",
};

void setup() {
    Serial.begin(115200);

    initBLE();
    initDisplays();

    encoder.attachHalfQuad(ENCODER_A, ENCODER_B);
    encoder.setCount(0);

    getCanvas()->setTextSize(2);
    getCanvas()->setTextColor(SSD1306_WHITE);

    int y = 10;
    for (int i = 0; i < sizeof(scrollText) / sizeof(scrollText[0]); i++) {
        drawText(scrollText[i], 10, y);
        y += 30;
    }

    pushToDisplays();
}

void loop() {
    updateDisplay();
}

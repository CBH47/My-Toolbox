#include <Arduino.h>
#include <SPI.h>
#include <SD.h>
#include "sd_card.h"

#define SD_CS_PIN 46
#define SD_SCK_PIN 10
#define SD_MOSI_PIN 11
#define SD_MISO_PIN 12

static SPIClass hspi(HSPI);
static bool sdPresent = false;

bool sdCard_init() {
  pinMode(SD_CS_PIN, OUTPUT);
  digitalWrite(SD_CS_PIN, HIGH);

  hspi.begin(SD_SCK_PIN, SD_MISO_PIN, SD_MOSI_PIN, -1);
  delay(50);

  if (!SD.begin(SD_CS_PIN, hspi, 80000000)) {
    Serial.println("ERROR: SD card initialization failed");
    Serial.println("Check: Card inserted? CS pin wiring? SPI bus conflict?");
    sdPresent = false;
    return false;
  }

  Serial.println("SD card initialized successfully");
  Serial.printf("Card type: %d\n", SD.cardType());
  Serial.printf("Card size: %.2f MB\n", SD.cardSize() / (1024.0 * 1024.0));
  Serial.printf("File system: %s\n", SD.cardType() == CARD_MMC ? "MMC" : (SD.cardType() == CARD_SDHC ? "SDHC" : "SDSC"));
  
  // Verify we can write and read back
  File testFile = SD.open("/sd_test.txt");
  if (testFile) {
    testFile.close();
    SD.remove("/sd_test.txt");
    Serial.println("SD read/write verification: OK");
  } else {
    File writeFile = SD.open("/sd_test.txt", FILE_WRITE);
    if (writeFile) {
      writeFile.println("SD write test");
      writeFile.close();
      Serial.println("SD write verification: OK");
      
      File readFile = SD.open("/sd_test.txt");
      if (readFile) {
        String content = readFile.readStringUntil('\n');
        readFile.close();
        SD.remove("/sd_test.txt");
        Serial.printf("SD read verification: OK - '%s'\n", content.c_str());
      } else {
        Serial.println("WARNING: SD write OK but read failed");
      }
    } else {
      Serial.println("WARNING: SD init reports OK but cannot write files");
    }
  }
  
  sdPresent = true;
  return true;
}

bool sdCard_isPresent() {
  return sdPresent;
}

uint32_t sdCard_fileCount() {
  if (!sdPresent) return 0;

  File root = SD.open("/");
  if (!root) {
    Serial.println("ERROR: Failed to open root directory");
    return 0;
  }

  uint32_t count = 0;
  File entry = root.openNextFile();
  while (entry) {
    count++;
    entry = root.openNextFile();
  }
  entry.close();
  root.close();

  Serial.printf("SD card file count: %lu\n", count);
  return count;
}

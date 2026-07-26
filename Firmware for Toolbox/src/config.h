#pragma once

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ESP32Encoder.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Display constants
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_ADDR 0x3C
#define SEAM 128

// BLE constants
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// I2C bus pins - Display A (Bus 0)
#define OLED1_SDA 8
#define OLED1_SCL 9

// I2C bus pins - Display B (Bus 1)
#define OLED2_SDA 4
#define OLED2_SCL 5

// Encoder pins
#define ENCODER_A 15
#define ENCODER_B 16

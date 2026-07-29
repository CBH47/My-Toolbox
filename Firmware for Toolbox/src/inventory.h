#ifndef INVENTORY_H
#define INVENTORY_H

#include <Arduino.h>
#include <ArduinoJson.h>
#include <vector>

struct Component {
  String id;
  String name;
  int quantity = 1;
  double price = 0.0;
  int x = 0;
  int y = 0;
  String folderId; // reference to parent folder

  JsonDocument toJson() const;
  static Component fromJson(const JsonVariantConst& src);
};

struct Folder {
  String id;
  String name;
  String parentId; // reference to parent folder (empty for root)

  std::vector<Component> components;
  std::vector<Folder*> subfolders;

  void toJson(JsonDocument& doc) const;
  static Folder* fromJson(const JsonVariantConst& src);

  void addComponent(Component comp);
  bool removeComponent(const String& componentId);
  void addSubfolder(Folder* folder);
  bool removeSubfolder(const String& folderId);
  Component* findComponent(const String& id);
  Folder* findSubfolder(const String& id);
};

bool inventory_init();
Folder* inventory_getRoot();
bool inventory_save_components();
bool inventory_save_folders();
bool inventory_save_all();
bool inventory_load();
void inventory_clear();

#endif

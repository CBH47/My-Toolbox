#include "inventory.h"
#include "sd_card.h"
#include <SD.h>
#include <ArduinoJson.h>

#define COMPONENTS_FILE "/components.json"
#define FOLDERS_FILE "/folders.json"

static Folder* rootFolder = nullptr;

// ---- Component JSON serialization ----

JsonDocument Component::toJson() const {
  JsonDocument doc;
  doc["id"] = id;
  doc["name"] = name;
  doc["quantity"] = quantity;
  doc["price"] = price;
  doc["x"] = x;
  doc["y"] = y;
  doc["folderId"] = folderId;
  return doc;
}

Component Component::fromJson(const JsonVariantConst& src) {
  Component comp;
  comp.id = src["id"].as<String>();
  comp.name = src["name"].as<String>();
  comp.quantity = src["quantity"].as<int>();
  comp.price = src["price"].as<double>();
  comp.x = src["x"].as<int>();
  comp.y = src["y"].as<int>();
  comp.folderId = src["folderId"].as<String>();
  return comp;
}

// ---- Folder JSON serialization (flat record, no nested data) ----

void Folder::toJson(JsonDocument& doc) const {
  doc["id"] = id;
  doc["name"] = name;
  doc["parentId"] = parentId;
}

Folder* Folder::fromJson(const JsonVariantConst& src) {
  Folder* folder = new Folder();
  folder->id = src["id"].as<String>();
  folder->name = src["name"].as<String>();
  folder->parentId = src["parentId"].as<String>();
  return folder;
}

// ---- CRUD operations (in-memory tree) ----

void Folder::addComponent(Component comp) {
  components.push_back(comp);
}

bool Folder::removeComponent(const String& componentId) {
  for (int i = static_cast<int>(components.size()) - 1; i >= 0; i--) {
    if (components[i].id == componentId) {
      components.erase(components.begin() + i);
      return true;
    }
  }
  return false;
}

void Folder::addSubfolder(Folder* folder) {
  subfolders.push_back(folder);
}

bool Folder::removeSubfolder(const String& folderId) {
  for (int i = static_cast<int>(subfolders.size()) - 1; i >= 0; i--) {
    if (subfolders[i]->id == folderId) {
      delete subfolders[i];
      subfolders.erase(subfolders.begin() + i);
      return true;
    }
  }
  return false;
}

Component* Folder::findComponent(const String& id) {
  for (auto& comp : components) {
    if (comp.id == id) return &comp;
  }
  return nullptr;
}

Folder* Folder::findSubfolder(const String& id) {
  for (auto* folderPtr : subfolders) {
    if (folderPtr->id == id) return folderPtr;
    Folder* found = folderPtr->findSubfolder(id);
    if (found) return found;
  }
  return nullptr;
}

// ---- Save: write flat arrays to SD card ----

bool inventory_save_components() {
  if (!sdCard_isPresent()) {
    Serial.println("ERROR: Cannot save components - SD card not present");
    return false;
  }

  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();

  std::vector<Folder*> stack;
  stack.push_back(rootFolder);

  while (!stack.empty()) {
    Folder* current = stack.back();
    stack.pop_back();

    for (size_t i = 0; i < current->components.size(); i++) {
      arr.add(current->components[i].toJson());
    }

    for (size_t i = 0; i < current->subfolders.size(); i++) {
      stack.push_back(current->subfolders[i]);
    }
  }

  // FILE_WRITE appends on SD; remove first so JSON is always rewritten cleanly.
  SD.remove(COMPONENTS_FILE);
  File file = SD.open(COMPONENTS_FILE, FILE_WRITE);
  if (!file) {
    Serial.println("ERROR: Failed to open components file for writing");
    return false;
  }

  size_t bytesWritten = serializeJson(doc, file);
  file.flush();
  file.close();

  if (bytesWritten == 0) {
    Serial.println("ERROR: Failed to write components data");
    return false;
  }

  Serial.printf("Components saved: %d records, %d bytes\n", static_cast<int>(arr.size()), static_cast<int>(bytesWritten));
  return true;
}

bool inventory_save_folders() {
  if (!sdCard_isPresent()) {
    Serial.println("ERROR: Cannot save folders - SD card not present");
    return false;
  }

  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();

  std::vector<Folder*> stack;
  stack.push_back(rootFolder);

  while (!stack.empty()) {
    Folder* current = stack.back();
    stack.pop_back();

    JsonDocument folderDoc;
    current->toJson(folderDoc);
    arr.add(folderDoc);

    for (size_t i = 0; i < current->subfolders.size(); i++) {
      stack.push_back(current->subfolders[i]);
    }
  }

  // FILE_WRITE appends on SD; remove first so JSON is always rewritten cleanly.
  SD.remove(FOLDERS_FILE);
  File file = SD.open(FOLDERS_FILE, FILE_WRITE);
  if (!file) {
    Serial.println("ERROR: Failed to open folders file for writing");
    return false;
  }

  size_t bytesWritten = serializeJson(doc, file);
  file.flush();
  file.close();

  if (bytesWritten == 0) {
    Serial.println("ERROR: Failed to write folders data");
    return false;
  }

  Serial.printf("Folders saved: %d records, %d bytes\n", static_cast<int>(arr.size()), static_cast<int>(bytesWritten));
  return true;
}

bool inventory_save_all() {
  bool ok1 = inventory_save_folders();
  bool ok2 = inventory_save_components();
  return ok1 && ok2;
}

// ---- Load: read flat arrays and reconstruct tree ----

static Folder* buildFolderTree(JsonArray folders) {
  std::vector<Folder*> allFolders;
  for (size_t i = 0; i < folders.size(); i++) {
    Folder* f = Folder::fromJson(folders[i]);
    allFolders.push_back(f);
  }

  Folder* root = nullptr;
  for (size_t i = 0; i < allFolders.size(); i++) {
    if (allFolders[i]->id == "root") {
      root = allFolders[i];
      break;
    }
  }

  if (!root) {
    root = new Folder();
    root->name = "Root";
    root->id = "root";
    root->parentId = "";
  }

  for (size_t i = 0; i < allFolders.size(); i++) {
    Folder* f = allFolders[i];
    if (f == root) {
      continue;
    }

    if (f->parentId.isEmpty() || f->parentId == "root") {
      root->subfolders.push_back(f);
      continue;
    }

    Folder* parent = nullptr;
    for (size_t j = 0; j < allFolders.size(); j++) {
      if (allFolders[j]->id == f->parentId) {
        parent = allFolders[j];
        break;
      }
    }

    if (parent) {
      parent->subfolders.push_back(f);
    } else {
      // Fallback to root when stored parent is missing.
      root->subfolders.push_back(f);
    }
  }

  return root;
}

bool inventory_load() {
  if (!sdCard_isPresent()) {
    Serial.println("ERROR: SD card not present, cannot load");
    return false;
  }

  rootFolder = new Folder();
  rootFolder->name = "Root";
  rootFolder->id = "root";
  rootFolder->parentId = "";

  File folderFile = SD.open(FOLDERS_FILE);
  if (folderFile) {
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, folderFile);
    folderFile.close();

    if (!error && doc.is<JsonArray>()) {
      Folder* loadedRoot = buildFolderTree(doc.as<JsonArray>());
      if (loadedRoot) {
        for (size_t i = 0; i < loadedRoot->subfolders.size(); i++) {
          rootFolder->subfolders.push_back(loadedRoot->subfolders[i]);
        }
        delete loadedRoot;

        Serial.printf("Folders loaded: %d subfolders\n", static_cast<int>(rootFolder->subfolders.size()));
      } else {
        Serial.println("WARNING: Failed to build folder tree");
      }
    } else if (error) {
      Serial.printf("WARNING: No valid folders file (%s), starting fresh\n", error.c_str());
    }
  } else {
    Serial.println("No existing folders file found, starting fresh");
  }

  File compFile = SD.open(COMPONENTS_FILE);
  if (compFile) {
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, compFile);
    compFile.close();

    if (!error && doc.is<JsonArray>()) {
      for (size_t i = 0; i < doc.size(); i++) {
        Component comp = Component::fromJson(doc[i]);

        Folder* targetFolder = rootFolder->findSubfolder(comp.folderId);
        if (!targetFolder && comp.folderId == "root") {
          targetFolder = rootFolder;
        }

        if (targetFolder) {
          targetFolder->addComponent(comp);
        } else {
          Serial.printf("WARNING: Component '%s' references unknown folder '%s', placing in root\n",
                        comp.name.c_str(), comp.folderId.c_str());
          rootFolder->addComponent(comp);
        }
      }

      Serial.printf("Components loaded: %d records\n", static_cast<int>(doc.size()));
    } else if (error) {
      Serial.printf("WARNING: No valid components file (%s), starting fresh\n", error.c_str());
    }
  } else {
    Serial.println("No existing components file found, starting fresh");
  }

  int totalComps = 0;
  int totalFolders = 0;
  std::vector<Folder*> stack;
  stack.push_back(rootFolder);
  while (!stack.empty()) {
    Folder* current = stack.back();
    stack.pop_back();
    totalComps += static_cast<int>(current->components.size());
    totalFolders++;
    for (size_t i = 0; i < current->subfolders.size(); i++) {
      stack.push_back(current->subfolders[i]);
    }
  }

  Serial.printf("Inventory loaded: %d components, %d folders\n", totalComps, totalFolders);
  return true;
}

// ---- Init / Clear ----

bool inventory_init() {
  rootFolder = new Folder();
  rootFolder->name = "Root";
  rootFolder->id = "root";
  rootFolder->parentId = "";

  bool loaded = inventory_load();
  if (!loaded) {
    Serial.println("WARNING: Load failed, using empty inventory");
  }
  return true;
}

Folder* inventory_getRoot() {
  return rootFolder;
}

void inventory_clear() {
  if (!rootFolder) return;

  std::vector<Folder*> stack;
  stack.push_back(rootFolder);
  while (!stack.empty()) {
    Folder* current = stack.back();
    stack.pop_back();
    for (size_t i = 0; i < current->subfolders.size(); i++) {
      stack.push_back(current->subfolders[i]);
    }
  }

  rootFolder->components.clear();
  rootFolder->subfolders.clear();

  inventory_save_all();
  Serial.println("Inventory cleared");
}

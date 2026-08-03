#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <functional>
#include "wifi.h"
#include "oled_a.h"
#include "oled_b.h"
#include "inventory.h"

#define AP_SSID "Cam's Toolbox"
#define AP_PASSWORD ""

static AsyncWebServer server(80);
static const char* APP_CLIENT_HEADER = "X-Toolbox-Client";
static const char* APP_CLIENT_VALUE = "mobile-app";

const char index_html[] PROGMEM = R"rawliteral(<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Toolbox Inventory</title>
<style>body{font-family:Arial,sans-serif;max-width:700px;margin:40px auto;padding:20px;background:#1a1a2e;color:#eee;}
h1{text-align:center;color:#00d4ff;}h2{color:#00d4ff;border-bottom:1px solid #333;padding-bottom:5px;}
form{background:#16213e;padding:15px;border-radius:8px;margin:10px 0;}label{display:block;margin-top:10px;font-weight:bold;}
input,select{width:100%;padding:8px;margin-top:4px;background:#0f3460;color:#eee;border:1px solid #333;border-radius:4px;box-sizing:border-box;}
button{display:inline-block;margin:8px 5px 0;padding:10px 20px;font-size:14px;border:none;border-radius:5px;cursor:pointer;color:#fff;}
.btn-add{background:#2ecc71;}
.btn-save{background:#3498db;}.btn-refresh{background:#9b59b6;}
#status{text-align:center;margin-top:10px;font-size:14px;color:#aaa;}
.folder-item{border-left:3px solid #00d4ff;padding-left:10px;margin:5px 0;}
.comp-row{display:flex;gap:8px;align-items:center;background:#0f3460;padding:6px;border-radius:4px;margin:4px 0;}
.comp-row input{flex:1;margin-top:0;}
.comp-name{font-weight:bold;color:#00d4ff;min-width:120px;}
#inventory-tree{margin:15px 0;}
</style></head>
<body><h1>Toolbox Inventory Manager</h1>
<div id="status"></div>

<h2>Add Component</h2>
<form id="compForm">
<label>Name:</label><input type="text" id="compName" required>
<label>Quantity:</label><input type="number" id="compQty" value="1" min="0">
<label>Price:</label><input type="number" id="compPrice" step="0.01" value="0.00">
<label>X Position:</label><input type="number" id="compX" value="0">
<label>Y Position:</label><input type="number" id="compY" value="0">
<label>Folder (optional):</label><select id="compFolder"><option value="">Root</option></select>
<button type="submit" class="btn-add">Add Component</button>
</form>

<h2>Add Folder</h2>
<form id="folderForm">
<label>Folder Name:</label><input type="text" id="folderName" required>
<label>Parent Folder (optional):</label><select id="parentFolder"><option value="">Root</option></select>
<button type="submit" class="btn-add">Add Folder</button>
</form>

<h2>Inventory Structure</h2>
<div id="inventory-tree"></div>
<button onclick="loadInventory()" class="btn-refresh">Refresh</button>

<script>
function showStatus(msg) {
  var el = document.getElementById('status');
  el.textContent = msg;
  setTimeout(function(){ el.textContent=''; }, 2000);
}

function sendReq(method, url, data, cb) {
  var x = new XMLHttpRequest();
  x.open(method, url);
  if (data && method === 'POST') {
    x.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  }
  x.onload = function() {
    showStatus(x.responseText);
    if (cb) cb(x.responseText);
  };
  x.send(data || null);
}

document.getElementById('compForm').onsubmit = function(e) {
  e.preventDefault();
  var name = document.getElementById('compName').value;
  var qty = document.getElementById('compQty').value;
  var price = document.getElementById('compPrice').value;
  var x = document.getElementById('compX').value;
  var y = document.getElementById('compY').value;
  var folderId = document.getElementById('compFolder').value;
  sendReq('POST', '/api/component?name='+encodeURIComponent(name)+'&quantity='+qty+'&price='+price+'&x='+x+'&y='+y+(folderId?'&folderId='+encodeURIComponent(folderId):''));
  this.reset();
};

document.getElementById('folderForm').onsubmit = function(e) {
  e.preventDefault();
  var name = document.getElementById('folderName').value;
  var parentId = document.getElementById('parentFolder').value;
  sendReq('POST', '/api/folder?name='+encodeURIComponent(name)+(parentId?'&parentId='+encodeURIComponent(parentId):''));
  this.reset();
};

function loadInventory() {
  var x = new XMLHttpRequest();
  x.open('GET', '/api/inventory');
  x.onload = function() {
    if (x.status === 200) {
      renderTree(JSON.parse(x.responseText));
      updateFolderSelects(JSON.parse(x.responseText));
    } else {
      showStatus('Failed to load inventory');
    }
  };
  x.send();
}

function updateFolderSelects(folder) {
  var compSel = document.getElementById('compFolder');
  var parentSel = document.getElementById('parentFolder');
  compSel.innerHTML = '<option value="">Root</option>';
  parentSel.innerHTML = '<option value="">Root</option>';
  buildOptions(folder, compSel);
  buildOptions(folder, parentSel);
}

function buildOptions(f, sel) {
  var subs = f.subfolders || [];
  for (var i = 0; i < subs.length; i++) {
    var opt = document.createElement('option');
    opt.value = subs[i].id;
    opt.textContent = subs[i].name;
    sel.appendChild(opt);
    buildOptions(subs[i], sel);
  }
}

function renderTree(folder) {
  var container = document.getElementById('inventory-tree');
  container.innerHTML = '';
  container.appendChild(renderFolderNode(folder, ''));
}

function renderFolderNode(folder, prefix) {
  var div = document.createElement('div');
  div.className = 'folder-item';
  var title = document.createElement('strong');
  title.textContent = (prefix ? prefix + ' > ' : '') + folder.name;
  div.appendChild(title);

  var comps = folder.components || [];
  for (var i = 0; i < comps.length; i++) {
    var c = comps[i];
    var row = document.createElement('div');
    row.className = 'comp-row';
    row.innerHTML = '<span class="comp-name">'+c.name+'</span><span>Qty: '+c.quantity+' | $'+c.price+' | ('+c.x+','+c.y+')</span>';
    div.appendChild(row);
  }

  var subs = folder.subfolders || [];
  for (var j = 0; j < subs.length; j++) {
    div.appendChild(renderFolderNode(subs[j], prefix + 'Sub'));
  }

  return div;
}

loadInventory();
</script>
</body></html>)rawliteral";

void wifi_handleMessage(const char* oledTarget, const char* message) {
  if (strcmp(oledTarget, "A") == 0) {
    oledA_showMessage(message);
  } else if (strcmp(oledTarget, "B") == 0) {
    oledB_showMessage(message);
  } else {
    oledA_showMessage(message);
    oledB_showMessage(message);
  }
}

static String generateId() {
  return String(micros()) + "-" + String(random(0xFFFF), HEX);
}

static String requestArgValue(AsyncWebServerRequest* request, const char* key) {
  if (request->hasParam(key, true)) {
    return request->getParam(key, true)->value();
  }
  if (request->hasParam(key)) {
    return request->getParam(key)->value();
  }
  return request->arg(key);
}

static bool removeComponentFromTree(Folder* folder, const String& componentId) {
  if (!folder) return false;
  if (folder->removeComponent(componentId)) {
    return true;
  }
  for (size_t i = 0; i < folder->subfolders.size(); i++) {
    if (removeComponentFromTree(folder->subfolders[i], componentId)) {
      return true;
    }
  }
  return false;
}

static Folder* findParentFolder(Folder* current, const String& childId) {
  if (!current) return nullptr;
  for (size_t i = 0; i < current->subfolders.size(); i++) {
    Folder* child = current->subfolders[i];
    if (child && child->id == childId) {
      return current;
    }
    Folder* found = findParentFolder(child, childId);
    if (found) {
      return found;
    }
  }
  return nullptr;
}

static bool folderContainsId(Folder* folder, const String& candidateId) {
  if (!folder) return false;
  if (folder->id == candidateId) return true;
  for (size_t i = 0; i < folder->subfolders.size(); i++) {
    if (folderContainsId(folder->subfolders[i], candidateId)) {
      return true;
    }
  }
  return false;
}

static Folder* detachSubfolder(Folder* parent, const String& folderId) {
  if (!parent) return nullptr;
  for (size_t i = 0; i < parent->subfolders.size(); i++) {
    Folder* child = parent->subfolders[i];
    if (child && child->id == folderId) {
      parent->subfolders.erase(parent->subfolders.begin() + i);
      return child;
    }
  }
  return nullptr;
}

void setupWebServer() {
  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send_P(200, "text/html", index_html);
  });

  server.on("/api/ping", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(200, "text/plain", "OK");
  });

  server.on("/send", HTTP_POST, [](AsyncWebServerRequest *request) {
    String target = request->arg("target");
    String message = request->arg("message");
    if (message.length() > 0) {
      wifi_handleMessage(target.c_str(), message.c_str());
      request->send(200, "text/plain", "OK");
    } else {
      request->send(400, "text/plain", "No message");
    }
  });

  server.on("/clear", HTTP_POST, [](AsyncWebServerRequest *request) {
    oledA_showMessage("");
    oledB_showMessage("");
    request->send(200, "text/plain", "OK");
  });

  server.on("/api/component", HTTP_POST, [](AsyncWebServerRequest *request) {
    String action = requestArgValue(request, "action");
    if (action == "delete") {
      if (!request->hasHeader(APP_CLIENT_HEADER) || request->getHeader(APP_CLIENT_HEADER)->value() != APP_CLIENT_VALUE) {
        request->send(403, "text/plain", "Delete is app-only");
        return;
      }

      String componentId = requestArgValue(request, "id");
      String folderId = requestArgValue(request, "folderId");
      if (componentId.length() == 0) {
        request->send(400, "text/plain", "Missing component id");
        return;
      }

      Folder* root = inventory_getRoot();
      if (!root) {
        request->send(503, "text/plain", "Inventory not ready");
        return;
      }

      bool removed = false;
      if (folderId.length() > 0 && folderId != "root") {
        Folder* targetFolder = root->findSubfolder(folderId);
        if (!targetFolder) {
          request->send(404, "text/plain", "Folder not found");
          return;
        }
        removed = targetFolder->removeComponent(componentId);
        if (!removed) {
          removed = removeComponentFromTree(root, componentId);
        }
      } else {
        removed = removeComponentFromTree(root, componentId);
      }

      if (!removed) {
        request->send(404, "text/plain", "Component not found");
        return;
      }

      if (inventory_save_all()) {
        request->send(200, "text/plain", "Component deleted");
      } else {
        request->send(500, "text/plain", "Failed to save to SD card");
      }
      return;
    }

    String id = requestArgValue(request, "id");
    String name = requestArgValue(request, "name");
    int qty = requestArgValue(request, "quantity").toInt();
    double price = requestArgValue(request, "price").toDouble();
    int x = requestArgValue(request, "x").toInt();
    int y = requestArgValue(request, "y").toInt();
    String folderId = requestArgValue(request, "folderId");

    // Safety net: if an app-authenticated request includes only id (no name), treat it as delete.
    const bool isAppClient = request->hasHeader(APP_CLIENT_HEADER) && request->getHeader(APP_CLIENT_HEADER)->value() == APP_CLIENT_VALUE;
    if (isAppClient && id.length() > 0 && name.length() == 0) {
      Folder* root = inventory_getRoot();
      if (!root) {
        request->send(503, "text/plain", "Inventory not ready");
        return;
      }

      bool removed = false;
      if (folderId.length() > 0 && folderId != "root") {
        Folder* targetFolder = root->findSubfolder(folderId);
        if (!targetFolder) {
          request->send(404, "text/plain", "Folder not found");
          return;
        }
        removed = targetFolder->removeComponent(id);
        if (!removed) {
          removed = removeComponentFromTree(root, id);
        }
      } else {
        removed = removeComponentFromTree(root, id);
      }

      if (!removed) {
        request->send(404, "text/plain", "Component not found");
        return;
      }

      if (inventory_save_all()) {
        request->send(200, "text/plain", "Component deleted");
      } else {
        request->send(500, "text/plain", "Failed to save to SD card");
      }
      return;
    }

    if (name.length() == 0) {
      request->send(400, "text/plain", "Missing name");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }
    Folder* targetFolder = root;

    if (folderId.length() > 0 && folderId != "root") {
      targetFolder = root->findSubfolder(folderId);
      if (!targetFolder) {
        Serial.printf("Delete request referenced missing folder '%s'; falling back to full-tree search\n", folderId.c_str());
        targetFolder = root;
      }
    }

    Component comp;
    comp.id = id.length() > 0 ? id : generateId();
    comp.name = name;
    comp.quantity = qty;
    comp.price = price;
    comp.x = x;
    comp.y = y;
    comp.folderId = folderId.length() > 0 ? folderId : "root";

    targetFolder->addComponent(comp);
    if (inventory_save_all()) {
      request->send(200, "text/plain", "Component added");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });


  server.on("/api/folder", HTTP_POST, [](AsyncWebServerRequest *request) {
    String action = requestArgValue(request, "action");
    String id = requestArgValue(request, "id");
    String name = requestArgValue(request, "name");
    String parentId = requestArgValue(request, "parentId");
    String cascadeRaw = requestArgValue(request, "cascade");
    bool cascade = cascadeRaw == "1" || cascadeRaw == "true" || cascadeRaw == "TRUE";

    const bool isAppClient = request->hasHeader(APP_CLIENT_HEADER) && request->getHeader(APP_CLIENT_HEADER)->value() == APP_CLIENT_VALUE;

    // Compatibility path for older app flows: accept delete through /api/folder.
    const bool looksLikeLegacyDelete = isAppClient && id.length() > 0 && name.length() == 0 && parentId.length() == 0;
    if (action == "delete" || looksLikeLegacyDelete) {
      if (!isAppClient) {
        request->send(403, "text/plain", "Folder management is app-only");
        return;
      }
      if (id == "root") {
        request->send(400, "text/plain", "Invalid folder id");
        return;
      }

      Folder* root = inventory_getRoot();
      if (!root) {
        request->send(503, "text/plain", "Inventory not ready");
        return;
      }

      Folder* target = root->findSubfolder(id);
      if (!target) {
        request->send(404, "text/plain", "Folder not found");
        return;
      }

      if (!cascade && (!target->components.empty() || !target->subfolders.empty())) {
        request->send(409, "text/plain", "Folder not empty");
        return;
      }

      Folder* parent = findParentFolder(root, id);
      if (!parent) {
        request->send(404, "text/plain", "Parent folder not found");
        return;
      }

      if (!parent->removeSubfolder(id)) {
        request->send(500, "text/plain", "Failed to delete folder");
        return;
      }

      if (inventory_save_all()) {
        request->send(200, "text/plain", "Folder deleted");
      } else {
        request->send(500, "text/plain", "Failed to save to SD card");
      }
      return;
    }

    if (name.length() == 0) {
      request->send(400, "text/plain", "Missing folder name");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }
    Folder* targetFolder = root;

    if (parentId.length() > 0 && parentId != "root") {
      targetFolder = root->findSubfolder(parentId);
      if (!targetFolder) {
        request->send(404, "text/plain", "Parent folder not found");
        return;
      }
    }

    Folder* newFolder = new Folder();
    newFolder->name = name;
    newFolder->id = id.length() > 0 ? id : generateId();
    newFolder->parentId = (parentId.length() > 0 && parentId != "root") ? parentId : "";

    targetFolder->addSubfolder(newFolder);
    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder added");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
      targetFolder->removeSubfolder(newFolder->id);
    }
  });

  server.on("/api/folder/rename", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (!request->hasHeader(APP_CLIENT_HEADER) || request->getHeader(APP_CLIENT_HEADER)->value() != APP_CLIENT_VALUE) {
      request->send(403, "text/plain", "Folder management is app-only");
      return;
    }

    String folderId = requestArgValue(request, "id");
    String name = requestArgValue(request, "name");

    if (folderId.length() == 0 || folderId == "root") {
      request->send(400, "text/plain", "Invalid folder id");
      return;
    }
    if (name.length() == 0) {
      request->send(400, "text/plain", "Missing folder name");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }

    Folder* target = root->findSubfolder(folderId);
    if (!target) {
      request->send(404, "text/plain", "Folder not found");
      return;
    }

    target->name = name;
    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder renamed");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/folder/move", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (!request->hasHeader(APP_CLIENT_HEADER) || request->getHeader(APP_CLIENT_HEADER)->value() != APP_CLIENT_VALUE) {
      request->send(403, "text/plain", "Folder management is app-only");
      return;
    }

    String folderId = requestArgValue(request, "id");
    String newParentId = requestArgValue(request, "parentId");

    if (folderId.length() == 0 || folderId == "root") {
      request->send(400, "text/plain", "Invalid folder id");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }

    Folder* target = root->findSubfolder(folderId);
    if (!target) {
      request->send(404, "text/plain", "Folder not found");
      return;
    }

    Folder* newParent = root;
    if (newParentId.length() > 0 && newParentId != "root") {
      newParent = root->findSubfolder(newParentId);
      if (!newParent) {
        request->send(404, "text/plain", "Destination folder not found");
        return;
      }
    }

    if (newParent->id == target->id || folderContainsId(target, newParent->id)) {
      request->send(400, "text/plain", "Invalid destination");
      return;
    }

    Folder* oldParent = findParentFolder(root, folderId);
    if (!oldParent) {
      request->send(404, "text/plain", "Current parent not found");
      return;
    }

    Folder* detached = detachSubfolder(oldParent, folderId);
    if (!detached) {
      request->send(500, "text/plain", "Failed to detach folder");
      return;
    }

    detached->parentId = (newParent == root) ? "" : newParent->id;
    newParent->addSubfolder(detached);

    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder moved");
    } else {
      detachSubfolder(newParent, detached->id);
      oldParent->addSubfolder(detached);
      detached->parentId = oldParent->id == "root" ? "" : oldParent->id;
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/folder/delete", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (!request->hasHeader(APP_CLIENT_HEADER) || request->getHeader(APP_CLIENT_HEADER)->value() != APP_CLIENT_VALUE) {
      request->send(403, "text/plain", "Folder management is app-only");
      return;
    }

    String folderId = requestArgValue(request, "id");
    String cascadeRaw = requestArgValue(request, "cascade");
    bool cascade = cascadeRaw == "1" || cascadeRaw == "true" || cascadeRaw == "TRUE";

    if (folderId.length() == 0 || folderId == "root") {
      request->send(400, "text/plain", "Invalid folder id");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }

    Folder* target = root->findSubfolder(folderId);
    if (!target) {
      request->send(404, "text/plain", "Folder not found");
      return;
    }

    if (!cascade && (!target->components.empty() || !target->subfolders.empty())) {
      request->send(409, "text/plain", "Folder not empty");
      return;
    }

    Folder* parent = findParentFolder(root, folderId);
    if (!parent) {
      request->send(404, "text/plain", "Parent folder not found");
      return;
    }

    if (!parent->removeSubfolder(folderId)) {
      request->send(500, "text/plain", "Failed to delete folder");
      return;
    }

    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder deleted");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/component/delete", HTTP_POST, [](AsyncWebServerRequest *request) {
    if (!request->hasHeader(APP_CLIENT_HEADER) || request->getHeader(APP_CLIENT_HEADER)->value() != APP_CLIENT_VALUE) {
      request->send(403, "text/plain", "Delete is app-only");
      return;
    }

    String componentId = requestArgValue(request, "id");
    String folderId = requestArgValue(request, "folderId");

    if (componentId.length() == 0) {
      request->send(400, "text/plain", "Missing component id");
      return;
    }

    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "text/plain", "Inventory not ready");
      return;
    }

    bool removed = false;
    if (folderId.length() > 0 && folderId != "root") {
      Folder* targetFolder = root->findSubfolder(folderId);
      if (!targetFolder) {
        request->send(404, "text/plain", "Folder not found");
        return;
      }
      removed = targetFolder->removeComponent(componentId);
      if (!removed) {
        // Fallback in case stale folder context was provided by the app.
        removed = removeComponentFromTree(root, componentId);
      }
    } else {
      removed = removeComponentFromTree(root, componentId);
    }

    if (!removed) {
      request->send(404, "text/plain", "Component not found");
      return;
    }

    if (inventory_save_all()) {
      request->send(200, "text/plain", "Component deleted");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/inventory", HTTP_GET, [](AsyncWebServerRequest *request) {
    Folder* root = inventory_getRoot();
    if (!root) {
      request->send(503, "application/json", "{\"id\":\"root\",\"name\":\"Root\",\"components\":[],\"subfolders\":[]}");
      return;
    }

    // Build nested tree structure and always include empty arrays for UI stability.
    std::function<void(Folder*, JsonObject)> buildNode = [&](Folder* f, JsonObject node) {
      node["id"] = f->id;
      node["name"] = f->name;

      JsonArray components = node["components"].to<JsonArray>();
      for (size_t i = 0; i < f->components.size(); i++) {
        JsonObject comp = components.add<JsonObject>();
        comp["id"] = f->components[i].id;
        comp["name"] = f->components[i].name;
        comp["quantity"] = f->components[i].quantity;
        comp["price"] = f->components[i].price;
        comp["x"] = f->components[i].x;
        comp["y"] = f->components[i].y;
      }

      JsonArray subfolders = node["subfolders"].to<JsonArray>();
      for (size_t i = 0; i < f->subfolders.size(); i++) {
        JsonObject subNode = subfolders.add<JsonObject>();
        buildNode(f->subfolders[i], subNode);
      }
    };

    JsonDocument rootDoc;
    buildNode(root, rootDoc.to<JsonObject>());
    String output;
    serializeJson(rootDoc, output);
    request->send(200, "application/json", output);
  });

  server.begin();
}

void wifiTask(void* parameter) {
  WiFi.mode(WIFI_AP);
  bool apStarted = WiFi.softAP(AP_SSID, AP_PASSWORD);
  if (!apStarted) {
    Serial.println("ERROR: Failed to start WiFi AP");
  }
  Serial.printf("WiFi AP started: %s\n", AP_SSID);
  Serial.printf("Connect to: http://%s\n", WiFi.softAPIP().toString().c_str());

  setupWebServer();

  while (true) {
    delay(5);
  }
}

void wifi_init() {
  xTaskCreatePinnedToCore(
    wifiTask,
    "wifi_task",
    10000,
    NULL,
    1,
    NULL,
    1
  );
}

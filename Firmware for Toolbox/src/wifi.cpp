#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include "wifi.h"
#include "oled_a.h"
#include "oled_b.h"
#include "inventory.h"

#define AP_SSID "Toolbox-OLED"
#define AP_PASSWORD ""

static AsyncWebServer server(80);

const char index_html[] PROGMEM = R"rawliteral(<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>Toolbox Inventory</title>
<style>body{font-family:Arial,sans-serif;max-width:700px;margin:40px auto;padding:20px;background:#1a1a2e;color:#eee;}
h1{text-align:center;color:#00d4ff;}h2{color:#00d4ff;border-bottom:1px solid #333;padding-bottom:5px;}
form{background:#16213e;padding:15px;border-radius:8px;margin:10px 0;}label{display:block;margin-top:10px;font-weight:bold;}
input,select{width:100%;padding:8px;margin-top:4px;background:#0f3460;color:#eee;border:1px solid #333;border-radius:4px;box-sizing:border-box;}
button{display:inline-block;margin:8px 5px 0;padding:10px 20px;font-size:14px;border:none;border-radius:5px;cursor:pointer;color:#fff;}
.btn-add{background:#2ecc71;}.btn-del{background:#e74c3c;padding:5px 10px;margin:2px;font-size:12px;}
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
  for (var i = 0; i < f.subfolders.length; i++) {
    var opt = document.createElement('option');
    opt.value = f.subfolders[i].id;
    opt.textContent = f.subfolders[i].name;
    sel.appendChild(opt);
    buildOptions(f.subfolders[i], sel);
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

  for (var i = 0; i < folder.components.length; i++) {
    var c = folder.components[i];
    var row = document.createElement('div');
    row.className = 'comp-row';
    row.innerHTML = '<span class="comp-name">'+c.name+'</span><span>Qty: '+c.quantity+' | $'+c.price+' | ('+c.x+','+c.y+')</span>';
    var delBtn = document.createElement('button');
    delBtn.className = 'btn-del';
    delBtn.textContent = 'Delete';
    delBtn.onclick = (function(id, fid) { return function() { sendReq('POST', '/api/component/delete?id='+encodeURIComponent(id)+'&folderId='+(fid||'root')); loadInventory(); }; })(c.id, folder.id);
    row.appendChild(delBtn);
    div.appendChild(row);
  }

  for (var j = 0; j < folder.subfolders.length; j++) {
    div.appendChild(renderFolderNode(folder.subfolders[j], prefix + 'Sub'));
  }

  var delFolderBtn = document.createElement('button');
  delFolderBtn.className = 'btn-del';
  delFolderBtn.textContent = 'Delete Folder';
  delFolderBtn.onclick = (function(id) { return function() { sendReq('POST', '/api/folder/delete?id='+encodeURIComponent(id)); loadInventory(); }; })(folder.id);
  div.appendChild(delFolderBtn);

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

void setupWebServer() {
  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send_P(200, "text/html", index_html);
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
    String name = request->arg("name");
    int qty = request->arg("quantity").toInt();
    double price = request->arg("price").toDouble();
    int x = request->arg("x").toInt();
    int y = request->arg("y").toInt();
    String folderId = request->arg("folderId");

    if (name.length() == 0) {
      request->send(400, "text/plain", "Missing name");
      return;
    }

    Folder* root = inventory_getRoot();
    Folder* targetFolder = root;

    if (folderId.length() > 0 && folderId != "root") {
      targetFolder = root->findSubfolder(folderId);
      if (!targetFolder) {
        request->send(404, "text/plain", "Folder not found");
        return;
      }
    }

    Component comp;
    comp.id = generateId();
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

  server.on("/api/component/delete", HTTP_POST, [](AsyncWebServerRequest *request) {
    String compId = request->arg("id");
    String folderId = request->arg("folderId");

    if (compId.length() == 0) {
      request->send(400, "text/plain", "Missing component id");
      return;
    }

    Folder* root = inventory_getRoot();
    Folder* targetFolder = root;

    if (folderId.length() > 0 && folderId != "root") {
      targetFolder = root->findSubfolder(folderId);
      if (!targetFolder) {
        request->send(404, "text/plain", "Folder not found");
        return;
      }
    }

    bool removed = targetFolder->removeComponent(compId);
    if (removed && inventory_save_all()) {
      request->send(200, "text/plain", "Component deleted");
    } else if (!removed) {
      request->send(404, "text/plain", "Component not found");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/folder", HTTP_POST, [](AsyncWebServerRequest *request) {
    String name = request->arg("name");
    String parentId = request->arg("parentId");

    if (name.length() == 0) {
      request->send(400, "text/plain", "Missing folder name");
      return;
    }

    Folder* root = inventory_getRoot();
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
    newFolder->id = generateId();
    newFolder->parentId = (parentId.length() > 0 && parentId != "root") ? parentId : "";

    targetFolder->addSubfolder(newFolder);
    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder added");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
      targetFolder->removeSubfolder(newFolder->id);
    }
  });

  server.on("/api/folder/delete", HTTP_POST, [](AsyncWebServerRequest *request) {
    String id = request->arg("id");

    if (id.length() == 0 || id == "root") {
      request->send(400, "text/plain", "Cannot delete root folder");
      return;
    }

    Folder* root = inventory_getRoot();
    
    // Find the folder and its parent to move components up
    std::vector<Folder*> stack;
    stack.push_back(root);
    Folder* targetFolder = nullptr;
    Folder* parentFolder = nullptr;

    while (!stack.empty()) {
      Folder* current = stack.back();
      stack.pop_back();

      for (size_t i = 0; i < current->subfolders.size(); i++) {
        if (current->subfolders[i]->id == id) {
          targetFolder = current->subfolders[i];
          parentFolder = current;
          break;
        }
        stack.push_back(current->subfolders[i]);
      }
      if (targetFolder) break;
    }

    if (!targetFolder || !parentFolder) {
      request->send(404, "text/plain", "Folder not found");
      return;
    }

    // Move components from deleted folder to parent folder
    for (size_t i = 0; i < targetFolder->components.size(); i++) {
      targetFolder->components[i].folderId = parentFolder->id;
      parentFolder->addComponent(targetFolder->components[i]);
    }

    parentFolder->removeSubfolder(id);
    
    if (inventory_save_all()) {
      request->send(200, "text/plain", "Folder deleted");
    } else {
      request->send(500, "text/plain", "Failed to save to SD card");
    }
  });

  server.on("/api/inventory", HTTP_GET, [](AsyncWebServerRequest *request) {
    Folder* root = inventory_getRoot();
    JsonDocument doc;
    
    // Build tree structure for the web UI (nested format)
    doc["id"] = root->id;
    doc["name"] = root->name;
    doc["components"] = JsonArray();
    doc["subfolders"] = JsonArray();

    for (size_t i = 0; i < root->components.size(); i++) {
      JsonDocument compDoc;
      compDoc["id"] = root->components[i].id;
      compDoc["name"] = root->components[i].name;
      compDoc["quantity"] = root->components[i].quantity;
      compDoc["price"] = root->components[i].price;
      compDoc["x"] = root->components[i].x;
      compDoc["y"] = root->components[i].y;
      doc["components"].add(compDoc);
    }

    for (size_t i = 0; i < root->subfolders.size(); i++) {
      // Recursively build subfolder nodes
      std::vector<Folder*> stack;
      stack.push_back(root->subfolders[i]);
      
      while (!stack.empty()) {
        Folder* f = stack.back();
        stack.pop_back();

        JsonDocument folderDoc;
        folderDoc["id"] = f->id;
        folderDoc["name"] = f->name;
        
        for (size_t j = 0; j < f->components.size(); j++) {
          JsonDocument compDoc;
          compDoc["id"] = f->components[j].id;
          compDoc["name"] = f->components[j].name;
          compDoc["quantity"] = f->components[j].quantity;
          compDoc["price"] = f->components[j].price;
          compDoc["x"] = f->components[j].x;
          compDoc["y"] = f->components[j].y;
          folderDoc["components"].add(compDoc);
        }

        for (size_t j = 0; j < f->subfolders.size(); j++) {
          stack.push_back(f->subfolders[j]);
        }

        doc["subfolders"].add(folderDoc);
      }
    }

    String output;
    serializeJson(doc, output);
    request->send(200, "application/json", output);
  });

  server.begin();
}

void wifiTask(void* parameter) {
  WiFi.softAP(AP_SSID, AP_PASSWORD);
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

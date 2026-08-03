import '../models/component.dart';
import '../models/folder.dart';
import '../services/database_service.dart';
import '../services/firmware_api_service.dart';

enum ConflictChoice { esp, app }

class ComponentConflict {
  final String id;
  final Component? espComponent;
  final Component? appComponent;

  const ComponentConflict({
    required this.id,
    required this.espComponent,
    required this.appComponent,
  });
}

class FolderConflict {
  final String id;
  final Folder? espFolder;
  final Folder? appFolder;

  const FolderConflict({
    required this.id,
    required this.espFolder,
    required this.appFolder,
  });
}

class SyncResult {
  final bool success;
  final int itemCount;
  final String? error;
  final List<ComponentConflict> conflicts;
  final List<FolderConflict> folderConflicts;

  SyncResult({
    required this.success,
    this.itemCount = 0,
    this.error,
    this.conflicts = const [],
    this.folderConflicts = const [],
  });
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final FirmwareApiService _api = FirmwareApiService();
  final DatabaseService _db = DatabaseService();

  bool get isConnected => _api.isConnected;
  String? get espIp => _api.espIp;
  String? get lastConnectionError => _api.lastConnectionError;
  String? get lastDeleteError => _api.lastDeleteError;
  String? get lastFolderError => _api.lastFolderError;

  void setEspIp(String ip) {
    _api.setEspIp(ip);
  }

  void setConnectionState(bool connected) {
    _api.setConnectionState(connected);
  }

  Future<bool> checkConnection() async {
    return await _api.checkConnection();
  }

  bool _componentsEqual(Component a, Component b) {
    return a.id == b.id &&
        a.name == b.name &&
        a.quantity == b.quantity &&
        a.price.toStringAsFixed(2) == b.price.toStringAsFixed(2) &&
        a.x == b.x &&
        a.y == b.y &&
        a.folderId == b.folderId;
  }

  Future<Map<String, Component>> _getLocalComponentMap() async {
    final folders = await _db.getAllFolders();
    final byId = <String, Component>{};

    final rootComponents = await _db.getComponentsByFolder('root');
    for (final component in rootComponents) {
      byId[component.id] = component;
    }

    for (final folder in folders) {
      final components = await _db.getComponentsByFolder(folder.id);
      for (final component in components) {
        byId[component.id] = component;
      }
    }
    return byId;
  }

  Map<String, Component> _getFirmwareComponentMap(Folder root) {
    final byId = <String, Component>{};
    for (final component in root.getAllComponents()) {
      byId[component.id] = component;
    }
    return byId;
  }

  Future<Map<String, Folder>> _getLocalFolderMap() async {
    final folders = await _db.getAllFolders();
    final byId = <String, Folder>{};
    for (final folder in folders) {
      if (folder.id == 'root') continue;
      byId[folder.id] = folder;
    }
    return byId;
  }

  Map<String, Folder> _getFirmwareFolderMap(Folder root) {
    final byId = <String, Folder>{};
    for (final folder in root.getAllFolders()) {
      if (folder.id == 'root') continue;
      byId[folder.id] = folder;
    }
    return byId;
  }

  bool _foldersEqual(Folder a, Folder b) {
    return a.id == b.id && a.name == b.name && a.parentId == b.parentId;
  }

  Future<SyncResult> syncItems() async {
    if (!isConnected) {
      return SyncResult(success: false, error: 'Not connected to ESP');
    }

    try {
      final firmwareFolder = await _api.fetchInventory();
      final espById = _getFirmwareComponentMap(firmwareFolder);
      final appById = await _getLocalComponentMap();
      final espFoldersById = _getFirmwareFolderMap(firmwareFolder);
      final appFoldersById = await _getLocalFolderMap();

      final allIds = <String>{...espById.keys, ...appById.keys};
      final conflicts = <ComponentConflict>[];

      for (final id in allIds) {
        final esp = espById[id];
        final app = appById[id];
        if (esp == null || app == null || !_componentsEqual(esp, app)) {
          conflicts.add(ComponentConflict(id: id, espComponent: esp, appComponent: app));
        }
      }

      final allFolderIds = <String>{...espFoldersById.keys, ...appFoldersById.keys};
      final folderConflicts = <FolderConflict>[];
      for (final id in allFolderIds) {
        final espFolder = espFoldersById[id];
        final appFolder = appFoldersById[id];
        if (espFolder == null || appFolder == null || !_foldersEqual(espFolder, appFolder)) {
          folderConflicts.add(FolderConflict(id: id, espFolder: espFolder, appFolder: appFolder));
        }
      }

      return SyncResult(
        success: true,
        itemCount: appById.length,
        conflicts: conflicts,
        folderConflicts: folderConflicts,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  Future<void> resolveComponentConflictWithValue(ComponentConflict conflict, Component? resolvedComponent) async {
    final esp = conflict.espComponent;

    if (resolvedComponent == null) {
      await _db.deleteComponentById(conflict.id);
      if (isConnected && esp != null) {
        await _api.deleteComponent(id: esp.id, folderId: esp.folderId);
      }
      return;
    }

    await _db.insertComponent(resolvedComponent);
    if (!isConnected) return;

    if (esp != null) {
      await _api.deleteComponent(id: esp.id, folderId: esp.folderId);
    }

    await _api.addComponent(
      id: resolvedComponent.id,
      name: resolvedComponent.name,
      quantity: resolvedComponent.quantity,
      price: resolvedComponent.price,
      x: resolvedComponent.x,
      y: resolvedComponent.y,
      folderId: resolvedComponent.folderId,
    );
  }

  Future<void> resolveComponentConflict(ComponentConflict conflict, ConflictChoice choice) async {
    final resolved = choice == ConflictChoice.esp ? conflict.espComponent : conflict.appComponent;
    await resolveComponentConflictWithValue(conflict, resolved);
  }

  Future<void> resolveFolderConflict(FolderConflict conflict, ConflictChoice choice) async {
    final esp = conflict.espFolder;
    final app = conflict.appFolder;

    if (choice == ConflictChoice.esp) {
      if (esp == null) {
        if (app != null) {
          await _db.deleteFolderCascade(app.id);
        }
        return;
      }

      await _db.insertFolder(esp);
      return;
    }

    // ConflictChoice.app
    if (app == null) {
      if (esp != null) {
        await _db.deleteFolderCascade(esp.id);
        if (isConnected) {
          await _api.deleteFolder(id: esp.id, cascade: true);
        }
      }
      return;
    }

    await _db.insertFolder(app);

    if (!isConnected) return;

    if (esp == null) {
      await _api.addFolder(
        app.name,
        parentId: app.parentId.isEmpty ? 'root' : app.parentId,
        id: app.id,
      );
      return;
    }

    if (esp.name != app.name) {
      await _api.renameFolder(id: app.id, name: app.name);
    }
    if (esp.parentId != app.parentId) {
      await _api.moveFolder(id: app.id, parentId: app.parentId.isEmpty ? 'root' : app.parentId);
    }
  }

  Future<bool> addItem(Component component) async {
    if (isConnected) {
      await _api.addComponent(
        id: component.id,
        name: component.name,
        quantity: component.quantity,
        price: component.price,
        x: component.x,
        y: component.y,
        folderId: component.folderId,
      );
    }

    await _db.insertComponent(component);
    return true;
  }

  Future<bool> deleteItem(Component component) async {
    if (isConnected) {
      await _api.deleteComponent(
        id: component.id,
        folderId: component.folderId,
      );
    }

    await _db.deleteComponentById(component.id);
    return true;
  }

  Future<bool> replaceItem({
    required Component oldComponent,
    required Component updatedComponent,
  }) async {
    final addSuccess = await addItem(updatedComponent);
    if (!addSuccess) {
      return false;
    }

    final deleteOldSuccess = await deleteItem(oldComponent);
    if (deleteOldSuccess) {
      return true;
    }

    // Best-effort rollback so failed edits do not leave duplicates.
    await deleteItem(updatedComponent);
    return false;
  }


  Future<bool> addFolder(String name, {String parentId = ''}) async {
    final newId = 'fld_${DateTime.now().millisecondsSinceEpoch}';
    if (isConnected) {
      await _api.addFolder(name, parentId: parentId, id: newId);
    }

    final newFolder = Folder(
      id: newId,
      name: name,
      parentId: parentId.isNotEmpty && parentId != 'root' ? parentId : '',
    );
    await _db.insertFolder(newFolder);

    return true;
  }

  Future<List<Folder>> getFolders() async {
    return await _db.getAllFolders();
  }

  Future<List<Component>> getComponentsByFolder(String folderId) async {
    return await _db.getComponentsByFolder(folderId);
  }

  Future<Map<String, dynamic>> getStats() async {
    return await _db.getStats();
  }

  Future<Folder> fetchInventoryFromFirmware() async {
    return await _api.fetchInventory();
  }

  Future<bool> sendMessage(String message, {String target = 'both'}) async {
    return await _api.sendMessage(message, target: target);
  }

  Future<bool> clearMessages() async {
    return await _api.clearMessages();
  }

  Future<bool> renameFolder({required String id, required String name}) async {
    if (isConnected) {
      await _api.renameFolder(id: id, name: name);
    }
    await _db.updateFolderName(id, name);
    return true;
  }

  Future<bool> moveFolder({required String id, required String parentId}) async {
    if (isConnected) {
      await _api.moveFolder(id: id, parentId: parentId);
    }
    final normalizedParent = parentId == 'root' ? '' : parentId;
    await _db.updateFolderParent(id, normalizedParent);
    return true;
  }

  Future<bool> deleteFolder({required String id, bool cascade = false}) async {
    if (isConnected) {
      await _api.deleteFolder(id: id, cascade: cascade);
    }
    await _db.deleteFolderCascade(id);
    return true;
  }
}

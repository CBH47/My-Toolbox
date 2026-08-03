import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/component.dart';
import '../models/folder.dart';
import 'database_service.dart';

class FirmwareApiService {
  static final FirmwareApiService _instance = FirmwareApiService._internal();
  factory FirmwareApiService() => _instance;
  FirmwareApiService._internal();

  final DatabaseService _db = DatabaseService();
  static const String _appClientHeader = 'X-Toolbox-Client';
  static const String _appClientValue = 'mobile-app';
  String? _espIp;
  bool _isConnected = false;
  String? _lastConnectionError;
  String? _lastDeleteError;
  String? _lastFolderError;

  String? get espIp => _espIp;
  bool get isConnected => _isConnected;
  String? get lastConnectionError => _lastConnectionError;
  String? get lastDeleteError => _lastDeleteError;
  String? get lastFolderError => _lastFolderError;

  void setEspIp(String ip) {
    _espIp = ip;
    _lastConnectionError = null;
  }

  void setConnectionState(bool connected) {
    _isConnected = connected;
    if (connected) {
      _lastConnectionError = null;
    }
  }

  Future<bool> checkConnection() async {
    if (_espIp == null) {
      _lastConnectionError = 'ESP IP is not set';
      return false;
    }

    final baseUrl = 'http://$_espIp';

    try {
      final pingResponse = await http.get(Uri.parse('$baseUrl/api/ping')).timeout(const Duration(seconds: 3));
      if (pingResponse.statusCode == 200) {
        _isConnected = true;
        _lastConnectionError = null;
        return true;
      }
    } catch (_) {}

    try {
      final rootResponse = await http.get(Uri.parse('$baseUrl/')).timeout(const Duration(seconds: 3));
      if (rootResponse.statusCode == 200) {
        _isConnected = true;
        _lastConnectionError = null;
        return true;
      }
    } catch (_) {}

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/inventory'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      if (_isConnected) {
        _lastConnectionError = null;
      } else {
        _lastConnectionError = 'API responded with HTTP ${response.statusCode}';
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      _lastConnectionError = e.toString();
      return false;
    }
  }

  Future<Folder> fetchInventory() async {
    if (_espIp == null) {
      return Folder(id: 'root', name: 'Root');
    }
    try {
      final response = await http.get(
        Uri.parse('http://$_espIp/api/inventory'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _isConnected = true;
        _lastConnectionError = null;
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Folder.fromJson(json);
      }
      _isConnected = false;
      _lastConnectionError = 'Inventory API responded with HTTP ${response.statusCode}';
    } catch (e) {
      print('Error fetching inventory: $e');
      _isConnected = false;
      _lastConnectionError = e.toString();
    }
    return Folder(id: 'root', name: 'Root');
  }

  Future<bool> addComponent({
    String? id,
    required String name,
    int quantity = 1,
    double price = 0.0,
    int x = 0,
    int y = 0,
    String folderId = 'root',
  }) async {
    if (_espIp == null) return false;

    try {
      final uri = Uri.parse('http://$_espIp/api/component');
      final body = <String, String>{
        if (id != null && id.isNotEmpty) 'id': id,
        'name': name,
        'quantity': quantity.toString(),
        'price': price.toStringAsFixed(2),
        'x': x.toString(),
        'y': y.toString(),
        if (folderId != 'root') 'folderId': folderId,
      };

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      } else {
        print('Failed to add component: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error adding component: $e');
      return false;
    }
  }


  Future<bool> addFolder(String name, {String parentId = '', String? id}) async {
    if (_espIp == null) return false;
    _lastFolderError = null;

    try {
      final uri = Uri.parse('http://$_espIp/api/folder');
      final body = <String, String>{
        if (id != null && id.isNotEmpty) 'id': id,
        'name': name,
        if (parentId.isNotEmpty && parentId != 'root') 'parentId': parentId,
      };

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      } else {
        _lastFolderError = 'HTTP ${response.statusCode}: ${response.body}';
        print('Failed to add folder: ${response.body}');
        return false;
      }
    } catch (e) {
      _lastFolderError = e.toString();
      print('Error adding folder: $e');
      return false;
    }
  }

  Future<bool> renameFolder({required String id, required String name}) async {
    if (_espIp == null) return false;
    _lastFolderError = null;

    try {
      final uri = Uri.parse('http://$_espIp/api/folder/rename');
      final response = await http.post(
        uri,
        headers: {
          _appClientHeader: _appClientValue,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'id': id,
          'name': name,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      _lastFolderError = 'HTTP ${response.statusCode}: ${response.body}';
      print('Failed to rename folder: ${response.body}');
      return false;
    } catch (e) {
      _lastFolderError = e.toString();
      print('Error renaming folder: $e');
      return false;
    }
  }

  Future<bool> moveFolder({required String id, required String parentId}) async {
    if (_espIp == null) return false;
    _lastFolderError = null;

    try {
      final uri = Uri.parse('http://$_espIp/api/folder/move');
      final response = await http.post(
        uri,
        headers: {
          _appClientHeader: _appClientValue,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'id': id,
          if (parentId != 'root') 'parentId': parentId,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      _lastFolderError = 'HTTP ${response.statusCode}: ${response.body}';
      print('Failed to move folder: ${response.body}');
      return false;
    } catch (e) {
      _lastFolderError = e.toString();
      print('Error moving folder: $e');
      return false;
    }
  }

  Future<bool> deleteFolder({required String id, bool cascade = false}) async {
    if (_espIp == null) return false;
    _lastFolderError = null;

    try {
      final uri = Uri.parse('http://$_espIp/api/folder/delete');
      final response = await http.post(
        uri,
        headers: {
          _appClientHeader: _appClientValue,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'id': id,
          'cascade': cascade ? 'true' : 'false',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      if (response.statusCode == 404 || response.statusCode == 400) {
        final fallbackUri = Uri.parse('http://$_espIp/api/folder');
        final fallbackResponse = await http.post(
          fallbackUri,
          headers: {
            _appClientHeader: _appClientValue,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {
            'action': 'delete',
            'id': id,
            'cascade': cascade ? 'true' : 'false',
          },
        ).timeout(const Duration(seconds: 10));

        if (fallbackResponse.statusCode == 200) {
          return true;
        }

        _lastFolderError = 'HTTP ${fallbackResponse.statusCode}: ${fallbackResponse.body}';
        print('Failed to delete folder (fallback): ${fallbackResponse.body}');
        return false;
      }

      _lastFolderError = 'HTTP ${response.statusCode}: ${response.body}';
      print('Failed to delete folder: ${response.body}');
      return false;
    } catch (e) {
      _lastFolderError = e.toString();
      print('Error deleting folder: $e');
      return false;
    }
  }

  Future<bool> deleteComponent({required String id, String folderId = 'root'}) async {
    if (_espIp == null) return false;
    _lastDeleteError = null;

    try {
      final uri = Uri.parse('http://$_espIp/api/component/delete');
      final deleteBody = <String, String>{
        'id': id,
        if (folderId.isNotEmpty && folderId != 'root') 'folderId': folderId,
      };

      final response = await http.post(
        uri,
        headers: {
          _appClientHeader: _appClientValue,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: deleteBody,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      } else if (response.statusCode == 404) {
        // Compatibility fallback for firmware that may not yet expose /api/component/delete.
        final fallbackUri = Uri.parse('http://$_espIp/api/component');
        final fallbackBody = <String, String>{
          'action': 'delete',
          'id': id,
          if (folderId.isNotEmpty && folderId != 'root') 'folderId': folderId,
        };
        final fallbackResponse = await http.post(
          fallbackUri,
          headers: {
            _appClientHeader: _appClientValue,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: fallbackBody,
        ).timeout(const Duration(seconds: 10));
        if (fallbackResponse.statusCode == 200) {
          return true;
        }

        _lastDeleteError = 'HTTP ${fallbackResponse.statusCode}: ${fallbackResponse.body}';
        print('Failed to delete component (fallback): ${fallbackResponse.body}');
        return false;
      } else {
        _lastDeleteError = 'HTTP ${response.statusCode}: ${response.body}';
        print('Failed to delete component: ${response.body}');
        return false;
      }
    } catch (e) {
      _lastDeleteError = e.toString();
      print('Error deleting component: $e');
      return false;
    }
  }

  Future<bool> sendMessage(String message, {String target = 'both'}) async {
    if (_espIp == null) return false;

    try {
      final response = await http.post(
        Uri.parse('http://$_espIp/send'),
        body: {'target': target, 'message': message},
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('Error sending message: $e');
      return false;
    }
  }

  Future<bool> clearMessages() async {
    if (_espIp == null) return false;

    try {
      final response = await http.post(
        Uri.parse('http://$_espIp/clear'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      print('Error clearing messages: $e');
      return false;
    }
  }

  Future<SyncResult> syncFromFirmware() async {
    if (_espIp == null || !await checkConnection()) {
      return SyncResult(success: false, error: 'Cannot connect to Toolbox ESP');
    }

    try {
      final firmwareFolder = await fetchInventory();
      await _db.syncFromFirmware(firmwareFolder);

      int totalComponents = 0;
      for (final folder in await _db.getAllFolders()) {
        totalComponents += (await _db.getComponentsByFolder(folder.id)).length;
      }

      return SyncResult(
        success: true,
        itemCount: totalComponents,
        folderCount: (await _db.getAllFolders()).length,
      );
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  Future<bool> pushComponentToFirmware(Component component) async {
    final success = await addComponent(
      name: component.name,
      quantity: component.quantity,
      price: component.price,
      x: component.x,
      y: component.y,
      folderId: component.folderId,
    );

    if (success) {
      await _db.insertComponent(component);
    }

    return success;
  }

  Future<bool> pushFolderToFirmware(Folder folder) async {
    final success = await addFolder(folder.name, parentId: folder.parentId);

    if (success && folder.parentId.isNotEmpty) {
      await _db.insertFolder(folder);
    } else if (folder.parentId.isEmpty || folder.id == 'root') {
      await _db.insertFolder(folder);
    }

    return success;
  }
}

class SyncResult {
  final bool success;
  final int itemCount;
  final int? folderCount;
  final String? error;

  SyncResult({
    required this.success,
    this.itemCount = 0,
    this.folderCount,
    this.error,
  });
}

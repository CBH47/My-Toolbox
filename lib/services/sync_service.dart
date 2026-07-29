import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/inventory_item.dart';
import 'database_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DatabaseService _db = DatabaseService();
  String? _espIp;
  bool _isConnected = false;
  String? _clientId;

  String? get espIp => _espIp;
  bool get isConnected => _isConnected;

  void setEspIp(String ip) {
    _espIp = ip;
    _isConnected = true;
  }

  void disconnect() {
    _isConnected = false;
  }

  Future<bool> checkConnection() async {
    if (_espIp == null) return false;
    try {
      final response = await http.get(
        Uri.parse('http://$_espIp/api/status'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      return false;
    }
  }

  Future<List<InventoryItem>> fetchItems() async {
    if (_espIp == null || !await checkConnection()) return [];
    try {
      final response = await http.get(
        Uri.parse('http://$_espIp/api/items'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((j) => InventoryItem.fromJson(j as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      print('Error fetching items: $e');
    }
    return [];
  }

  Future<SyncResult> syncItems() async {
    if (_espIp == null || !await checkConnection()) {
      return SyncResult(success: false, error: 'Cannot connect to Toolbox ESP');
    }

    try {
      // Get local client ID for tracking
      String clientId = await _getClientId();

      // Get non-deleted local items to send to ESP
      List<InventoryItem> localItems = await _db.getAllItems();
      List<Map<String, dynamic>> itemsToSend = localItems.map((i) => i.toJson()).toList();

      final payload = jsonEncode({
        'client_id': clientId,
        'items': itemsToSend,
      });

      final response = await http.post(
        Uri.parse('http://$_espIp/api/sync'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        
        // ESP always wins - replace local items with server's authoritative list
        if (data['items'] != null && data['items'] is List) {
          List<InventoryItem> serverItems = (data['items'] as List<dynamic>)
              .map((j) => InventoryItem.fromJson(j as Map<String, dynamic>))
              .toList();

          // Merge into local database (ESP's version wins for conflicts)
          await _db.mergeItems(serverItems);

          return SyncResult(
            success: true,
            items: serverItems,
            itemCount: serverItems.length,
            serverWins: data['server_wins'] == true,
          );
        } else {
          // Fallback: fetch fresh items from ESP
          List<InventoryItem> fetched = await fetchItems();
          await _db.mergeItems(fetched);

          return SyncResult(
            success: true,
            items: fetched,
            itemCount: fetched.length,
          );
        }
      } else {
        return SyncResult(success: false, error: 'Sync failed with status ${response.statusCode}');
      }
    } catch (e) {
      return SyncResult(success: false, error: e.toString());
    }
  }

  Future<bool> addItem(InventoryItem item) async {
    if (_espIp == null || !await checkConnection()) {
      // Save locally only
      await _db.insertItem(item);
      return true;
    }

    try {
      final response = await http.post(
        Uri.parse('http://$_espIp/api/items'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode(item.toJson()),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // Save locally too for consistency
        await _db.insertItem(item);
        return true;
      }
    } catch (e) {
      print('Error adding item: $e');
    }

    // Fallback to local only
    await _db.insertItem(item);
    return false;
  }

  Future<bool> deleteItem(String id, {double? timestamp}) async {
    double ts = timestamp ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);
    
    if (_espIp == null || !await checkConnection()) {
      await _db.softDeleteItem(id, ts);
      return true;
    }

    try {
      final response = await http.delete(
        Uri.parse('http://$_espIp/api/items?id=$id'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        await _db.softDeleteItem(id, ts);
        return true;
      }
    } catch (e) {
      print('Error deleting item: $e');
    }

    // Fallback to local only
    await _db.softDeleteItem(id, ts);
    return false;
  }

  Future<String> _getClientId() async {
    if (_clientId != null) return _clientId!;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString('toolbox_client_id');
      if (id == null) {
        id = 'flutter_${const Uuid().v4()}';
        await prefs.setString('toolbox_client_id', id);
      }
      _clientId = id;
    } catch (e) {
      _clientId = 'flutter_unknown';
    }
    return _clientId!;
  }

  Future<Map<String, dynamic>> getStatus() async {
    if (_espIp == null) return {'error': 'No ESP IP configured'};
    
    try {
      final response = await http.get(
        Uri.parse('http://$_espIp/api/status'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      return {'error': e.toString()};
    }
    return {'error': 'Failed to get status'};
  }
}

class SyncResult {
  final bool success;
  final List<InventoryItem> items;
  final int itemCount;
  final bool? serverWins;
  final String? error;

  SyncResult({
    required this.success,
    this.items = const [],
    this.itemCount = 0,
    this.serverWins,
    this.error,
  });
}

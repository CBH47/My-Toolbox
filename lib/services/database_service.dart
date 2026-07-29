import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/inventory_item.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'toolbox_inventory.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            category TEXT DEFAULT 'Uncategorized',
            quantity INTEGER DEFAULT 1,
            location TEXT DEFAULT '',
            notes TEXT DEFAULT '',
            timestamp REAL NOT NULL,
            deleted INTEGER DEFAULT 0
          )
        ''');
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_items_name ON items(name COLLATE NOCASE)"
        );
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_items_category ON items(category)"
        );
      },
    );
  }

  Future<int> insertItem(InventoryItem item) async {
    final db = await database;
    return await db.insert(
      'items',
      item.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateItem(InventoryItem item) async {
    final db = await database;
    return await db.update(
      'items',
      item.toJson(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteItem(String id) async {
    final db = await database;
    return await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> softDeleteItem(String id, double timestamp) async {
    final db = await database;
    return await db.update(
      'items',
      {'deleted': 1, 'timestamp': timestamp},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<InventoryItem>> getAllItems() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'deleted = 0',
      orderBy: 'name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) {
      return InventoryItem.fromJson(maps[i]);
    });
  }

  Future<List<InventoryItem>> searchItems(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'deleted = 0 AND (name LIKE ? OR description LIKE ? OR location LIKE ?)',
      orderBy: 'name COLLATE NOCASE',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    return List.generate(maps.length, (i) {
      return InventoryItem.fromJson(maps[i]);
    });
  }

  Future<List<InventoryItem>> getItemsByCategory(String category) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'deleted = 0 AND category = ?',
      orderBy: 'name COLLATE NOCASE',
      whereArgs: [category],
    );
    return List.generate(maps.length, (i) {
      return InventoryItem.fromJson(maps[i]);
    });
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      "SELECT DISTINCT category FROM items WHERE deleted = 0 AND category != 'Uncategorized' ORDER BY category"
    );
    return maps.map((m) => m['category'] as String).toList();
  }

  Future<int> getItemCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM items WHERE deleted = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<InventoryItem>> getItemsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await database;
    final String placeholders = ids.map((_) => '?').join(',');
    final List<Map<String, dynamic>> maps = await db.query(
      'items',
      where: 'id IN ($placeholders) AND deleted = 0',
      whereArgs: ids,
      orderBy: 'name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) {
      return InventoryItem.fromJson(maps[i]);
    });
  }

  Future<void> mergeItems(List<InventoryItem> remoteItems) async {
    final db = await database;
    final batch = db.batch();

    for (final item in remoteItems) {
      if (!item.deleted) {
        batch.insert(
          'items',
          item.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        batch.delete('items', where: 'id = ?', whereArgs: [item.id]);
      }
    }

    await batch.commit(noResult: true);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('items');
  }
}

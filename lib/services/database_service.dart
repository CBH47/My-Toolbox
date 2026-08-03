import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/component.dart';
import '../models/folder.dart';
import '../models/project.dart';

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
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE folders (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            parentId TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE components (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            quantity INTEGER DEFAULT 1,
            price REAL DEFAULT 0.0,
            x INTEGER DEFAULT 0,
            y INTEGER DEFAULT 0,
            folderId TEXT NOT NULL,
            FOREIGN KEY (folderId) REFERENCES folders(id)
          )
        ''');
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_components_folderId ON components(folderId)"
        );
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_folders_parentId ON folders(parentId)"
        );
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            createdAt INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE project_components (
            projectId TEXT NOT NULL,
            componentId TEXT NOT NULL,
            requiredQuantity INTEGER NOT NULL DEFAULT 1,
            PRIMARY KEY (projectId, componentId),
            FOREIGN KEY (projectId) REFERENCES projects(id)
          )
        ''');
        await db.execute(
          "CREATE INDEX IF NOT EXISTS idx_project_components_projectId ON project_components(projectId)"
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('DROP TABLE items');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE folders (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              parentId TEXT DEFAULT ''
            )
          ''');
          await db.execute('''
            CREATE TABLE components (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              quantity INTEGER DEFAULT 1,
              price REAL DEFAULT 0.0,
              x INTEGER DEFAULT 0,
              y INTEGER DEFAULT 0,
              folderId TEXT NOT NULL,
              FOREIGN KEY (folderId) REFERENCES folders(id)
            )
          ''');
          await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_components_folderId ON components(folderId)"
          );
          await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_folders_parentId ON folders(parentId)"
          );
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              createdAt INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS project_components (
              projectId TEXT NOT NULL,
              componentId TEXT NOT NULL,
              requiredQuantity INTEGER NOT NULL DEFAULT 1,
              PRIMARY KEY (projectId, componentId),
              FOREIGN KEY (projectId) REFERENCES projects(id)
            )
          ''');
          await db.execute(
            "CREATE INDEX IF NOT EXISTS idx_project_components_projectId ON project_components(projectId)"
          );
        }
      },
    );
  }

  Future<void> insertProject(Project project) async {
    final db = await database;
    await db.insert(
      'projects',
      project.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Project>> getProjects() async {
    final db = await database;
    final maps = await db.query(
      'projects',
      orderBy: 'createdAt DESC',
    );
    return maps.map((row) => Project.fromJson(row)).toList();
  }

  Future<void> deleteProject(String projectId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'project_components',
        where: 'projectId = ?',
        whereArgs: [projectId],
      );
      await txn.delete(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
      );
    });
  }

  Future<void> upsertProjectRequirement({
    required String projectId,
    required String componentId,
    required int requiredQuantity,
  }) async {
    final db = await database;
    await db.insert(
      'project_components',
      {
        'projectId': projectId,
        'componentId': componentId,
        'requiredQuantity': requiredQuantity,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeProjectRequirement({
    required String projectId,
    required String componentId,
  }) async {
    final db = await database;
    await db.delete(
      'project_components',
      where: 'projectId = ? AND componentId = ?',
      whereArgs: [projectId, componentId],
    );
  }

  Future<List<ProjectRequirement>> getProjectRequirements(String projectId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT
        pc.projectId as projectId,
        pc.componentId as componentId,
        pc.requiredQuantity as requiredQuantity,
        c.name as componentName,
        c.quantity as availableQuantity,
        c.price as componentPrice
      FROM project_components pc
      LEFT JOIN components c ON c.id = pc.componentId
      WHERE pc.projectId = ?
      ORDER BY COALESCE(c.name, pc.componentId) COLLATE NOCASE
      ''',
      [projectId],
    );

    return rows.map((row) {
      return ProjectRequirement(
        projectId: row['projectId'] as String,
        componentId: row['componentId'] as String,
        requiredQuantity: row['requiredQuantity'] as int? ?? 1,
        componentName: row['componentName'] as String?,
        availableQuantity: row['availableQuantity'] as int?,
        componentPrice: (row['componentPrice'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<void> insertFolder(Folder folder) async {
    final db = await database;
    await db.insert(
      'folders',
      {'id': folder.id, 'name': folder.name, 'parentId': folder.parentId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertComponent(Component component) async {
    final db = await database;
    await db.insert(
      'components',
      component.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Folder>> getAllFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'folders',
      orderBy: 'name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) {
      return Folder(
        id: maps[i]['id'] as String,
        name: maps[i]['name'] as String,
        parentId: maps[i]['parentId'] as String? ?? '',
      );
    });
  }

  Future<List<Component>> getComponentsByFolder(String folderId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'components',
      where: 'folderId = ?',
      whereArgs: [folderId],
      orderBy: 'name COLLATE NOCASE',
    );
    return List.generate(maps.length, (i) {
      return Component.fromJson(maps[i]);
    });
  }

  Future<Component?> getComponentById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'components',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Component.fromJson(maps.first);
  }

  Future<void> deleteComponentById(String id) async {
    final db = await database;
    await db.delete(
      'components',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateFolderName(String id, String name) async {
    final db = await database;
    await db.update(
      'folders',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateFolderParent(String id, String parentId) async {
    final db = await database;
    await db.update(
      'folders',
      {'parentId': parentId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteFolderCascade(String folderId) async {
    final db = await database;
    final folders = await getAllFolders();

    final childMap = <String, List<String>>{};
    for (final folder in folders) {
      final parent = folder.parentId;
      if (parent.isEmpty) continue;
      childMap.putIfAbsent(parent, () => <String>[]).add(folder.id);
    }

    final toDelete = <String>{folderId};
    final stack = <String>[folderId];

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final children = childMap[current] ?? const <String>[];
      for (final child in children) {
        if (toDelete.add(child)) {
          stack.add(child);
        }
      }
    }

    if (toDelete.isEmpty) return;

    final ids = toDelete.toList();
    final placeholders = List.filled(ids.length, '?').join(',');

    await db.transaction((txn) async {
      await txn.delete(
        'components',
        where: 'folderId IN ($placeholders)',
        whereArgs: ids,
      );
      await txn.delete(
        'folders',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    });
  }

  Future<List<Folder>> getRootFolders() async {
    final allFolders = await getAllFolders();
    return allFolders.where((f) => f.parentId.isEmpty || f.id == 'root').toList();
  }

  Future<List<Folder>> getChildFolders(String parentId) async {
    final allFolders = await getAllFolders();
    return allFolders
        .where((f) => f.parentId == parentId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<int> getComponentCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM components');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> syncFromFirmware(Folder firmwareFolder) async {
    final db = await database;
    final batch = db.batch();

    batch.delete('components');
    batch.delete('folders');

    void processFolder(Folder folder) {
      batch.insert(
        'folders',
        {'id': folder.id, 'name': folder.name, 'parentId': folder.parentId},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final comp in folder.components) {
        batch.insert(
          'components',
          comp.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final sub in folder.subfolders) {
        processFolder(sub);
      }
    }

    processFolder(firmwareFolder);
    await batch.commit(noResult: true);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('components');
    await db.delete('folders');
  }

  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    final folderCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM folders'),
    ) ?? 0;
    final componentCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM components'),
    ) ?? 0;
    final totalValue = await db.rawQuery(
      'SELECT SUM(quantity * price) as total FROM components',
    );
    final totalPrice = (totalValue.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'folders': folderCount,
      'components': componentCount,
      'totalPrice': totalPrice,
    };
  }
}

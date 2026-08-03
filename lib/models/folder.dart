import 'package:my_toolbox/models/component.dart';

class Folder {
  final String id;
  final String name;
  final String parentId;
  List<Component> components;
  List<Folder> subfolders;

  Folder({
    required this.id,
    required this.name,
    this.parentId = '',
    this.components = const [],
    this.subfolders = const [],
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return _fromJsonWithContext(json, parentIdOverride: '');
  }

  static Folder _fromJsonWithContext(
    Map<String, dynamic> json, {
    required String parentIdOverride,
  }) {
    final folderId = json['id'] as String? ?? '';
    final folderParentId = (json['parentId'] as String?) ?? parentIdOverride;

    final components = <Component>[];
    if (json['components'] != null && json['components'] is List) {
      for (var comp in json['components'] as List<dynamic>) {
        if (comp is Map) {
          final compMap = Map<String, dynamic>.from(comp as Map);
          // Firmware nested API does not include folderId per component; inherit from containing folder.
          compMap.putIfAbsent('folderId', () => folderId);
          components.add(Component.fromJson(compMap));
        }
      }
    }

    final subfolders = <Folder>[];
    if (json['subfolders'] != null && json['subfolders'] is List) {
      for (var sub in json['subfolders'] as List<dynamic>) {
        if (sub is Map) {
          subfolders.add(_fromJsonWithContext(
            Map<String, dynamic>.from(sub as Map),
            parentIdOverride: folderId,
          ));
        }
      }
    }

    return Folder(
      id: folderId,
      name: json['name'] as String? ?? 'Untitled',
      parentId: folderParentId,
      components: components,
      subfolders: subfolders,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parentId': parentId,
      'components': components.map((c) => c.toJson()).toList(),
      'subfolders': subfolders.map((f) => f.toJson()).toList(),
    };
  }

  Folder? findSubfolder(String id) {
    for (final folder in subfolders) {
      if (folder.id == id) return folder;
      final found = folder.findSubfolder(id);
      if (found != null) return found;
    }
    return null;
  }

  Folder? findFolderByPath(String path) {
    if (path.isEmpty || path == 'root') return this;
    final parts = path.split('>');
    Folder current = this;
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      Folder? found;
      for (final sub in current.subfolders) {
        if (sub.name.toLowerCase() == trimmed.toLowerCase()) {
          found = sub;
          break;
        }
      }
      if (found != null) {
        current = found;
      } else {
        return null;
      }
    }
    return current;
  }

  List<Component> getAllComponents() {
    final all = <Component>[];
    void collect(Folder folder) {
      all.addAll(folder.components);
      for (final sub in folder.subfolders) {
        collect(sub);
      }
    }
    collect(this);
    return all;
  }

  List<Folder> getAllFolders() {
    final all = <Folder>[this];
    void collect(Folder folder) {
      for (final sub in folder.subfolders) {
        all.add(sub);
        collect(sub);
      }
    }
    collect(this);
    return all;
  }

  int get totalComponents => getAllComponents().length;
  double get totalPrice => getAllComponents().fold(0.0, (sum, c) => sum + (c.price * c.quantity));

  @override
  String toString() => 'Folder($name, ${components.length} components, ${subfolders.length} subfolders)';
}

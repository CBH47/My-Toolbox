import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/component.dart';
import '../models/folder.dart';
import '../models/project.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseService _db = DatabaseService();
  final SyncService _sync = SyncService();
  static const MethodChannel _networkChannel = MethodChannel('toolbox/network');

  Folder _rootFolder = Folder(id: 'root', name: 'Root');
  List<Folder> _allFolders = [];
  String? _selectedFolderId;
  bool _isLoading = true;
  String _connectionStatus = 'Disconnected';
  Color _statusColor = Colors.grey;
  bool _isSyncing = false;
  String _searchQuery = '';
  int _selectedTabIndex = 0;
  List<Project> _projects = [];
  String? _selectedProjectId;
  List<ProjectRequirement> _projectRequirements = [];

  Timer? _syncTimer;

  Future<String> _getAndroidNetworkDiagSummary() async {
    if (!Platform.isAndroid) return 'diag:n/a';
    try {
      final diag = await _networkChannel.invokeMapMethod<String, dynamic>('getNetworkDiagnostics');
      if (diag == null) return 'diag:none';

      final active = diag['active']?.toString() ?? 'unknown';
      final bound = diag['bound']?.toString() ?? 'unknown';
      final wifiCount = diag['wifiCount']?.toString() ?? '?';
      final cellCount = diag['cellCount']?.toString() ?? '?';
      return 'diag:a=$active b=$bound w=$wifiCount c=$cellCount';
    } on PlatformException catch (e) {
      final msg = (e.message ?? e.code).replaceAll('\n', ' ');
      return 'diag:err=$msg';
    } catch (e) {
      return 'diag:err=${e.runtimeType}';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _startPeriodicSync();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final storedFolders = await _db.getAllFolders();

      // Build mutable folder instances keyed by id so we can wire hierarchy and hydrate components.
      final folderById = <String, Folder>{
        'root': Folder(id: 'root', name: 'Root', components: [], subfolders: []),
      };

      for (final f in storedFolders) {
        folderById[f.id] = Folder(
          id: f.id,
          name: f.name,
          parentId: f.parentId,
          components: [],
          subfolders: [],
        );
      }

      final root = folderById['root']!;

      // Link subfolders to parents (fallback to root when parent is missing).
      for (final f in folderById.values) {
        if (f.id == 'root') continue;
        final parentId = f.parentId.trim();
        final parent = (parentId.isEmpty ? root : folderById[parentId]) ?? root;
        parent.subfolders = [...parent.subfolders, f];
      }

      // Hydrate components for every known folder so UI lists populate correctly.
      for (final f in folderById.values) {
        final comps = await _db.getComponentsByFolder(f.id);
        f.components = comps;
      }

      setState(() {
        _rootFolder = root;
        final seenIds = <String>{};
        _allFolders = root
            .getAllFolders()
            .where((folder) => seenIds.add(folder.id))
            .toList();
        _selectedFolderId ??= 'root';
      });
      await _loadProjects();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProjects() async {
    final projects = await _db.getProjects();
    String? selectedProjectId = _selectedProjectId;
    if (projects.isEmpty) {
      selectedProjectId = null;
    } else {
      selectedProjectId ??= projects.first.id;
      final exists = projects.any((p) => p.id == selectedProjectId);
      if (!exists) {
        selectedProjectId = projects.first.id;
      }
    }

    List<ProjectRequirement> requirements = [];
    if (selectedProjectId != null) {
      requirements = await _db.getProjectRequirements(selectedProjectId);
    }

    if (!mounted) return;
    setState(() {
      _projects = projects;
      _selectedProjectId = selectedProjectId;
      _projectRequirements = requirements;
    });
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_sync.isConnected) {
        await _performSync();
      }
    });
  }

  Future<bool> _probeEspReachability(String ip) async {
    final socket = await Socket.connect(ip, 80, timeout: const Duration(seconds: 3));
    socket.destroy();
    final pingResponse = await http.get(Uri.parse('http://$ip/api/ping')).timeout(const Duration(seconds: 3));
    return pingResponse.statusCode == 200;
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _sync.syncItems();
      if (result.success && mounted) {
        final totalConflicts = result.conflicts.length + result.folderConflicts.length;
        if (totalConflicts > 0) {
          await _resolveConflictQueue(result.folderConflicts, result.conflicts);
          if (!mounted) return;
          await _loadData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resolved $totalConflicts sync conflicts')),
          );
        } else {
          await _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Synced: ${result.itemCount} components')),
          );
        }
      } else if (mounted) {
        setState(() {
          _connectionStatus = _sync.isConnected ? 'Connected (sync failed)' : 'Sync failed';
          _statusColor = _sync.isConnected ? Colors.orange : Colors.red;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectionStatus = 'Sync error');
        setState(() => _statusColor = Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  String _componentSummary(Component? component) {
    if (component == null) {
      return 'No component';
    }

    final total = (component.quantity * component.price).toStringAsFixed(2);
    return 'Name: ${component.name}\n'
        'Qty: ${component.quantity}\n'
        'Unit: \$${component.price.toStringAsFixed(2)}\n'
        'Total: \$$total\n'
        'Pos: (${component.x}, ${component.y})\n'
        'Folder: ${component.folderId}';
  }

  String _folderSummary(Folder? folder) {
    if (folder == null) {
      return 'No folder';
    }

    return 'Name: ${folder.name}\n'
        'Parent: ${folder.parentId.isEmpty ? 'root' : folder.parentId}\n'
        'ID: ${folder.id}';
  }

  Widget _buildConflictChoiceCard({
    required String label,
    required String details,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(details),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMergeRow({
    required String field,
    required String espValue,
    required String appValue,
    required bool useEsp,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: useEsp ? Theme.of(context).colorScheme.primaryContainer : null,
                  ),
                  onPressed: () => onChanged(true),
                  child: Text('ESP: $espValue'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: !useEsp ? Theme.of(context).colorScheme.primaryContainer : null,
                  ),
                  onPressed: () => onChanged(false),
                  child: Text('App: $appValue'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<ConflictChoice> _showFolderConflictDialog(
    FolderConflict conflict, {
    required int index,
    required int total,
  }) async {
    final choice = await showDialog<ConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Sync Conflict $index of $total'),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Folder ID: ${conflict.id}'),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildConflictChoiceCard(
                    label: 'ESP Version',
                    details: _folderSummary(conflict.espFolder),
                    onTap: () => Navigator.pop(context, ConflictChoice.esp),
                  ),
                  const SizedBox(width: 12),
                  _buildConflictChoiceCard(
                    label: 'App Version',
                    details: _folderSummary(conflict.appFolder),
                    onTap: () => Navigator.pop(context, ConflictChoice.app),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text('Tap the folder version you want to keep as true.'),
            ],
          ),
        ),
      ),
    );

    return choice ?? ConflictChoice.app;
  }

  Future<Component?> _showComponentConflictDialog(
    ComponentConflict conflict, {
    required int index,
    required int total,
  }) async {
    final esp = conflict.espComponent;
    final app = conflict.appComponent;

    if (esp == null || app == null) {
      final choice = await showDialog<ConflictChoice>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Sync Conflict $index of $total'),
          content: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Component ID: ${conflict.id}'),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildConflictChoiceCard(
                      label: 'ESP Version',
                      details: _componentSummary(esp),
                      onTap: () => Navigator.pop(context, ConflictChoice.esp),
                    ),
                    const SizedBox(width: 12),
                    _buildConflictChoiceCard(
                      label: 'App Version',
                      details: _componentSummary(app),
                      onTap: () => Navigator.pop(context, ConflictChoice.app),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('Tap the component version you want to keep as true.'),
              ],
            ),
          ),
        ),
      );

      return (choice ?? ConflictChoice.app) == ConflictChoice.esp ? esp : app;
    }

    bool useEspName = false;
    bool useEspQuantity = false;
    bool useEspPrice = false;
    bool useEspX = false;
    bool useEspY = false;
    bool useEspFolder = false;

    final merged = await showDialog<Component>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final mergedComponent = Component(
            id: conflict.id,
            name: useEspName ? esp.name : app.name,
            quantity: useEspQuantity ? esp.quantity : app.quantity,
            price: useEspPrice ? esp.price : app.price,
            x: useEspX ? esp.x : app.x,
            y: useEspY ? esp.y : app.y,
            folderId: useEspFolder ? esp.folderId : app.folderId,
          );

          return AlertDialog(
            title: Text('Sync Conflict $index of $total'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Component ID: ${conflict.id}'),
                    const SizedBox(height: 12),
                    _buildMergeRow(
                      field: 'Name',
                      espValue: esp.name,
                      appValue: app.name,
                      useEsp: useEspName,
                      onChanged: (value) => setDialogState(() => useEspName = value),
                    ),
                    _buildMergeRow(
                      field: 'Quantity',
                      espValue: esp.quantity.toString(),
                      appValue: app.quantity.toString(),
                      useEsp: useEspQuantity,
                      onChanged: (value) => setDialogState(() => useEspQuantity = value),
                    ),
                    _buildMergeRow(
                      field: 'Price',
                      espValue: esp.price.toStringAsFixed(2),
                      appValue: app.price.toStringAsFixed(2),
                      useEsp: useEspPrice,
                      onChanged: (value) => setDialogState(() => useEspPrice = value),
                    ),
                    _buildMergeRow(
                      field: 'X Position',
                      espValue: esp.x.toString(),
                      appValue: app.x.toString(),
                      useEsp: useEspX,
                      onChanged: (value) => setDialogState(() => useEspX = value),
                    ),
                    _buildMergeRow(
                      field: 'Y Position',
                      espValue: esp.y.toString(),
                      appValue: app.y.toString(),
                      useEsp: useEspY,
                      onChanged: (value) => setDialogState(() => useEspY = value),
                    ),
                    _buildMergeRow(
                      field: 'Folder',
                      espValue: esp.folderId,
                      appValue: app.folderId,
                      useEsp: useEspFolder,
                      onChanged: (value) => setDialogState(() => useEspFolder = value),
                    ),
                    const SizedBox(height: 8),
                    Text('Merged Result', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_componentSummary(mergedComponent)),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, esp),
                child: const Text('Keep ESP Whole'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, app),
                child: const Text('Keep App Whole'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, mergedComponent),
                child: const Text('Keep Merged'),
              ),
            ],
          );
        },
      ),
    );

    return merged ?? app;
  }

  Future<void> _resolveConflictQueue(List<FolderConflict> folderConflicts, List<ComponentConflict> componentConflicts) async {
    final total = folderConflicts.length + componentConflicts.length;
    int currentIndex = 1;

    for (final folderConflict in folderConflicts) {
      if (!mounted) return;
      final choice = await _showFolderConflictDialog(
        folderConflict,
        index: currentIndex,
        total: total,
      );
      await _sync.resolveFolderConflict(folderConflict, choice);
      currentIndex++;
    }

    for (final componentConflict in componentConflicts) {
      if (!mounted) return;
      final resolved = await _showComponentConflictDialog(
        componentConflict,
        index: currentIndex,
        total: total,
      );
      await _sync.resolveComponentConflictWithValue(componentConflict, resolved);
      currentIndex++;
    }
  }

  Future<void> _connectToEsp(String ip) async {
    setState(() {
      _connectionStatus = 'Connecting...';
      _statusColor = Colors.orange;
    });

    try {
      if (Platform.isAndroid) {
        try {
          await _networkChannel.invokeMethod<bool>('bindToWifiNetwork');
        } catch (_) {
          // Fall through and still attempt normal HTTP connection.
        }
      }

      final normalizedIp = ip
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceAll('/', '')
          .trim();

      _sync.setEspIp(normalizedIp);
      final connected = await _probeEspReachability(normalizedIp);
      if (connected) {
        _sync.setConnectionState(true);
        setState(() {
          _connectionStatus = 'Connected to $normalizedIp';
          _statusColor = Colors.green;
        });
        await _performSync();
      } else {
        _sync.setConnectionState(false);
        final details = _sync.lastConnectionError;
        setState(() {
          _connectionStatus = details == null || details.isEmpty
              ? 'Connection failed'
              : 'Connection failed: $details';
          _statusColor = Colors.red;
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = 'Error: $e';
        _statusColor = Colors.red;
      });
    }
  }

  Future<void> _runApDiagnostic() async {
    final targetIp = (_sync.espIp ?? '192.168.4.1')
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll('/', '')
        .trim();

    setState(() {
      _connectionStatus = 'Testing AP route to $targetIp...';
      _statusColor = Colors.orange;
    });

    final diagSummary = await _getAndroidNetworkDiagSummary();

    try {
      if (Platform.isAndroid) {
        try {
          await _networkChannel.invokeMethod<bool>('bindToWifiNetwork');
        } catch (_) {
          // Continue with diagnostic even if network bind call is unavailable.
        }
      }

      final sw = Stopwatch()..start();
      final socket = await Socket.connect(targetIp, 80, timeout: const Duration(seconds: 3));
      sw.stop();
      socket.destroy();

      final pingResponse = await http
          .get(Uri.parse('http://$targetIp/api/ping'))
          .timeout(const Duration(seconds: 3));

      if (pingResponse.statusCode == 200) {
        setState(() {
          _connectionStatus = 'AP OK: ${sw.elapsedMilliseconds}ms ping 200 | $diagSummary';
          _statusColor = Colors.green;
        });
      } else {
        setState(() {
          _connectionStatus = 'AP route OK, ping ${pingResponse.statusCode} | $diagSummary';
          _statusColor = Colors.orange;
        });
      }
    } on TimeoutException {
      setState(() {
        _connectionStatus = 'AP timeout $targetIp:80 | $diagSummary';
        _statusColor = Colors.red;
      });
    } on SocketException catch (e) {
      setState(() {
        _connectionStatus = 'AP socket err: ${e.message} | $diagSummary';
        _statusColor = Colors.red;
      });
    } catch (e) {
      setState(() {
        _connectionStatus = 'AP test error: $e | $diagSummary';
        _statusColor = Colors.red;
      });
    }
  }

  Future<void> _showConnectDialog() async {
    final ipController = TextEditingController(text: '192.168.4.1');
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect to Toolbox ESP'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the IP address of your Toolbox ESP32:'),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                border: OutlineInputBorder(),
                hintText: '192.168.4.1',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final ip = ipController.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(context);
              _connectToEsp(ip);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Folder? get _selectedFolder {
    if (_selectedFolderId == null || _selectedFolderId == 'root') return _rootFolder;
    return _allFolders.firstWhere((f) => f.id == _selectedFolderId, orElse: () => _rootFolder);
  }

  List<Folder> _collectFolderTree(Folder folder) {
    final all = <Folder>[folder];
    for (final sub in folder.subfolders) {
      all.addAll(_collectFolderTree(sub));
    }
    return all;
  }

  Future<void> _manageSelectedFolder() async {
    final folder = _selectedFolder;
    if (folder == null || folder.id == 'root') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a non-root folder to manage')),
      );
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameFolderDialog(folder);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('Move Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _showMoveFolderDialog(folder);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('Delete Folder', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteFolder(folder);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRenameFolderDialog(Folder folder) async {
    final nameCtrl = TextEditingController(text: folder.name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Folder Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) return;

              final success = await _sync.renameFolder(id: folder.id, name: newName);
              if (!mounted) return;

              if (success) {
                await _loadData();
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder renamed')),
                );
              } else {
                final err = _sync.lastFolderError;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err == null || err.isEmpty ? 'Failed to rename folder' : 'Rename failed: $err')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveFolderDialog(Folder folder) async {
    final excludedIds = _collectFolderTree(folder).map((f) => f.id).toSet();
    final candidates = _allFolders.where((f) => !excludedIds.contains(f.id)).toList();
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid destination folders available')),
      );
      return;
    }

    String parentId = folder.parentId.isNotEmpty ? folder.parentId : 'root';
    if (!candidates.any((f) => f.id == parentId)) {
      parentId = candidates.first.id;
    }

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Move Folder'),
          content: DropdownButtonFormField<String>(
            value: parentId,
            decoration: const InputDecoration(
              labelText: 'New Parent Folder',
              border: OutlineInputBorder(),
            ),
            items: candidates.map((candidate) {
              return DropdownMenuItem<String>(
                value: candidate.id,
                child: Text(candidate.name),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                parentId = val;
                setDialogState(() {});
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final success = await _sync.moveFolder(id: folder.id, parentId: parentId);
                if (!mounted) return;

                if (success) {
                  await _loadData();
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder moved')),
                  );
                } else {
                  final err = _sync.lastFolderError;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err == null || err.isEmpty ? 'Failed to move folder' : 'Move failed: $err')),
                  );
                }
              },
              child: const Text('Move'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final hasContent = folder.subfolders.isNotEmpty || folder.components.isNotEmpty;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          hasContent
              ? 'Delete "${folder.name}" and all nested contents? This cannot be undone.'
              : 'Delete empty folder "${folder.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _sync.deleteFolder(id: folder.id, cascade: true);
    if (!mounted) return;

    if (success) {
      setState(() => _selectedFolderId = 'root');
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder deleted')),
      );
    } else {
      final err = _sync.lastFolderError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err == null || err.isEmpty ? 'Failed to delete folder' : 'Delete failed: $err')),
      );
    }
  }

  List<Component> get _filteredComponents {
    final folder = _selectedFolder;
    if (folder == null) return [];
    
    return folder.components.where((component) {
      if (_searchQuery.isEmpty) return true;
      return component.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Project? get _selectedProject {
    if (_selectedProjectId == null) return null;
    for (final project in _projects) {
      if (project.id == _selectedProjectId) {
        return project;
      }
    }
    return null;
  }

  List<Component> get _allComponentsForProjects {
    final byId = <String, Component>{};
    for (final component in _rootFolder.getAllComponents()) {
      byId[component.id] = component;
    }
    final list = byId.values.toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<void> _showAddProjectDialog() async {
    final nameCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Project'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Project Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final project = Project(
                id: 'proj_${const Uuid().v4()}',
                name: name,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
              await _db.insertProject(project);
              await _loadProjects();
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Project created')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Delete "${project.name}" and all required components?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _db.deleteProject(project.id);
    await _loadProjects();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Project deleted')),
    );
  }

  Future<void> _showAddRequirementDialog(Project project) async {
    final components = _allComponentsForProjects;
    if (components.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No components available to add')),
      );
      return;
    }

    String selectedComponentId = components.first.id;
    final qtyCtrl = TextEditingController(text: '1');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Required Component'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedComponentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Component',
                  border: OutlineInputBorder(),
                ),
                items: components.map((component) {
                  return DropdownMenuItem<String>(
                    value: component.id,
                    child: Text(component.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedComponentId = value;
                    setDialogState(() {});
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Required Quantity',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (qty <= 0) return;
                await _db.upsertProjectRequirement(
                  projectId: project.id,
                  componentId: selectedComponentId,
                  requiredQuantity: qty,
                );
                await _loadProjects();
                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Requirement saved')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeRequirement(Project project, ProjectRequirement requirement) async {
    await _db.removeProjectRequirement(
      projectId: project.id,
      componentId: requirement.componentId,
    );
    await _loadProjects();
  }

  Future<void> _showAddComponentModal() async {
    final nameCtrl = TextEditingController(text: '');
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: '0.00');
    final xCtrl = TextEditingController(text: '0');
    final yCtrl = TextEditingController(text: '0');

    String folderId = _selectedFolderId ?? 'root';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Component'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: folderId,
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    border: OutlineInputBorder(),
                  ),
                  items: _allFolders.map((folder) {
                    return DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      folderId = val;
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Price (\$)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: xCtrl,
                        decoration: const InputDecoration(
                          labelText: 'X Position',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: yCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Y Position',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;

                final newComponent = Component(
                  id: 'comp_${const Uuid().v4()}',
                  name: nameCtrl.text.trim(),
                  quantity: int.tryParse(qtyCtrl.text) ?? 1,
                  price: double.tryParse(priceCtrl.text) ?? 0.0,
                  x: int.tryParse(xCtrl.text) ?? 0,
                  y: int.tryParse(yCtrl.text) ?? 0,
                  folderId: folderId,
                );

                final success = await _sync.addItem(newComponent);

                if (success && mounted) {
                  await _loadData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Component added')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to add component')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddFolderDialog() async {
    final nameCtrl = TextEditingController();
    String selectedParentId = 'root';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Folder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Folder Name *',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedParentId,
                  decoration: const InputDecoration(
                    labelText: 'Parent Folder',
                    border: OutlineInputBorder(),
                  ),
                  items: _allFolders.map((folder) {
                    return DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      selectedParentId = val;
                      setDialogState(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;

                final success = await _sync.addFolder(
                  nameCtrl.text.trim(),
                  parentId: selectedParentId,
                );

                if (success && mounted) {
                  await _loadData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder created')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to create folder')),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteComponent(Component component) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Component'),
        content: Text('Delete "${component.name}" from inventory? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _sync.deleteItem(component);
    if (!mounted) return;

    if (success) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${component.name}')),
      );
    } else {
      final deleteError = _sync.lastDeleteError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(deleteError == null || deleteError.isEmpty ? 'Failed to delete component' : 'Delete failed: $deleteError')),
      );
    }
  }

  Future<void> _showEditComponentModal(Component original) async {
    final nameCtrl = TextEditingController(text: original.name);
    final qtyCtrl = TextEditingController(text: original.quantity.toString());
    final priceCtrl = TextEditingController(text: original.price.toStringAsFixed(2));
    final xCtrl = TextEditingController(text: original.x.toString());
    final yCtrl = TextEditingController(text: original.y.toString());

    String folderId = original.folderId;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Component'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Name *',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: folderId,
                  decoration: const InputDecoration(
                    labelText: 'Folder',
                    border: OutlineInputBorder(),
                  ),
                  items: _allFolders.map((folder) {
                    return DropdownMenuItem(
                      value: folder.id,
                      child: Text(folder.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      folderId = val;
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Price (\$)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: xCtrl,
                        decoration: const InputDecoration(
                          labelText: 'X Position',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: yCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Y Position',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;

                final updatedComponent = Component(
                  id: 'comp_${const Uuid().v4()}',
                  name: nameCtrl.text.trim(),
                  quantity: int.tryParse(qtyCtrl.text) ?? 1,
                  price: double.tryParse(priceCtrl.text) ?? 0.0,
                  x: int.tryParse(xCtrl.text) ?? 0,
                  y: int.tryParse(yCtrl.text) ?? 0,
                  folderId: folderId,
                );

                final success = await _sync.replaceItem(
                  oldComponent: original,
                  updatedComponent: updatedComponent,
                );

                if (success && mounted) {
                  await _loadData();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Component updated')),
                  );
                } else if (mounted) {
                  final deleteError = _sync.lastDeleteError;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        deleteError == null || deleteError.isEmpty
                            ? 'Failed to update component'
                            : 'Update failed: $deleteError',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }


  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Add Folder'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddFolderDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add Component'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddComponentModal();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderPickerBar() {
    if (_allFolders.isEmpty) return const SizedBox.shrink();
    final selected = _selectedFolderId ?? 'root';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Current Folder',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _allFolders.map((folder) {
          return DropdownMenuItem<String>(
            value: folder.id,
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() => _selectedFolderId = val);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final isInventoryTab = _selectedTabIndex == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(isInventoryTab ? 'Toolbox Control' : 'Projects'),
        actions: [
          if (isInventoryTab)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Manage Selected Folder',
              onPressed: _manageSelectedFolder,
            ),
          IconButton(
            icon: Icon(_sync.isConnected ? Icons.wifi : Icons.wifi_off),
            color: _statusColor == Colors.green ? Colors.green : _statusColor == Colors.red ? Colors.red : null,
            tooltip: 'ESP Connection',
            onPressed: () => _showConnectDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConnectionBar(),
          Expanded(
            child: isInventoryTab
                ? (isMobile
                    ? Column(
                        children: [
                          _buildFolderPickerBar(),
                          Expanded(child: _buildComponentList()),
                        ],
                      )
                    : Row(
                        children: [
                          _buildFolderSidebar(),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildComponentList()),
                        ],
                      ))
                : _buildProjectsTab(),
          ),
        ],
      ),
      floatingActionButton: isInventoryTab
          ? (isMobile
              ? FloatingActionButton(
                  onPressed: _showCreateMenu,
                  child: const Icon(Icons.add),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.extended(
                      onPressed: _showAddFolderDialog,
                      icon: const Icon(Icons.folder),
                      label: const Text('Add Folder'),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.extended(
                      onPressed: () => _showAddComponentModal(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Component'),
                    ),
                  ],
                ))
          : FloatingActionButton.extended(
              onPressed: _showAddProjectDialog,
              icon: const Icon(Icons.add),
              label: const Text('New Project'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTabIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedTabIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspaces_outline),
            selectedIcon: Icon(Icons.workspaces),
            label: 'Projects',
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black.withOpacity(0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi, size: 18, color: _statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _connectionStatus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _statusColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_sync.isConnected)
                FilledButton.tonalIcon(
                  onPressed: _isSyncing ? null : _performSync,
                  icon: _isSyncing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                ),
              OutlinedButton.icon(
                onPressed: _runApDiagnostic,
                icon: const Icon(Icons.network_check, size: 18),
                label: const Text('Test AP'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSidebar() {
    return Container(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Folders',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _buildFolderTile(_rootFolder, level: 0),
                ..._buildSubfolderTiles(_rootFolder.subfolders, level: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(Folder folder, {int level = 0}) {
    final isSelected = _selectedFolderId == folder.id;
    final hasChildren = folder.subfolders.isNotEmpty || folder.components.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(left: level * 16.0),
      child: ListTile(
        leading: Icon(
          isSelected ? Icons.folder_open : Icons.folder,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          folder.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: hasChildren
            ? Text('${folder.components.length} items')
            : null,
        selected: isSelected,
        onTap: () {
          setState(() => _selectedFolderId = folder.id);
        },
        trailing: null,
      ),
    );
  }

  List<Widget> _buildSubfolderTiles(List<Folder> folders, {int level = 0}) {
    final widgets = <Widget>[];
    for (final folder in folders) {
      widgets.add(_buildFolderTile(folder, level: level));
      if (folder.subfolders.isNotEmpty) {
        widgets.addAll(_buildSubfolderTiles(folder.subfolders, level: level + 1));
      }
    }
    return widgets;
  }

  Widget _buildComponentList() {
    final folder = _selectedFolder;
    if (folder == null) return const Center(child: Text('No folder selected'));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search components in "${folder.name}"...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      setState(() => _searchQuery = '');
                    })
                  : null,
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildComponentCards(folder),
        ),
      ],
    );
  }

  Widget _buildComponentCards(Folder folder) {
    final filtered = _filteredComponents;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (filtered.isEmpty) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty ? 'No matching components' : 'No components in this folder',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final component = filtered[index];
        return SizedBox(
          width: double.infinity,
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      '${component.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          component.name,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Qty: ${component.quantity}  |  Unit: \$${component.price.toStringAsFixed(2)}  |  Total: \$${(component.quantity * component.price).toStringAsFixed(2)}',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Position: (${component.x}, ${component.y})',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Edit component',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showEditComponentModal(component),
                  ),
                  IconButton(
                    tooltip: 'Delete component',
                    icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                    onPressed: () => _confirmDeleteComponent(component),
                  ),
                  if (!isMobile) const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProjectListPane() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Projects',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'New Project',
                  onPressed: _showAddProjectDialog,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Expanded(
            child: _projects.isEmpty
                ? const Center(child: Text('No projects yet'))
                : ListView.builder(
                    itemCount: _projects.length,
                    itemBuilder: (context, index) {
                      final project = _projects[index];
                      final selected = _selectedProjectId == project.id;
                      return ListTile(
                        selected: selected,
                        title: Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () async {
                          setState(() => _selectedProjectId = project.id);
                          await _loadProjects();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectRequirementsPane() {
    final project = _selectedProject;
    if (project == null) {
      return const Center(child: Text('Select or create a project'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  project.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Add Component Requirement',
                onPressed: () => _showAddRequirementDialog(project),
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: 'Delete Project',
                onPressed: () => _confirmDeleteProject(project),
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
        Expanded(
          child: _projectRequirements.isEmpty
              ? const Center(child: Text('No required components yet'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _projectRequirements.length,
                  itemBuilder: (context, index) {
                    final requirement = _projectRequirements[index];
                    final missing = requirement.availableQuantity == null;
                    final availableQty = requirement.availableQuantity ?? 0;
                    final neededQty = requirement.requiredQuantity;
                    final shortage = neededQty - availableQty;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(requirement.componentName ?? '(missing) ${requirement.componentId}'),
                        subtitle: Text(
                          missing
                              ? 'Required: $neededQty | Missing from inventory'
                              : shortage > 0
                                  ? 'Required: $neededQty | Available: $availableQty | Short by: $shortage'
                                  : 'Required: $neededQty | Available: $availableQty',
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove requirement',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _removeRequirement(project, requirement),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProjectsTab() {
    final isMobile = MediaQuery.of(context).size.width < 900;

    if (isMobile) {
      return Column(
        children: [
          SizedBox(
            height: 72,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: OutlinedButton.icon(
                    onPressed: _showAddProjectDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Project'),
                  ),
                ),
                ..._projects.map((project) {
                  final selected = _selectedProjectId == project.id;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: ChoiceChip(
                      label: Text(project.name),
                      selected: selected,
                      onSelected: (_) async {
                        setState(() => _selectedProjectId = project.id);
                        await _loadProjects();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildProjectRequirementsPane()),
        ],
      );
    }

    return Row(
      children: [
        _buildProjectListPane(),
        Expanded(child: _buildProjectRequirementsPane()),
      ],
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

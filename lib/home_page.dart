import 'package:flutter/material.dart';
import 'dart:async';
import '../models/inventory_item.dart';
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
  
  List<InventoryItem> _items = [];
  bool _isLoading = true;
  String _connectionStatus = 'Disconnected';
  Color _statusColor = Colors.grey;
  bool _isSyncing = false;
  String _searchQuery = '';
  String _selectedCategory = '';

  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _startPeriodicSync();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final items = await _db.getAllItems();
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_sync.isConnected) {
        await _performSync();
      }
    });
  }

  Future<void> _performSync() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _sync.syncItems();
      if (result.success && mounted) {
        await _loadItems();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Synced: ${result.itemCount} items')),
        );
      } else if (mounted) {
        setState(() => _connectionStatus = 'Sync failed');
        setState(() => _statusColor = Colors.red);
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

  Future<void> _connectToEsp(String ip) async {
    setState(() {
      _connectionStatus = 'Connecting...';
      _statusColor = Colors.orange;
    });

    try {
      final connected = await _sync.checkConnection();
      if (connected) {
        _sync.setEspIp(ip);
        setState(() {
          _connectionStatus = 'Connected to $ip';
          _statusColor = Colors.green;
        });
        await _performSync();
      } else {
        setState(() {
          _connectionStatus = 'Connection failed';
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

  Future<void> _showAddEditModal([InventoryItem? item]) async {
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final descCtrl = TextEditingController(text: item?.description ?? '');
    final locCtrl = TextEditingController(text: item?.location ?? '');
    final notesCtrl = TextEditingController(text: item?.notes ?? '');
    
    String category = item?.category ?? 'Uncategorized';
    int quantity = item?.quantity ?? 1;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Add New Item' : 'Edit Item'),
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
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Uncategorized', child: Text('Uncategorized')),
                    DropdownMenuItem(value: 'Power Tools', child: Text('Power Tools')),
                    DropdownMenuItem(value: 'Hand Tools', child: Text('Hand Tools')),
                    DropdownMenuItem(value: 'Fasteners', child: Text('Fasteners')),
                    DropdownMenuItem(value: 'Measuring', child: Text('Measuring')),
                    DropdownMenuItem(value: 'Safety', child: Text('Safety')),
                    DropdownMenuItem(value: 'Electrical', child: Text('Electrical')),
                    DropdownMenuItem(value: 'Plumbing', child: Text('Plumbing')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      category = val;
                      setDialogState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(text: quantity.toString()),
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => quantity = int.tryParse(val) ?? 1,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Shelf A, Bin 3',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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

                final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
                final newItem = InventoryItem(
                  id: item?.id ?? 'item_${DateTime.now().millisecondsSinceEpoch}_${UniqueKey().toString()}',
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  category: category,
                  quantity: quantity,
                  location: locCtrl.text.trim(),
                  notes: notesCtrl.text.trim(),
                  timestamp: now,
                );

                final success = await _sync.addItem(newItem);
                if (success && mounted) {
                  await _loadItems();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Item saved')),
                  );
                } else if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved locally only - sync failed')),
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

  Future<void> _confirmDelete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _sync.deleteItem(item.id);
      await _loadItems();
    }
  }

  List<InventoryItem> get _filteredItems {
    return _items.where((item) {
      final matchSearch = _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.location.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchCategory = _selectedCategory.isEmpty || item.category == _selectedCategory;
      return matchSearch && matchCategory;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toolbox Inventory'),
        actions: [
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCards(),
                  const SizedBox(height: 24),
                  _buildToolbar(),
                  const SizedBox(height: 16),
                  _buildItemList(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditModal(),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildConnectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black.withOpacity(0.2),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 18, color: _statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _connectionStatus,
              style: TextStyle(fontSize: 13, color: _statusColor),
            ),
          ),
          if (_sync.isConnected)
            FilledButton.tonalIcon(
              onPressed: _isSyncing ? null : _performSync,
              icon: _isSyncing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 18),
              label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final categories = _items.map((i) => i.category).toSet();
    
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            context,
            icon: Icons.inventory_2,
            label: 'Total Items',
            value: _items.length.toString(),
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            context,
            icon: Icons.category,
            label: 'Categories',
            value: categories.where((c) => c != 'Uncategorized').length.toString(),
            color: Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final categoryList = categories.where((c) => c != 'Uncategorized').toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Search items...',
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
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedCategory.isEmpty ? '' : _selectedCategory,
          decoration: const InputDecoration(
            labelText: 'Filter by Category',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('All Categories')),
            ...categoryList.map((cat) => DropdownMenuItem(
              value: cat,
              child: Text(cat),
            )),
          ],
          onChanged: (val) => setState(() => _selectedCategory = val ?? ''),
        ),
      ],
    );
  }

  Set<String> get categories {
    return _items.map((i) => i.category).toSet();
  }

  Widget _buildItemList() {
    final filtered = _filteredItems;
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (filtered.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  _searchQuery.isNotEmpty || _selectedCategory.isNotEmpty
                      ? 'No matching items'
                      : 'No items yet',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_searchQuery.isEmpty && _selectedCategory.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to add your first tool',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = filtered[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _categoryColor(item.category),
              child: Text('${item.quantity}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.category != 'Uncategorized')
                  Chip(label: Text(item.category, style: const TextStyle(fontSize: 11))),
                if (item.location.isNotEmpty)
                  Text('📍 ${item.location}', style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showAddEditModal(item),
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _confirmDelete(item),
                  tooltip: 'Delete',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _categoryColor(String category) {
    final colors = {
      'Power Tools': Colors.red,
      'Hand Tools': Colors.orange,
      'Fasteners': Colors.amber,
      'Measuring': Colors.teal,
      'Safety': Colors.blue,
      'Electrical': Colors.purple,
      'Plumbing': Colors.cyan,
      'Other': Colors.grey,
    };
    return colors[category] ?? Colors.blueGrey;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

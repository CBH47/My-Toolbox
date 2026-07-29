class InventoryItem {
  final String id;
  final String name;
  final String description;
  final String category;
  final int quantity;
  final String location;
  final String notes;
  final double timestamp;
  final bool deleted;

  InventoryItem({
    required this.id,
    required this.name,
    this.description = '',
    this.category = 'Uncategorized',
    this.quantity = 1,
    this.location = '',
    this.notes = '',
    required this.timestamp,
    this.deleted = false,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'Uncategorized',
      quantity: json['quantity'] as int? ?? 1,
      location: json['location'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toDouble() ?? 0.0,
      deleted: (json['deleted'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'quantity': quantity,
      'location': location,
      'notes': notes,
      'timestamp': timestamp,
      'deleted': deleted ? 1 : 0,
    };
  }

  InventoryItem copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    int? quantity,
    String? location,
    String? notes,
    double? timestamp,
    bool? deleted,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      quantity: quantity ?? this.quantity,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      timestamp: timestamp ?? this.timestamp,
      deleted: deleted ?? this.deleted,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InventoryItem && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

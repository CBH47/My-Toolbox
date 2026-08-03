class Component {
  final String id;
  final String name;
  final int quantity;
  final double price;
  final int x;
  final int y;
  final String folderId;

  Component({
    required this.id,
    required this.name,
    this.quantity = 1,
    this.price = 0.0,
    this.x = 0,
    this.y = 0,
    required this.folderId,
  });

  factory Component.fromJson(Map<String, dynamic> json) {
    return Component(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 1,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      folderId: json['folderId'] as String? ?? 'root',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'price': price,
      'x': x,
      'y': y,
      'folderId': folderId,
    };
  }

  Component copyWith({
    String? id,
    String? name,
    int? quantity,
    double? price,
    int? x,
    int? y,
    String? folderId,
  }) {
    return Component(
      id: id ?? this.id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      x: x ?? this.x,
      y: y ?? this.y,
      folderId: folderId ?? this.folderId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Component && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Component($name, qty: $quantity, \$${price.toStringAsFixed(2)}, ($x,$y), folder: $folderId)';
}

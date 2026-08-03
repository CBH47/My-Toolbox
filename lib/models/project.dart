class Project {
  final String id;
  final String name;
  final int createdAt;

  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt,
    };
  }
}

class ProjectRequirement {
  final String projectId;
  final String componentId;
  final int requiredQuantity;
  final String? componentName;
  final int? availableQuantity;
  final double? componentPrice;

  const ProjectRequirement({
    required this.projectId,
    required this.componentId,
    required this.requiredQuantity,
    this.componentName,
    this.availableQuantity,
    this.componentPrice,
  });
}

final class RemoteProject {
  const RemoteProject({
    required this.id,
    required this.hostId,
    required this.name,
    required this.cwd,
  });

  factory RemoteProject.fromJson(Map<String, dynamic> json) => RemoteProject(
        id: json['id'] as String,
        hostId: json['hostId'] as String,
        name: json['name'] as String,
        cwd: json['cwd'] as String,
      );

  final String id;
  final String hostId;
  final String name;
  final String cwd;

  RemoteProject copyWith({
    String? id,
    String? hostId,
    String? name,
    String? cwd,
  }) =>
      RemoteProject(
        id: id ?? this.id,
        hostId: hostId ?? this.hostId,
        name: name ?? this.name,
        cwd: cwd ?? this.cwd,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostId': hostId,
        'name': name,
        'cwd': cwd,
      };

  @override
  bool operator ==(Object other) =>
      other is RemoteProject &&
      other.id == id &&
      other.hostId == hostId &&
      other.name == name &&
      other.cwd == cwd;

  @override
  int get hashCode => Object.hash(id, hostId, name, cwd);
}

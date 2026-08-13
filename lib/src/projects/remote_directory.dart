final class RemoteDirectoryEntry {
  const RemoteDirectoryEntry({required this.name, required this.path});

  final String name;
  final String path;
}

final class RemoteDirectoryListing {
  const RemoteDirectoryListing({required this.path, required this.directories});

  final String path;
  final List<RemoteDirectoryEntry> directories;
}

String remotePathChild(String parent, String child) {
  final normalizedParent = parent.trim();
  if (normalizedParent.isEmpty || normalizedParent == '.') return child;
  if (normalizedParent == '/') return '/$child';
  final separator = normalizedParent.contains('\\') ? '\\' : '/';
  final withoutTrailing = normalizedParent.replaceFirst(RegExp(r'[/\\]+$'), '');
  return '$withoutTrailing$separator$child';
}

String? remotePathParent(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  if (normalized.isEmpty || normalized == '.' || normalized == '/') return null;

  final withoutTrailing = normalized.replaceFirst(RegExp(r'/+$'), '');
  if (RegExp(r'^[A-Za-z]:$').hasMatch(withoutTrailing) ||
      RegExp(r'^[A-Za-z]:/$').hasMatch(normalized)) {
    return null;
  }
  final separator = withoutTrailing.lastIndexOf('/');
  if (separator < 0) return '.';
  if (separator == 0) return '/';
  final parent = withoutTrailing.substring(0, separator);
  return RegExp(r'^[A-Za-z]:$').hasMatch(parent) ? '$parent/' : parent;
}

import 'package:flutter/material.dart';

import '../projects/remote_directory.dart';

typedef RemoteDirectoryLoader = Future<RemoteDirectoryListing> Function(
  String path,
);

Future<String?> showRemoteDirectoryPicker(
  BuildContext context, {
  required RemoteDirectoryLoader loadDirectories,
  String initialPath = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => RemoteDirectoryPicker(
        loadDirectories: loadDirectories,
        initialPath: initialPath,
      ),
    );

class RemoteDirectoryPicker extends StatefulWidget {
  const RemoteDirectoryPicker({
    required this.loadDirectories,
    this.initialPath = '',
    super.key,
  });

  final RemoteDirectoryLoader loadDirectories;
  final String initialPath;

  @override
  State<RemoteDirectoryPicker> createState() => _RemoteDirectoryPickerState();
}

class _RemoteDirectoryPickerState extends State<RemoteDirectoryPicker> {
  late final TextEditingController _path;
  List<RemoteDirectoryEntry> _directories = const [];
  Object? _error;
  var _loading = false;
  var _generation = 0;

  String get _currentPath {
    final path = _path.text.trim();
    return path.isEmpty ? '.' : path;
  }

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(
      text: widget.initialPath.trim().isEmpty ? '.' : widget.initialPath.trim(),
    );
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _path.dispose();
    super.dispose();
  }

  Future<void> _load([String? path]) async {
    final requestedPath = (path ?? _currentPath).trim();
    final effectivePath = requestedPath.isEmpty ? '.' : requestedPath;
    _path.text = effectivePath;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await widget.loadDirectories(effectivePath);
      if (!mounted || generation != _generation) return;
      setState(() {
        _path.text = listing.path;
        _directories = listing.directories;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _directories = const [];
        _error = error;
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Choose remote folder'),
        content: SizedBox(
          width: 520,
          height: 480,
          child: Column(
            children: [
              TextField(
                key: const Key('remote-directory-path'),
                controller: _path,
                decoration: InputDecoration(
                  labelText: 'Remote path',
                  prefixIcon: const Icon(Icons.route_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Open path',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: _loading ? null : _load,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Parent folder',
                    onPressed: _loading
                        ? null
                        : () {
                            final parent = remotePathParent(_currentPath);
                            if (parent != null) _load(parent);
                          },
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const Divider(height: 1),
              Expanded(child: _directoryList()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('select-remote-directory'),
            onPressed:
                _loading ? null : () => Navigator.pop(context, _currentPath),
            icon: const Icon(Icons.check),
            label: const Text('Select this folder'),
          ),
        ],
      );

  Widget _directoryList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 36),
              const SizedBox(height: 12),
              Text(
                'Could not list this folder.\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_directories.isEmpty) {
      return const Center(child: Text('No subfolders'));
    }
    return ListView.builder(
      itemCount: _directories.length,
      itemBuilder: (context, index) {
        final directory = _directories[index];
        return ListTile(
          key: ValueKey('remote-directory-${directory.path}'),
          leading: const Icon(Icons.folder_outlined),
          title: Text(directory.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _load(directory.path),
        );
      },
    );
  }
}

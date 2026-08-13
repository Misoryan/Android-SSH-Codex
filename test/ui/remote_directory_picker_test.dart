import 'package:android_ssh_codex/src/projects/remote_directory.dart';
import 'package:android_ssh_codex/src/ui/remote_directory_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('browses children and selects the resolved remote path', (
    tester,
  ) async {
    final requests = <String>[];
    Future<RemoteDirectoryListing> load(String path) async {
      requests.add(path);
      return switch (path) {
        '.' => const RemoteDirectoryListing(
            path: '/home/owner',
            directories: [
              RemoteDirectoryEntry(
                name: 'projects',
                path: '/home/owner/projects',
              ),
            ],
          ),
        '/home/owner/projects' => const RemoteDirectoryListing(
            path: '/home/owner/projects',
            directories: [
              RemoteDirectoryEntry(
                name: 'mobile',
                path: '/home/owner/projects/mobile',
              ),
            ],
          ),
        '/home/owner' => const RemoteDirectoryListing(
            path: '/home/owner',
            directories: [],
          ),
        _ => throw StateError('Unexpected path $path'),
      };
    }

    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          onPressed: () async {
            selected = await showRemoteDirectoryPicker(
              context,
              loadDirectories: load,
            );
          },
          child: const Text('Open'),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(requests, ['.']);
    final pathField = tester.widget<TextField>(
      find.byKey(const Key('remote-directory-path')),
    );
    expect(pathField.controller!.text, '/home/owner');
    await tester.tap(find.text('projects'));
    await tester.pumpAndSettle();
    expect(requests.last, '/home/owner/projects');
    expect(find.text('mobile'), findsOneWidget);

    await tester.tap(find.byTooltip('Parent folder'));
    await tester.pumpAndSettle();
    expect(requests.last, '/home/owner');

    await tester.tap(find.byKey(const Key('select-remote-directory')));
    await tester.pumpAndSettle();
    expect(selected, '/home/owner');
  });

  testWidgets('keeps manual path editing available after an SFTP error', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: RemoteDirectoryPicker(
        loadDirectories: (_) async => throw StateError('SFTP unavailable'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('SFTP unavailable'), findsOneWidget);
    expect(find.byKey(const Key('remote-directory-path')), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}

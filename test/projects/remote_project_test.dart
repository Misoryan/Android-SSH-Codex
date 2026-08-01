import 'package:android_ssh_codex/src/projects/remote_project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('remote project round-trips its host and working directory', () {
    const project = RemoteProject(
      id: 'mobile',
      hostId: 'pi',
      name: 'Mobile',
      cwd: '/srv/mobile',
    );

    expect(RemoteProject.fromJson(project.toJson()), project);
  });

  test('copyWith can rename a project without changing its directory', () {
    const project = RemoteProject(
      id: 'mobile',
      hostId: 'pi',
      name: 'Mobile',
      cwd: '/srv/mobile',
    );

    expect(
      project.copyWith(name: 'Mobile app'),
      const RemoteProject(
        id: 'mobile',
        hostId: 'pi',
        name: 'Mobile app',
        cwd: '/srv/mobile',
      ),
    );
  });
}

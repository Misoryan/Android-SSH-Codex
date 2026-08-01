import 'package:android_ssh_codex/src/profiles/profile_store.dart';
import 'package:android_ssh_codex/src/projects/remote_project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory project storage stays scoped to one host', () async {
    final store = MemoryProfileStore();
    await store.writeProject(
      const RemoteProject(
        id: 'mobile',
        hostId: 'pi',
        name: 'Mobile',
        cwd: '/srv/mobile',
      ),
    );

    expect((await store.readProjects('pi')).single.name, 'Mobile');
    expect(await store.readProjects('other'), isEmpty);
  });

  test(
    'writing an existing project replaces it and keeps name ordering',
    () async {
      final store = MemoryProfileStore();
      await store.writeProject(
        const RemoteProject(
          id: 'web',
          hostId: 'pi',
          name: 'Web',
          cwd: '/srv/web',
        ),
      );
      await store.writeProject(
        const RemoteProject(
          id: 'mobile',
          hostId: 'pi',
          name: 'Mobile',
          cwd: '/srv/mobile',
        ),
      );
      await store.writeProject(
        const RemoteProject(
          id: 'web',
          hostId: 'pi',
          name: 'API',
          cwd: '/srv/api',
        ),
      );

      final projects = await store.readProjects('pi');
      expect(projects.map((project) => project.name), ['API', 'Mobile']);
      expect(projects.first.cwd, '/srv/api');
    },
  );

  test(
    'deleting a project leaves other projects on the host intact',
    () async {
      final store = MemoryProfileStore();
      for (final project in const [
        RemoteProject(
          id: 'mobile',
          hostId: 'pi',
          name: 'Mobile',
          cwd: '/srv/mobile',
        ),
        RemoteProject(
          id: 'web',
          hostId: 'pi',
          name: 'Web',
          cwd: '/srv/web',
        ),
      ]) {
        await store.writeProject(project);
      }

      await store.deleteProject('pi', 'mobile');

      expect((await store.readProjects('pi')).single.id, 'web');
    },
  );
}

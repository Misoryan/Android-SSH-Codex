import 'package:android_ssh_codex/src/app_controller.dart';
import 'package:android_ssh_codex/src/profiles/host_profile.dart';
import 'package:android_ssh_codex/src/profiles/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage failures do not prevent application initialization', () async {
    final controller = AppController(store: _FailingProfileStore());

    await controller.initialize();

    expect(controller.profiles, isEmpty);
    expect(controller.error, contains('secure storage'));
  });
}

final class _FailingProfileStore implements ProfileStore {
  @override
  Future<List<HostProfile>> readProfiles() =>
      Future.error(StateError('plugin unavailable'));

  @override
  Future<void> deleteProfile(String id) => throw UnimplementedError();

  @override
  Future<Set<String>> readOwnedThreads(String profileId) =>
      throw UnimplementedError();

  @override
  Future<HostSecret> readSecret(String id) => throw UnimplementedError();

  @override
  Future<String?> readHostFingerprint(String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> writeHostFingerprint(String profileId, String fingerprint) =>
      throw UnimplementedError();

  @override
  Future<void> writeOwnedThreads(String profileId, Set<String> threadIds) =>
      throw UnimplementedError();

  @override
  Future<void> writeProfile(HostProfile profile, HostSecret secret) =>
      throw UnimplementedError();
}

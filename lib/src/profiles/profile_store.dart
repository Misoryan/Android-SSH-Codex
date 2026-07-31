import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';

import 'host_profile.dart';

abstract interface class ProfileStore {
  Future<List<HostProfile>> readProfiles();
  Future<void> writeProfile(HostProfile profile, HostSecret secret);
  Future<void> deleteProfile(String id);
  Future<HostSecret> readSecret(String id);
  Future<String?> readHostFingerprint(String profileId);
  Future<void> writeHostFingerprint(String profileId, String fingerprint);
  Future<Set<String>> readOwnedThreads(String profileId);
  Future<void> writeOwnedThreads(String profileId, Set<String> threadIds);
}

final class SecureProfileStore implements ProfileStore {
  SecureProfileStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<List<HostProfile>> readProfiles() async {
    final value = await _storage.read(key: 'profiles');
    if (value == null || value.isEmpty) return [];
    final decoded = jsonDecode(value) as List<dynamic>;
    return decoded
        .map((item) =>
            HostProfile.fromJson((item as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<void> writeProfile(HostProfile profile, HostSecret secret) async {
    final profiles = (await readProfiles()).toList();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      profiles.add(profile);
    } else {
      profiles[index] = profile;
    }
    await _storage.write(
      key: 'profiles',
      value: jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    await _storage.write(
      key: 'secret.${profile.id}',
      value: jsonEncode(secret.toJson()),
    );
  }

  @override
  Future<void> deleteProfile(String id) async {
    final profiles = (await readProfiles())
        .where((profile) => profile.id != id)
        .toList(growable: false);
    await _storage.write(
      key: 'profiles',
      value: jsonEncode(profiles.map((item) => item.toJson()).toList()),
    );
    await _storage.delete(key: 'secret.$id');
    await _storage.delete(key: 'fingerprint.$id');
    await _storage.delete(key: 'owned.$id');
  }

  @override
  Future<HostSecret> readSecret(String id) async {
    final value = await _storage.read(key: 'secret.$id');
    if (value == null || value.isEmpty) return const HostSecret();
    return HostSecret.fromJson(
      (jsonDecode(value) as Map).cast<String, dynamic>(),
    );
  }

  @override
  Future<String?> readHostFingerprint(String profileId) =>
      _storage.read(key: 'fingerprint.$profileId');

  @override
  Future<void> writeHostFingerprint(
    String profileId,
    String fingerprint,
  ) =>
      _storage.write(key: 'fingerprint.$profileId', value: fingerprint);

  @override
  Future<Set<String>> readOwnedThreads(String profileId) async {
    final value = await _storage.read(key: 'owned.$profileId');
    if (value == null || value.isEmpty) return <String>{};
    return (jsonDecode(value) as List<dynamic>).cast<String>().toSet();
  }

  @override
  Future<void> writeOwnedThreads(
    String profileId,
    Set<String> threadIds,
  ) =>
      _storage.write(
          key: 'owned.$profileId', value: jsonEncode(threadIds.toList()));
}

final class MemoryProfileStore implements ProfileStore {
  final Map<String, HostProfile> _profiles = {};
  final Map<String, HostSecret> _secrets = {};
  final Map<String, String> _fingerprints = {};
  final Map<String, Set<String>> _owned = {};

  @override
  Future<List<HostProfile>> readProfiles() async =>
      _profiles.values.toList(growable: false);

  @override
  Future<void> writeProfile(HostProfile profile, HostSecret secret) async {
    _profiles[profile.id] = profile;
    _secrets[profile.id] = secret;
  }

  @override
  Future<void> deleteProfile(String id) async {
    _profiles.remove(id);
    _secrets.remove(id);
    _fingerprints.remove(id);
    _owned.remove(id);
  }

  @override
  Future<HostSecret> readSecret(String id) async =>
      _secrets[id] ?? const HostSecret();

  @override
  Future<String?> readHostFingerprint(String profileId) async =>
      _fingerprints[profileId];

  @override
  Future<void> writeHostFingerprint(
    String profileId,
    String fingerprint,
  ) async {
    _fingerprints[profileId] = fingerprint;
  }

  @override
  Future<Set<String>> readOwnedThreads(String profileId) async =>
      Set<String>.of(_owned[profileId] ?? const {});

  @override
  Future<void> writeOwnedThreads(
    String profileId,
    Set<String> threadIds,
  ) async {
    _owned[profileId] = Set<String>.of(threadIds);
  }
}

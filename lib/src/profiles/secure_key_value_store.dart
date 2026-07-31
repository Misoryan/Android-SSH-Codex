import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    as android_storage;
import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart'
    as ohos_storage;

abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String? value});
  Future<void> delete({required String key});
}

SecureKeyValueStore createSecureKeyValueStore() =>
    switch (Platform.operatingSystem) {
      'android' => AndroidSecureKeyValueStore(),
      'ohos' => OhosSecureKeyValueStore(),
      final platform =>
        throw UnsupportedError('Secure storage is unavailable on $platform.'),
    };

final class AndroidSecureKeyValueStore implements SecureKeyValueStore {
  AndroidSecureKeyValueStore([
    android_storage.FlutterSecureStorage? storage,
  ]) : _storage = storage ?? const android_storage.FlutterSecureStorage();

  final android_storage.FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

final class OhosSecureKeyValueStore implements SecureKeyValueStore {
  OhosSecureKeyValueStore([
    ohos_storage.FlutterSecureStorage? storage,
  ]) : _storage = storage ?? const ohos_storage.FlutterSecureStorage();

  final ohos_storage.FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

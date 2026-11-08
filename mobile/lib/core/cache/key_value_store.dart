import 'package:shared_preferences/shared_preferences.dart';

/// A minimal async string key/value store. Abstracting this lets the response
/// cache stay backend-agnostic: the app uses [SharedPreferencesKeyValueStore],
/// tests use [InMemoryKeyValueStore], and a heavier engine (e.g. Drift/SQLite)
/// could be dropped in later without touching the cache logic above it.
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Keys currently present that start with [prefix].
  Future<List<String>> keys(String prefix);
}

/// Volatile store for tests and previews — never persisted.
class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _data = {};

  InMemoryKeyValueStore([Map<String, String>? seed]) {
    if (seed != null) _data.addAll(seed);
  }

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<List<String>> keys(String prefix) async =>
      _data.keys.where((k) => k.startsWith(prefix)).toList();
}

/// Persistent store backed by [SharedPreferences]. The instance is resolved
/// lazily on first use so construction stays synchronous and cheap.
class SharedPreferencesKeyValueStore implements KeyValueStore {
  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> _instance() =>
      _prefs ??= SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _instance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await _instance()).setString(key, value);

  @override
  Future<void> delete(String key) async => (await _instance()).remove(key);

  @override
  Future<List<String>> keys(String prefix) async =>
      (await _instance()).getKeys().where((k) => k.startsWith(prefix)).toList();
}

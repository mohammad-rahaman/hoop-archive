import 'dart:convert';

import 'key_value_store.dart';

/// A cached API response body plus the moment it was stored.
class CacheEntry {
  final dynamic body;
  final DateTime cachedAt;
  const CacheEntry({required this.body, required this.cachedAt});
}

/// How the most recent load for a given key was satisfied. The UI reads this to
/// decide whether to show a "saved copy" / staleness hint.
class LoadOutcome {
  /// True when the value came from the local cache (a network call failed).
  final bool fromCache;

  /// When the served data was originally fetched from the network. Null for a
  /// fresh network load with no prior cache timestamp.
  final DateTime? cachedAt;

  const LoadOutcome({required this.fromCache, this.cachedAt});
}

/// Write-through / read-through cache for raw JSON API responses.
///
/// Successful network responses are stored verbatim (no model `toJson` needed),
/// and when the network is unreachable the last stored body is replayed. The
/// cache never hard-expires entries — stale data is still worth showing offline
/// — but [freshFor] marks when a copy should be labelled as aged in the UI. A
/// bounded [maxEntries] with oldest-first eviction keeps storage in check.
class ResponseCache {
  final KeyValueStore store;
  final int maxEntries;
  final Duration freshFor;

  static const _blobPrefix = 'hoopcache:';
  static const _indexKey = 'hoopcache_index';

  /// Ephemeral, per-key record of the last load. Keyed by request key so
  /// concurrent loads of different keys don't clobber each other.
  final Map<String, LoadOutcome> _outcomes = {};

  ResponseCache(
    this.store, {
    this.maxEntries = 64,
    this.freshFor = const Duration(hours: 12),
  });

  /// The outcome of the most recent [resolve] for [key], if any.
  LoadOutcome? outcomeFor(String key) => _outcomes[key];

  bool isStale(DateTime cachedAt) =>
      DateTime.now().toUtc().difference(cachedAt.toUtc()) > freshFor;

  /// Runs [fetch] and caches its decoded body on success. If [fetch] throws,
  /// the last cached body for [key] is parsed and returned instead; when no
  /// cached copy exists the original error is rethrown.
  ///
  /// [parse] turns a decoded JSON body into the domain object. It is applied to
  /// both fresh and cached bodies so callers get one consistent type.
  Future<T> resolve<T>(
    String key,
    Future<dynamic> Function() fetch,
    T Function(dynamic body) parse,
  ) async {
    try {
      final body = await fetch();
      await _put(key, body);
      _outcomes[key] = const LoadOutcome(fromCache: false);
      return parse(body);
    } catch (error) {
      final entry = await get(key);
      if (entry == null) rethrow;
      _outcomes[key] = LoadOutcome(fromCache: true, cachedAt: entry.cachedAt);
      return parse(entry.body);
    }
  }

  /// Reads a cached entry for [key], or null when absent/corrupt.
  Future<CacheEntry?> get(String key) async {
    final raw = await store.read(_blobPrefix + key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final ts = DateTime.tryParse(decoded['ts'] as String? ?? '');
      if (ts == null) return null;
      return CacheEntry(body: decoded['body'], cachedAt: ts);
    } catch (_) {
      // Corrupt entry — drop it so it can be rewritten cleanly.
      await store.delete(_blobPrefix + key);
      return null;
    }
  }

  Future<void> _put(String key, dynamic body) async {
    final now = DateTime.now().toUtc();
    await store.write(
      _blobPrefix + key,
      jsonEncode({'v': 1, 'ts': now.toIso8601String(), 'body': body}),
    );
    await _touchIndex(key, now.millisecondsSinceEpoch);
  }

  /// Records [key] in the LRU index and evicts the oldest entries past
  /// [maxEntries]. The index holds only timestamps, so eviction never has to
  /// read (potentially large) response bodies.
  Future<void> _touchIndex(String key, int tsMillis) async {
    final index = await _readIndex();
    index[key] = tsMillis;

    if (index.length > maxEntries) {
      final ordered = index.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final overflow = index.length - maxEntries;
      for (final stale in ordered.take(overflow)) {
        index.remove(stale.key);
        await store.delete(_blobPrefix + stale.key);
      }
    }
    await store.write(_indexKey, jsonEncode(index));
  }

  Future<Map<String, int>> _readIndex() async {
    final raw = await store.read(_indexKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Removes every cached entry and the index. Used when the user explicitly
  /// clears offline data.
  Future<void> clear() async {
    for (final k in await store.keys(_blobPrefix)) {
      await store.delete(k);
    }
    await store.delete(_indexKey);
    _outcomes.clear();
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/cache/key_value_store.dart';
import 'package:hoop_archive/core/cache/response_cache.dart';

void main() {
  group('ResponseCache.resolve', () {
    test('write-through on success, then read-through on failure', () async {
      final cache = ResponseCache(InMemoryKeyValueStore());
      final body = {'value': 42};

      // 1) Network succeeds → body is parsed and stored, marked fresh.
      final fresh = await cache.resolve<int>(
        'k',
        () async => body,
        (b) => (b as Map)['value'] as int,
      );
      expect(fresh, 42);
      expect(cache.outcomeFor('k')!.fromCache, isFalse);

      // 2) Network fails → the stored body is replayed, marked from-cache.
      final offline = await cache.resolve<int>(
        'k',
        () async => throw Exception('no network'),
        (b) => (b as Map)['value'] as int,
      );
      expect(offline, 42);
      final outcome = cache.outcomeFor('k')!;
      expect(outcome.fromCache, isTrue);
      expect(outcome.cachedAt, isNotNull);
    });

    test('rethrows when the fetch fails and nothing is cached', () async {
      final cache = ResponseCache(InMemoryKeyValueStore());
      expect(
        () => cache.resolve<int>(
          'missing',
          () async => throw StateError('x'),
          (b) => b as int,
        ),
        throwsStateError,
      );
    });

    test('a corrupt stored entry is ignored (and dropped)', () async {
      final store = InMemoryKeyValueStore();
      await store.write('hoopcache:k', 'not valid json');
      final cache = ResponseCache(store);
      expect(await cache.get('k'), isNull);
      // The bad entry was removed so a future write starts clean.
      expect(await store.read('hoopcache:k'), isNull);
    });
  });

  test('isStale reflects freshFor window', () {
    final cache = ResponseCache(
      InMemoryKeyValueStore(),
      freshFor: const Duration(hours: 1),
    );
    expect(
      cache.isStale(
        DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
      ),
      isFalse,
    );
    expect(
      cache.isStale(DateTime.now().toUtc().subtract(const Duration(hours: 2))),
      isTrue,
    );
  });

  test('evicts the oldest entries beyond maxEntries', () async {
    final store = InMemoryKeyValueStore();
    final cache = ResponseCache(store, maxEntries: 2);

    Future<void> put(String k) =>
        cache.resolve<int>(k, () async => 1, (b) => b as int);

    await put('a');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await put('b');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await put('c'); // 'a' is the oldest → evicted.

    expect(await cache.get('a'), isNull);
    expect(await cache.get('b'), isNotNull);
    expect(await cache.get('c'), isNotNull);
  });
}

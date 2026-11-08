import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/cache/key_value_store.dart';
import 'package:hoop_archive/core/cache/response_cache.dart';

/// Returns a canned JSON response until [failNow] is set, after which it
/// simulates an unreachable network by throwing a connection error.
class _QueueAdapter implements HttpClientAdapter {
  final Map<String, dynamic> payload;
  bool failNow = false;

  _QueueAdapter(this.payload);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (failNow) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'fetchPlayers falls back to cached data when the network fails',
    () async {
      final payload = {
        'items': [
          {
            'id': 1,
            'full_name': 'Cached Carter',
            'position': 'PG',
            'latest_team': 'BOS',
            'teams': ['BOS'],
            'season_count': 1,
            'first_year': 2000,
            'last_year': 2000,
            'latest_season': '2000-01',
          },
        ],
        'total': 1,
        'page': 1,
        'page_size': 25,
        'has_more': false,
      };

      final adapter = _QueueAdapter(payload);
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
        ..httpClientAdapter = adapter;
      final cache = ResponseCache(InMemoryKeyValueStore());
      final api = ApiClient(dio, cache: cache);
      final key = ApiClient.playersKey();

      // Online: served from the network, cached under the hood.
      final online = await api.fetchPlayers();
      expect(online.items.single.fullName, 'Cached Carter');
      expect(cache.outcomeFor(key)!.fromCache, isFalse);

      // Offline: the same request now fails, so the cached page is replayed.
      adapter.failNow = true;
      final offline = await api.fetchPlayers();
      expect(offline.items.single.fullName, 'Cached Carter');
      expect(cache.outcomeFor(key)!.fromCache, isTrue);
      expect(cache.outcomeFor(key)!.cachedAt, isNotNull);
    },
  );

  test('without a cache, a network failure propagates', () async {
    final adapter = _QueueAdapter(const {})..failNow = true;
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost'))
      ..httpClientAdapter = adapter;
    final api = ApiClient(dio); // no cache

    expect(() => api.fetchPlayers(), throwsA(isA<DioException>()));
  });
}

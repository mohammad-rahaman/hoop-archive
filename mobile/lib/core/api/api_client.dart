import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cache/key_value_store.dart';
import '../cache/response_cache.dart';
import '../env.dart';
import 'models.dart';

/// Thin wrapper over Dio. Feature repositories call into this; no provider API
/// keys ever live here — all third-party calls are proxied by the backend.
///
/// When a [ResponseCache] is supplied, every GET is write-through on success
/// and read-through on failure, so previously loaded data stays available
/// offline. The cache is optional: tests construct the client without one and
/// exercise the network path directly.
class ApiClient {
  final Dio _dio;

  /// When present, every GET is write-through on success and read-through on
  /// failure. Exposed so screens/controllers can read the freshness of the last
  /// load (whether it was served from cache and when it was fetched).
  final ResponseCache? cache;

  ApiClient(this._dio, {this.cache});

  factory ApiClient.create({ResponseCache? cache}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );
    return ApiClient(dio, cache: cache);
  }

  // --- Stable cache keys (shared by the client and the UI) -------------------

  static String metaKey() => 'meta';
  static String filtersKey() => 'filters';
  static String playerKey(int id) => 'player:$id';
  static String comparisonKey(
    int a,
    int b,
    String seasonType, {
    String? aSeason,
    String? bSeason,
  }) =>
      'compare:$a:$b:$seasonType:${aSeason ?? 'career'}:${bSeason ?? 'career'}';

  static String playersKey({
    String? q,
    String? team,
    String? position,
    String? season,
    int page = 1,
    int pageSize = 25,
  }) =>
      'players:q=${q ?? ''}&team=${team ?? ''}&position=${position ?? ''}'
      '&season=${season ?? ''}&page=$page&size=$pageSize';

  /// Fetch + parse, routed through the cache when one is configured.
  Future<T> _load<T>(
    String key,
    Future<dynamic> Function() fetch,
    T Function(dynamic body) parse,
  ) {
    final c = cache;
    if (c == null) return fetch().then(parse);
    return c.resolve(key, fetch, parse);
  }

  Future<MetaInfo> fetchMeta() => _load(
    metaKey(),
    () async => (await _dio.get('/meta')).data,
    (b) => MetaInfo.fromJson(b as Map<String, dynamic>),
  );

  Future<PlayersPage> fetchPlayers({
    String? q,
    String? team,
    String? position,
    String? season,
    int page = 1,
    int pageSize = 25,
  }) => _load(
    playersKey(
      q: q,
      team: team,
      position: position,
      season: season,
      page: page,
      pageSize: pageSize,
    ),
    () async => (await _dio.get(
      '/players',
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        'team': ?team,
        'position': ?position,
        'season': ?season,
        'page': page,
        'page_size': pageSize,
      },
    )).data,
    (b) => PlayersPage.fromJson(b as Map<String, dynamic>),
  );

  Future<FilterOptions> fetchFilters() => _load(
    filtersKey(),
    () async => (await _dio.get('/players/filters')).data,
    (b) => FilterOptions.fromJson(b as Map<String, dynamic>),
  );

  Future<PlayerDetail> fetchPlayerDetail(int id) => _load(
    playerKey(id),
    () async => (await _dio.get('/players/$id')).data,
    (b) => PlayerDetail.fromJson(b as Map<String, dynamic>),
  );

  /// Compares two players. Each side is a career line unless its season
  /// ([aSeason] / [bSeason], e.g. "2015-16") is given.
  Future<PlayerComparison> fetchComparison({
    required int a,
    required int b,
    String seasonType = 'regular',
    String? aSeason,
    String? bSeason,
  }) => _load(
    comparisonKey(a, b, seasonType, aSeason: aSeason, bSeason: bSeason),
    () async => (await _dio.get(
      '/players/compare',
      queryParameters: {
        'a': a,
        'b': b,
        'season_type': seasonType,
        'a_season': ?aSeason,
        'b_season': ?bSeason,
      },
    )).data,
    (body) => PlayerComparison.fromJson(body as Map<String, dynamic>),
  );
}

/// Keys a comparison request: the two player ids, the split, and an optional
/// season per side (null = career).
class CompareArgs {
  final int a;
  final int b;
  final String seasonType;
  final String? aSeason;
  final String? bSeason;
  const CompareArgs(
    this.a,
    this.b,
    this.seasonType, {
    this.aSeason,
    this.bSeason,
  });

  @override
  bool operator ==(Object other) =>
      other is CompareArgs &&
      other.a == a &&
      other.b == b &&
      other.seasonType == seasonType &&
      other.aSeason == aSeason &&
      other.bSeason == bSeason;

  @override
  int get hashCode => Object.hash(a, b, seasonType, aSeason, bSeason);
}

/// Persistent cache store. One instance per app; lazily opens SharedPreferences.
final cacheStoreProvider = Provider<KeyValueStore>(
  (ref) => SharedPreferencesKeyValueStore(),
);

final responseCacheProvider = Provider<ResponseCache>(
  (ref) => ResponseCache(ref.watch(cacheStoreProvider)),
);

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient.create(cache: ref.watch(responseCacheProvider)),
);

final metaProvider = FutureProvider<MetaInfo>((ref) async {
  return ref.watch(apiClientProvider).fetchMeta();
});

final filterOptionsProvider = FutureProvider<FilterOptions>((ref) async {
  return ref.watch(apiClientProvider).fetchFilters();
});

final playerDetailProvider = FutureProvider.family<PlayerDetail, int>((
  ref,
  id,
) async {
  return ref.watch(apiClientProvider).fetchPlayerDetail(id);
});

final comparisonProvider = FutureProvider.family<PlayerComparison, CompareArgs>(
  (ref, args) async {
    return ref
        .watch(apiClientProvider)
        .fetchComparison(
          a: args.a,
          b: args.b,
          seasonType: args.seasonType,
          aSeason: args.aSeason,
          bSeason: args.bSeason,
        );
  },
);

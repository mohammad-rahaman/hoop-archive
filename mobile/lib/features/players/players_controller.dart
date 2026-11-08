import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';

/// Immutable view state for the players browse screen.
class PlayersState {
  final String query;
  final String? team;
  final String? position;

  final List<PlayerListItem> items;
  final int total;
  final int page;
  final bool hasMore;

  final bool loading; // initial / filter-change load
  final bool loadingMore; // appending next page
  final Object? error;

  /// True when the current list was replayed from the offline cache.
  final bool fromCache;

  /// When the cached list was originally fetched (only set when [fromCache]).
  final DateTime? cachedAt;

  const PlayersState({
    this.query = '',
    this.team,
    this.position,
    this.items = const [],
    this.total = 0,
    this.page = 0,
    this.hasMore = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.fromCache = false,
    this.cachedAt,
  });

  bool get isEmpty => !loading && error == null && items.isEmpty;
  bool get hasActiveFilters =>
      query.isNotEmpty || team != null || position != null;

  PlayersState copyWith({
    String? query,
    Object? team = _sentinel,
    Object? position = _sentinel,
    List<PlayerListItem>? items,
    int? total,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error = _sentinel,
    bool? fromCache,
    Object? cachedAt = _sentinel,
  }) {
    return PlayersState(
      query: query ?? this.query,
      team: identical(team, _sentinel) ? this.team : team as String?,
      position: identical(position, _sentinel)
          ? this.position
          : position as String?,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: identical(error, _sentinel) ? this.error : error,
      fromCache: fromCache ?? this.fromCache,
      cachedAt: identical(cachedAt, _sentinel)
          ? this.cachedAt
          : cachedAt as DateTime?,
    );
  }

  static const _sentinel = Object();
}

class PlayersController extends StateNotifier<PlayersState> {
  final ApiClient _api;
  static const _pageSize = 25;

  PlayersController(this._api) : super(const PlayersState()) {
    refresh();
  }

  Future<void> setQuery(String q) async {
    if (q == state.query) return;
    state = state.copyWith(query: q);
    await _loadFirstPage();
  }

  Future<void> setTeam(String? team) async {
    state = state.copyWith(team: team);
    await _loadFirstPage();
  }

  Future<void> setPosition(String? position) async {
    state = state.copyWith(position: position);
    await _loadFirstPage();
  }

  Future<void> clearFilters() async {
    state = state.copyWith(query: '', team: null, position: null);
    await _loadFirstPage();
  }

  Future<void> refresh() => _loadFirstPage();

  Future<void> _loadFirstPage() async {
    final q = state.query;
    final team = state.team;
    final position = state.position;
    state = state.copyWith(loading: true, error: null);
    try {
      final result = await _api.fetchPlayers(
        q: q,
        team: team,
        position: position,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      final outcome = _api.cache?.outcomeFor(
        ApiClient.playersKey(
          q: q,
          team: team,
          position: position,
          page: 1,
          pageSize: _pageSize,
        ),
      );
      state = state.copyWith(
        items: result.items,
        total: result.total,
        page: result.page,
        hasMore: result.hasMore,
        loading: false,
        fromCache: outcome?.fromCache ?? false,
        cachedAt: outcome?.cachedAt,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true);
    try {
      final result = await _api.fetchPlayers(
        q: state.query,
        team: state.team,
        position: state.position,
        page: state.page + 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      state = state.copyWith(
        items: [...state.items, ...result.items],
        page: result.page,
        hasMore: result.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loadingMore: false, error: e);
    }
  }
}

final playersControllerProvider =
    StateNotifierProvider<PlayersController, PlayersState>(
      (ref) => PlayersController(ref.watch(apiClientProvider)),
    );

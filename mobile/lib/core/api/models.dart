/// Backend DTOs. Hand-written for the skeleton; Freezed/json_serializable are
/// introduced in later phases as the model surface grows.
class MetaInfo {
  final int players;
  final int teams;
  final int seasons;
  final int playerSeasonStats;
  final List<int>? seasonYearRange;
  final bool sportradarConfigured;
  final SyncInfo? lastSync;

  const MetaInfo({
    required this.players,
    required this.teams,
    required this.seasons,
    required this.playerSeasonStats,
    required this.seasonYearRange,
    required this.sportradarConfigured,
    required this.lastSync,
  });

  factory MetaInfo.fromJson(Map<String, dynamic> json) {
    final counts = (json['counts'] as Map?) ?? const {};
    final range = json['season_year_range'] as List?;
    return MetaInfo(
      players: (counts['players'] ?? 0) as int,
      teams: (counts['teams'] ?? 0) as int,
      seasons: (counts['seasons'] ?? 0) as int,
      playerSeasonStats: (counts['player_season_stats'] ?? 0) as int,
      seasonYearRange: range?.map((e) => e as int).toList(),
      sportradarConfigured: (json['sportradar_configured'] ?? false) as bool,
      lastSync: json['last_sync'] == null
          ? null
          : SyncInfo.fromJson(json['last_sync'] as Map<String, dynamic>),
    );
  }

  String get seasonRangeLabel {
    final r = seasonYearRange;
    if (r == null || r.length != 2) return '—';
    return '${r[0]} – ${r[1] + 1}';
  }
}

class SyncInfo {
  final String provider;
  final String? sourceLabel;
  final String? finishedAt;
  final int rowsIngested;
  final int rowsUpdated;

  const SyncInfo({
    required this.provider,
    required this.sourceLabel,
    required this.finishedAt,
    required this.rowsIngested,
    required this.rowsUpdated,
  });

  factory SyncInfo.fromJson(Map<String, dynamic> json) => SyncInfo(
        provider: (json['provider'] ?? 'unknown') as String,
        sourceLabel: json['source_label'] as String?,
        finishedAt: json['finished_at'] as String?,
        rowsIngested: (json['rows_ingested'] ?? 0) as int,
        rowsUpdated: (json['rows_updated'] ?? 0) as int,
      );
}

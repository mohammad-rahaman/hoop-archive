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

class PlayerListItem {
  final int id;
  final String fullName;
  final String? position;
  final String? latestTeam;
  final List<String> teams;
  final int seasonCount;
  final int? firstYear;
  final int? lastYear;
  final String? latestSeason;
  final String? imageUrl;

  const PlayerListItem({
    required this.id,
    required this.fullName,
    required this.position,
    required this.latestTeam,
    required this.teams,
    required this.seasonCount,
    required this.firstYear,
    required this.lastYear,
    required this.latestSeason,
    this.imageUrl,
  });

  factory PlayerListItem.fromJson(Map<String, dynamic> json) => PlayerListItem(
    id: json['id'] as int,
    fullName: json['full_name'] as String,
    position: json['position'] as String?,
    latestTeam: json['latest_team'] as String?,
    teams: ((json['teams'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    seasonCount: (json['season_count'] ?? 0) as int,
    firstYear: json['first_year'] as int?,
    lastYear: json['last_year'] as int?,
    latestSeason: json['latest_season'] as String?,
    imageUrl: json['image_url'] as String?,
  );

  String get careerSpan {
    if (firstYear == null || lastYear == null) return '—';
    final end = ((lastYear! + 1) % 100).toString().padLeft(2, '0');
    return '$firstYear–$end';
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class PlayersPage {
  final List<PlayerListItem> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  const PlayersPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
  });

  factory PlayersPage.fromJson(Map<String, dynamic> json) => PlayersPage(
    items: ((json['items'] as List?) ?? const [])
        .map((e) => PlayerListItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: (json['total'] ?? 0) as int,
    page: (json['page'] ?? 1) as int,
    pageSize: (json['page_size'] ?? 0) as int,
    hasMore: (json['has_more'] ?? false) as bool,
  );
}

class SeasonStatRow {
  final String season;
  final int yearStart;
  final String seasonType; // 'regular' | 'playoff'
  final String team;
  final String statMode;
  final int? gp;
  final double? min;
  final double? pts;
  final double? reb;
  final double? ast;
  final double? stl;
  final double? blk;
  final double? tov;
  final double? fgPct;
  final double? fg3Pct;
  final double? ftPct;
  final double? per;
  final double? tsPct;

  const SeasonStatRow({
    required this.season,
    required this.yearStart,
    required this.seasonType,
    required this.team,
    required this.statMode,
    this.gp,
    this.min,
    this.pts,
    this.reb,
    this.ast,
    this.stl,
    this.blk,
    this.tov,
    this.fgPct,
    this.fg3Pct,
    this.ftPct,
    this.per,
    this.tsPct,
  });

  bool get isPlayoff => seasonType == 'playoff';

  static double? _d(dynamic v) => v == null ? null : (v as num).toDouble();

  factory SeasonStatRow.fromJson(Map<String, dynamic> json) => SeasonStatRow(
    season: json['season'] as String,
    yearStart: json['year_start'] as int,
    seasonType: json['season_type'] as String,
    team: json['team'] as String,
    statMode: json['stat_mode'] as String,
    gp: json['gp'] as int?,
    min: _d(json['min']),
    pts: _d(json['pts']),
    reb: _d(json['reb']),
    ast: _d(json['ast']),
    stl: _d(json['stl']),
    blk: _d(json['blk']),
    tov: _d(json['tov']),
    fgPct: _d(json['fg_pct']),
    fg3Pct: _d(json['fg3_pct']),
    ftPct: _d(json['ft_pct']),
    per: _d(json['per']),
    tsPct: _d(json['ts_pct']),
  );
}

class PlayerDetail {
  final int id;
  final String fullName;
  final String? position;
  final String? jerseyNumber;
  final List<String> teams;
  final int? firstYear;
  final int? lastYear;
  final int seasonCount;
  final bool hasPlayoffs;
  final String? imageUrl;
  final List<SeasonStatRow> seasons;

  const PlayerDetail({
    required this.id,
    required this.fullName,
    required this.position,
    required this.jerseyNumber,
    required this.teams,
    required this.firstYear,
    required this.lastYear,
    required this.seasonCount,
    required this.hasPlayoffs,
    this.imageUrl,
    required this.seasons,
  });

  factory PlayerDetail.fromJson(Map<String, dynamic> json) => PlayerDetail(
    id: json['id'] as int,
    fullName: json['full_name'] as String,
    position: json['position'] as String?,
    jerseyNumber: json['jersey_number'] as String?,
    teams: ((json['teams'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    firstYear: json['first_year'] as int?,
    lastYear: json['last_year'] as int?,
    seasonCount: (json['season_count'] ?? 0) as int,
    hasPlayoffs: (json['has_playoffs'] ?? false) as bool,
    imageUrl: json['image_url'] as String?,
    seasons: ((json['seasons'] as List?) ?? const [])
        .map((e) => SeasonStatRow.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  String get careerSpan {
    if (firstYear == null || lastYear == null) return '—';
    final end = ((lastYear! + 1) % 100).toString().padLeft(2, '0');
    return '$firstYear–$end';
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class FilterOptions {
  final List<String> teams;
  final List<String> positions;

  /// Season labels with recorded stats, newest first (e.g. "2020-21").
  final List<String> seasons;

  const FilterOptions({
    required this.teams,
    required this.positions,
    this.seasons = const [],
  });

  static const empty = FilterOptions(teams: [], positions: []);

  factory FilterOptions.fromJson(Map<String, dynamic> json) => FilterOptions(
    teams: ((json['teams'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    positions: ((json['positions'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    seasons: ((json['seasons'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
  );
}

class ComparisonPlayer {
  final int id;
  final String fullName;
  final String? position;
  final List<String> teams;
  final int? firstYear;
  final int? lastYear;
  final int seasonCount;
  final String? imageUrl;

  /// Set when this side compares one season instead of the career.
  final String? season;

  /// Team for that season ("TOT" when split across teams).
  final String? seasonTeam;

  const ComparisonPlayer({
    required this.id,
    required this.fullName,
    required this.position,
    required this.teams,
    required this.firstYear,
    required this.lastYear,
    required this.seasonCount,
    this.imageUrl,
    this.season,
    this.seasonTeam,
  });

  factory ComparisonPlayer.fromJson(Map<String, dynamic> json) =>
      ComparisonPlayer(
        id: json['id'] as int,
        fullName: json['full_name'] as String,
        position: json['position'] as String?,
        teams: ((json['teams'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        firstYear: json['first_year'] as int?,
        lastYear: json['last_year'] as int?,
        seasonCount: (json['season_count'] ?? 0) as int,
        imageUrl: json['image_url'] as String?,
        season: json['season'] as String?,
        seasonTeam: json['season_team'] as String?,
      );

  String get careerSpan {
    if (firstYear == null || lastYear == null) return '—';
    final end = ((lastYear! + 1) % 100).toString().padLeft(2, '0');
    return '$firstYear–$end';
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

/// A single metric compared across two players. `leader` is 'a' | 'b' | 'tie'
/// | null (unavailable — never scored). Values are null when not recorded.
class MetricComparisonRow {
  final String key;
  final String label;
  final String unit;
  final bool percent;
  final double? aValue;
  final double? bValue;
  final String? leader;
  final bool available;

  const MetricComparisonRow({
    required this.key,
    required this.label,
    required this.unit,
    required this.percent,
    required this.aValue,
    required this.bValue,
    required this.leader,
    required this.available,
  });

  static double? _d(dynamic v) => v == null ? null : (v as num).toDouble();

  factory MetricComparisonRow.fromJson(Map<String, dynamic> json) =>
      MetricComparisonRow(
        key: json['key'] as String,
        label: json['label'] as String,
        unit: json['unit'] as String? ?? '',
        percent: (json['percent'] ?? false) as bool,
        aValue: _d(json['a_value']),
        bValue: _d(json['b_value']),
        leader: json['leader'] as String?,
        available: (json['available'] ?? false) as bool,
      );

  String _fmt(double? v) {
    if (v == null) return '—';
    if (percent) return (v * 100).toStringAsFixed(1);
    if (key == 'gp') return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  String get aDisplay => _fmt(aValue);
  String get bDisplay => _fmt(bValue);
}

class PlayerComparison {
  final String seasonType; // 'regular' | 'playoff'
  final ComparisonPlayer a;
  final ComparisonPlayer b;
  final List<MetricComparisonRow> metrics;
  final int aWins;
  final int bWins;
  final int ties;

  const PlayerComparison({
    required this.seasonType,
    required this.a,
    required this.b,
    required this.metrics,
    required this.aWins,
    required this.bWins,
    required this.ties,
  });

  factory PlayerComparison.fromJson(Map<String, dynamic> json) =>
      PlayerComparison(
        seasonType: json['season_type'] as String,
        a: ComparisonPlayer.fromJson(json['a'] as Map<String, dynamic>),
        b: ComparisonPlayer.fromJson(json['b'] as Map<String, dynamic>),
        metrics: ((json['metrics'] as List?) ?? const [])
            .map((e) => MetricComparisonRow.fromJson(e as Map<String, dynamic>))
            .toList(),
        aWins: (json['a_wins'] ?? 0) as int,
        bWins: (json['b_wins'] ?? 0) as int,
        ties: (json['ties'] ?? 0) as int,
      );

  int get comparedCount => aWins + bWins + ties;
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

  /// Human label for the provider that last populated data.
  String get providerLabel {
    switch (provider) {
      case 'kaggle_csv':
        return 'Historical dataset';
      case 'sportradar':
        return 'Sportradar';
      default:
        return provider;
    }
  }

  /// Relative "updated …" label from [finishedAt], or null if unknown.
  String? get updatedLabel {
    final iso = finishedAt;
    if (iso == null) return null;
    final when = DateTime.tryParse(iso);
    if (when == null) return null;
    final diff = DateTime.now().toUtc().difference(when.toUtc());
    if (diff.inSeconds < 60) return 'updated just now';
    if (diff.inMinutes < 60) return 'updated ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'updated ${diff.inHours}h ago';
    if (diff.inDays < 30) return 'updated ${diff.inDays}d ago';
    final local = when.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return 'updated ${local.year}-$mm-$dd';
  }
}

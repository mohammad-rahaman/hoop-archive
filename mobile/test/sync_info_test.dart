import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/models.dart';

SyncInfo _sync(String provider, String? finishedAt) => SyncInfo(
      provider: provider,
      sourceLabel: null,
      finishedAt: finishedAt,
      rowsIngested: 0,
      rowsUpdated: 0,
    );

void main() {
  test('provider labels are humanized', () {
    expect(_sync('kaggle_csv', null).providerLabel, 'Historical dataset');
    expect(_sync('sportradar', null).providerLabel, 'Sportradar');
    expect(_sync('other', null).providerLabel, 'other');
  });

  test('updatedLabel is null when timestamp missing or unparseable', () {
    expect(_sync('sportradar', null).updatedLabel, isNull);
    expect(_sync('sportradar', 'not-a-date').updatedLabel, isNull);
  });

  test('updatedLabel renders recent relative times', () {
    final now = DateTime.now().toUtc();
    final fiveMinAgo = now.subtract(const Duration(minutes: 5)).toIso8601String();
    expect(_sync('sportradar', fiveMinAgo).updatedLabel, 'updated 5m ago');

    final threeHoursAgo = now.subtract(const Duration(hours: 3)).toIso8601String();
    expect(_sync('sportradar', threeHoursAgo).updatedLabel, 'updated 3h ago');
  });

  test('old timestamps fall back to a date', () {
    final label = _sync('kaggle_csv', '2020-01-15T00:00:00Z').updatedLabel;
    expect(label, startsWith('updated 2020-01-'));
  });
}

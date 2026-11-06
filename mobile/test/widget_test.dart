import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/api/api_client.dart';
import 'package:hoop_archive/core/api/models.dart';
import 'package:hoop_archive/main.dart';

void main() {
  testWidgets('Home renders brand and overview from meta', (tester) async {
    const fakeMeta = MetaInfo(
      players: 42,
      teams: 7,
      seasons: 9,
      playerSeasonStats: 123,
      seasonYearRange: [1980, 2020],
      sportradarConfigured: false,
      lastSync: null,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metaProvider.overrideWith((ref) async => fakeMeta),
        ],
        child: const HoopArchiveApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoop Archive'), findsOneWidget);
    expect(find.text('42'), findsOneWidget); // players stat tile
    expect(find.text('1980 – 2021'), findsOneWidget); // season span label
  });
}

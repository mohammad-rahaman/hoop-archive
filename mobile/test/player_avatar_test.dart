import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoop_archive/core/widgets/player_avatar.dart';

void main() {
  testWidgets('PlayerAvatar renders initials fallback when imageUrl is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlayerAvatar(initials: 'MJ', radius: 24)),
      ),
    );

    expect(find.text('MJ'), findsOneWidget);
  });

  testWidgets('PlayerAvatar renders initials fallback when imageUrl is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerAvatar(
            initials: 'LJ',
            imageUrl: '',
            radius: 30,
            borderColor: Colors.amber,
          ),
        ),
      ),
    );

    expect(find.text('LJ'), findsOneWidget);
  });
}

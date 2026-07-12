import 'package:analyse_faciale/screens/skin_result/diagnostic_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hero shows type, score, label and age (photo null fallback)',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiagnosticHero(
          frontPhoto: null,
          skinTypeLabel: 'Mixte',
          globalScore: 82,
          globalLabel: 'Excellent',
          estimatedAge: 28,
        ),
      ),
    ));
    expect(find.text('Mixte'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('Excellent'), findsOneWidget);
    expect(find.textContaining('28 ans'), findsOneWidget);
  });

  testWidgets('hero hides age row when age null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DiagnosticHero(
          frontPhoto: null,
          skinTypeLabel: 'Grasse',
          globalScore: 60,
          globalLabel: 'Correct',
          estimatedAge: null,
        ),
      ),
    ));
    expect(find.textContaining('ans'), findsNothing);
  });
}

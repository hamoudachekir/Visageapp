import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/detailed_report.dart';
import 'package:analyse_faciale/screens/skin_result/observation_card.dart';
import 'package:analyse_faciale/screens/skin_result/routine_placeholder.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ObservationCard renders forts and vigilance', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ObservationCard(
          observation: Observation(
            forts: ['Rides', 'Taches'],
            vigilance: ['Rougeurs'],
          ),
        ),
      ),
    ));
    expect(find.text('Observation'), findsOneWidget);
    expect(find.textContaining('Rides'), findsOneWidget);
    expect(find.textContaining('Rougeurs'), findsOneWidget);
  });

  testWidgets('ObservationCard empty renders nothing visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ObservationCard(
          observation: Observation(forts: [], vigilance: []),
        ),
      ),
    ));
    expect(find.text('Observation'), findsNothing);
  });

  testWidgets('DetailedReport toggles list', (tester) async {
    const conditions = [
      SkinCondition(
          code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailedReport(
          conditions: conditions,
          expanded: false,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.textContaining('1 critère'), findsOneWidget);
    expect(find.text('Voir plus'), findsOneWidget);
    expect(find.text('Rides'), findsNothing);
  });

  testWidgets('DetailedReport expanded shows rows', (tester) async {
    const conditions = [
      SkinCondition(
          code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailedReport(
          conditions: conditions,
          expanded: true,
          onToggle: () {},
        ),
      ),
    ));
    expect(find.text('Rides'), findsOneWidget);
    expect(find.textContaining('92/100'), findsOneWidget);
  });

  testWidgets('RoutinePlaceholder fires onCreate', (tester) async {
    var created = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutinePlaceholder(onCreate: () => created = true),
      ),
    ));
    expect(find.text('Créer ma routine'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'Créer ma routine'));
    expect(created, isTrue);
  });

  testWidgets('DetailedReport renders conditions in health-descending order',
      (tester) async {
    const conditions = [
      SkinCondition(
          code: 'a', labelFr: 'Alpha', score: 40, severity: 'moderate'),
      SkinCondition(code: 'b', labelFr: 'Beta', score: 10, severity: 'mild'),
      SkinCondition(code: 'c', labelFr: 'Gamma', score: 25, severity: 'mild'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DetailedReport(
            conditions: conditions,
            expanded: true,
            onToggle: () {},
          ),
        ),
      ),
    ));
    // reportConditions sorts by health (100 - score) descending: Beta(90) > Gamma(75) > Alpha(60)
    final betaY = tester.getTopLeft(find.text('Beta')).dy;
    final gammaY = tester.getTopLeft(find.text('Gamma')).dy;
    final alphaY = tester.getTopLeft(find.text('Alpha')).dy;
    expect(betaY, lessThan(gammaY));
    expect(gammaY, lessThan(alphaY));
  });
}

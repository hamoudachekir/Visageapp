import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SkinAnalysisResult sample() => const SkinAnalysisResult(
      analysisId: 1,
      skinType: 'combination',
      conditions: [
        SkinCondition(
            code: 'redness',
            labelFr: 'Rougeurs et sensibilité',
            score: 28,
            severity: 'mild'),
        SkinCondition(
            code: 'oiliness',
            labelFr: 'Excès de sébum',
            score: 40,
            severity: 'moderate'),
        SkinCondition(
            code: 'wrinkles', labelFr: 'Rides', score: 8, severity: 'mild'),
      ],
      recommendations: [
        ProductRecommendation(
          productId: 1,
          name: 'Crème apaisante',
          brand: 'Vichy',
          price: 28.95,
          reasonFr: 'Pour vos rougeurs.',
          matchedConditions: ['oiliness'],
        ),
      ],
      disclaimerFr: 'Analyse indicative.',
      age: AgeInfo(estimatedAge: 28, messageFr: 'x'),
    );

void main() {
  testWidgets('renders hero, priority condition, reveals products',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SkinResultScreen(result: sample(), onRetry: () {}),
    ));
    // Skin type + age in hero.
    expect(find.text('Mixte'), findsOneWidget);
    expect(find.textContaining('28 ans'), findsOneWidget);
    // Priority condition card present (sébum score 40 => priority).
    expect(find.text('Excès de sébum'), findsOneWidget);

    // Reveal products for the sébum condition (scroll the button into view
    // first: the default test viewport is shorter than the full page).
    await tester.ensureVisible(find.text('Trouver des produits').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trouver des produits').first);
    await tester.pumpAndSettle();
    expect(find.text('Crème apaisante'), findsOneWidget);
  });

  testWidgets('healthy-only result shows the peau saine state', (tester) async {
    const healthy = SkinAnalysisResult(
      analysisId: 2,
      skinType: 'normal',
      conditions: [
        SkinCondition(
            code: 'wrinkles', labelFr: 'Rides', score: 5, severity: 'mild'),
      ],
      recommendations: [],
      disclaimerFr: 'x',
    );
    await tester.pumpWidget(MaterialApp(
      home: SkinResultScreen(result: healthy, onRetry: () {}),
    ));
    expect(find.textContaining('Peau globalement saine'), findsOneWidget);
  });
}

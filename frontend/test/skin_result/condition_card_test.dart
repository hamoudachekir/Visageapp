import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/condition_card.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const condition = SkinCondition(
    code: 'redness',
    labelFr: 'Rougeurs et sensibilité',
    score: 28,
    severity: 'mild',
  );
  const products = [
    ProductView(
      product: ProductRecommendation(
        productId: 1,
        name: 'Crème apaisante',
        reasonFr: 'r',
        matchedConditions: ['redness'],
      ),
      matchPercent: 88,
    ),
  ];

  testWidgets('collapsed shows label, health/100 and reveal button',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: false,
          onToggle: () {},
          products: products,
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.text('Rougeurs et sensibilité'), findsOneWidget);
    expect(find.textContaining('72/100'), findsOneWidget);
    expect(find.text('Trouver des produits'), findsOneWidget);
    expect(find.text('Crème apaisante'), findsNothing);
  });

  testWidgets('expanded reveals products and Masquer label', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: true,
          onToggle: () {},
          products: products,
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.text('Masquer les produits'), findsOneWidget);
    expect(find.text('Crème apaisante'), findsOneWidget);
  });

  testWidgets('expanded with no products shows empty message', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: true,
          onToggle: () {},
          products: const [],
          onProductTap: (_) {},
          onProductAdd: (_) {},
        ),
      ),
    ));
    expect(find.textContaining('Aucun produit correspondant'), findsOneWidget);
  });

  testWidgets('expanded fires product tap and add callbacks', (tester) async {
    ProductView? tapped;
    ProductView? added;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConditionCard(
          condition: condition,
          health: 72,
          severity: Severity.faible,
          expanded: true,
          onToggle: () {},
          products: products,
          onProductTap: (v) => tapped = v,
          onProductAdd: (v) => added = v,
        ),
      ),
    ));
    await tester.tap(find.text('Crème apaisante'));
    expect(tapped, isNotNull);
    expect(tapped!.product.productId, 1);
    await tester.tap(find.text('Ajouter'));
    expect(added, isNotNull);
    expect(added!.product.productId, 1);
  });
}

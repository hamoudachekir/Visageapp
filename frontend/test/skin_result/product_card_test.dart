import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/product_card.dart';
import 'package:analyse_faciale/screens/skin_result/product_detail_sheet.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProductView view() => const ProductView(
      product: ProductRecommendation(
        productId: 1,
        name: 'Crème hydratante',
        brand: 'Vichy',
        price: 28.95,
        reasonFr: 'Recommandé pour vos rougeurs.',
        matchedConditions: ['redness'],
      ),
      matchPercent: 91,
    );

void main() {
  testWidgets('ProductCard shows name, brand, price TND, match%, add button',
      (tester) async {
    var tapped = false;
    var added = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductCard(
          view: view(),
          onTap: () => tapped = true,
          onAdd: () => added = true,
        ),
      ),
    ));
    expect(find.text('Crème hydratante'), findsOneWidget);
    expect(find.text('Vichy'), findsOneWidget);
    expect(find.textContaining('28.950 TND'), findsOneWidget);
    expect(find.textContaining('91'), findsWidgets);
    await tester.tap(find.text('Ajouter'));
    expect(added, isTrue);
    await tester.tap(find.text('Crème hydratante'));
    expect(tapped, isTrue);
  });

  testWidgets('detail sheet shows reason and matched labels', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ProductDetailSheet.show(
              context,
              view: view(),
              matchedLabels: const ['Rougeurs et sensibilité'],
              onAdd: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Recommandé pour vos rougeurs'), findsOneWidget);
    expect(find.text('Rougeurs et sensibilité'), findsOneWidget);
  });

  testWidgets('detail sheet shows product description when present',
      (tester) async {
    const v = ProductView(
      product: ProductRecommendation(
        productId: 9,
        name: 'Soin',
        reasonFr: 'Pour vous.',
        description: 'Formule apaisante sans parfum.',
        matchedConditions: [],
      ),
      matchPercent: 80,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => ProductDetailSheet.show(
              context,
              view: v,
              matchedLabels: const [],
              onAdd: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.textContaining('Formule apaisante'), findsOneWidget);
  });
}

import 'package:analyse_faciale/screens/skin_result/product_filter_bar.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collapsed shows only header; expands on demand', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: false,
          onToggleExpanded: () {},
          filter: const FilterState(),
          brands: const ['Avene', 'Vichy'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Filtrer et trier les produits'), findsOneWidget);
    expect(find.text('Trier par'), findsNothing);
  });

  testWidgets('expanded exposes sort and brand toggle; emits change',
      (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: const FilterState(),
          brands: const ['Avene', 'Vichy'],
          onChanged: (f) => emitted = f,
        ),
      ),
    ));
    expect(find.text('Trier par'), findsOneWidget);
    expect(find.text('Utiliser toutes les marques'), findsOneWidget);
    // Toggle the "all brands" switch off.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.useAllBrands, isFalse);
  });

  testWidgets('toggling all-brands ON clears priorityBrands', (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: const FilterState(
              useAllBrands: false, priorityBrands: ['Vichy']),
          brands: const ['Avene', 'Vichy'],
          onChanged: (f) => emitted = f,
        ),
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.useAllBrands, isTrue);
    expect(emitted!.priorityBrands, isEmpty);
  });

  testWidgets('selecting a brand chip adds it to priorityBrands',
      (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: const FilterState(useAllBrands: false),
          brands: const ['Avene', 'Vichy'],
          onChanged: (f) => emitted = f,
        ),
      ),
    ));
    await tester.tap(find.widgetWithText(FilterChip, 'Vichy'));
    await tester.pump();
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, contains('Vichy'));
  });
}

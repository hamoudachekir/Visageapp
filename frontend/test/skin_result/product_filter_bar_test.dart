import 'package:analyse_faciale/screens/skin_result/product_filter_bar.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required FilterState filter,
  required List<String> catalog,
  ValueChanged<FilterState>? onChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProductFilterBar(
          expanded: true,
          onToggleExpanded: () {},
          filter: filter,
          catalog: catalog,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('collapsed shows only header', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProductFilterBar(
          expanded: false,
          onToggleExpanded: () {},
          filter: const FilterState(),
          catalog: const ['Avene', 'Vichy'],
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('Filtrer et trier les produits'), findsOneWidget);
    expect(find.text('Marques prioritaires'), findsNothing);
  });

  testWidgets('expanded shows sort, brand section, search', (tester) async {
    await tester.pumpWidget(_host(
        filter: const FilterState(), catalog: const ['Avene', 'Vichy']));
    expect(find.text('Trier les produits par'), findsOneWidget);
    expect(find.text('Marques prioritaires'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('tapping a catalog chip adds brand as priority', (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    await tester.tap(find.text('Vichy'));
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, ['Vichy']);
    expect(emitted!.useAllBrands, isFalse);
  });

  testWidgets('search filters catalog chips', (tester) async {
    await tester.pumpWidget(_host(
        filter: const FilterState(), catalog: const ['Avene', 'Vichy']));
    expect(find.text('Avene'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'vic');
    await tester.pump();
    expect(find.text('Avene'), findsNothing);
    expect(find.text('Vichy'), findsOneWidget);
  });

  testWidgets('clear-all empties priority and turns useAllBrands on',
      (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(useAllBrands: false, priorityBrands: ['Vichy']),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    expect(find.text('Marques sélectionnées (Ordre de priorité)'),
        findsOneWidget);
    await tester.tap(find.text('Tout effacer'));
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, isEmpty);
    expect(emitted!.useAllBrands, isTrue);
  });

  testWidgets('reorder moves a selected brand up', (tester) async {
    FilterState? emitted;
    await tester.pumpWidget(_host(
      filter: const FilterState(
          useAllBrands: false, priorityBrands: ['Vichy', 'Avene']),
      catalog: const ['Avene', 'Vichy'],
      onChanged: (f) => emitted = f,
    ));
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    expect(emitted, isNotNull);
    expect(emitted!.priorityBrands, ['Avene', 'Vichy']);
  });
}

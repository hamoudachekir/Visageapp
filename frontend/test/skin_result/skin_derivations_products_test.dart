import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:analyse_faciale/screens/skin_result/skin_derivations.dart';
import 'package:flutter_test/flutter_test.dart';

ProductRecommendation prod(
  int id, {
  String? brand,
  List<String> matched = const [],
}) =>
    ProductRecommendation(
      productId: id,
      name: 'P$id',
      brand: brand,
      reasonFr: 'r',
      matchedConditions: matched,
    );

void main() {
  const flagged = {'redness', 'oiliness', 'dark_circles'};

  test('matchPercent: coverage + rank bonus, clamped', () {
    // covers 1/3 => 70 + 8.33 + rankBonus
    expect(
        matchPercent(
            product: prod(1, matched: ['redness']),
            flagged: flagged,
            indexInGroup: 0),
        83); // 70 + 8 (round of 8.33) ... exact below
    // covers 2/3 => 70 + 16.67 + 5 => 92
    expect(
        matchPercent(
            product: prod(2, matched: ['redness', 'oiliness']),
            flagged: flagged,
            indexInGroup: 0),
        92);
    // rank bonus decays; index 6 => bonus 0
    expect(
        matchPercent(
            product: prod(3, matched: ['redness']),
            flagged: flagged,
            indexInGroup: 6),
        78); // 70 + 8 + 0
  });

  test('matchPercent clamps to [70,99]', () {
    expect(
        matchPercent(
            product: prod(1, matched: []),
            flagged: <String>{},
            indexInGroup: 10),
        70);
  });

  test('productsForCondition filters by matched code, preserves order', () {
    final recs = [
      prod(1, matched: ['redness']),
      prod(2, matched: ['acne']),
      prod(3, matched: ['redness', 'oiliness']),
    ];
    expect(productsForCondition('redness', recs).map((p) => p.productId),
        [1, 3]);
  });

  test('brandsInResults: distinct non-empty, sorted', () {
    final recs = [
      prod(1, brand: 'Vichy'),
      prod(2, brand: 'Avene'),
      prod(3, brand: 'Vichy'),
      prod(4, brand: null),
    ];
    expect(brandsInResults(recs), ['Avene', 'Vichy']);
  });

  test('productViewsForCondition sorts by score desc by default', () {
    final recs = [
      prod(1, matched: ['redness']), // 83 @ index0
      prod(2, matched: ['redness', 'oiliness']), // 91 @ index1
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(),
    );
    expect(views.first.product.productId, 2); // highest match first
  });

  test('productViewsForCondition displayOrder keeps backend order', () {
    final recs = [
      prod(1, matched: ['redness', 'oiliness']),
      prod(2, matched: ['redness']),
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(sortBy: SortBy.displayOrder, sortDir: SortDir.asc),
    );
    expect(views.map((v) => v.product.productId), [1, 2]);
  });

  test('brand priority floats selected brands, stable within rank', () {
    final recs = [
      prod(1, brand: 'Avene', matched: ['redness']),
      prod(2, brand: 'Vichy', matched: ['redness']),
      prod(3, brand: 'Avene', matched: ['redness']),
    ];
    final views = productViewsForCondition(
      code: 'redness',
      recs: recs,
      flagged: flagged,
      filter: const FilterState(
        sortBy: SortBy.displayOrder,
        sortDir: SortDir.asc,
        useAllBrands: false,
        priorityBrands: ['Vichy'],
      ),
    );
    expect(views.first.product.brand, 'Vichy');
  });
}

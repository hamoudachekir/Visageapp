import 'package:analyse_faciale/models/skin_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SkinAnalysisResult.fromJson parse le contrat complet', () {
    final json = {
      'analysis_id': 123,
      'skin_type': 'combination',
      'conditions': [
        {
          'code': 'acne',
          'label_fr': 'Acné / boutons',
          'score': 62,
          'severity': 'severe',
          'zones': ['chin', 'forehead'],
        },
      ],
      'recommendations': [
        {
          'product_id': 45,
          'name': 'Gel nettoyant',
          'brand': 'Marque',
          'price': 25.5,
          'image_url': null,
          'reason_fr': 'Recommandé pour votre acné marquée.',
          'matched_conditions': ['acne'],
        },
      ],
      'disclaimer_fr':
          'Cette analyse est indicative et ne remplace pas un avis dermatologique.',
    };

    final result = SkinAnalysisResult.fromJson(json);

    expect(result.analysisId, 123);
    expect(result.skinType, 'combination');
    expect(result.conditions.single.labelFr, 'Acné / boutons');
    expect(result.conditions.single.zones, ['chin', 'forehead']);
    expect(result.recommendations.single.productId, 45);
    expect(result.recommendations.single.price, 25.5);
    expect(result.recommendations.single.imageUrl, isNull);
    expect(result.recommendations.single.matchedConditions, ['acne']);
    expect(result.disclaimerFr, contains('dermatologique'));
  });
}

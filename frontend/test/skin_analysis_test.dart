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

  test('bloc age présent', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [],
      'age': {
        'estimated_age': 32,
        'real_age': 28,
        'skin_age_delta': 4,
        'message_fr': 'Votre peau paraît 4 ans de plus — voici des soins ciblés.',
      },
      'disclaimer_fr': 'x',
    };
    final result = SkinAnalysisResult.fromJson(json);
    expect(result.age, isNotNull);
    expect(result.age!.estimatedAge, 32);
    expect(result.age!.realAge, 28);
    expect(result.age!.skinAgeDelta, 4);
    expect(result.age!.messageFr, contains('4 ans de plus'));
  });

  test('bloc age absent ou null', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [],
      'age': null,
      'disclaimer_fr': 'x',
    };
    expect(SkinAnalysisResult.fromJson(json).age, isNull);
  });

  test('ProductRecommendation parse la description', () {
    final json = {
      'analysis_id': 1,
      'skin_type': 'oily',
      'conditions': [],
      'recommendations': [
        {
          'product_id': 7,
          'name': 'Gel',
          'reason_fr': 'r',
          'description': 'Nettoie en douceur.',
          'matched_conditions': [],
        },
      ],
      'disclaimer_fr': 'x',
    };
    final result = SkinAnalysisResult.fromJson(json);
    expect(result.recommendations.single.description, 'Nettoie en douceur.');
  });
}

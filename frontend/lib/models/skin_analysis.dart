/// Modèles du diagnostic de peau renvoyé par `POST /v1/skin/analyze`.
class SkinCondition {
  final String code;
  final String labelFr;
  final int score; // 0-100
  final String severity; // mild | moderate | severe
  final List<String> zones;

  const SkinCondition({
    required this.code,
    required this.labelFr,
    required this.score,
    required this.severity,
    this.zones = const [],
  });

  factory SkinCondition.fromJson(Map<String, dynamic> json) {
    return SkinCondition(
      code: json['code'] as String,
      labelFr: json['label_fr'] as String? ?? json['code'] as String,
      score: (json['score'] as num?)?.toInt() ?? 0,
      severity: json['severity'] as String? ?? 'mild',
      zones: (json['zones'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class ProductRecommendation {
  final int productId;
  final String name;
  final String? brand;
  final double? price;
  final String? imageUrl;
  final String reasonFr;
  final List<String> matchedConditions;

  const ProductRecommendation({
    required this.productId,
    required this.name,
    this.brand,
    this.price,
    this.imageUrl,
    required this.reasonFr,
    this.matchedConditions = const [],
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      productId: (json['product_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      reasonFr: json['reason_fr'] as String? ?? '',
      matchedConditions:
          (json['matched_conditions'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class SkinAnalysisResult {
  final int analysisId;
  final String skinType; // oily | dry | combination | normal
  final List<SkinCondition> conditions;
  final List<ProductRecommendation> recommendations;
  final String disclaimerFr;

  const SkinAnalysisResult({
    required this.analysisId,
    required this.skinType,
    required this.conditions,
    required this.recommendations,
    required this.disclaimerFr,
  });

  factory SkinAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SkinAnalysisResult(
      analysisId: (json['analysis_id'] as num).toInt(),
      skinType: json['skin_type'] as String? ?? 'normal',
      conditions: (json['conditions'] as List? ?? const [])
          .map((c) => SkinCondition.fromJson(c as Map<String, dynamic>))
          .toList(),
      recommendations: (json['recommendations'] as List? ?? const [])
          .map((r) => ProductRecommendation.fromJson(r as Map<String, dynamic>))
          .toList(),
      disclaimerFr: json['disclaimer_fr'] as String? ?? '',
    );
  }
}

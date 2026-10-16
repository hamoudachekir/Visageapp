// Modèles du diagnostic de peau renvoyé par `POST /v1/skin/analyze`.

/// Bloc âge — `estimatedAge` est une estimation IA, jamais exacte.
class AgeInfo {
  final int estimatedAge;
  final int? realAge;
  final int? skinAgeDelta;
  final String messageFr;

  const AgeInfo({
    required this.estimatedAge,
    this.realAge,
    this.skinAgeDelta,
    required this.messageFr,
  });

  factory AgeInfo.fromJson(Map<String, dynamic> json) {
    return AgeInfo(
      estimatedAge: (json['estimated_age'] as num).toInt(),
      realAge: (json['real_age'] as num?)?.toInt(),
      skinAgeDelta: (json['skin_age_delta'] as num?)?.toInt(),
      messageFr: json['message_fr'] as String? ?? '',
    );
  }
}

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
  final double? oldPrice;
  final double? rating;
  final String? imageUrl;
  final String reasonFr;
  final List<String> matchedConditions;
  final String? description;
  final String? sub;
  final String? ean;
  final String? sourceUrl;

  const ProductRecommendation({
    required this.productId,
    required this.name,
    this.brand,
    this.price,
    this.oldPrice,
    this.rating,
    this.imageUrl,
    required this.reasonFr,
    this.matchedConditions = const [],
    this.description,
    this.sub,
    this.ean,
    this.sourceUrl,
  });

  factory ProductRecommendation.fromJson(Map<String, dynamic> json) {
    return ProductRecommendation(
      productId: (json['product_id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      oldPrice: (json['old_price'] as num?)?.toDouble(),
      rating: (json['rating'] as num?)?.toDouble(),
      imageUrl: json['image_url'] as String?,
      reasonFr: json['reason_fr'] as String? ?? '',
      matchedConditions:
          (json['matched_conditions'] as List?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      sub: json['sub'] as String?,
      ean: json['ean'] as String?,
      sourceUrl: json['source_url'] as String?,
    );
  }
}

class SkinAnalysisResult {
  final int analysisId;
  final String skinType; // oily | dry | combination | normal
  final List<SkinCondition> conditions;
  final List<ProductRecommendation> recommendations;
  final String disclaimerFr;
  final AgeInfo? age;

  const SkinAnalysisResult({
    required this.analysisId,
    required this.skinType,
    required this.conditions,
    required this.recommendations,
    required this.disclaimerFr,
    this.age,
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
      age: json['age'] == null
          ? null
          : AgeInfo.fromJson(json['age'] as Map<String, dynamic>),
    );
  }
}

/// Profil d'une pharmacie (renvoyé par /v1/auth/me, PATCH /v1/pharmacy, etc.).
class PharmacyProfile {
  final int id;
  final String nom;
  final String email;
  final String? telephone;
  final String? adresse;
  final String? ville;
  final String? description;
  final bool hasLogo;
  final String? updatedAt;

  const PharmacyProfile({
    required this.id,
    required this.nom,
    required this.email,
    this.telephone,
    this.adresse,
    this.ville,
    this.description,
    this.hasLogo = false,
    this.updatedAt,
  });

  factory PharmacyProfile.fromJson(Map<String, dynamic> json) {
    return PharmacyProfile(
      id: (json['id'] as num).toInt(),
      nom: json['nom'] as String? ?? 'Pharmacie',
      email: json['email'] as String? ?? '',
      telephone: json['telephone'] as String?,
      adresse: json['adresse'] as String?,
      ville: json['ville'] as String?,
      description: json['description'] as String?,
      hasLogo: json['has_logo'] as bool? ?? false,
      updatedAt: json['updated_at'] as String?,
    );
  }

  /// Jeton de cache pour l'URL du logo (change à chaque mise à jour).
  String get logoCacheKey => updatedAt ?? '0';
}

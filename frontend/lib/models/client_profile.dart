class ClientProfile {
  /// Identifiant en base. Null tant que le client n'a pas été persisté.
  final int? id;
  final String prenom;
  final String nom;
  final String telephone;
  final String? email;
  final String peauSensible;

  /// Date de naissance (optionnelle) — sert au calcul de l'« âge de la peau ».
  final DateTime? birthDate;

  const ClientProfile({
    this.id,
    required this.prenom,
    required this.nom,
    required this.telephone,
    this.email,
    required this.peauSensible,
    this.birthDate,
  });

  String get nomComplet => '$prenom $nom';

  bool get isPersisted => id != null;

  ClientProfile copyWith({int? id}) => ClientProfile(
        id: id ?? this.id,
        prenom: prenom,
        nom: nom,
        telephone: telephone,
        email: email,
        peauSensible: peauSensible,
        birthDate: birthDate,
      );

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: (json['id'] as num?)?.toInt(),
        prenom: json['prenom'] as String,
        nom: json['nom'] as String,
        telephone: json['telephone'] as String,
        email: json['email'] as String?,
        peauSensible: (json['peau_sensible'] as String?) ?? 'non',
        birthDate: json['birth_date'] == null
            ? null
            : DateTime.parse(json['birth_date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'prenom': prenom,
        'nom': nom,
        'telephone': telephone,
        'email': email,
        'peau_sensible': peauSensible,
        'birth_date': birthDate == null
            ? null
            : '${birthDate!.year.toString().padLeft(4, '0')}-'
                '${birthDate!.month.toString().padLeft(2, '0')}-'
                '${birthDate!.day.toString().padLeft(2, '0')}',
      };
}

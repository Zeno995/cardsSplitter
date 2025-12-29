class Movement {
  final String id;
  final String fromPlayerId;
  final String toPlayerId;
  final double amount;
  final String? description;
  final DateTime createdAt;
  final String createdBy;
  final String? handId; // ID della mano a cui appartiene questo movimento (per annullamento)

  Movement({
    required this.id,
    required this.fromPlayerId,
    required this.toPlayerId,
    required this.amount,
    this.description,
    required this.createdAt,
    required this.createdBy,
    this.handId,
  });

  factory Movement.fromMap(Map<String, dynamic> map) {
    return Movement(
      id: map['id'] as String,
      fromPlayerId: map['fromPlayerId'] as String,
      toPlayerId: map['toPlayerId'] as String,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      createdBy: map['createdBy'] as String,
      handId: map['handId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromPlayerId': fromPlayerId,
      'toPlayerId': toPlayerId,
      'amount': amount,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'handId': handId,
    };
  }

  Movement copyWith({
    String? id,
    String? fromPlayerId,
    String? toPlayerId,
    double? amount,
    String? description,
    DateTime? createdAt,
    String? createdBy,
    String? handId,
  }) {
    return Movement(
      id: id ?? this.id,
      fromPlayerId: fromPlayerId ?? this.fromPlayerId,
      toPlayerId: toPlayerId ?? this.toPlayerId,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      handId: handId ?? this.handId,
    );
  }
}



class Movement {
  final String id;
  final String fromPlayerId;
  final String toPlayerId;
  final double amount;
  final String? description;
  final DateTime createdAt;
  final String createdBy;

  Movement({
    required this.id,
    required this.fromPlayerId,
    required this.toPlayerId,
    required this.amount,
    this.description,
    required this.createdAt,
    required this.createdBy,
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
    };
  }
}



class Player {
  final String id;
  final String name;
  final String? userId; // null se ospite
  final bool isAdmin;
  final DateTime joinedAt;
  final String? joinCode; // Codice specifico per invitare qualcuno direttamente come questo giocatore

  Player({
    required this.id,
    required this.name,
    this.userId,
    this.isAdmin = false,
    required this.joinedAt,
    this.joinCode,
  });

  factory Player.fromMap(Map<String, dynamic> map) {
    return Player(
      id: map['id'] as String,
      name: map['name'] as String,
      userId: map['userId'] as String?,
      isAdmin: map['isAdmin'] as bool? ?? false,
      joinedAt: DateTime.parse(map['joinedAt'] as String),
      joinCode: map['joinCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'userId': userId,
      'isAdmin': isAdmin,
      'joinedAt': joinedAt.toIso8601String(),
      'joinCode': joinCode,
    };
  }

  Player copyWith({
    String? id,
    String? name,
    String? userId,
    bool? isAdmin,
    DateTime? joinedAt,
    String? joinCode,
    bool clearJoinCode = false,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      isAdmin: isAdmin ?? this.isAdmin,
      joinedAt: joinedAt ?? this.joinedAt,
      joinCode: clearJoinCode ? null : (joinCode ?? this.joinCode),
    );
  }

  // Controlla se il giocatore è collegato a un account utente
  bool get isLinkedToUser => userId != null;

  // Controlla se il giocatore ha un codice di invito attivo
  bool get hasActiveJoinCode => joinCode != null;
}

import 'player.dart';
import 'movement.dart';

class GameSession {
  final String id;
  final String name;
  final String adminId;
  final String shareCode;
  final List<Player> players;
  final List<Movement> movements;
  final DateTime createdAt;
  final bool isActive;

  GameSession({
    required this.id,
    required this.name,
    required this.adminId,
    required this.shareCode,
    this.players = const [],
    this.movements = const [],
    required this.createdAt,
    this.isActive = true,
  });

  factory GameSession.fromMap(Map<String, dynamic> map) {
    return GameSession(
      id: map['id'] as String,
      name: map['name'] as String,
      adminId: map['adminId'] as String,
      shareCode: map['shareCode'] as String,
      players: (map['players'] as List<dynamic>?)
              ?.map((p) => Player.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      movements: (map['movements'] as List<dynamic>?)
              ?.map((m) => Movement.fromMap(m as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(map['createdAt'] as String),
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'adminId': adminId,
      'shareCode': shareCode,
      'players': players.map((p) => p.toMap()).toList(),
      'movements': movements.map((m) => m.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  GameSession copyWith({
    String? id,
    String? name,
    String? adminId,
    String? shareCode,
    List<Player>? players,
    List<Movement>? movements,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return GameSession(
      id: id ?? this.id,
      name: name ?? this.name,
      adminId: adminId ?? this.adminId,
      shareCode: shareCode ?? this.shareCode,
      players: players ?? this.players,
      movements: movements ?? this.movements,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  // Calcola il bilancio di ogni giocatore
  Map<String, double> calculateBalances() {
    final balances = <String, double>{};
    
    for (final player in players) {
      balances[player.id] = 0;
    }
    
    for (final movement in movements) {
      balances[movement.fromPlayerId] = 
          (balances[movement.fromPlayerId] ?? 0) - movement.amount;
      balances[movement.toPlayerId] = 
          (balances[movement.toPlayerId] ?? 0) + movement.amount;
    }
    
    return balances;
  }

  // Trova il nome del giocatore dato l'ID
  String? getPlayerName(String playerId) {
    try {
      return players.firstWhere((p) => p.id == playerId).name;
    } catch (_) {
      return null;
    }
  }
}



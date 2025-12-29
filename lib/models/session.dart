import 'player.dart';
import 'movement.dart';
import 'game_hand.dart';

class GameSession {
  final String id;
  final String name;
  final String adminId;
  final String shareCode;
  final List<Player> players;
  final List<Movement> movements;
  final DateTime createdAt;
  final bool isActive;
  final ActiveHand? activeHand;
  final List<String> participantUserIds; // userId dei partecipanti (non admin) per query efficienti

  GameSession({
    required this.id,
    required this.name,
    required this.adminId,
    required this.shareCode,
    this.players = const [],
    this.movements = const [],
    required this.createdAt,
    this.isActive = true,
    this.activeHand,
    this.participantUserIds = const [],
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
      activeHand: map['activeHand'] != null
          ? ActiveHand.fromMap(map['activeHand'] as Map<String, dynamic>)
          : null,
      participantUserIds: (map['participantUserIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
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
      'activeHand': activeHand?.toMap(),
      'participantUserIds': participantUserIds,
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
    ActiveHand? activeHand,
    bool clearActiveHand = false,
    List<String>? participantUserIds,
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
      activeHand: clearActiveHand ? null : (activeHand ?? this.activeHand),
      participantUserIds: participantUserIds ?? this.participantUserIds,
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



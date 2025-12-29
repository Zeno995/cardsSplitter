import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../models/movement.dart';
import '../models/game_mode.dart';
import '../models/game_hand.dart';

class DatabaseService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _sessionsCollection =>
      _db.collection('sessions');

  // Genera un codice di condivisione univoco
  String _generateShareCode() {
    return _uuid.v4().substring(0, 8).toUpperCase();
  }

  // Crea una nuova sessione
  Future<GameSession> createSession({
    required String name,
    required String adminId,
    required String adminName,
    GameMode gameMode = const GameMode(type: GameType.libera),
  }) async {
    final sessionId = _uuid.v4();
    final shareCode = _generateShareCode();
    
    final adminPlayer = Player(
      id: _uuid.v4(),
      name: adminName,
      userId: adminId,
      isAdmin: true,
      joinedAt: DateTime.now(),
    );

    final session = GameSession(
      id: sessionId,
      name: name,
      adminId: adminId,
      shareCode: shareCode,
      players: [adminPlayer],
      movements: [],
      createdAt: DateTime.now(),
      isActive: true,
      gameMode: gameMode,
    );

    await _sessionsCollection.doc(sessionId).set(session.toMap());
    return session;
  }

  // Ottieni sessione per ID
  Future<GameSession?> getSession(String sessionId) async {
    final doc = await _sessionsCollection.doc(sessionId).get();
    if (!doc.exists) return null;
    return GameSession.fromMap(doc.data()!);
  }

  // Ottieni sessione per codice di condivisione
  Future<GameSession?> getSessionByShareCode(String shareCode) async {
    final query = await _sessionsCollection
        .where('shareCode', isEqualTo: shareCode.toUpperCase())
        .limit(1)
        .get();
    
    if (query.docs.isEmpty) return null;
    return GameSession.fromMap(query.docs.first.data());
  }

  // Stream di una sessione (real-time)
  Stream<GameSession?> streamSession(String sessionId) {
    return _sessionsCollection.doc(sessionId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return GameSession.fromMap(doc.data()!);
    });
  }

  // Ottieni tutte le sessioni di un utente
  Stream<List<GameSession>> streamUserSessions(String userId) {
    return _sessionsCollection
        .where('adminId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final sessions = snapshot.docs
              .map((doc) => GameSession.fromMap(doc.data()))
              .toList();
          // Ordina lato client per evitare di richiedere un indice composito
          sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return sessions;
        });
  }

  // Unisciti a una sessione come giocatore
  Future<Player> joinSession({
    required String sessionId,
    required String playerName,
    String? userId,
  }) async {
    final player = Player(
      id: _uuid.v4(),
      name: playerName,
      userId: userId,
      isAdmin: false,
      joinedAt: DateTime.now(),
    );

    await _sessionsCollection.doc(sessionId).update({
      'players': FieldValue.arrayUnion([player.toMap()]),
    });

    return player;
  }

  // Aggiungi un movimento
  Future<Movement> addMovement({
    required String sessionId,
    required String fromPlayerId,
    required String toPlayerId,
    required double amount,
    String? description,
    required String createdBy,
    String? handId,
  }) async {
    final movement = Movement(
      id: _uuid.v4(),
      fromPlayerId: fromPlayerId,
      toPlayerId: toPlayerId,
      amount: amount,
      description: description,
      createdAt: DateTime.now(),
      createdBy: createdBy,
      handId: handId,
    );

    await _sessionsCollection.doc(sessionId).update({
      'movements': FieldValue.arrayUnion([movement.toMap()]),
    });

    return movement;
  }

  // Rimuovi un movimento (solo admin)
  // Se il movimento coinvolge il piatto e c'è una mano attiva, aggiorna il piatto
  Future<void> removeMovement({
    required String sessionId,
    required Movement movement,
  }) async {
    // Prima rimuovi il movimento
    await _sessionsCollection.doc(sessionId).update({
      'movements': FieldValue.arrayRemove([movement.toMap()]),
    });

    // Se il movimento coinvolge il piatto, aggiorna la mano attiva
    final session = await getSession(sessionId);
    if (session?.activeHand != null) {
      final hand = session!.activeHand!;
      double potAdjustment = 0;

      // Se qualcuno aveva pagato al piatto, restituisci
      if (movement.toPlayerId == '_piatto_') {
        potAdjustment = -movement.amount;
      }
      // Se qualcuno aveva ricevuto dal piatto, aggiungi
      else if (movement.fromPlayerId == '_piatto_') {
        potAdjustment = movement.amount;
      }

      if (potAdjustment != 0) {
        final newPot = (hand.dealerPot + potAdjustment).clamp(0.0, double.infinity).toDouble();
        final newHand = hand.copyWith(dealerPot: newPot);
        await updateActiveHand(sessionId: sessionId, hand: newHand);
      }
    }
  }

  // Annulla tutti i movimenti di una mano specifica (solo admin)
  Future<void> cancelHandMovements({
    required String sessionId,
    required String handId,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) return;

    // Trova tutti i movimenti associati a questa mano
    final movementsToRemove = session.movements
        .where((m) => m.handId == handId)
        .toList();

    if (movementsToRemove.isEmpty) return;

    // Rimuovi tutti i movimenti della mano
    for (final movement in movementsToRemove) {
      await _sessionsCollection.doc(sessionId).update({
        'movements': FieldValue.arrayRemove([movement.toMap()]),
      });
    }
  }

  // Aggiorna la sessione
  Future<void> updateSession(GameSession session) async {
    await _sessionsCollection.doc(session.id).set(session.toMap());
  }

  // Elimina una sessione (solo admin)
  Future<void> deleteSession(String sessionId) async {
    await _sessionsCollection.doc(sessionId).delete();
  }

  // Chiudi una sessione
  Future<void> closeSession(String sessionId) async {
    await _sessionsCollection.doc(sessionId).update({
      'isActive': false,
    });
  }

  // Rimuovi un giocatore dalla sessione (rimuove anche tutti i movimenti associati)
  Future<void> removePlayer({
    required String sessionId,
    required Player player,
    required bool deleteMovements,
  }) async {
    if (deleteMovements) {
      // Recupera la sessione per ottenere i movimenti
      final session = await getSession(sessionId);
      if (session != null) {
        // Filtra i movimenti rimuovendo quelli che coinvolgono il giocatore
        final updatedMovements = session.movements
            .where((m) => m.fromPlayerId != player.id && m.toPlayerId != player.id)
            .toList();

        // Aggiorna la sessione rimuovendo il giocatore e i suoi movimenti
        final updatedPlayers = session.players.where((p) => p.id != player.id).toList();

        await _sessionsCollection.doc(sessionId).update({
          'players': updatedPlayers.map((p) => p.toMap()).toList(),
          'movements': updatedMovements.map((m) => m.toMap()).toList(),
        });
      }
    } else {
      await _sessionsCollection.doc(sessionId).update({
        'players': FieldValue.arrayRemove([player.toMap()]),
      });
    }
  }

  // Genera un codice di invito per un giocatore esistente
  Future<String> generatePlayerJoinCode({
    required String sessionId,
    required Player player,
  }) async {
    final joinCode = 'P${_uuid.v4().substring(0, 6).toUpperCase()}';
    
    // Recupera la sessione
    final session = await getSession(sessionId);
    if (session == null) {
      throw Exception('Sessione non trovata');
    }

    // Aggiorna il giocatore con il nuovo codice
    final updatedPlayers = session.players.map((p) {
      if (p.id == player.id) {
        return p.copyWith(joinCode: joinCode);
      }
      return p;
    }).toList();

    await _sessionsCollection.doc(sessionId).update({
      'players': updatedPlayers.map((p) => p.toMap()).toList(),
    });

    return joinCode;
  }

  // Rimuovi il codice di invito di un giocatore
  Future<void> removePlayerJoinCode({
    required String sessionId,
    required Player player,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) {
      throw Exception('Sessione non trovata');
    }

    final updatedPlayers = session.players.map((p) {
      if (p.id == player.id) {
        return p.copyWith(clearJoinCode: true);
      }
      return p;
    }).toList();

    await _sessionsCollection.doc(sessionId).update({
      'players': updatedPlayers.map((p) => p.toMap()).toList(),
    });
  }

  // Cerca una sessione tramite codice di invito specifico per giocatore
  Future<({GameSession session, Player player})?> getSessionByPlayerJoinCode(String joinCode) async {
    // Cerca nelle sessioni un giocatore con questo joinCode
    final query = await _sessionsCollection.get();
    
    for (final doc in query.docs) {
      final session = GameSession.fromMap(doc.data());
      for (final player in session.players) {
        if (player.joinCode == joinCode.toUpperCase()) {
          return (session: session, player: player);
        }
      }
    }
    return null;
  }

  // Collega un utente a un giocatore esistente tramite codice di invito
  Future<void> linkUserToPlayer({
    required String sessionId,
    required Player player,
    required String userId,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) {
      throw Exception('Sessione non trovata');
    }

    final updatedPlayers = session.players.map((p) {
      if (p.id == player.id) {
        return p.copyWith(userId: userId, clearJoinCode: true);
      }
      return p;
    }).toList();

    await _sessionsCollection.doc(sessionId).update({
      'players': updatedPlayers.map((p) => p.toMap()).toList(),
    });
  }

  // ===== GESTIONE MANO ATTIVA =====

  /// Avvia una nuova mano
  Future<void> startActiveHand({
    required String sessionId,
    required ActiveHand hand,
  }) async {
    await _sessionsCollection.doc(sessionId).update({
      'activeHand': hand.toMap(),
    });
  }

  /// Aggiorna la mano attiva
  Future<void> updateActiveHand({
    required String sessionId,
    required ActiveHand hand,
  }) async {
    await _sessionsCollection.doc(sessionId).update({
      'activeHand': hand.toMap(),
    });
  }

  /// Termina la mano attiva
  Future<void> endActiveHand({
    required String sessionId,
  }) async {
    await _sessionsCollection.doc(sessionId).update({
      'activeHand': null,
    });
  }
}



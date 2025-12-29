import 'game_mode.dart';

/// Rappresenta una mano/round di gioco
class GameHand {
  final String id;
  final GameType gameType;
  final DateTime createdAt;
  final String createdBy;
  final HandStatus status;
  final List<HandBet> bets;
  final List<HandWinner> winners;
  final Map<String, dynamic> gameData;

  const GameHand({
    required this.id,
    required this.gameType,
    required this.createdAt,
    required this.createdBy,
    this.status = HandStatus.inProgress,
    this.bets = const [],
    this.winners = const [],
    this.gameData = const {},
  });

  factory GameHand.fromMap(Map<String, dynamic> map) {
    return GameHand(
      id: map['id'] as String,
      gameType: GameType.values.firstWhere(
        (e) => e.name == map['gameType'],
        orElse: () => GameType.libera,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      createdBy: map['createdBy'] as String,
      status: HandStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => HandStatus.inProgress,
      ),
      bets: (map['bets'] as List<dynamic>?)
              ?.map((b) => HandBet.fromMap(b as Map<String, dynamic>))
              .toList() ??
          [],
      winners: (map['winners'] as List<dynamic>?)
              ?.map((w) => HandWinner.fromMap(w as Map<String, dynamic>))
              .toList() ??
          [],
      gameData: Map<String, dynamic>.from(map['gameData'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gameType': gameType.name,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'status': status.name,
      'bets': bets.map((b) => b.toMap()).toList(),
      'winners': winners.map((w) => w.toMap()).toList(),
      'gameData': gameData,
    };
  }

  GameHand copyWith({
    String? id,
    GameType? gameType,
    DateTime? createdAt,
    String? createdBy,
    HandStatus? status,
    List<HandBet>? bets,
    List<HandWinner>? winners,
    Map<String, dynamic>? gameData,
  }) {
    return GameHand(
      id: id ?? this.id,
      gameType: gameType ?? this.gameType,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      bets: bets ?? this.bets,
      winners: winners ?? this.winners,
      gameData: gameData ?? this.gameData,
    );
  }

  /// Calcola il totale del piatto
  double get totalPot {
    return bets.fold(0.0, (sum, bet) => sum + bet.totalAmount);
  }

  /// Calcola quanto ha puntato ogni giocatore
  Map<String, double> get playerBets {
    final result = <String, double>{};
    for (final bet in bets) {
      for (final entry in bet.amounts.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    return result;
  }
}

/// Stato della mano
enum HandStatus {
  inProgress,
  completed,
  cancelled,
}

/// Rappresenta una fase di puntate in una mano
class HandBet {
  final String id;
  final String phase; // es: "ante", "carta1", "carta2", etc.
  final Map<String, double> amounts; // playerId -> amount
  final DateTime createdAt;

  const HandBet({
    required this.id,
    required this.phase,
    required this.amounts,
    required this.createdAt,
  });

  factory HandBet.fromMap(Map<String, dynamic> map) {
    return HandBet(
      id: map['id'] as String,
      phase: map['phase'] as String,
      amounts: Map<String, double>.from(
        (map['amounts'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phase': phase,
      'amounts': amounts,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  double get totalAmount => amounts.values.fold(0.0, (a, b) => a + b);
}

/// Rappresenta un vincitore (o più vincitori) di una mano
class HandWinner {
  final String id;
  final WinnerType type;
  final List<String> playerIds;
  final double amount;
  final String? reason;

  const HandWinner({
    required this.id,
    required this.type,
    required this.playerIds,
    required this.amount,
    this.reason,
  });

  factory HandWinner.fromMap(Map<String, dynamic> map) {
    return HandWinner(
      id: map['id'] as String,
      type: WinnerType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => WinnerType.normal,
      ),
      playerIds: List<String>.from(map['playerIds'] ?? []),
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'playerIds': playerIds,
      'amount': amount,
      'reason': reason,
    };
  }

  /// Quanto riceve ogni vincitore
  double get amountPerWinner => playerIds.isEmpty ? 0 : amount / playerIds.length;
}

/// Tipo di vincita
enum WinnerType {
  /// Vincita normale
  normal,
  
  /// Las Vegas - punteggio più alto
  lasVegasHigh,
  
  /// Las Vegas - punteggio più basso
  lasVegasLow,
  
  /// Las Vegas - vittoria totale (ha scartato tutte le carte)
  lasVegasFull,
  
  /// Sette e mezzo - vincitore contro il mazziere
  setteEMezzoWin,
  
  /// Sette e mezzo - sette e mezzo reale
  setteEMezzoReale,
  
  /// Sette e mezzo - mazziere sballa (paga tutti)
  setteEMezzoMazziereSballa,
  
  /// Cucù - perdente (paga)
  cucuLoser,
  
  /// Trentuno - vincitore
  trentunoWin,
  
  /// Trentuno - 31 esatto
  trentuno31,
  
  /// Bestia - vincitore prese
  bestiaWin,
  
  /// Bestia - andato in bestia (paga)
  bestiaPay,
}

/// Configurazione delle fasi di puntata per ogni gioco
class GameBetPhases {
  static List<BetPhaseConfig> getPhases(GameType type) {
    switch (type) {
      case GameType.libera:
        return [];
      
      case GameType.setteEMezzo:
        // Sette e Mezzo ha una gestione speciale senza fasi predefinite
        // Le puntate vengono gestite direttamente nella schermata di gioco
        return [];
      
      case GameType.cucu:
        return [
          const BetPhaseConfig(
            id: 'ante',
            name: 'Ante',
            description: 'Puntata iniziale di tutti i giocatori',
            isRequired: true,
          ),
        ];
      
      case GameType.trentuno:
        return [
          const BetPhaseConfig(
            id: 'ante',
            name: 'Ante',
            description: 'Puntata iniziale di tutti i giocatori',
            isRequired: true,
          ),
        ];
      
      case GameType.lasVegas:
        return [
          const BetPhaseConfig(
            id: 'ante',
            name: 'Puntata Iniziale',
            description: 'Puntata obbligatoria per formare il piatto',
            isRequired: true,
          ),
          const BetPhaseConfig(
            id: 'carta1',
            name: 'Dopo Carta 1',
            description: 'Puntate dopo la prima carta scoperta',
            isRequired: false,
          ),
          const BetPhaseConfig(
            id: 'carta2',
            name: 'Dopo Carta 2',
            description: 'Puntate dopo la seconda carta scoperta',
            isRequired: false,
          ),
          const BetPhaseConfig(
            id: 'carta3',
            name: 'Dopo Carta 3',
            description: 'Puntate dopo la terza carta scoperta',
            isRequired: false,
          ),
          const BetPhaseConfig(
            id: 'carta4',
            name: 'Dopo Carta 4',
            description: 'Puntate dopo l\'ultima carta scoperta',
            isRequired: false,
          ),
        ];
      
      case GameType.bestia:
        return [
          const BetPhaseConfig(
            id: 'piatto',
            name: 'Piatto',
            description: 'Contributo al piatto iniziale',
            isRequired: true,
          ),
        ];
    }
  }

  /// Ottiene i tipi di vincita possibili per un gioco
  static List<WinnerTypeConfig> getWinnerTypes(GameType type) {
    switch (type) {
      case GameType.libera:
        return [
          const WinnerTypeConfig(
            type: WinnerType.normal,
            name: 'Vincitore',
            description: 'Assegna il piatto al vincitore',
            allowMultiple: true,
          ),
        ];
      
      case GameType.setteEMezzo:
        return [
          const WinnerTypeConfig(
            type: WinnerType.setteEMezzoWin,
            name: 'Vincitore',
            description: 'Chi si avvicina di più a 7,5 senza sballare',
            allowMultiple: false,
          ),
          const WinnerTypeConfig(
            type: WinnerType.setteEMezzoReale,
            name: 'Sette e Mezzo Reale',
            description: '7,5 con sole 2 carte (7 + figura)',
            allowMultiple: false,
          ),
        ];
      
      case GameType.cucu:
        return [
          const WinnerTypeConfig(
            type: WinnerType.cucuLoser,
            name: 'Perdente',
            description: 'Chi ha la carta più bassa paga',
            allowMultiple: true,
          ),
        ];
      
      case GameType.trentuno:
        return [
          const WinnerTypeConfig(
            type: WinnerType.trentunoWin,
            name: 'Vincitore',
            description: 'Chi ha il punteggio più alto',
            allowMultiple: false,
          ),
          const WinnerTypeConfig(
            type: WinnerType.trentuno31,
            name: 'Trentuno!',
            description: 'Ha fatto esattamente 31 punti',
            allowMultiple: false,
          ),
        ];
      
      case GameType.lasVegas:
        return [
          const WinnerTypeConfig(
            type: WinnerType.lasVegasHigh,
            name: 'Punteggio Alto',
            description: 'Vince metà piatto con il punteggio più alto',
            allowMultiple: true,
          ),
          const WinnerTypeConfig(
            type: WinnerType.lasVegasLow,
            name: 'Punteggio Basso',
            description: 'Vince metà piatto con il punteggio più basso',
            allowMultiple: true,
          ),
          const WinnerTypeConfig(
            type: WinnerType.lasVegasFull,
            name: 'Las Vegas!',
            description: 'Ha scartato tutte le carte, vince tutto il piatto!',
            allowMultiple: true,
          ),
        ];
      
      case GameType.bestia:
        return [
          const WinnerTypeConfig(
            type: WinnerType.bestiaWin,
            name: 'Vincitore Prese',
            description: 'Chi ha vinto più prese prende il piatto',
            allowMultiple: false,
          ),
          const WinnerTypeConfig(
            type: WinnerType.bestiaPay,
            name: 'In Bestia',
            description: 'Chi non ha fatto prese deve pagare',
            allowMultiple: true,
          ),
        ];
    }
  }
}

/// Configurazione di una fase di puntata
class BetPhaseConfig {
  final String id;
  final String name;
  final String description;
  final bool isRequired;

  const BetPhaseConfig({
    required this.id,
    required this.name,
    required this.description,
    this.isRequired = false,
  });
}

/// Configurazione di un tipo di vincita
class WinnerTypeConfig {
  final WinnerType type;
  final String name;
  final String description;
  final bool allowMultiple;

  const WinnerTypeConfig({
    required this.type,
    required this.name,
    required this.description,
    this.allowMultiple = false,
  });
}

/// Stato di una mano attiva sincronizzata tra tutti i dispositivi
class ActiveHand {
  final String id;
  final GameType gameType;
  final String? variantId;
  final DateTime createdAt;
  final String createdBy;
  final int currentPhaseIndex;
  final List<String> playerOrder;
  final Map<String, String> playerStatus; // playerId -> status name
  final Map<String, double> currentPhaseBets;
  final int currentPlayerTurnIndex;
  final double currentBetToMatch;
  final List<HandBet> completedBets;
  
  // Campi specifici per Sette e Mezzo
  final String? dealerId; // ID del mazziere corrente
  final double dealerPot; // Piatto del mazziere (modalità 1v1)
  final String? pendingDealerRequest; // ID giocatore che vuole diventare mazziere
  final List<PendingPayment> pendingPayments; // Pagamenti in attesa di conferma
  final bool needsDealerPotSetup; // True se il mazziere deve impostare il piatto

  // Campi specifici per giochi con vite (31, Cucù)
  final Map<String, int> playerLives; // playerId -> numero di vite
  final double lifeValue; // Valore monetario di ogni vita
  final double lifePot; // Piatto accumulato dalle vite perse
  final bool needsLifeSetup; // True se l'admin deve configurare le vite
  final PendingLifeRequest? pendingLifeRequest; // Richiesta di vita pendente

  // Campi specifici per Bestia
  final double bestiaBaseValue; // Valore base della quota (impostato dall'admin)
  final double bestiaPot; // Piatto totale della bestia
  final bool needsBestiaSetup; // True se l'admin deve impostare la quota base
  final bool needsBestiaPlayerOrder; // True se l'admin deve impostare l'ordine dei giocatori
  final String? bestiaDealerId; // ID del mazziere corrente
  final int bestiaDealerIndex; // Indice del mazziere corrente nell'ordine dei giocatori
  final Map<String, String> bestiaPlayerChoice; // playerId -> scelta ('out', 'pay', 'take1', 'take2', 'take3')
  final bool bestiaChoicePhase; // True se siamo nella fase delle scelte (post-round)
  final bool bestiaNeedsDealerBet; // True se il mazziere deve ancora mettere la quota

  const ActiveHand({
    required this.id,
    required this.gameType,
    this.variantId,
    required this.createdAt,
    required this.createdBy,
    this.currentPhaseIndex = 0,
    this.playerOrder = const [],
    this.playerStatus = const {},
    this.currentPhaseBets = const {},
    this.currentPlayerTurnIndex = 0,
    this.currentBetToMatch = 0,
    this.completedBets = const [],
    this.dealerId,
    this.dealerPot = 0,
    this.pendingDealerRequest,
    this.pendingPayments = const [],
    this.needsDealerPotSetup = false,
    this.playerLives = const {},
    this.lifeValue = 0,
    this.lifePot = 0,
    this.needsLifeSetup = false,
    this.pendingLifeRequest,
    this.bestiaBaseValue = 0,
    this.bestiaPot = 0,
    this.needsBestiaSetup = false,
    this.needsBestiaPlayerOrder = false,
    this.bestiaDealerId,
    this.bestiaDealerIndex = 0,
    this.bestiaPlayerChoice = const {},
    this.bestiaChoicePhase = false,
    this.bestiaNeedsDealerBet = false,
  });

  factory ActiveHand.fromMap(Map<String, dynamic> map) {
    return ActiveHand(
      id: map['id'] as String,
      gameType: GameType.values.firstWhere(
        (e) => e.name == map['gameType'],
        orElse: () => GameType.libera,
      ),
      variantId: map['variantId'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      createdBy: map['createdBy'] as String,
      currentPhaseIndex: map['currentPhaseIndex'] as int? ?? 0,
      playerOrder: List<String>.from(map['playerOrder'] ?? []),
      playerStatus: Map<String, String>.from(map['playerStatus'] ?? {}),
      currentPhaseBets: Map<String, double>.from(
        (map['currentPhaseBets'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      currentPlayerTurnIndex: map['currentPlayerTurnIndex'] as int? ?? 0,
      currentBetToMatch: (map['currentBetToMatch'] as num?)?.toDouble() ?? 0,
      completedBets: (map['completedBets'] as List<dynamic>?)
              ?.map((b) => HandBet.fromMap(b as Map<String, dynamic>))
              .toList() ??
          [],
      dealerId: map['dealerId'] as String?,
      dealerPot: (map['dealerPot'] as num?)?.toDouble() ?? 0,
      pendingDealerRequest: map['pendingDealerRequest'] as String?,
      pendingPayments: (map['pendingPayments'] as List<dynamic>?)
              ?.map((p) => PendingPayment.fromMap(p as Map<String, dynamic>))
              .toList() ??
          [],
      needsDealerPotSetup: map['needsDealerPotSetup'] as bool? ?? false,
      playerLives: Map<String, int>.from(
        (map['playerLives'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        ),
      ),
      lifeValue: (map['lifeValue'] as num?)?.toDouble() ?? 0,
      lifePot: (map['lifePot'] as num?)?.toDouble() ?? 0,
      needsLifeSetup: map['needsLifeSetup'] as bool? ?? false,
      pendingLifeRequest: map['pendingLifeRequest'] != null
          ? PendingLifeRequest.fromMap(map['pendingLifeRequest'] as Map<String, dynamic>)
          : null,
      bestiaBaseValue: (map['bestiaBaseValue'] as num?)?.toDouble() ?? 0,
      bestiaPot: (map['bestiaPot'] as num?)?.toDouble() ?? 0,
      needsBestiaSetup: map['needsBestiaSetup'] as bool? ?? false,
      needsBestiaPlayerOrder: map['needsBestiaPlayerOrder'] as bool? ?? false,
      bestiaDealerId: map['bestiaDealerId'] as String?,
      bestiaDealerIndex: map['bestiaDealerIndex'] as int? ?? 0,
      bestiaPlayerChoice: Map<String, String>.from(map['bestiaPlayerChoice'] ?? {}),
      bestiaChoicePhase: map['bestiaChoicePhase'] as bool? ?? false,
      bestiaNeedsDealerBet: map['bestiaNeedsDealerBet'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'gameType': gameType.name,
      'variantId': variantId,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'currentPhaseIndex': currentPhaseIndex,
      'playerOrder': playerOrder,
      'playerStatus': playerStatus,
      'currentPhaseBets': currentPhaseBets,
      'currentPlayerTurnIndex': currentPlayerTurnIndex,
      'currentBetToMatch': currentBetToMatch,
      'completedBets': completedBets.map((b) => b.toMap()).toList(),
      'dealerId': dealerId,
      'dealerPot': dealerPot,
      'pendingDealerRequest': pendingDealerRequest,
      'pendingPayments': pendingPayments.map((p) => p.toMap()).toList(),
      'needsDealerPotSetup': needsDealerPotSetup,
      'playerLives': playerLives,
      'lifeValue': lifeValue,
      'lifePot': lifePot,
      'needsLifeSetup': needsLifeSetup,
      'pendingLifeRequest': pendingLifeRequest?.toMap(),
      'bestiaBaseValue': bestiaBaseValue,
      'bestiaPot': bestiaPot,
      'needsBestiaSetup': needsBestiaSetup,
      'needsBestiaPlayerOrder': needsBestiaPlayerOrder,
      'bestiaDealerId': bestiaDealerId,
      'bestiaDealerIndex': bestiaDealerIndex,
      'bestiaPlayerChoice': bestiaPlayerChoice,
      'bestiaChoicePhase': bestiaChoicePhase,
      'bestiaNeedsDealerBet': bestiaNeedsDealerBet,
    };
  }

  ActiveHand copyWith({
    String? id,
    GameType? gameType,
    String? variantId,
    DateTime? createdAt,
    String? createdBy,
    int? currentPhaseIndex,
    List<String>? playerOrder,
    Map<String, String>? playerStatus,
    Map<String, double>? currentPhaseBets,
    int? currentPlayerTurnIndex,
    double? currentBetToMatch,
    List<HandBet>? completedBets,
    String? dealerId,
    double? dealerPot,
    String? pendingDealerRequest,
    List<PendingPayment>? pendingPayments,
    bool? needsDealerPotSetup,
    bool clearPendingDealerRequest = false,
    Map<String, int>? playerLives,
    double? lifeValue,
    double? lifePot,
    bool? needsLifeSetup,
    PendingLifeRequest? pendingLifeRequest,
    bool clearPendingLifeRequest = false,
    double? bestiaBaseValue,
    double? bestiaPot,
    bool? needsBestiaSetup,
    bool? needsBestiaPlayerOrder,
    String? bestiaDealerId,
    int? bestiaDealerIndex,
    Map<String, String>? bestiaPlayerChoice,
    bool? bestiaChoicePhase,
    bool? bestiaNeedsDealerBet,
  }) {
    return ActiveHand(
      id: id ?? this.id,
      gameType: gameType ?? this.gameType,
      variantId: variantId ?? this.variantId,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      currentPhaseIndex: currentPhaseIndex ?? this.currentPhaseIndex,
      playerOrder: playerOrder ?? this.playerOrder,
      playerStatus: playerStatus ?? this.playerStatus,
      currentPhaseBets: currentPhaseBets ?? this.currentPhaseBets,
      currentPlayerTurnIndex: currentPlayerTurnIndex ?? this.currentPlayerTurnIndex,
      currentBetToMatch: currentBetToMatch ?? this.currentBetToMatch,
      completedBets: completedBets ?? this.completedBets,
      dealerId: dealerId ?? this.dealerId,
      dealerPot: dealerPot ?? this.dealerPot,
      pendingDealerRequest: clearPendingDealerRequest ? null : (pendingDealerRequest ?? this.pendingDealerRequest),
      pendingPayments: pendingPayments ?? this.pendingPayments,
      needsDealerPotSetup: needsDealerPotSetup ?? this.needsDealerPotSetup,
      playerLives: playerLives ?? this.playerLives,
      lifeValue: lifeValue ?? this.lifeValue,
      lifePot: lifePot ?? this.lifePot,
      needsLifeSetup: needsLifeSetup ?? this.needsLifeSetup,
      pendingLifeRequest: clearPendingLifeRequest ? null : (pendingLifeRequest ?? this.pendingLifeRequest),
      bestiaBaseValue: bestiaBaseValue ?? this.bestiaBaseValue,
      bestiaPot: bestiaPot ?? this.bestiaPot,
      needsBestiaSetup: needsBestiaSetup ?? this.needsBestiaSetup,
      needsBestiaPlayerOrder: needsBestiaPlayerOrder ?? this.needsBestiaPlayerOrder,
      bestiaDealerId: bestiaDealerId ?? this.bestiaDealerId,
      bestiaDealerIndex: bestiaDealerIndex ?? this.bestiaDealerIndex,
      bestiaPlayerChoice: bestiaPlayerChoice ?? this.bestiaPlayerChoice,
      bestiaChoicePhase: bestiaChoicePhase ?? this.bestiaChoicePhase,
      bestiaNeedsDealerBet: bestiaNeedsDealerBet ?? this.bestiaNeedsDealerBet,
    );
  }

  /// Calcola il totale del piatto (completato + fase corrente)
  double get totalPot {
    final completedTotal = completedBets.fold(0.0, (sum, bet) => sum + bet.totalAmount);
    final currentTotal = currentPhaseBets.values.fold(0.0, (a, b) => a + b);
    return completedTotal + currentTotal;
  }

  /// Calcola quanto ha puntato ogni giocatore in totale
  Map<String, double> get totalPlayerBets {
    final result = <String, double>{};
    for (final bet in completedBets) {
      for (final entry in bet.amounts.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + entry.value;
      }
    }
    for (final entry in currentPhaseBets.entries) {
      result[entry.key] = (result[entry.key] ?? 0) + entry.value;
    }
    return result;
  }

  /// Ottiene l'ID del giocatore corrente
  String? get currentTurnPlayerId {
    final activeIds = playerOrder.where((id) => 
      playerStatus[id] != 'folded'
    ).toList();
    if (currentPlayerTurnIndex >= activeIds.length) return null;
    return activeIds[currentPlayerTurnIndex];
  }

  /// Lista dei giocatori attivi (non foldati)
  List<String> get activePlayerIds => playerOrder.where((id) => 
    playerStatus[id] != 'folded'
  ).toList();

  /// Verifica se è modalità Sette e Mezzo 1v1
  bool get isSetteEMezzoOneVsOne => 
    gameType == GameType.setteEMezzo && 
    variantId == SetteEMezzoVariant.unoVsUnoConPiatto.name;

  /// Verifica se è modalità Sette e Mezzo Mazziere vs Tutti
  bool get isSetteEMezzoVsTutti => 
    gameType == GameType.setteEMezzo && 
    variantId == SetteEMezzoVariant.mazziereVsTutti.name;

  /// Verifica se è un gioco con vite (31 o Cucù)
  bool get isLifeBasedGame => 
    gameType == GameType.trentuno || gameType == GameType.cucu;

  /// Giocatori ancora in gioco (con almeno 1 vita)
  List<String> get playersWithLives => 
    playerLives.entries.where((e) => e.value > 0).map((e) => e.key).toList();

  /// Controlla se siamo nella situazione "pari" (ultimi 2 con 1 vita)
  bool get canReenterAll {
    final alive = playersWithLives;
    if (alive.length != 2) return false;
    return alive.every((id) => playerLives[id] == 1);
  }

  /// Controlla se il gioco è terminato (1 solo giocatore con vite)
  bool get isGameOver {
    final alive = playersWithLives;
    return alive.length == 1;
  }

  /// Ottiene il vincitore (se il gioco è terminato)
  String? get winnerId => isGameOver ? playersWithLives.first : null;

  /// Verifica se è un gioco Bestia
  bool get isBestia => gameType == GameType.bestia;

  /// Verifica se il mazziere ha già messo la quota in Bestia
  bool get bestiaDealerHasBet => bestiaDealerId != null && !bestiaNeedsDealerBet;

  /// Ottiene l'ID del prossimo mazziere in Bestia
  String? getNextBestiaDealer(int currentIndex) {
    if (playerOrder.isEmpty) return null;
    final nextIndex = (currentIndex + 1) % playerOrder.length;
    return playerOrder[nextIndex];
  }

  /// Controlla se tutti i giocatori hanno fatto la loro scelta in Bestia
  bool get allPlayersHaveChosen => 
    bestiaPlayerChoice.length == playerOrder.length;

  /// Giocatori ancora "in gioco" in Bestia (non hanno scelto 'out')
  List<String> get bestiaActivePlayers => 
    playerOrder.where((id) => bestiaPlayerChoice[id] != 'out').toList();

  /// Giocatori che devono pagare la bestia
  List<String> get bestiaPayingPlayers =>
    bestiaPlayerChoice.entries
        .where((e) => e.value == 'pay')
        .map((e) => e.key)
        .toList();

  /// Mappa delle quote prese da ogni giocatore (1, 2 o 3)
  Map<String, int> get bestiaTakenQuotes {
    final result = <String, int>{};
    for (final entry in bestiaPlayerChoice.entries) {
      if (entry.value.startsWith('take')) {
        final num = int.tryParse(entry.value.replaceAll('take', '')) ?? 0;
        if (num > 0) result[entry.key] = num;
      }
    }
    return result;
  }
}

/// Rappresenta un pagamento in attesa di conferma (per Sette e Mezzo 1v1)
class PendingPayment {
  final String id;
  final String fromPlayerId;
  final String toPlayerId;
  final double amount;
  final PaymentDirection direction;
  final DateTime createdAt;
  final bool confirmed;

  const PendingPayment({
    required this.id,
    required this.fromPlayerId,
    required this.toPlayerId,
    required this.amount,
    required this.direction,
    required this.createdAt,
    this.confirmed = false,
  });

  factory PendingPayment.fromMap(Map<String, dynamic> map) {
    return PendingPayment(
      id: map['id'] as String,
      fromPlayerId: map['fromPlayerId'] as String,
      toPlayerId: map['toPlayerId'] as String,
      amount: (map['amount'] as num).toDouble(),
      direction: PaymentDirection.values.firstWhere(
        (e) => e.name == map['direction'],
        orElse: () => PaymentDirection.playerPaysDealer,
      ),
      createdAt: DateTime.parse(map['createdAt'] as String),
      confirmed: map['confirmed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromPlayerId': fromPlayerId,
      'toPlayerId': toPlayerId,
      'amount': amount,
      'direction': direction.name,
      'createdAt': createdAt.toIso8601String(),
      'confirmed': confirmed,
    };
  }

  PendingPayment copyWith({
    String? id,
    String? fromPlayerId,
    String? toPlayerId,
    double? amount,
    PaymentDirection? direction,
    DateTime? createdAt,
    bool? confirmed,
  }) {
    return PendingPayment(
      id: id ?? this.id,
      fromPlayerId: fromPlayerId ?? this.fromPlayerId,
      toPlayerId: toPlayerId ?? this.toPlayerId,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      createdAt: createdAt ?? this.createdAt,
      confirmed: confirmed ?? this.confirmed,
    );
  }
}

/// Direzione del pagamento in Sette e Mezzo 1v1
enum PaymentDirection {
  /// Giocatore paga al mazziere (automatico)
  playerPaysDealer,
  
  /// Giocatore chiede soldi al mazziere (richiede conferma)
  playerRequestsFromDealer,
}

/// Rappresenta una richiesta di vita pendente (per 31 e Cucù)
class PendingLifeRequest {
  final String id;
  final String fromPlayerId; // Chi richiede la vita
  final String toPlayerId; // A chi la chiede
  final DateTime createdAt;

  const PendingLifeRequest({
    required this.id,
    required this.fromPlayerId,
    required this.toPlayerId,
    required this.createdAt,
  });

  factory PendingLifeRequest.fromMap(Map<String, dynamic> map) {
    return PendingLifeRequest(
      id: map['id'] as String,
      fromPlayerId: map['fromPlayerId'] as String,
      toPlayerId: map['toPlayerId'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromPlayerId': fromPlayerId,
      'toPlayerId': toPlayerId,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}


/// Rappresenta i diversi tipi di giochi di carte natalizi
enum GameType {
  /// Modalità libera - nessuna regola predefinita
  libera,
  
  /// Sette e Mezzo - gioco simile al Blackjack
  setteEMezzo,
  
  /// Cucù (o Saltacavallo) - gioco di eliminazione
  cucu,
  
  /// Trentuno - raggiungere 31 punti con carte dello stesso seme
  trentuno,
  
  /// Las Vegas - gioco ispirato ai casinò
  lasVegas,
  
  /// Bestia - gioco di prese
  bestia,
}

/// Varianti specifiche per il Sette e Mezzo
enum SetteEMezzoVariant {
  /// Mazziere contro tutti - classico
  mazziereVsTutti,
  
  /// 1 contro 1 con piatto
  unoVsUnoConPiatto,
}

/// Varianti specifiche per il Cucù
enum CucuVariant {
  /// Classico con vite
  classico,
  
  /// Con penalità monetarie
  conPenalita,
  
  /// Saltacavallo - possibilità di saltare il turno di scambio
  saltacavallo,
}

/// Varianti specifiche per il Trentuno
enum TrentunoVariant {
  /// Classico con dichiarazione
  classico,
  
  /// Con vite - eliminazione progressiva
  conVite,
  
  /// Con scarti visibili
  scartiVisibili,
}

/// Varianti specifiche per Las Vegas
enum LasVegasVariant {
  /// Classico
  classico,
  
  /// Con rilancio limitato
  rilancioLimitato,
}

/// Varianti specifiche per la Bestia
enum BestiaVariant {
  /// Tre carte
  treCarte,
  
  /// Quattro carte
  quattroCarte,
  
  /// Cinque carte
  cinqueCarte,
  
  /// Con accomodo (cambio carte)
  conAccomodo,
}

/// Configurazione completa di una modalità di gioco
class GameMode {
  final GameType type;
  final String? variantId;
  final Map<String, dynamic> settings;

  const GameMode({
    required this.type,
    this.variantId,
    this.settings = const {},
  });

  /// Modalità libera predefinita
  static const GameMode libera = GameMode(type: GameType.libera);

  factory GameMode.fromMap(Map<String, dynamic> map) {
    return GameMode(
      type: GameType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => GameType.libera,
      ),
      variantId: map['variantId'] as String?,
      settings: Map<String, dynamic>.from(map['settings'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'variantId': variantId,
      'settings': settings,
    };
  }

  GameMode copyWith({
    GameType? type,
    String? variantId,
    Map<String, dynamic>? settings,
  }) {
    return GameMode(
      type: type ?? this.type,
      variantId: variantId ?? this.variantId,
      settings: settings ?? this.settings,
    );
  }

  /// Ottiene il nome visualizzabile del tipo di gioco
  String get displayName {
    switch (type) {
      case GameType.libera:
        return 'Modalità Libera';
      case GameType.setteEMezzo:
        return 'Sette e Mezzo';
      case GameType.cucu:
        return 'Cucù';
      case GameType.trentuno:
        return 'Trentuno';
      case GameType.lasVegas:
        return 'Las Vegas';
      case GameType.bestia:
        return 'Bestia';
    }
  }

  /// Ottiene l'icona associata al gioco
  String get icon {
    switch (type) {
      case GameType.libera:
        return '🎴';
      case GameType.setteEMezzo:
        return '7️⃣';
      case GameType.cucu:
        return '🐦';
      case GameType.trentuno:
        return '3️⃣1️⃣';
      case GameType.lasVegas:
        return '🎰';
      case GameType.bestia:
        return '🦁';
    }
  }

  /// Ottiene la descrizione breve del gioco
  String get shortDescription {
    switch (type) {
      case GameType.libera:
        return 'Nessuna regola predefinita, gestione libera dei movimenti';
      case GameType.setteEMezzo:
        return 'Avvicinati a 7,5 punti senza sballare';
      case GameType.cucu:
        return 'Non restare con la carta più bassa';
      case GameType.trentuno:
        return 'Raggiungi 31 punti con lo stesso seme';
      case GameType.lasVegas:
        return 'Punteggio più alto e più basso vincono!';
      case GameType.bestia:
        return 'Vinci le prese, non andare in bestia!';
    }
  }

  /// Ottiene il nome della variante corrente
  String? get variantDisplayName {
    if (variantId == null) return null;
    
    switch (type) {
      case GameType.setteEMezzo:
        final variant = SetteEMezzoVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => SetteEMezzoVariant.mazziereVsTutti,
        );
        return _getSetteEMezzoVariantName(variant);
      case GameType.cucu:
        final variant = CucuVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => CucuVariant.classico,
        );
        return _getCucuVariantName(variant);
      case GameType.trentuno:
        final variant = TrentunoVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => TrentunoVariant.classico,
        );
        return _getTrentunoVariantName(variant);
      case GameType.lasVegas:
        final variant = LasVegasVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => LasVegasVariant.classico,
        );
        return _getLasVegasVariantName(variant);
      case GameType.bestia:
        final variant = BestiaVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => BestiaVariant.treCarte,
        );
        return _getBestiaVariantName(variant);
      default:
        return null;
    }
  }

  static String _getSetteEMezzoVariantName(SetteEMezzoVariant variant) {
    switch (variant) {
      case SetteEMezzoVariant.mazziereVsTutti:
        return 'Mazziere vs Tutti';
      case SetteEMezzoVariant.unoVsUnoConPiatto:
        return '1 vs 1 con Piatto';
    }
  }

  static String _getCucuVariantName(CucuVariant variant) {
    switch (variant) {
      case CucuVariant.classico:
        return 'Classico';
      case CucuVariant.conPenalita:
        return 'Con Penalità';
      case CucuVariant.saltacavallo:
        return 'Saltacavallo';
    }
  }

  static String _getTrentunoVariantName(TrentunoVariant variant) {
    switch (variant) {
      case TrentunoVariant.classico:
        return 'Classico';
      case TrentunoVariant.conVite:
        return 'Con Vite';
      case TrentunoVariant.scartiVisibili:
        return 'Scarti Visibili';
    }
  }

  static String _getLasVegasVariantName(LasVegasVariant variant) {
    switch (variant) {
      case LasVegasVariant.classico:
        return 'Classico';
      case LasVegasVariant.rilancioLimitato:
        return 'Rilancio Limitato';
    }
  }

  static String _getBestiaVariantName(BestiaVariant variant) {
    switch (variant) {
      case BestiaVariant.treCarte:
        return 'Tre Carte';
      case BestiaVariant.quattroCarte:
        return 'Quattro Carte';
      case BestiaVariant.cinqueCarte:
        return 'Cinque Carte';
      case BestiaVariant.conAccomodo:
        return 'Con Accomodo';
    }
  }

  /// Ottiene le regole complete del gioco
  String get fullRules {
    switch (type) {
      case GameType.libera:
        return '''
🎴 MODALITÀ LIBERA

Questa modalità non ha regole predefinite. È perfetta per:
• Giochi non inclusi nell'app
• Situazioni personalizzate
• Gestione libera di vincite e perdite

Registra semplicemente chi paga e chi riceve dopo ogni mano.
''';
      case GameType.setteEMezzo:
        return '''
7️⃣ SETTE E MEZZO

📜 OBIETTIVO
Avvicinarsi il più possibile a 7,5 punti senza superarlo.

🃏 VALORE DELLE CARTE
• Carte da 1 a 7: valore nominale
• Fante, Cavallo, Re: ½ punto ciascuno
• Re di Denari (Matta): assume qualsiasi valore (da 0,5 a 7)

⭐ SETTE E MEZZO REALE
Fare 7,5 con sole 2 carte (un 7 + una figura) batte qualsiasi altro 7,5.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 MODALITÀ: MAZZIERE VS TUTTI

📋 SVOLGIMENTO
1. Un giocatore è il mazziere (banco)
2. Ogni giocatore fa la propria puntata
3. Il mazziere distribuisce le carte e gioca per ultimo
4. Al termine, il mazziere decide:
   • Da quali giocatori prendere (se li ha battuti)
   • A quali giocatori pagare (se hanno battuto lui)
   • Se ha sballato, paga tutti i giocatori

💱 CAMBIO MAZZIERE
• Qualsiasi giocatore può dichiararsi mazziere
• Il mazziere corrente deve confermare
• Se conferma, avviene il passaggio

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 MODALITÀ: 1 VS 1 CON PIATTO

📋 SVOLGIMENTO
1. C'è un piatto comune
2. Il mazziere gioca contro un giocatore alla volta
3. Non c'è un ordine fisso
4. Ogni giocatore può:
   • Pagare al mazziere una somma (entra nel piatto)
   • Richiedere soldi al mazziere (il mazziere conferma e il giocatore prende dal piatto)

💱 CAMBIO MAZZIERE
• Qualsiasi giocatore può dichiararsi mazziere
• Il mazziere corrente deve confermare
• Se conferma, il piatto viene dato al mazziere uscente
• Il nuovo mazziere inizia con piatto vuoto
''';
      case GameType.cucu:
        return '''
🐦 CUCÙ (SALTACAVALLO)

📜 OBIETTIVO
Non avere la carta di valore più basso alla fine del turno.

🃏 GERARCHIA DELLE CARTE
Dal valore più alto al più basso:
Re > Cavallo > Fante > 7 > 6 > 5 > 4 > 3 > 2 > 1 (Asso)

📋 SVOLGIMENTO
1. Ogni giocatore riceve una carta coperta
2. Partendo dalla sinistra del mazziere, ogni giocatore può:
   - Tenere la propria carta ("Sto bene")
   - Scambiarla con il giocatore successivo
3. Il giocatore successivo DEVE scambiare, a meno che non abbia un Re
4. Il mazziere può scambiare con il mazzo
5. Chi ha la carta più bassa perde una vita

🛡️ CARTE SPECIALI
• Re: blocca lo scambio (chi ha il Re dice "Cucù!")
• Asso: è la carta più bassa, si cerca sempre di scambiarla

💀 ELIMINAZIONE
Ogni giocatore ha 3 vite. Perde chi le esaurisce tutte.
L'ultimo rimasto vince!
''';
      case GameType.trentuno:
        return '''
3️⃣1️⃣ TRENTUNO

📜 OBIETTIVO
Ottenere 31 punti o il punteggio più alto con carte dello stesso seme.

🃏 VALORE DELLE CARTE
• Asso: 11 punti
• Re, Cavallo, Fante: 10 punti ciascuno
• Carte numeriche: valore nominale

📋 SVOLGIMENTO
1. Ogni giocatore riceve 3 carte
2. Si scopre una carta per iniziare gli scarti
3. A turno, ogni giocatore può:
   - Pescare dal mazzo o dagli scarti
   - Scartare una carta
4. Chi raggiunge 31 lo dichiara immediatamente
5. Chi pensa di avere un buon punteggio può "bussare"
6. Dopo il bussare, ogni altro giocatore ha un ultimo turno

🏆 COMBINAZIONI SPECIALI
• 31: tre carte dello stesso seme che sommano 31
• Tris: tre carte dello stesso valore (vale 30,5 punti)

💀 VARIANTE CON VITE
Ogni giocatore ha 3 vite. Chi ha il punteggio più basso perde una vita.
''';
      case GameType.lasVegas:
        return '''
🎰 LAS VEGAS

📜 OBIETTIVO
Ottenere il punteggio più alto O il punteggio più basso. Il piatto viene diviso tra questi due vincitori!

🃏 CARTE E VALORI
• Mazzo da 40 carte italiane
• Carte numeriche: valore nominale (1-7)
• Figure (Re, Cavallo, Fante): 10 punti ciascuna
• Asso singolo: vale 1 punto
• Due o più Assi: valgono 11 punti ciascuno!

👥 GIOCATORI
Da 2 a 6 giocatori

📋 SVOLGIMENTO

1️⃣ DISTRIBUZIONE
• Il mazziere dà 3 carte coperte a ogni giocatore
• Posiziona 4 carte coperte al centro del tavolo
• Tutti versano una puntata obbligatoria nel piatto

2️⃣ GIRO DI PUNTATE
Come nel Poker, in senso antiorario:
• Puntare: mettere una somma nel piatto
• Bussare/Passare: se nessuno ha puntato
• Vedere: pareggiare la puntata altrui
• Rilanciare: puntare di più
• Lasciare: uscire dalla mano

3️⃣ SCARTO CARTE
Dopo ogni giro di puntate, il mazziere scopre una carta centrale.
Tutti i giocatori DEVONO scartare le carte dello stesso valore!
(Se esce una carta già uscita, si sostituisce con una dal mazzo)

4️⃣ RIPETERE
Si ripete il giro di puntate e lo scarto per tutte e 4 le carte centrali.

🏆 FINALE
Dopo l'ultimo giro, si mostrano le carte:
• Metà piatto → punteggio PIÙ ALTO
• Metà piatto → punteggio PIÙ BASSO

⭐ LAS VEGAS!
Se un giocatore scarta TUTTE le sue carte, fa "Las Vegas" e vince L'INTERO piatto!
''';
      case GameType.bestia:
        return '''
🦁 BESTIA

📜 OBIETTIVO
Vincere almeno una presa per non "andare in bestia".

🃏 CARTE UTILIZZATE
Mazzo da 40 carte italiane.

📋 SVOLGIMENTO
1. Ogni giocatore riceve 3 carte (o 4-5 in alcune varianti)
2. Si scopre una carta per determinare la briscola
3. Ogni giocatore decide se partecipare ("Busso") o passare
4. Si giocano le prese come a briscola
5. Chi non fa nessuna presa "va in bestia"

🔥 ANDARE IN BESTIA
Chi non vince alcuna presa deve pagare una penalità:
• In genere si raddoppia il piatto esistente
• O si versa una quota fissa stabilita all'inizio

🎴 VARIANTI
• Tre Carte: versione classica veloce
• Quattro Carte: più strategia
• Cinque Carte: partite più lunghe
• Con Accomodo: prima del gioco si possono cambiare carte

💡 STRATEGIA
Se hai carte deboli, meglio passare che rischiare di andare in bestia!
''';
    }
  }
}

/// Definisce tutte le opzioni disponibili per un tipo di gioco
class GameModeOptions {
  final GameType type;
  final List<GameModeVariantOption> variants;
  final List<GameModeSetting> settings;

  const GameModeOptions({
    required this.type,
    required this.variants,
    this.settings = const [],
  });

  static List<GameModeOptions> get allOptions => [
    const GameModeOptions(
      type: GameType.libera,
      variants: [],
    ),
    GameModeOptions(
      type: GameType.setteEMezzo,
      variants: SetteEMezzoVariant.values.map((v) => GameModeVariantOption(
        id: v.name,
        name: GameMode._getSetteEMezzoVariantName(v),
        description: _getSetteEMezzoVariantDescription(v),
      )).toList(),
      settings: [
        const GameModeSetting(
          id: 'usaMatta',
          name: 'Usa la Matta (Re di Denari)',
          type: SettingType.toggle,
          defaultValue: true,
        ),
        const GameModeSetting(
          id: 'setteEMezzoReale',
          name: 'Sette e Mezzo Reale batte tutto',
          type: SettingType.toggle,
          defaultValue: true,
        ),
      ],
    ),
    GameModeOptions(
      type: GameType.cucu,
      variants: CucuVariant.values.map((v) => GameModeVariantOption(
        id: v.name,
        name: GameMode._getCucuVariantName(v),
        description: _getCucuVariantDescription(v),
      )).toList(),
      settings: [
        const GameModeSetting(
          id: 'numeroVite',
          name: 'Numero di vite',
          type: SettingType.number,
          defaultValue: 3,
          minValue: 1,
          maxValue: 5,
        ),
      ],
    ),
    GameModeOptions(
      type: GameType.trentuno,
      variants: TrentunoVariant.values.map((v) => GameModeVariantOption(
        id: v.name,
        name: GameMode._getTrentunoVariantName(v),
        description: _getTrentunoVariantDescription(v),
      )).toList(),
      settings: [
        const GameModeSetting(
          id: 'numeroVite',
          name: 'Numero di vite',
          type: SettingType.number,
          defaultValue: 3,
          minValue: 1,
          maxValue: 5,
        ),
        const GameModeSetting(
          id: 'trisVale30',
          name: 'Tris vale 30,5 punti',
          type: SettingType.toggle,
          defaultValue: true,
        ),
      ],
    ),
    GameModeOptions(
      type: GameType.lasVegas,
      variants: LasVegasVariant.values.map((v) => GameModeVariantOption(
        id: v.name,
        name: GameMode._getLasVegasVariantName(v),
        description: _getLasVegasVariantDescription(v),
      )).toList(),
    ),
    GameModeOptions(
      type: GameType.bestia,
      variants: BestiaVariant.values.map((v) => GameModeVariantOption(
        id: v.name,
        name: GameMode._getBestiaVariantName(v),
        description: _getBestiaVariantDescription(v),
      )).toList(),
      settings: [
        const GameModeSetting(
          id: 'bestiaPaga',
          name: 'Chi va in bestia raddoppia il piatto',
          type: SettingType.toggle,
          defaultValue: true,
        ),
      ],
    ),
  ];

  static String _getSetteEMezzoVariantDescription(SetteEMezzoVariant variant) {
    switch (variant) {
      case SetteEMezzoVariant.mazziereVsTutti:
        return 'Il mazziere gioca contro tutti i giocatori. Ogni giocatore punta e il mazziere decide chi paga e chi riceve.';
      case SetteEMezzoVariant.unoVsUnoConPiatto:
        return 'Modalità 1 contro 1 con piatto. I giocatori pagano o richiedono dal piatto del mazziere.';
    }
  }

  static String _getCucuVariantDescription(CucuVariant variant) {
    switch (variant) {
      case CucuVariant.classico:
        return 'Gioco classico con 3 vite per giocatore. L\'ultimo rimasto vince.';
      case CucuVariant.conPenalita:
        return 'Chi perde paga una penalità monetaria invece di perdere vite.';
      case CucuVariant.saltacavallo:
        return 'I giocatori possono scegliere di "saltare" il loro turno di scambio.';
    }
  }

  static String _getTrentunoVariantDescription(TrentunoVariant variant) {
    switch (variant) {
      case TrentunoVariant.classico:
        return 'Chi raggiunge 31 dichiara immediatamente e vince la mano.';
      case TrentunoVariant.conVite:
        return 'Chi ha il punteggio più basso perde una vita. Eliminazione progressiva.';
      case TrentunoVariant.scartiVisibili:
        return 'Gli scarti sono visibili a tutti, aggiungendo un elemento strategico.';
    }
  }

  static String _getLasVegasVariantDescription(LasVegasVariant variant) {
    switch (variant) {
      case LasVegasVariant.classico:
        return 'Regole standard con puntate e rilanci liberi.';
      case LasVegasVariant.rilancioLimitato:
        return 'I rilanci sono limitati a un massimo stabilito all\'inizio.';
    }
  }

  static String _getBestiaVariantDescription(BestiaVariant variant) {
    switch (variant) {
      case BestiaVariant.treCarte:
        return 'Versione classica e veloce con 3 carte per giocatore.';
      case BestiaVariant.quattroCarte:
        return '4 carte per giocatore, più possibilità strategiche.';
      case BestiaVariant.cinqueCarte:
        return '5 carte per giocatore, partite più lunghe e complesse.';
      case BestiaVariant.conAccomodo:
        return 'Prima del gioco si possono scartare e cambiare carte.';
    }
  }
}

/// Rappresenta un'opzione di variante per un tipo di gioco
class GameModeVariantOption {
  final String id;
  final String name;
  final String description;

  const GameModeVariantOption({
    required this.id,
    required this.name,
    required this.description,
  });
}

/// Tipo di impostazione
enum SettingType {
  toggle,
  number,
  choice,
}

/// Rappresenta un'impostazione configurabile per un gioco
class GameModeSetting {
  final String id;
  final String name;
  final SettingType type;
  final dynamic defaultValue;
  final int? minValue;
  final int? maxValue;
  final List<String>? choices;

  const GameModeSetting({
    required this.id,
    required this.name,
    required this.type,
    required this.defaultValue,
    this.minValue,
    this.maxValue,
    this.choices,
  });
}


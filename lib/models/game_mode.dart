import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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

  /// Ottiene il nome visualizzabile del tipo di gioco (senza localizzazione - fallback)
  String get displayName => _getDisplayNameFallback();
  
  String _getDisplayNameFallback() {
    switch (type) {
      case GameType.libera:
        return 'Free Mode';
      case GameType.setteEMezzo:
        return 'Seven and a Half';
      case GameType.cucu:
        return 'Cucù';
      case GameType.trentuno:
        return 'Thirty-One';
      case GameType.lasVegas:
        return 'Las Vegas';
      case GameType.bestia:
        return 'Bestia';
    }
  }

  /// Ottiene il nome visualizzabile del tipo di gioco (con localizzazione)
  String getDisplayName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case GameType.libera:
        return l10n.gameModeLibera;
      case GameType.setteEMezzo:
        return l10n.gameModeSetteEMezzo;
      case GameType.cucu:
        return l10n.gameModeCucu;
      case GameType.trentuno:
        return l10n.gameModeTrentuno;
      case GameType.lasVegas:
        return l10n.gameModeLasVegas;
      case GameType.bestia:
        return l10n.gameModeBestia;
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

  /// Ottiene la descrizione breve del gioco (senza localizzazione - fallback)
  String get shortDescription => _getShortDescriptionFallback();

  String _getShortDescriptionFallback() {
    switch (type) {
      case GameType.libera:
        return 'No preset rules, free management of movements';
      case GameType.setteEMezzo:
        return 'Get close to 7.5 points without busting';
      case GameType.cucu:
        return 'Don\'t be left with the lowest card';
      case GameType.trentuno:
        return 'Reach 31 points with the same suit';
      case GameType.lasVegas:
        return 'Highest and lowest scores win!';
      case GameType.bestia:
        return 'Win tricks, don\'t go in bestia!';
    }
  }

  /// Ottiene la descrizione breve del gioco (con localizzazione)
  String getShortDescription(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case GameType.libera:
        return l10n.gameModeShortLibera;
      case GameType.setteEMezzo:
        return l10n.gameModeShortSetteEMezzo;
      case GameType.cucu:
        return l10n.gameModeShortCucu;
      case GameType.trentuno:
        return l10n.gameModeShortTrentuno;
      case GameType.lasVegas:
        return l10n.gameModeShortLasVegas;
      case GameType.bestia:
        return l10n.gameModeShortBestia;
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

  /// Ottiene il nome della variante corrente (con localizzazione)
  String? getVariantDisplayName(BuildContext context) {
    if (variantId == null) return null;
    
    switch (type) {
      case GameType.setteEMezzo:
        final variant = SetteEMezzoVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => SetteEMezzoVariant.mazziereVsTutti,
        );
        return getSetteEMezzoVariantNameLocalized(variant, context);
      case GameType.cucu:
        final variant = CucuVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => CucuVariant.classico,
        );
        return getCucuVariantNameLocalized(variant, context);
      case GameType.trentuno:
        final variant = TrentunoVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => TrentunoVariant.classico,
        );
        return getTrentunoVariantNameLocalized(variant, context);
      case GameType.lasVegas:
        final variant = LasVegasVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => LasVegasVariant.classico,
        );
        return getLasVegasVariantNameLocalized(variant, context);
      case GameType.bestia:
        final variant = BestiaVariant.values.firstWhere(
          (v) => v.name == variantId,
          orElse: () => BestiaVariant.treCarte,
        );
        return getBestiaVariantNameLocalized(variant, context);
      default:
        return null;
    }
  }

  static String _getSetteEMezzoVariantName(SetteEMezzoVariant variant) {
    switch (variant) {
      case SetteEMezzoVariant.mazziereVsTutti:
        return 'Dealer vs All';
      case SetteEMezzoVariant.unoVsUnoConPiatto:
        return '1 vs 1 with Pot';
    }
  }

  static String getSetteEMezzoVariantNameLocalized(SetteEMezzoVariant variant, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case SetteEMezzoVariant.mazziereVsTutti:
        return l10n.variantMazziereVsTutti;
      case SetteEMezzoVariant.unoVsUnoConPiatto:
        return l10n.variant1vs1ConPiatto;
    }
  }

  static String _getCucuVariantName(CucuVariant variant) {
    switch (variant) {
      case CucuVariant.classico:
        return 'Classic';
      case CucuVariant.conPenalita:
        return 'With Penalties';
      case CucuVariant.saltacavallo:
        return 'Saltacavallo';
    }
  }

  static String getCucuVariantNameLocalized(CucuVariant variant, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case CucuVariant.classico:
        return l10n.variantClassico;
      case CucuVariant.conPenalita:
        return l10n.variantConPenalita;
      case CucuVariant.saltacavallo:
        return l10n.variantSaltacavallo;
    }
  }

  static String _getTrentunoVariantName(TrentunoVariant variant) {
    switch (variant) {
      case TrentunoVariant.classico:
        return 'Classic';
      case TrentunoVariant.conVite:
        return 'With Lives';
      case TrentunoVariant.scartiVisibili:
        return 'Visible Discards';
    }
  }

  static String getTrentunoVariantNameLocalized(TrentunoVariant variant, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case TrentunoVariant.classico:
        return l10n.variantClassico;
      case TrentunoVariant.conVite:
        return l10n.variantConVite;
      case TrentunoVariant.scartiVisibili:
        return l10n.variantScartiVisibili;
    }
  }

  static String _getLasVegasVariantName(LasVegasVariant variant) {
    switch (variant) {
      case LasVegasVariant.classico:
        return 'Classic';
      case LasVegasVariant.rilancioLimitato:
        return 'Limited Raise';
    }
  }

  static String getLasVegasVariantNameLocalized(LasVegasVariant variant, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case LasVegasVariant.classico:
        return l10n.variantClassico;
      case LasVegasVariant.rilancioLimitato:
        return l10n.variantRilancioLimitato;
    }
  }

  static String _getBestiaVariantName(BestiaVariant variant) {
    switch (variant) {
      case BestiaVariant.treCarte:
        return 'Three Cards';
      case BestiaVariant.quattroCarte:
        return 'Four Cards';
      case BestiaVariant.cinqueCarte:
        return 'Five Cards';
      case BestiaVariant.conAccomodo:
        return 'With Accomodo';
    }
  }

  static String getBestiaVariantNameLocalized(BestiaVariant variant, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (variant) {
      case BestiaVariant.treCarte:
        return l10n.variantTreCarte;
      case BestiaVariant.quattroCarte:
        return l10n.variantQuattroCarte;
      case BestiaVariant.cinqueCarte:
        return l10n.variantCinqueCarte;
      case BestiaVariant.conAccomodo:
        return l10n.variantConAccomodo;
    }
  }

  /// Ottiene le regole complete del gioco (senza localizzazione - fallback)
  String get fullRules => _getFullRulesFallback();

  String _getFullRulesFallback() {
    // Fallback in English
    switch (type) {
      case GameType.libera:
        return 'Free Mode - No preset rules.';
      case GameType.setteEMezzo:
        return 'Seven and a Half - Get close to 7.5 without busting.';
      case GameType.cucu:
        return 'Cucù - Don\'t be left with the lowest card.';
      case GameType.trentuno:
        return 'Thirty-One - Reach 31 points with same suit cards.';
      case GameType.lasVegas:
        return 'Las Vegas - Highest and lowest scores win!';
      case GameType.bestia:
        return 'Bestia - Win tricks, don\'t go in bestia!';
    }
  }

  /// Ottiene le regole complete del gioco (con localizzazione)
  String getFullRules(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (type) {
      case GameType.libera:
        return l10n.gameRulesLibera;
      case GameType.setteEMezzo:
        return l10n.gameRulesSetteEMezzo;
      case GameType.cucu:
        return l10n.gameRulesCucu;
      case GameType.trentuno:
        return l10n.gameRulesTrentuno;
      case GameType.lasVegas:
        return l10n.gameRulesLasVegas;
      case GameType.bestia:
        return l10n.gameRulesBestia;
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


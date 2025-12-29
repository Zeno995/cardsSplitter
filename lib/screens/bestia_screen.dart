import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../models/game_mode.dart';
import '../models/game_hand.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import '../widgets/amount_keypad.dart';

/// Schermata per gestire una partita a Bestia
class BestiaScreen extends StatefulWidget {
  final String sessionId;
  final GameMode? initialGameMode;

  const BestiaScreen({
    super.key, 
    required this.sessionId,
    this.initialGameMode,
  });

  @override
  State<BestiaScreen> createState() => _BestiaScreenState();
}

class _BestiaScreenState extends State<BestiaScreen> {
  final _uuid = const Uuid();
  final _currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
  final _baseValueController = TextEditingController();
  List<String>? _tempPlayerOrder; // Ordine temporaneo durante la configurazione

  @override
  void dispose() {
    _baseValueController.dispose();
    super.dispose();
  }

  String? get _currentUserId => context.read<AuthService>().currentUser?.uid;

  bool _isAdmin(GameSession session) => session.adminId == _currentUserId;

  Player? _getCurrentUserPlayer(GameSession session) {
    try {
      return session.players.firstWhere((p) => p.userId == _currentUserId);
    } catch (_) {
      return null;
    }
  }

  Player _getPlayerById(GameSession session, String id) {
    return session.players.firstWhere((p) => p.id == id);
  }

  /// Ottiene il GameMode corrente (dalla mano attiva o da initialGameMode)
  GameMode _getGameMode(GameSession session) {
    if (session.activeHand != null) {
      return GameMode(
        type: session.activeHand!.gameType,
        variantId: session.activeHand!.variantId,
      );
    }
    return widget.initialGameMode ?? const GameMode(type: GameType.bestia);
  }

  /// Avvia una nuova mano di Bestia
  Future<void> _startNewHand(GameSession session, String? variantId) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();

    final playerOrder = session.players.map((p) => p.id).toList();
    final playerStatus = <String, String>{};

    for (final playerId in playerOrder) {
      playerStatus[playerId] = 'waiting';
    }

    final hand = ActiveHand(
      id: _uuid.v4(),
      gameType: GameType.bestia,
      variantId: variantId,
      createdAt: DateTime.now(),
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      playerOrder: playerOrder,
      playerStatus: playerStatus,
      needsBestiaPlayerOrder: true, // Prima l'admin deve impostare l'ordine
      needsBestiaSetup: false, // Poi imposterà la quota base
    );

    await dbService.startActiveHand(sessionId: session.id, hand: hand);
  }

  /// Conferma l'ordine dei giocatori
  Future<void> _confirmPlayerOrder(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    
    final order = _tempPlayerOrder ?? hand.playerOrder;
    
    // Aggiorna l'ordine e passa alla fase di setup quota
    final newHand = hand.copyWith(
      playerOrder: order,
      needsBestiaPlayerOrder: false,
      needsBestiaSetup: true, // Ora deve impostare la quota
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    _tempPlayerOrder = null;
  }

  /// Admin imposta la quota base del mazziere
  Future<void> _setupBestiaBase(
      GameSession session, ActiveHand hand, double baseValue) async {
    if (baseValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.enterValidAmountGreaterThan0),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final dbService = context.read<DatabaseService>();

    // La quota è impostata, il primo mazziere è il primo giocatore
    final firstDealerId = hand.playerOrder.isNotEmpty ? hand.playerOrder[0] : null;
    
    final newHand = hand.copyWith(
      bestiaBaseValue: baseValue,
      needsBestiaSetup: false,
      bestiaDealerId: firstDealerId,
      bestiaDealerIndex: 0,
      bestiaNeedsDealerBet: true, // Il mazziere deve mettere la quota
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    _baseValueController.clear();
  }

  /// Il mazziere mette la sua quota
  Future<void> _dealerBet(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (hand.bestiaDealerId == null) return;

    // Registra il movimento: mazziere paga al piatto
    await dbService.addMovement(
      sessionId: session.id,
      fromPlayerId: hand.bestiaDealerId!,
      toPlayerId: '_bestia_pot_',
      amount: hand.bestiaBaseValue,
      description: '🦁 Quota mazziere Bestia',
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      handId: hand.id,
    );

    // Aggiorna la mano - il mazziere ha pagato
    final newHand = hand.copyWith(
      bestiaPot: hand.bestiaPot + hand.bestiaBaseValue,
      bestiaNeedsDealerBet: false,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Admin avvia la fase delle scelte (dopo che la mano è stata giocata)
  Future<void> _startChoicePhase(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();

    final newHand = hand.copyWith(
      bestiaChoicePhase: true,
      bestiaPlayerChoice: {}, // Reset delle scelte
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Giocatore fa la propria scelta
  Future<void> _makeChoice(
      GameSession session, ActiveHand hand, String choice) async {
    final dbService = context.read<DatabaseService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer == null) return;

    final newChoices = Map<String, String>.from(hand.bestiaPlayerChoice);
    newChoices[myPlayer.id] = choice;

    final newHand = hand.copyWith(
      bestiaPlayerChoice: newChoices,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Finalizza il round quando tutti hanno scelto
  /// 
  /// Logica:
  /// 1. Il piatto viene SEMPRE diviso in 3 quote e distribuito ai vincitori
  /// 2. Chi paga la bestia mette nel NUOVO piatto l'equivalente del piatto corrente
  /// 3. Il mazziere successivo mette la quota fissa
  Future<void> _finalizeRound(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    final createdBy = authService.currentUser?.uid ?? 'anonymous';

    final currentPot = hand.bestiaPot;
    final payingPlayers = hand.bestiaPayingPlayers;
    final takenQuotes = hand.bestiaTakenQuotes;
    
    // STEP 1: Distribuisci SEMPRE il piatto ai vincitori (diviso in 3 quote)
    // La bestia ha sempre 3 quote
    const totalQuotes = 3;
    final quoteValue = currentPot / totalQuotes;
    
    // Calcola quante quote sono state prese
    final totalQuotesTaken = takenQuotes.values.fold(0, (sum, val) => sum + val);
    
    if (totalQuotesTaken > 0 && currentPot > 0) {
      for (final entry in takenQuotes.entries) {
        final playerId = entry.key;
        final quotes = entry.value;
        final amount = quoteValue * quotes;

        await dbService.addMovement(
          sessionId: session.id,
          fromPlayerId: '_bestia_pot_',
          toPlayerId: playerId,
          amount: amount,
          description: '🦁 Vince $quotes ${quotes == 1 ? "quota" : "quote"} della Bestia',
          createdBy: createdBy,
          handId: hand.id,
        );
      }
    }
    
    // STEP 2: Chi paga la bestia mette nel NUOVO piatto l'equivalente del piatto corrente
    double newPot = 0;
    for (final playerId in payingPlayers) {
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: playerId,
        toPlayerId: '_bestia_pot_',
        amount: currentPot, // Paga quanto c'ERA nel piatto
        description: '🦁 Paga la Bestia',
        createdBy: createdBy,
        handId: hand.id,
      );
      newPot += currentPot; // Accumula nel nuovo piatto
    }

    // STEP 3: Se qualcuno ha pagato la bestia, il gioco continua
    if (payingPlayers.isNotEmpty) {
      // Calcola il nuovo mazziere (ruota al prossimo)
      final nextDealerIndex = (hand.bestiaDealerIndex + 1) % hand.playerOrder.length;
      final nextDealerId = hand.playerOrder[nextDealerIndex];
      
      // Reset per nuovo round - nuovo piatto con i pagamenti bestia, nuovo mazziere che deve pagare
      final newHand = hand.copyWith(
        bestiaPot: newPot, // Nuovo piatto = somma dei pagamenti bestia
        bestiaChoicePhase: false, // Torna alla fase di gioco
        bestiaPlayerChoice: {}, // Reset scelte per nuovo round
        bestiaDealerId: nextDealerId,
        bestiaDealerIndex: nextDealerIndex,
        bestiaNeedsDealerBet: true, // Il nuovo mazziere deve mettere la quota fissa
      );
      await dbService.updateActiveHand(sessionId: session.id, hand: newHand);

      if (mounted) {
        final nextDealer = _getPlayerById(session, nextDealerId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🦁 La Bestia continua! Nuovo piatto: ${_currencyFormat.format(newPot)} - Mazziere: ${nextDealer.name}'),
            backgroundColor: AppTheme.gold,
          ),
        );
      }
      return;
    }

    // STEP 4: Nessuno ha pagato la bestia - la partita termina!
    await dbService.endActiveHand(sessionId: session.id);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🦁 La Bestia è terminata! Nessuno ha pagato.'),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  /// Annulla la mano corrente e tutti i suoi movimenti (solo admin)
  Future<void> _cancelHand(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();

    await dbService.cancelHandMovements(
      sessionId: session.id,
      handId: hand.id,
    );

    await dbService.endActiveHand(sessionId: session.id);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.handCancelledMovementsRemoved),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbService = context.read<DatabaseService>();

    return StreamBuilder<GameSession?>(
      stream: dbService.streamSession(widget.sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: ChristmasBackground(
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
            ),
          );
        }

        final session = snapshot.data;
        if (session == null) {
          return Scaffold(
            body: ChristmasBackground(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 60, color: AppTheme.accentRed),
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.sessionNotFound,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        color: AppTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLocalizations.of(context)!.goBack),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final hand = session.activeHand;
        final isAdmin = _isAdmin(session);

        // Se non c'è una mano attiva
        if (hand == null) {
          return _buildNoActiveHand(session, isAdmin);
        }

        // Mano attiva
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('🦁', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.bestia),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${AppLocalizations.of(context)!.pot}: ${_currencyFormat.format(hand.bestiaPot)}',
                      style: GoogleFonts.lato(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              if (isAdmin) ...[
                IconButton(
                  icon: const Icon(Icons.undo, color: AppTheme.accentRed),
                  onPressed: () => _showCancelHandDialog(session, hand),
                  tooltip: AppLocalizations.of(context)!.cancelHand,
                ),
              ],
            ],
          ),
          body: ChristmasBackground(
            child: _buildHandView(session, hand, isAdmin),
          ),
        );
      },
    );
  }

  Widget _buildNoActiveHand(GameSession session, bool isAdmin) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🦁', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.bestia),
          ],
        ),
      ),
      body: ChristmasBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🦁', style: TextStyle(fontSize: 60))
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(),
                const SizedBox(height: 24),
                Text(
                  AppLocalizations.of(context)!.readyToPlay,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                const SizedBox(height: 12),
                Text(
                  isAdmin
                      ? AppLocalizations.of(context)!.startHandWhenReady
                      : AppLocalizations.of(context)!.waitForAdminToStart,
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.mode(_getGameMode(session).getVariantDisplayName(context) ?? AppLocalizations.of(context)!.variantClassico),
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppTheme.gold.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                const SizedBox(height: 32),
                if (isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _startNewHand(session, _getGameMode(session).variantId),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(AppLocalizations.of(context)!.startHand),
                  ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandView(GameSession session, ActiveHand hand, bool isAdmin) {
    // Fase 0: Admin imposta l'ordine dei giocatori
    if (hand.needsBestiaPlayerOrder) {
      return _buildPlayerOrderView(session, hand, isAdmin);
    }

    // Fase 1: Admin imposta la quota base
    if (hand.needsBestiaSetup) {
      return _buildSetupView(session, hand, isAdmin);
    }

    // Fase 2: Il mazziere deve mettere la quota
    if (hand.bestiaNeedsDealerBet) {
      return _buildDealerBetView(session, hand);
    }

    // Fase 3: Attesa che l'admin avvii la fase scelte (dopo che si gioca il round)
    if (!hand.bestiaChoicePhase) {
      return _buildWaitingForChoicePhaseView(session, hand, isAdmin);
    }

    // Fase 4: Giocatori fanno le loro scelte
    if (hand.bestiaChoicePhase && !hand.allPlayersHaveChosen) {
      return _buildChoicePhaseView(session, hand, isAdmin);
    }

    // Fase 5: Tutti hanno scelto - admin finalizza il round
    if (hand.allPlayersHaveChosen) {
      return _buildFinalizeRoundView(session, hand, isAdmin);
    }

    return const Center(child: CircularProgressIndicator(color: AppTheme.gold));
  }

  Widget _buildPlayerOrderView(GameSession session, ActiveHand hand, bool isAdmin) {
    // Inizializza l'ordine temporaneo se non esiste
    _tempPlayerOrder ??= List.from(hand.playerOrder);
    
    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_empty,
                    size: 50, color: AppTheme.gold),
              ).animate().fadeIn(duration: 400.ms).scale(),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)!.waitingForAdmin,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)!.waitingAdminSetOrder,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            ],
          ),
        ),
      );
    }

    // Admin view - ordina i giocatori
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🦁', style: TextStyle(fontSize: 60))
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.setPlayerOrder,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.dragPlayersToSetOrder,
              style: GoogleFonts.lato(
                fontSize: 14,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 24),
            
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_vert, color: AppTheme.gold),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.playOrder,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Usa altezza fissa basata sul numero di giocatori
                    SizedBox(
                      height: _tempPlayerOrder!.length * 60.0,
                      child: ReorderableListView.builder(
                        itemCount: _tempPlayerOrder!.length,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = _tempPlayerOrder!.removeAt(oldIndex);
                            _tempPlayerOrder!.insert(newIndex, item);
                          });
                        },
                        proxyDecorator: (child, index, animation) {
                          return Material(
                            elevation: 4,
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            child: child,
                          );
                        },
                        itemBuilder: (context, index) {
                          final player = _getPlayerById(session, _tempPlayerOrder![index]);
                          final isFirst = index == 0;
                          
                          return Material(
                            key: ValueKey(player.id),
                            color: Colors.transparent,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: isFirst 
                                    ? AppTheme.gold.withValues(alpha: 0.2) 
                                    : AppTheme.darkGreen.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                border: isFirst 
                                    ? Border.all(color: AppTheme.gold.withValues(alpha: 0.5))
                                    : null,
                              ),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isFirst 
                                      ? AppTheme.gold 
                                      : AppTheme.gold.withValues(alpha: 0.2),
                                  child: Text(
                                    '${index + 1}',
                                    style: GoogleFonts.lato(
                                      color: isFirst ? AppTheme.darkGreen : AppTheme.gold,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      player.name,
                                      style: GoogleFonts.lato(
                                        color: AppTheme.cream,
                                        fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (isFirst) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.gold,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context)!.dealer,
                                          style: GoogleFonts.lato(
                                            fontSize: 10,
                                            color: AppTheme.darkGreen,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(Icons.drag_handle, color: AppTheme.cream),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            
            const SizedBox(height: 24),
            
            ElevatedButton.icon(
              onPressed: () => _confirmPlayerOrder(session, hand),
              icon: const Icon(Icons.check),
              label: Text(AppLocalizations.of(context)!.confirmOrder),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.darkGreen,
              ),
            ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupView(GameSession session, ActiveHand hand, bool isAdmin) {
    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_empty,
                    size: 50, color: AppTheme.gold),
              ).animate().fadeIn(duration: 400.ms).scale(),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)!.waitingForAdmin,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)!.waitingAdminSetQuota,
                style: GoogleFonts.lato(
                  fontSize: 14,
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            ],
          ),
        ),
      );
    }

    // Admin imposta la quota
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('💰', style: TextStyle(fontSize: 50)),
            ).animate().fadeIn(duration: 400.ms).scale(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.setQuota,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.whatShouldDealerBet,
              style: GoogleFonts.lato(
                fontSize: 14,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: _baseValueController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.lato(
                        color: AppTheme.gold,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        prefixText: '€ ',
                        prefixStyle: GoogleFonts.lato(
                          color: AppTheme.gold,
                          fontSize: 32,
                        ),
                        hintText: '0,00',
                        hintStyle: GoogleFonts.lato(
                          color: AppTheme.gold.withValues(alpha: 0.3),
                          fontSize: 32,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 16),
                    AmountKeypad(controller: _baseValueController),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final amount = double.tryParse(
                            _baseValueController.text.replaceAll(',', '.'),
                          );
                          if (amount != null && amount > 0) {
                            _setupBestiaBase(session, hand, amount);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(AppLocalizations.of(context)!.enterValidAmountGreaterThan0),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: Text(AppLocalizations.of(context)!.confirmQuota),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildDealerBetView(GameSession session, ActiveHand hand) {
    final myPlayer = _getCurrentUserPlayer(session);
    final isDealer = myPlayer != null && hand.bestiaDealerId == myPlayer.id;
    final dealerPlayer = hand.bestiaDealerId != null 
        ? _getPlayerById(session, hand.bestiaDealerId!) 
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('🎴', style: TextStyle(fontSize: 50)),
            ).animate().fadeIn(duration: 400.ms).scale(),
            const SizedBox(height: 24),
            Text(
              isDealer ? AppLocalizations.of(context)!.dealerBetPhase : '${AppLocalizations.of(context)!.dealer}: ${dealerPlayer?.name ?? "..."}',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              isDealer 
                  ? AppLocalizations.of(context)!.dealerMustPayQuota(_currencyFormat.format(hand.bestiaBaseValue))
                  : AppLocalizations.of(context)!.waitDealerPays(dealerPlayer?.name ?? AppLocalizations.of(context)!.dealer),
              style: GoogleFonts.lato(
                fontSize: 14,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 32),
            if (isDealer)
              ElevatedButton.icon(
                onPressed: () => _dealerBet(session, hand),
                icon: const Icon(Icons.payments),
                label: Text(AppLocalizations.of(context)!.payQuota(_currencyFormat.format(hand.bestiaBaseValue))),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: AppTheme.gold,
                  foregroundColor: AppTheme.darkGreen,
                ),
              ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
            if (!isDealer)
              const CircularProgressIndicator(color: AppTheme.gold)
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingForChoicePhaseView(
      GameSession session, ActiveHand hand, bool isAdmin) {
    final dealerPlayer = _getPlayerById(session, hand.bestiaDealerId!);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🃏', style: TextStyle(fontSize: 60))
                .animate()
                .fadeIn(duration: 400.ms)
                .scale(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.playTheRound,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.lato(
                  fontSize: 16,
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
                children: [
                  TextSpan(text: '${AppLocalizations.of(context)!.dealer}: '),
                  TextSpan(
                    text: dealerPlayer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                  TextSpan(text: '\n${AppLocalizations.of(context)!.nowPlayCards}'),
                ],
              ),
            ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${AppLocalizations.of(context)!.pot}: ${_currencyFormat.format(hand.bestiaPot)}',
                style: GoogleFonts.lato(
                  color: AppTheme.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.bestiaContinuesUntilWon,
              style: GoogleFonts.lato(
                fontSize: 12,
                color: AppTheme.cream.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              ),
            ).animate().fadeIn(delay: 450.ms, duration: 400.ms),
            const SizedBox(height: 32),
            if (isAdmin)
              ElevatedButton.icon(
                onPressed: () => _startChoicePhase(session, hand),
                icon: const Icon(Icons.arrow_forward),
                label: Text(AppLocalizations.of(context)!.roundPlayed),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  /// Calcola quante quote sono già state prese dagli altri giocatori
  int _getQuotesTakenByOthers(ActiveHand hand, String? myPlayerId) {
    int total = 0;
    for (final entry in hand.bestiaPlayerChoice.entries) {
      if (entry.key != myPlayerId && entry.value.startsWith('take')) {
        final num = int.tryParse(entry.value.replaceAll('take', '')) ?? 0;
        total += num;
      }
    }
    return total;
  }

  /// Calcola quante quote totali sono state prese
  int _getTotalQuotesTaken(ActiveHand hand) {
    int total = 0;
    for (final entry in hand.bestiaPlayerChoice.entries) {
      if (entry.value.startsWith('take')) {
        final num = int.tryParse(entry.value.replaceAll('take', '')) ?? 0;
        total += num;
      }
    }
    return total;
  }

  /// Calcola quanti giocatori devono ancora scegliere (escluso me)
  int _getPlayersWaitingCount(ActiveHand hand, String? myPlayerId) {
    int waiting = 0;
    for (final playerId in hand.playerOrder) {
      if (playerId != myPlayerId && !hand.bestiaPlayerChoice.containsKey(playerId)) {
        waiting++;
      }
    }
    return waiting;
  }

  /// Calcola quante quote devo prendere obbligatoriamente
  /// Sono l'ultimo a scegliere e ci sono quote non assegnate
  int _getForcedQuotes(ActiveHand hand, String? myPlayerId) {
    if (myPlayerId == null) return 0;
    
    // Quanti giocatori devono ancora scegliere (escluso me)
    final waitingCount = _getPlayersWaitingCount(hand, myPlayerId);
    
    // Se ci sono ancora altri giocatori che devono scegliere, non sono forzato
    if (waitingCount > 0) return 0;
    
    // Sono l'ultimo a scegliere - calcola le quote rimanenti
    final quotesTaken = _getQuotesTakenByOthers(hand, myPlayerId);
    final remainingQuotes = 3 - quotesTaken;
    
    // Se tutte e 3 le quote sono state prese, non devo prendere niente
    if (remainingQuotes <= 0) return 0;
    
    // Sono l'ultimo e ci sono quote rimanenti: DEVO prenderle tutte
    return remainingQuotes;
  }

  /// Resetta la scelta di un giocatore (solo admin)
  Future<void> _resetPlayerChoice(GameSession session, ActiveHand hand, String playerId) async {
    final dbService = context.read<DatabaseService>();
    
    final newChoices = Map<String, String>.from(hand.bestiaPlayerChoice);
    newChoices.remove(playerId);
    
    final newHand = hand.copyWith(
      bestiaPlayerChoice: newChoices,
    );
    
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    
    if (mounted) {
      final player = _getPlayerById(session, playerId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.choiceCancelled(player.name)),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  Widget _buildChoicePhaseView(
      GameSession session, ActiveHand hand, bool isAdmin) {
    final myPlayer = _getCurrentUserPlayer(session);
    final myChoice =
        myPlayer != null ? hand.bestiaPlayerChoice[myPlayer.id] : null;
    final hasChosen = myChoice != null;
    
    // Calcola quote disponibili
    final quotesTakenByOthers = _getQuotesTakenByOthers(hand, myPlayer?.id);
    final availableQuotes = 3 - quotesTakenByOthers;
    final forcedQuotes = _getForcedQuotes(hand, myPlayer?.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info piatto e quote
          Card(
            color: AppTheme.gold.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    AppLocalizations.of(context)!.currentPot,
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _currencyFormat.format(hand.bestiaPot),
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Visualizzazione delle 3 quote con stato
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: i < quotesTakenByOthers 
                                ? Colors.green.withValues(alpha: 0.3)
                                : AppTheme.darkGreen.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: i < quotesTakenByOthers 
                                  ? Colors.green.withValues(alpha: 0.7)
                                  : AppTheme.gold.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i < quotesTakenByOthers)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.check, color: Colors.green, size: 14),
                                ),
                              Text(
                                _currencyFormat.format(hand.bestiaPot / 3),
                                style: GoogleFonts.lato(
                                  color: i < quotesTakenByOthers 
                                      ? Colors.green 
                                      : AppTheme.gold,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    quotesTakenByOthers > 0 
                        ? '$availableQuotes ${availableQuotes == 1 ? "quota disponibile" : "quote disponibili"}'
                        : '3 quote da vincere',
                    style: GoogleFonts.lato(
                      color: availableQuotes < 3 
                          ? Colors.orange 
                          : AppTheme.cream.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: availableQuotes < 3 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${AppLocalizations.of(context)!.dealerQuota}: ${_currencyFormat.format(hand.bestiaBaseValue)}',
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 16),

          // Lista scelte dei giocatori
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context)!.playerChoices,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ),
                      if (isAdmin && hand.bestiaPlayerChoice.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _showResetChoicesDialog(session, hand),
                          icon: const Icon(Icons.edit, size: 16),
                          label: Text(AppLocalizations.of(context)!.edit),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...hand.playerOrder.map((playerId) {
                    final player = _getPlayerById(session, playerId);
                    final choice = hand.bestiaPlayerChoice[playerId];
                    final isMe = myPlayer?.id == playerId;
                    final isDealer = playerId == hand.bestiaDealerId;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.blue.withValues(alpha: 0.1)
                            : choice != null
                                ? AppTheme.gold.withValues(alpha: 0.1)
                                : AppTheme.darkGreen.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe
                              ? Colors.blue.withValues(alpha: 0.5)
                              : choice != null
                                  ? AppTheme.gold.withValues(alpha: 0.5)
                                  : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: choice != null
                                ? AppTheme.gold.withValues(alpha: 0.2)
                                : AppTheme.cream.withValues(alpha: 0.1),
                            child: choice != null
                                ? const Icon(Icons.check,
                                    color: AppTheme.gold, size: 20)
                                : Text(
                                    player.name[0].toUpperCase(),
                                    style: GoogleFonts.lato(
                                      color: AppTheme.cream,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      player.name + (isMe ? ' (Tu)' : ''),
                                      style: GoogleFonts.lato(
                                        color: AppTheme.cream,
                                        fontWeight:
                                            isMe ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (isDealer) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.gold.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          AppLocalizations.of(context)!.dealer,
                                          style: GoogleFonts.lato(
                                            fontSize: 10,
                                            color: AppTheme.gold,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (choice != null)
                                  Text(
                                    _getChoiceDisplayText(context, choice),
                                    style: GoogleFonts.lato(
                                      color: _getChoiceColor(choice),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (choice == null)
                            Text(
                              AppLocalizations.of(context)!.waiting,
                              style: GoogleFonts.lato(
                                color: AppTheme.cream.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Le mie scelte
          if (myPlayer != null && !hasChosen) ...[
            // Caso speciale: sono forzato a prendere le quote rimanenti
            if (forcedQuotes > 0) ...[
              Card(
                color: Colors.orange.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        AppLocalizations.of(context)!.mustTakeRemainingQuotes,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.allOthersOutOrPaid(forcedQuotes),
                        style: GoogleFonts.lato(
                          color: AppTheme.cream.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _makeChoice(session, hand, 'take$forcedQuotes'),
                        icon: const Icon(Icons.check),
                        label: Text(
                          AppLocalizations.of(context)!.takeQuotesAmount(forcedQuotes, _currencyFormat.format((hand.bestiaPot / 3) * forcedQuotes)),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (availableQuotes <= 0) ...[
              // Tutte le quote sono state prese - posso solo uscire o pagare
              Text(
                AppLocalizations.of(context)!.allQuotesTaken,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.canOnlyExitOrPay,
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Uscire dal gioco
              _buildChoiceButton(
                session,
                hand,
                'out',
                AppLocalizations.of(context)!.exitGame,
                Icons.exit_to_app,
                AppTheme.cream,
                AppLocalizations.of(context)!.dontParticipate,
              ),

              const SizedBox(height: 12),

              // Paga la bestia
              _buildChoiceButton(
                session,
                hand,
                'pay',
                AppLocalizations.of(context)!.payBestia,
                Icons.payments,
                AppTheme.accentRed,
                AppLocalizations.of(context)!.payInNewPot(_currencyFormat.format(hand.bestiaPot)),
              ),
            ] else ...[
              // Caso normale - mostra tutte le opzioni disponibili
              Text(
                AppLocalizations.of(context)!.whatDoYouWant,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Uscire dal gioco
              _buildChoiceButton(
                session,
                hand,
                'out',
                AppLocalizations.of(context)!.exitGame,
                Icons.exit_to_app,
                AppTheme.cream,
                AppLocalizations.of(context)!.dontParticipate,
              ),

              const SizedBox(height: 12),

              // Paga la bestia
              _buildChoiceButton(
                session,
                hand,
                'pay',
                AppLocalizations.of(context)!.payBestia,
                Icons.payments,
                AppTheme.accentRed,
                AppLocalizations.of(context)!.payInNewPot(_currencyFormat.format(hand.bestiaPot)),
              ),

              const SizedBox(height: 12),

              // Prendi quote
              Text(
                availableQuotes < 3 
                    ? AppLocalizations.of(context)!.takeQuotesMax(availableQuotes)
                    : AppLocalizations.of(context)!.orTakeQuotes,
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  for (int i = 1; i <= 3; i++) ...[
                    if (i > 1) const SizedBox(width: 8),
                    Expanded(
                      child: i <= availableQuotes
                          ? _buildQuoteButton(session, hand, i)
                          : _buildDisabledQuoteButton(i),
                    ),
                  ],
                ],
              ),
            ],
          ] else if (hasChosen)
            Card(
              color: AppTheme.gold.withValues(alpha: 0.2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.gold, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      AppLocalizations.of(context)!.youChose,
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      _getChoiceDisplayText(context, myChoice),
                      style: GoogleFonts.playfairDisplay(
                        color: _getChoiceColor(myChoice),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(context)!.waitForOthers,
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Pulsante quota disabilitato (quando le quote non sono disponibili)
  Widget _buildDisabledQuoteButton(int quotes) {
    return OutlinedButton(
      onPressed: null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.cream.withValues(alpha: 0.3),
        side: BorderSide(color: AppTheme.cream.withValues(alpha: 0.2)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$quotes',
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: AppTheme.cream.withValues(alpha: 0.3),
            ),
          ),
          Text(
            quotes == 1 ? 'quota' : 'quote',
            style: GoogleFonts.lato(
              fontSize: 10,
              color: AppTheme.cream.withValues(alpha: 0.3),
            ),
          ),
          Text(
            'N/D',
            style: GoogleFonts.lato(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.cream.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChoiceButton(
    GameSession session,
    ActiveHand hand,
    String choice,
    String label,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      color: AppTheme.darkGreen,
      child: InkWell(
        onTap: () => _makeChoice(session, hand, choice),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.lato(
                        color: color,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: color.withValues(alpha: 0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteButton(GameSession session, ActiveHand hand, int quotes) {
    final quoteValue = hand.bestiaPot / 3;
    final totalValue = quoteValue * quotes;
    
    return OutlinedButton(
      onPressed: () => _makeChoice(session, hand, 'take$quotes'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.green,
        side: const BorderSide(color: Colors.green),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$quotes',
            style: GoogleFonts.playfairDisplay(
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          Text(
            quotes == 1 ? 'quota' : 'quote',
            style: GoogleFonts.lato(fontSize: 10),
          ),
          Text(
            _currencyFormat.format(totalValue),
            style: GoogleFonts.lato(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalizeRoundView(GameSession session, ActiveHand hand, bool isAdmin) {
    final payingPlayers = hand.bestiaPayingPlayers;
    final willContinue = payingPlayers.isNotEmpty;
    
    // Il piatto corrente viene SEMPRE distribuito ai vincitori
    final currentPot = hand.bestiaPot;
    final quoteValue = currentPot / 3;
    
    // Il nuovo piatto = somma di chi paga la bestia (ognuno paga il valore del piatto corrente)
    final projectedNewPot = currentPot * payingPlayers.length;
    
    // Validazione: le quote totali devono essere esattamente 3
    final totalQuotesTaken = _getTotalQuotesTaken(hand);
    final hasValidQuotes = totalQuotesTaken == 3;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Errore: quote non valide
          if (!hasValidQuotes) ...[
            Card(
              color: AppTheme.accentRed.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 50),
                    const SizedBox(height: 12),
                    Text(
                      'Errore nelle scelte!',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentRed,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Le quote assegnate sono $totalQuotesTaken su 3.\nDevono essere esattamente 3 quote.',
                      style: GoogleFonts.lato(
                        color: AppTheme.cream,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (isAdmin)
                      ElevatedButton.icon(
                        onPressed: () => _showResetChoicesDialog(session, hand),
                        icon: const Icon(Icons.edit),
                        label: Text(AppLocalizations.of(context)!.modifyChoices),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ).animate().fadeIn(duration: 300.ms).shake(),
            const SizedBox(height: 16),
          ],
          
          // Riepilogo
          Card(
            color: !hasValidQuotes 
                ? AppTheme.cream.withValues(alpha: 0.1)
                : willContinue 
                    ? AppTheme.accentRed.withValues(alpha: 0.15)
                    : AppTheme.gold.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    !hasValidQuotes ? '⚠️' : (willContinue ? '🔥' : '🏆'), 
                    style: const TextStyle(fontSize: 40),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !hasValidQuotes 
                        ? AppLocalizations.of(context)!.choicesToFix
                        : willContinue 
                            ? AppLocalizations.of(context)!.bestiaContinues
                            : AppLocalizations.of(context)!.bestiaFallen,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: !hasValidQuotes 
                          ? Colors.orange 
                          : willContinue ? AppTheme.accentRed : AppTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Piatto corrente distribuito ai vincitori
                  Text(
                    AppLocalizations.of(context)!.potDistributed(_currencyFormat.format(currentPot)),
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    AppLocalizations.of(context)!.quotesOf(_currencyFormat.format(quoteValue)),
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (hasValidQuotes && willContinue) ...[
                    const Divider(color: AppTheme.cream, height: 20),
                    Text(
                      AppLocalizations.of(context)!.playersPayBestia(payingPlayers.length),
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)!.eachPayment(_currencyFormat.format(currentPot)),
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)!.newPot(_currencyFormat.format(projectedNewPot)),
                      style: GoogleFonts.lato(
                        color: AppTheme.accentRed,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 16),

          // Riepilogo scelte
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.choicesSummary,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...hand.playerOrder.map((playerId) {
                    final player = _getPlayerById(session, playerId);
                    final choice = hand.bestiaPlayerChoice[playerId] ?? 'out';
                    final isDealer = playerId == hand.bestiaDealerId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _getChoiceColor(choice).withValues(alpha: 0.2),
                            child: Text(
                              player.name[0].toUpperCase(),
                              style: GoogleFonts.lato(
                                color: _getChoiceColor(choice),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  player.name,
                                  style: GoogleFonts.lato(color: AppTheme.cream),
                                ),
                                if (isDealer) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.gold.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)!.dealer,
                                      style: GoogleFonts.lato(
                                        fontSize: 10,
                                        color: AppTheme.gold,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getChoiceColor(choice).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  _getChoiceDisplayText(context, choice),
                                  style: GoogleFonts.lato(
                                    color: _getChoiceColor(choice),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              // Mostra importo
                              if (choice == 'pay')
                                Text(
                                  '-${_currencyFormat.format(currentPot)}',
                                  style: GoogleFonts.lato(
                                    color: AppTheme.accentRed,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              else if (choice.startsWith('take'))
                                Text(
                                  '+${_currencyFormat.format(quoteValue * int.parse(choice.substring(4)))}',
                                  style: GoogleFonts.lato(
                                    color: Colors.green,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (isAdmin) ...[
            // Pulsante modifica scelte (sempre visibile per admin)
            if (hasValidQuotes)
              OutlinedButton.icon(
                onPressed: () => _showResetChoicesDialog(session, hand),
                icon: const Icon(Icons.edit, size: 18),
                label: Text(AppLocalizations.of(context)!.modifyChoices),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                  side: const BorderSide(color: Colors.orange),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            const SizedBox(height: 12),
            // Pulsante conferma (disabilitato se le quote non sono valide)
            ElevatedButton.icon(
              onPressed: hasValidQuotes ? () => _finalizeRound(session, hand) : null,
              icon: Icon(
                !hasValidQuotes 
                    ? Icons.block 
                    : willContinue ? Icons.replay : Icons.check_circle,
              ),
              label: Text(
                !hasValidQuotes 
                    ? AppLocalizations.of(context)!.fixChoicesBeforeConfirm
                    : willContinue 
                        ? AppLocalizations.of(context)!.confirmAndContinue
                        : AppLocalizations.of(context)!.confirmAndCloseBestia,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: !hasValidQuotes 
                    ? AppTheme.cream.withValues(alpha: 0.3)
                    : willContinue ? AppTheme.accentRed : AppTheme.gold,
                foregroundColor: !hasValidQuotes 
                    ? AppTheme.cream.withValues(alpha: 0.5)
                    : willContinue ? AppTheme.cream : AppTheme.darkGreen,
              ),
            ),
          ] else
            Card(
              color: Colors.blue.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_empty, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.waitAdminConfirm,
                      style: GoogleFonts.lato(color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getChoiceDisplayText(BuildContext context, String choice) {
    final l10n = AppLocalizations.of(context)!;
    switch (choice) {
      case 'out':
        return l10n.exits;
      case 'pay':
        return l10n.paysBestia;
      case 'take1':
        return l10n.takes1Quote;
      case 'take2':
        return l10n.takes2Quotes;
      case 'take3':
        return l10n.takes3Quotes;
      default:
        return choice;
    }
  }

  Color _getChoiceColor(String choice) {
    switch (choice) {
      case 'out':
        return AppTheme.cream.withValues(alpha: 0.7);
      case 'pay':
        return AppTheme.accentRed;
      case 'take1':
      case 'take2':
      case 'take3':
        return Colors.green;
      default:
        return AppTheme.cream;
    }
  }

  void _showResetChoicesDialog(GameSession session, ActiveHand hand) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Row(
          children: [
            const Icon(Icons.edit, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.modifyChoices,
                style: GoogleFonts.playfairDisplay(color: Colors.orange),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.selectPlayerToResetChoice,
                style: GoogleFonts.lato(color: AppTheme.cream),
              ),
              const SizedBox(height: 16),
              ...hand.bestiaPlayerChoice.entries.map((entry) {
                final player = _getPlayerById(session, entry.key);
                final choice = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
                    ),
                    tileColor: AppTheme.darkGreen.withValues(alpha: 0.5),
                    leading: CircleAvatar(
                      backgroundColor: _getChoiceColor(choice).withValues(alpha: 0.2),
                      child: Text(
                        player.name[0].toUpperCase(),
                        style: GoogleFonts.lato(
                          color: _getChoiceColor(choice),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      player.name,
                      style: GoogleFonts.lato(color: AppTheme.cream),
                    ),
                    subtitle: Text(
                      _getChoiceDisplayText(context, choice),
                      style: GoogleFonts.lato(
                        color: _getChoiceColor(choice),
                        fontSize: 12,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.undo, color: Colors.orange),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _resetPlayerChoice(session, hand, entry.key);
                      },
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.close, style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
        ],
      ),
    );
  }

  void _showCancelHandDialog(GameSession session, ActiveHand hand) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.accentRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.cancelHandQuestion,
                style: GoogleFonts.playfairDisplay(color: AppTheme.accentRed),
              ),
            ),
          ],
        ),
        content: Text(
          l10n.cancelHandWarning,
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text(l10n.noKeepIt, style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _cancelHand(session, hand);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            child: Text(l10n.yesCancelHand),
          ),
        ],
      ),
    );
  }
}

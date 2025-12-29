import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../models/game_mode.dart';
import '../models/game_hand.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Schermata per gestire una partita a Bestia
class BestiaScreen extends StatefulWidget {
  final String sessionId;

  const BestiaScreen({super.key, required this.sessionId});

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

  /// Avvia una nuova mano di Bestia
  Future<void> _startNewHand(GameSession session) async {
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
      variantId: session.gameMode.variantId,
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
        const SnackBar(
          content: Text('La quota deve essere maggiore di 0!'),
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
        const SnackBar(
          content: Text('Mano annullata! Tutti i movimenti sono stati rimossi.'),
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
                      'Sessione non trovata',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        color: AppTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Torna indietro'),
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
            title: const Row(
              children: [
                Text('🦁', style: TextStyle(fontSize: 24)),
                SizedBox(width: 8),
                Text('Bestia'),
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
                      'Piatto: ${_currencyFormat.format(hand.bestiaPot)}',
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
                  tooltip: 'Annulla Mano',
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
        title: const Row(
          children: [
            Text('🦁', style: TextStyle(fontSize: 24)),
            SizedBox(width: 8),
            Text('Bestia'),
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
                  'Pronto per giocare?',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                const SizedBox(height: 12),
                Text(
                  isAdmin
                      ? 'Inizia una nuova mano quando tutti sono pronti'
                      : 'Aspetta che l\'admin inizi la mano...',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 8),
                Text(
                  'Modalità: ${session.gameMode.variantDisplayName ?? "Standard"}',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppTheme.gold.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ).animate().fadeIn(delay: 500.ms, duration: 400.ms),
                const SizedBox(height: 32),
                if (isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _startNewHand(session),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Inizia Mano'),
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
                'In attesa dell\'admin',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 12),
              Text(
                'L\'amministratore sta impostando l\'ordine dei giocatori...',
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
              'Ordine dei Giocatori',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              'Trascina i giocatori per impostare l\'ordine del mazzo.\nIl primo sarà il mazziere iniziale.',
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
                          'Ordine di gioco',
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
                                          'Mazziere',
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
              label: const Text('Conferma Ordine'),
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
                'In attesa dell\'admin',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 12),
              Text(
                'L\'amministratore sta impostando la quota del mazziere...',
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
              'Imposta la Quota',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              'Quanto deve essere la puntata del mazziere?',
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
                              const SnackBar(
                                content: Text(
                                    'Inserisci un importo valido maggiore di 0'),
                                backgroundColor: AppTheme.accentRed,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Conferma Quota'),
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
              isDealer ? 'Sei tu il mazziere!' : 'Mazziere: ${dealerPlayer?.name ?? "..."}',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              isDealer 
                  ? 'Devi mettere ${_currencyFormat.format(hand.bestiaBaseValue)} nel piatto.'
                  : 'Attendi che ${dealerPlayer?.name ?? "il mazziere"} metta la quota...',
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
                label: Text('Paga ${_currencyFormat.format(hand.bestiaBaseValue)}'),
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
              'Gioca il round!',
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
                  const TextSpan(text: 'Mazziere: '),
                  TextSpan(
                    text: dealerPlayer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                  const TextSpan(text: '\nOra giocate le carte!'),
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
                'Piatto: ${_currencyFormat.format(hand.bestiaPot)}',
                style: GoogleFonts.lato(
                  color: AppTheme.gold,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              'La Bestia continua finché non viene vinta!',
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
                label: const Text('Round giocato! Vai alle scelte'),
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

  Widget _buildChoicePhaseView(
      GameSession session, ActiveHand hand, bool isAdmin) {
    final myPlayer = _getCurrentUserPlayer(session);
    final myChoice =
        myPlayer != null ? hand.bestiaPlayerChoice[myPlayer.id] : null;
    final hasChosen = myChoice != null;

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
                    'Piatto attuale',
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
                  // Visualizzazione delle 3 quote
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.darkGreen.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _currencyFormat.format(hand.bestiaPot / 3),
                            style: GoogleFonts.lato(
                              color: AppTheme.gold,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '3 quote da vincere',
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quota mazziere: ${_currencyFormat.format(hand.bestiaBaseValue)}',
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
                  Text(
                    'Scelte dei giocatori',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
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
                                          'Mazziere',
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
                                    _getChoiceDisplayText(choice),
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
                              'In attesa',
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
            Text(
              'Cosa vuoi fare?',
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
              'Esco dal gioco',
              Icons.exit_to_app,
              AppTheme.cream,
              'Non partecipi alla distribuzione',
            ),

            const SizedBox(height: 12),

            // Paga la bestia
            _buildChoiceButton(
              session,
              hand,
              'pay',
              'Pago la Bestia',
              Icons.payments,
              AppTheme.accentRed,
              'Paghi ${_currencyFormat.format(hand.bestiaPot)} nel nuovo piatto',
            ),

            const SizedBox(height: 12),

            // Prendi quote
            Text(
              'Oppure prendi delle quote:',
              style: GoogleFonts.lato(
                color: AppTheme.cream.withValues(alpha: 0.7),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _buildQuoteButton(session, hand, 1),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuoteButton(session, hand, 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuoteButton(session, hand, 3),
                ),
              ],
            ),
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
                      'Hai scelto:',
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                      ),
                    ),
                    Text(
                      _getChoiceDisplayText(myChoice),
                      style: GoogleFonts.playfairDisplay(
                        color: _getChoiceColor(myChoice),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Attendi che tutti scelgano...',
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Riepilogo
          Card(
            color: willContinue 
                ? AppTheme.accentRed.withValues(alpha: 0.15)
                : AppTheme.gold.withValues(alpha: 0.15),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(willContinue ? '🔥' : '🏆', style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(
                    willContinue 
                        ? 'La Bestia continua!' 
                        : 'La Bestia è caduta!',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: willContinue ? AppTheme.accentRed : AppTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Piatto corrente distribuito ai vincitori
                  Text(
                    'Piatto distribuito: ${_currencyFormat.format(currentPot)}',
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '(3 quote da ${_currencyFormat.format(quoteValue)})',
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (willContinue) ...[
                    const Divider(color: AppTheme.cream, height: 20),
                    Text(
                      '${payingPlayers.length} ${payingPlayers.length == 1 ? "giocatore paga" : "giocatori pagano"} la Bestia',
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Ogni pagamento: ${_currencyFormat.format(currentPot)}',
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Nuovo piatto: ${_currencyFormat.format(projectedNewPot)} + quota mazziere',
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
                    'Riepilogo scelte',
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
                                      'Mazziere',
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
                                  _getChoiceDisplayText(choice),
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

          if (isAdmin)
            ElevatedButton.icon(
              onPressed: () => _finalizeRound(session, hand),
              icon: Icon(willContinue ? Icons.replay : Icons.check_circle),
              label: Text(willContinue 
                  ? 'Conferma e Continua' 
                  : 'Conferma e Chiudi Bestia'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: willContinue ? AppTheme.accentRed : AppTheme.gold,
                foregroundColor: willContinue ? AppTheme.cream : AppTheme.darkGreen,
              ),
            )
          else
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
                      'Attendi che l\'admin confermi...',
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

  String _getChoiceDisplayText(String choice) {
    switch (choice) {
      case 'out':
        return 'Esce';
      case 'pay':
        return 'Paga la Bestia';
      case 'take1':
        return 'Prende 1 quota';
      case 'take2':
        return 'Prende 2 quote';
      case 'take3':
        return 'Prende 3 quote';
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

  void _showCancelHandDialog(GameSession session, ActiveHand hand) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.accentRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Annullare la mano?',
                style: GoogleFonts.playfairDisplay(color: AppTheme.accentRed),
              ),
            ),
          ],
        ),
        content: Text(
          'Questa azione annullerà la mano corrente e TUTTI i movimenti economici effettuati durante questa mano verranno eliminati.\n\nLa situazione economica tornerà allo stato precedente.',
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text('No, mantieni', style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelHand(session, hand);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            child: const Text('Sì, annulla mano'),
          ),
        ],
      ),
    );
  }
}

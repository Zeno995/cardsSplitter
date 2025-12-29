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
import 'sette_e_mezzo_screen.dart';
import 'trentuno_cucu_screen.dart';
import 'bestia_screen.dart';

class PlayHandScreen extends StatefulWidget {
  final String sessionId;

  const PlayHandScreen({super.key, required this.sessionId});

  @override
  State<PlayHandScreen> createState() => _PlayHandScreenState();
}

class _PlayHandScreenState extends State<PlayHandScreen> {
  final _uuid = const Uuid();
  final _betAmountController = TextEditingController();

  @override
  void dispose() {
    _betAmountController.dispose();
    super.dispose();
  }

  String? get _currentUserId => context.read<AuthService>().currentUser?.uid;

  List<BetPhaseConfig> _getPhases(GameType type) => GameBetPhases.getPhases(type);
  List<WinnerTypeConfig> _getWinnerTypes(GameType type) => GameBetPhases.getWinnerTypes(type);

  Future<void> _startNewHand(GameSession session) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    final playerOrder = session.players.map((p) => p.id).toList();
    final playerStatus = <String, String>{};
    final currentPhaseBets = <String, double>{};
    
    for (final playerId in playerOrder) {
      playerStatus[playerId] = 'waiting';
      currentPhaseBets[playerId] = 0;
    }

    final hand = ActiveHand(
      id: _uuid.v4(),
      gameType: session.gameMode.type,
      createdAt: DateTime.now(),
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      currentPhaseIndex: 0,
      playerOrder: playerOrder,
      playerStatus: playerStatus,
      currentPhaseBets: currentPhaseBets,
      currentPlayerTurnIndex: 0,
      currentBetToMatch: 0,
      completedBets: [],
    );

    await dbService.startActiveHand(sessionId: session.id, hand: hand);
  }

  Future<void> _playerAction(
    GameSession session,
    ActiveHand hand,
    PlayerAction action, {
    double? amount,
    String? forPlayerId,
  }) async {
    final dbService = context.read<DatabaseService>();
    
    final playerId = forPlayerId ?? hand.currentTurnPlayerId;
    if (playerId == null) return;

    final newPlayerStatus = Map<String, String>.from(hand.playerStatus);
    final newCurrentPhaseBets = Map<String, double>.from(hand.currentPhaseBets);
    var newCurrentBetToMatch = hand.currentBetToMatch;

    switch (action) {
      case PlayerAction.fold:
        newPlayerStatus[playerId] = 'folded';
        break;
      
      case PlayerAction.check:
        newPlayerStatus[playerId] = 'checked';
        break;
      
      case PlayerAction.call:
        final toCall = hand.currentBetToMatch - (hand.currentPhaseBets[playerId] ?? 0);
        newCurrentPhaseBets[playerId] = (hand.currentPhaseBets[playerId] ?? 0) + toCall;
        newPlayerStatus[playerId] = 'called';
        break;
      
      case PlayerAction.raise:
        if (amount != null && amount > hand.currentBetToMatch) {
          newCurrentPhaseBets[playerId] = amount;
          newCurrentBetToMatch = amount;
          newPlayerStatus[playerId] = 'raised';
          // Resetta gli altri giocatori che devono rispondere al rilancio
          for (final id in hand.activePlayerIds) {
            if (id != playerId) {
              final status = newPlayerStatus[id];
              if (status == 'called' || status == 'checked') {
                newPlayerStatus[id] = 'waiting';
              }
            }
          }
        }
        break;
      
      case PlayerAction.bet:
        if (amount != null && amount > 0) {
          newCurrentPhaseBets[playerId] = amount;
          newCurrentBetToMatch = amount;
          newPlayerStatus[playerId] = 'raised';
        }
        break;
    }

    // Trova il prossimo giocatore
    final activeIds = hand.playerOrder.where((id) => 
      newPlayerStatus[id] != 'folded'
    ).toList();
    
    // Controlla se tutti hanno agito e sono allineati
    bool allActed = true;
    bool allMatched = true;
    
    for (final id in activeIds) {
      final status = newPlayerStatus[id];
      if (status == 'waiting') {
        allActed = false;
      }
      final bet = newCurrentPhaseBets[id] ?? 0;
      if (bet < newCurrentBetToMatch) {
        allMatched = false;
      }
    }

    ActiveHand newHand;
    
    if (allActed && allMatched) {
      // Fase completata - salva la puntata e passa alla prossima fase
      final phases = _getPhases(hand.gameType);
      final currentPhase = phases.isNotEmpty && hand.currentPhaseIndex < phases.length
          ? phases[hand.currentPhaseIndex]
          : null;
      
      final newBet = HandBet(
        id: _uuid.v4(),
        phase: currentPhase?.id ?? 'unknown',
        amounts: newCurrentPhaseBets,
        createdAt: DateTime.now(),
      );
      
      // Reset per la nuova fase
      final resetStatus = <String, String>{};
      final resetBets = <String, double>{};
      for (final id in hand.playerOrder) {
        if (newPlayerStatus[id] != 'folded') {
          resetStatus[id] = 'waiting';
          resetBets[id] = 0;
        } else {
          resetStatus[id] = 'folded';
        }
      }
      
      newHand = hand.copyWith(
        currentPhaseIndex: hand.currentPhaseIndex + 1,
        playerStatus: resetStatus,
        currentPhaseBets: resetBets,
        currentPlayerTurnIndex: 0,
        currentBetToMatch: 0,
        completedBets: [...hand.completedBets, newBet],
      );
    } else {
      // Trova il prossimo giocatore che deve agire
      int nextIndex = (hand.currentPlayerTurnIndex + 1) % activeIds.length;
      int attempts = 0;
      
      while (attempts < activeIds.length) {
        final nextId = activeIds[nextIndex];
        final status = newPlayerStatus[nextId];
        final bet = newCurrentPhaseBets[nextId] ?? 0;
        
        if (status == 'waiting' || 
            (bet < newCurrentBetToMatch && status != 'called' && status != 'raised')) {
          break;
        }
        
        nextIndex = (nextIndex + 1) % activeIds.length;
        attempts++;
      }
      
      newHand = hand.copyWith(
        playerStatus: newPlayerStatus,
        currentPhaseBets: newCurrentPhaseBets,
        currentPlayerTurnIndex: nextIndex,
        currentBetToMatch: newCurrentBetToMatch,
      );
    }

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    _betAmountController.clear();
  }

  Future<void> _updatePlayerOrder(GameSession session, ActiveHand hand, List<String> newOrder) async {
    final dbService = context.read<DatabaseService>();
    final newHand = hand.copyWith(playerOrder: newOrder);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  Future<void> _completeHand(GameSession session, ActiveHand hand, List<HandWinner> winners) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    final createdBy = authService.currentUser?.uid ?? 'anonymous';

    final playerBets = hand.totalPlayerBets;

    for (final winner in winners) {
      if (winner.playerIds.isEmpty) continue;
      
      final amountPerWinner = winner.amountPerWinner;
      
      for (final winnerId in winner.playerIds) {
        for (final entry in playerBets.entries) {
          if (entry.key == winnerId) continue;
          
          final totalBets = playerBets.values.fold(0.0, (a, b) => a + b);
          if (totalBets == 0) continue;
          
          final playerShare = entry.value / totalBets;
          final amountToPay = amountPerWinner * playerShare;
          
          if (amountToPay > 0) {
            await dbService.addMovement(
              sessionId: session.id,
              fromPlayerId: entry.key,
              toPlayerId: winnerId,
              amount: amountToPay,
              description: _getWinnerDescription(hand.gameType, winner),
              createdBy: createdBy,
              handId: hand.id,
            );
          }
        }
      }
    }

    await dbService.endActiveHand(sessionId: session.id);
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mano completata!'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    }
  }

  /// Annulla la mano corrente e tutti i suoi movimenti (solo admin)
  Future<void> _cancelHand(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    
    // Annulla tutti i movimenti associati a questa mano
    await dbService.cancelHandMovements(
      sessionId: session.id,
      handId: hand.id,
    );
    
    // Termina la mano
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

  String _getWinnerDescription(GameType gameType, HandWinner winner) {
    final gameMode = GameMode(type: gameType);
    switch (winner.type) {
      case WinnerType.lasVegasHigh:
        return '${gameMode.displayName} - Punteggio Alto';
      case WinnerType.lasVegasLow:
        return '${gameMode.displayName} - Punteggio Basso';
      case WinnerType.lasVegasFull:
        return '${gameMode.displayName} - Las Vegas!';
      case WinnerType.setteEMezzoReale:
        return '${gameMode.displayName} - Sette e Mezzo Reale';
      case WinnerType.trentuno31:
        return '${gameMode.displayName} - Trentuno!';
      case WinnerType.cucuLoser:
        return '${gameMode.displayName} - Perdente';
      case WinnerType.bestiaPay:
        return '${gameMode.displayName} - In Bestia';
      default:
        return '${gameMode.displayName} - Vincita';
    }
  }

  bool _isAdmin(GameSession session) => session.adminId == _currentUserId;

  Player? _getCurrentUserPlayer(GameSession session) {
    try {
      return session.players.firstWhere((p) => p.userId == _currentUserId);
    } catch (_) {
      return null;
    }
  }

  bool _isMyTurn(GameSession session, ActiveHand hand) {
    final currentPlayerId = hand.currentTurnPlayerId;
    if (currentPlayerId == null) return false;
    final myPlayer = _getCurrentUserPlayer(session);
    return myPlayer?.id == currentPlayerId;
  }

  Player _getPlayerById(GameSession session, String id) {
    return session.players.firstWhere((p) => p.id == id);
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
                    const Icon(Icons.error_outline, size: 60, color: AppTheme.accentRed),
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

        // Redirect a schermate specifiche per giochi con logica custom
        if (session.gameMode.type == GameType.setteEMezzo) {
          return SetteEMezzoScreen(sessionId: widget.sessionId);
        }

        // Redirect per giochi con vite (31 e Cucù)
        if (session.gameMode.type == GameType.trentuno ||
            session.gameMode.type == GameType.cucu) {
          return TrentunoCucuScreen(sessionId: widget.sessionId);
        }

        // Redirect per Bestia
        if (session.gameMode.type == GameType.bestia) {
          return BestiaScreen(sessionId: widget.sessionId);
        }

        final hand = session.activeHand;
        final gameMode = session.gameMode;
        final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
        final isAdmin = _isAdmin(session);

        // Se non c'è una mano attiva, mostra l'opzione per iniziarne una
        if (hand == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text('${gameMode.icon} ${gameMode.displayName}'),
            ),
            body: ChristmasBackground(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        gameMode.icon,
                        style: const TextStyle(fontSize: 60),
                      ).animate()
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
                      ).animate()
                        .fadeIn(delay: 200.ms, duration: 400.ms),
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
                      ).animate()
                        .fadeIn(delay: 400.ms, duration: 400.ms),
                      const SizedBox(height: 32),
                      if (isAdmin)
                        ElevatedButton.icon(
                          onPressed: () => _startNewHand(session),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Inizia Mano'),
                        ).animate()
                          .fadeIn(delay: 600.ms, duration: 400.ms),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Mano attiva - mostra l'interfaccia di gioco
        final phases = _getPhases(hand.gameType);
        final isPokerStyle = hand.gameType == GameType.lasVegas;

        return Scaffold(
          appBar: AppBar(
            title: Text('${gameMode.icon} ${gameMode.displayName}'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Piatto: ${currencyFormat.format(hand.totalPot)}',
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
                  onPressed: () => _showCancelHandDialog(session, hand),
                  icon: const Icon(Icons.undo, color: AppTheme.accentRed),
                  tooltip: 'Annulla Mano',
                ),
                IconButton(
                  onPressed: () => _showAdminPanel(session, hand),
                  icon: const Icon(Icons.admin_panel_settings),
                  tooltip: 'Pannello Admin',
                ),
              ],
            ],
          ),
          body: ChristmasBackground(
            child: phases.isEmpty
                ? _buildFreeMode()
                : isPokerStyle
                    ? _buildPokerStyleView(session, hand, phases)
                    : _buildSimplePhase(session, hand, phases),
          ),
        );
      },
    );
  }

  Widget _buildFreeMode() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🎴', style: TextStyle(fontSize: 60))
              .animate()
              .fadeIn(duration: 400.ms)
              .scale(),
            const SizedBox(height: 24),
            Text(
              'Modalità Libera',
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate()
              .fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              'In questa modalità, usa il pulsante "Movimento" per registrare manualmente chi paga e chi riceve.',
              style: GoogleFonts.lato(
                fontSize: 16,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate()
              .fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Torna alla sessione'),
            ).animate()
              .fadeIn(delay: 600.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  Widget _buildPokerStyleView(GameSession session, ActiveHand hand, List<BetPhaseConfig> phases) {
    // Controlla se siamo oltre le fasi (assegnazione vincitori)
    if (hand.currentPhaseIndex >= phases.length) {
      return _buildAssignWinners(session, hand);
    }

    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    final currentPhase = phases[hand.currentPhaseIndex];
    final currentTurnPlayerId = hand.currentTurnPlayerId;
    final currentTurnPlayer = currentTurnPlayerId != null 
        ? _getPlayerById(session, currentTurnPlayerId) 
        : null;
    final myPlayer = _getCurrentUserPlayer(session);
    final isMyTurn = _isMyTurn(session, hand);
    final isAdmin = _isAdmin(session);
    
    final myBet = myPlayer != null ? (hand.currentPhaseBets[myPlayer.id] ?? 0) : 0.0;
    final toCall = hand.currentBetToMatch - myBet;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header fase
          Card(
            color: AppTheme.gold.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.accentRed,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Fase ${hand.currentPhaseIndex + 1}/${phases.length}',
                          style: GoogleFonts.lato(
                            color: AppTheme.cream,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentPhase.name,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                  if (hand.currentBetToMatch > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Puntata da vedere: ${currencyFormat.format(hand.currentBetToMatch)}',
                      style: GoogleFonts.lato(
                        color: AppTheme.cream.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ).animate()
            .fadeIn(duration: 400.ms),
          
          const SizedBox(height: 16),
          
          // Stato giocatori
          _buildPlayersStatus(session, hand, currencyFormat),
          
          const SizedBox(height: 24),
          
          // Chi sta giocando ora
          if (currentTurnPlayer != null) ...[
            Card(
              color: isMyTurn 
                  ? AppTheme.gold.withValues(alpha: 0.2)
                  : AppTheme.primaryGreen.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      isMyTurn ? 'Tocca a te!' : 'Tocca a:',
                      style: GoogleFonts.lato(
                        color: isMyTurn ? AppTheme.gold : AppTheme.cream.withValues(alpha: 0.7),
                        fontSize: isMyTurn ? 18 : 14,
                        fontWeight: isMyTurn ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentTurnPlayer.name,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: isMyTurn ? AppTheme.gold : AppTheme.cream,
                      ),
                    ),
                    
                    if (isMyTurn) ...[
                      const SizedBox(height: 24),
                      _buildMyActions(session, hand, toCall),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(
                        'Aspetta il tuo turno...',
                        style: GoogleFonts.lato(
                          color: AppTheme.cream.withValues(alpha: 0.5),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ).animate()
              .fadeIn(duration: 300.ms)
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1)),
          ],
          
          const SizedBox(height: 24),
          
          // Il mio stato (se non sono io a giocare)
          if (!isMyTurn && myPlayer != null) ...[
            _buildMyStatus(session, hand, myPlayer),
          ],
          
          // Admin: termina anticipatamente
          if (isAdmin && session.gameMode.type == GameType.lasVegas)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton.icon(
                onPressed: () => _showEndHandDialog(session, hand),
                icon: const Icon(Icons.star, color: AppTheme.gold),
                label: Text(
                  'Qualcuno ha fatto Las Vegas!',
                  style: GoogleFonts.lato(color: AppTheme.gold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayersStatus(GameSession session, ActiveHand hand, NumberFormat currencyFormat) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Giocatori',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ),
                const Spacer(),
                Text(
                  'Fase: ${currencyFormat.format(hand.currentPhaseBets.values.fold(0.0, (a, b) => a + b))}',
                  style: GoogleFonts.lato(
                    fontSize: 12,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hand.playerOrder.map((playerId) {
                final player = _getPlayerById(session, playerId);
                final status = hand.playerStatus[playerId] ?? 'waiting';
                final bet = hand.currentPhaseBets[playerId] ?? 0;
                final isCurrentTurn = hand.currentTurnPlayerId == playerId;
                final isMe = player.userId == _currentUserId;
                
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrentTurn 
                        ? AppTheme.gold.withValues(alpha: 0.3)
                        : status == 'folded'
                            ? AppTheme.accentRed.withValues(alpha: 0.2)
                            : AppTheme.darkGreen.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isCurrentTurn 
                          ? AppTheme.gold 
                          : isMe 
                              ? Colors.blue.withValues(alpha: 0.5)
                              : Colors.transparent,
                      width: isCurrentTurn ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        player.name,
                        style: GoogleFonts.lato(
                          color: status == 'folded'
                              ? AppTheme.cream.withValues(alpha: 0.5)
                              : AppTheme.cream,
                          fontWeight: isCurrentTurn || isMe ? FontWeight.bold : FontWeight.normal,
                          decoration: status == 'folded'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (bet > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          currencyFormat.format(bet),
                          style: GoogleFonts.lato(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      _buildStatusIcon(status),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'waiting':
        return const Icon(Icons.hourglass_empty, size: 14, color: AppTheme.cream);
      case 'checked':
        return const Icon(Icons.check, size: 14, color: Colors.blue);
      case 'called':
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case 'raised':
        return const Icon(Icons.arrow_upward, size: 14, color: AppTheme.gold);
      case 'folded':
        return const Icon(Icons.close, size: 14, color: AppTheme.accentRed);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMyActions(GameSession session, ActiveHand hand, double toCall) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _playerAction(session, hand, PlayerAction.fold),
                icon: const Icon(Icons.close, color: AppTheme.accentRed),
                label: Text('Lascia', style: GoogleFonts.lato(color: AppTheme.accentRed)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accentRed),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: toCall > 0
                  ? ElevatedButton.icon(
                      onPressed: () => _playerAction(session, hand, PlayerAction.call),
                      icon: const Icon(Icons.check),
                      label: Text('Vede ${currencyFormat.format(toCall)}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _playerAction(session, hand, PlayerAction.check),
                      icon: const Icon(Icons.check, color: Colors.blue),
                      label: Text('Check', style: GoogleFonts.lato(color: Colors.blue)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _betAmountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: GoogleFonts.lato(
                  color: AppTheme.gold,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: hand.currentBetToMatch > 0 
                      ? 'Min: ${currencyFormat.format(hand.currentBetToMatch + 0.01)}'
                      : 'Importo',
                  hintStyle: GoogleFonts.lato(
                    color: AppTheme.gold.withValues(alpha: 0.3),
                    fontSize: 14,
                  ),
                  prefixText: '€ ',
                  prefixStyle: GoogleFonts.lato(
                    color: AppTheme.gold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () {
                final amount = double.tryParse(
                  _betAmountController.text.replaceAll(',', '.'),
                );
                if (amount != null && amount > hand.currentBetToMatch) {
                  _playerAction(
                    session,
                    hand,
                    hand.currentBetToMatch > 0 ? PlayerAction.raise : PlayerAction.bet,
                    amount: amount,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'L\'importo deve essere maggiore di ${currencyFormat.format(hand.currentBetToMatch)}',
                      ),
                      backgroundColor: AppTheme.accentRed,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.arrow_upward),
              label: Text(hand.currentBetToMatch > 0 ? 'Rilancia' : 'Punta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.gold,
                foregroundColor: AppTheme.darkGreen,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMyStatus(GameSession session, ActiveHand hand, Player myPlayer) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    final status = hand.playerStatus[myPlayer.id] ?? 'waiting';
    final myBet = hand.currentPhaseBets[myPlayer.id] ?? 0;

    return Card(
      color: Colors.blue.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue.withValues(alpha: 0.2),
              child: Text(
                myPlayer.name[0].toUpperCase(),
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tu (${myPlayer.name})',
                    style: GoogleFonts.lato(
                      color: AppTheme.cream,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _getStatusText(status),
                    style: GoogleFonts.lato(
                      color: _getStatusColor(status),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (myBet > 0)
              Text(
                currencyFormat.format(myBet),
                style: GoogleFonts.lato(
                  color: AppTheme.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'waiting':
        return 'In attesa...';
      case 'checked':
        return 'Hai fatto check';
      case 'called':
        return 'Hai visto';
      case 'raised':
        return 'Hai rilanciato';
      case 'folded':
        return 'Hai lasciato';
      default:
        return '';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'waiting':
        return AppTheme.cream.withValues(alpha: 0.7);
      case 'checked':
        return Colors.blue;
      case 'called':
        return Colors.green;
      case 'raised':
        return AppTheme.gold;
      case 'folded':
        return AppTheme.accentRed;
      default:
        return AppTheme.cream;
    }
  }

  Widget _buildSimplePhase(GameSession session, ActiveHand hand, List<BetPhaseConfig> phases) {
    if (hand.currentPhaseIndex >= phases.length) {
      return _buildAssignWinners(session, hand);
    }

    final isAdmin = _isAdmin(session);
    
    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_empty, size: 60, color: AppTheme.gold),
              const SizedBox(height: 24),
              Text(
                'In attesa dell\'admin',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'L\'amministratore sta gestendo le puntate...',
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Admin gestisce le puntate semplici - implementazione simile
    return const Center(child: Text('Modalità semplice - Admin'));
  }

  Widget _buildAssignWinners(GameSession session, ActiveHand hand) {
    final isAdmin = _isAdmin(session);
    
    if (!isAdmin) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.emoji_events, size: 60, color: AppTheme.gold),
              const SizedBox(height: 24),
              Text(
                'Mano terminata!',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'L\'amministratore sta assegnando i vincitori...',
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return _EndHandSheet(
      session: session,
      hand: hand,
      winnerTypes: _getWinnerTypes(hand.gameType),
      onComplete: (winners) => _completeHand(session, hand, winners),
      isFullScreen: true,
    );
  }

  void _showAdminPanel(GameSession session, ActiveHand hand) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryGreen,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AdminPanelSheet(
        session: session,
        hand: hand,
        onReorder: (newOrder) {
          _updatePlayerOrder(session, hand, newOrder);
          Navigator.pop(context);
        },
        onPlayerAction: (playerId, action, amount) {
          _playerAction(session, hand, action, amount: amount, forPlayerId: playerId);
          Navigator.pop(context);
        },
        onSkipToWinners: () {
          Navigator.pop(context);
          _showEndHandDialog(session, hand);
        },
      ),
    );
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
            child: Text('No, mantieni', style: GoogleFonts.lato(color: AppTheme.cream)),
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

  void _showEndHandDialog(GameSession session, ActiveHand hand) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.primaryGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _EndHandSheet(
        session: session,
        hand: hand,
        winnerTypes: _getWinnerTypes(hand.gameType),
        onComplete: (winners) => _completeHand(session, hand, winners),
      ),
    );
  }
}

// Enum per le azioni del giocatore
enum PlayerAction {
  fold,
  check,
  call,
  raise,
  bet,
}

// Pannello Admin
class _AdminPanelSheet extends StatefulWidget {
  final GameSession session;
  final ActiveHand hand;
  final Function(List<String>) onReorder;
  final Function(String, PlayerAction, double?) onPlayerAction;
  final VoidCallback onSkipToWinners;

  const _AdminPanelSheet({
    required this.session,
    required this.hand,
    required this.onReorder,
    required this.onPlayerAction,
    required this.onSkipToWinners,
  });

  @override
  State<_AdminPanelSheet> createState() => _AdminPanelSheetState();
}

class _AdminPanelSheetState extends State<_AdminPanelSheet> {
  late List<String> _order;
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.hand.playerOrder);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Player _getPlayerById(String id) {
    return widget.session.players.firstWhere((p) => p.id == id);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.cream.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            Text(
              'Pannello Admin',
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 24),
            
            // Ordine giocatori
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.swap_vert, color: AppTheme.gold),
                        const SizedBox(width: 8),
                        Text(
                          'Ordine Giocatori',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _order.length,
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (newIndex > oldIndex) newIndex--;
                          final item = _order.removeAt(oldIndex);
                          _order.insert(newIndex, item);
                        });
                      },
                      itemBuilder: (context, index) {
                        final player = _getPlayerById(_order[index]);
                        final status = widget.hand.playerStatus[player.id];
                        final isCurrentTurn = widget.hand.currentTurnPlayerId == player.id;
                        
                        return Container(
                          key: ValueKey(player.id),
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isCurrentTurn ? AppTheme.gold.withValues(alpha: 0.2) : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: AppTheme.gold.withValues(alpha: 0.2),
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.lato(
                                  color: AppTheme.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              player.name,
                              style: GoogleFonts.lato(
                                color: status == 'folded'
                                    ? AppTheme.cream.withValues(alpha: 0.5)
                                    : AppTheme.cream,
                                decoration: status == 'folded'
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            trailing: const Icon(Icons.drag_handle, color: AppTheme.cream),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => widget.onReorder(_order),
                      child: const Text('Applica Ordine'),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Salta ai vincitori
            Card(
              color: AppTheme.accentRed.withValues(alpha: 0.2),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: AppTheme.gold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Termina Mano',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: widget.onSkipToWinners,
                      icon: const Icon(Icons.emoji_events),
                      label: const Text('Assegna Vincitori'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: AppTheme.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sheet per assegnare i vincitori
class _EndHandSheet extends StatefulWidget {
  final GameSession session;
  final ActiveHand hand;
  final List<WinnerTypeConfig> winnerTypes;
  final Function(List<HandWinner>) onComplete;
  final bool isFullScreen;

  const _EndHandSheet({
    required this.session,
    required this.hand,
    required this.winnerTypes,
    required this.onComplete,
    this.isFullScreen = false,
  });

  @override
  State<_EndHandSheet> createState() => _EndHandSheetState();
}

class _EndHandSheetState extends State<_EndHandSheet> {
  final _uuid = const Uuid();
  final Map<WinnerType, List<String>> _selectedWinners = {};
  final Map<WinnerType, TextEditingController> _amountControllers = {};
  bool _isLoading = false;

  List<Player> get _activePlayers => widget.session.players
      .where((p) => widget.hand.playerStatus[p.id] != 'folded')
      .toList();

  @override
  void initState() {
    super.initState();
    for (final config in widget.winnerTypes) {
      _selectedWinners[config.type] = [];
      _amountControllers[config.type] = TextEditingController();
      
      if (config.type == WinnerType.lasVegasHigh || 
          config.type == WinnerType.lasVegasLow) {
        _amountControllers[config.type]!.text = 
            (widget.hand.totalPot / 2).toStringAsFixed(2);
      } else if (config.type == WinnerType.lasVegasFull) {
        _amountControllers[config.type]!.text = 
            widget.hand.totalPot.toStringAsFixed(2);
      } else {
        _amountControllers[config.type]!.text = 
            widget.hand.totalPot.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _amountControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _togglePlayer(WinnerType type, String playerId) {
    setState(() {
      final list = _selectedWinners[type]!;
      final config = widget.winnerTypes.firstWhere((c) => c.type == type);
      
      if (list.contains(playerId)) {
        list.remove(playerId);
      } else {
        if (!config.allowMultiple) {
          list.clear();
        }
        list.add(playerId);
      }
    });
  }

  void _confirm() {
    setState(() => _isLoading = true);
    
    final winners = <HandWinner>[];
    
    for (final config in widget.winnerTypes) {
      final playerIds = _selectedWinners[config.type] ?? [];
      if (playerIds.isEmpty) continue;
      
      final amountText = _amountControllers[config.type]?.text ?? '0';
      final amount = double.tryParse(amountText.replaceAll(',', '.')) ?? 0;
      
      if (amount <= 0) continue;
      
      winners.add(HandWinner(
        id: _uuid.v4(),
        type: config.type,
        playerIds: playerIds,
        amount: amount,
        reason: config.name,
      ));
    }

    if (winners.isEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona almeno un vincitore'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    widget.onComplete(winners);
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.isFullScreen) ...[
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.cream.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          
          Text(
            'Assegna Vincitori',
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.gold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Piatto Totale: ${currencyFormat.format(widget.hand.totalPot)}',
              style: GoogleFonts.lato(
                color: AppTheme.gold,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 24),
          
          ...widget.winnerTypes.map((config) => _buildWinnerTypeSection(config)),
          
          const SizedBox(height: 24),
          
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _confirm,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.cream,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(_isLoading ? 'Salvataggio...' : 'Conferma e Chiudi Mano'),
          ),
        ],
      ),
    );

    if (widget.isFullScreen) {
      return content;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => content,
    );
  }

  Widget _buildWinnerTypeSection(WinnerTypeConfig config) {
    final selectedIds = _selectedWinners[config.type] ?? [];
    final controller = _amountControllers[config.type]!;
    
    if ((config.type == WinnerType.lasVegasHigh || 
         config.type == WinnerType.lasVegasLow) &&
        (_selectedWinners[WinnerType.lasVegasFull]?.isNotEmpty ?? false)) {
      return const SizedBox.shrink();
    }
    
    if (config.type == WinnerType.lasVegasFull &&
        ((_selectedWinners[WinnerType.lasVegasHigh]?.isNotEmpty ?? false) ||
         (_selectedWinners[WinnerType.lasVegasLow]?.isNotEmpty ?? false))) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ),
                      Text(
                        config.description,
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          color: AppTheme.cream.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      prefixText: '€ ',
                      prefixStyle: GoogleFonts.lato(color: AppTheme.gold),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activePlayers.map((player) {
                final isSelected = selectedIds.contains(player.id);
                return FilterChip(
                  label: Text(player.name),
                  selected: isSelected,
                  onSelected: (_) => _togglePlayer(config.type, player.id),
                  selectedColor: AppTheme.gold.withValues(alpha: 0.3),
                  checkmarkColor: AppTheme.gold,
                  labelStyle: GoogleFonts.lato(
                    color: isSelected ? AppTheme.gold : AppTheme.cream,
                  ),
                  backgroundColor: AppTheme.darkGreen,
                  side: BorderSide(
                    color: isSelected ? AppTheme.gold : AppTheme.cream.withValues(alpha: 0.3),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

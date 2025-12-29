import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../models/game_hand.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

/// Schermata per gestire partite a 31 e Cucù (giochi con vite)
class TrentunoCucuScreen extends StatefulWidget {
  final String sessionId;

  const TrentunoCucuScreen({super.key, required this.sessionId});

  @override
  State<TrentunoCucuScreen> createState() => _TrentunoCucuScreenState();
}

class _TrentunoCucuScreenState extends State<TrentunoCucuScreen> {
  final _uuid = const Uuid();
  final _currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
  final _livesController = TextEditingController(text: '3');
  final _lifeValueController = TextEditingController();

  @override
  void dispose() {
    _livesController.dispose();
    _lifeValueController.dispose();
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

  /// Avvia una nuova mano
  Future<void> _startNewHand(GameSession session) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();

    final playerOrder = session.players.map((p) => p.id).toList();
    final playerStatus = <String, String>{};

    for (final playerId in playerOrder) {
      playerStatus[playerId] = 'alive';
    }

    final hand = ActiveHand(
      id: _uuid.v4(),
      gameType: session.gameMode.type,
      variantId: session.gameMode.variantId,
      createdAt: DateTime.now(),
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      playerOrder: playerOrder,
      playerStatus: playerStatus,
      needsLifeSetup: true, // L'admin deve configurare le vite
    );

    await dbService.startActiveHand(sessionId: session.id, hand: hand);
  }

  /// Admin imposta le vite iniziali
  Future<void> _setupLives(GameSession session, ActiveHand hand) async {
    final lives = int.tryParse(_livesController.text) ?? 3;
    final lifeValue = double.tryParse(
          _lifeValueController.text.replaceAll(',', '.'),
        ) ??
        0;

    if (lifeValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Il valore della vita deve essere maggiore di 0!'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    final createdBy = authService.currentUser?.uid ?? 'anonymous';

    // Imposta le vite per tutti i giocatori
    final playerLives = <String, int>{};
    for (final playerId in hand.playerOrder) {
      playerLives[playerId] = lives;
    }

    // Calcola il piatto totale: ogni giocatore paga tutte le sue vite subito
    final totalPerPlayer = lifeValue * lives;
    final totalPot = totalPerPlayer * hand.playerOrder.length;

    // Crea un movimento per ogni giocatore verso il piatto
    for (final playerId in hand.playerOrder) {
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: playerId,
        toPlayerId: '_piatto_vita_',
        amount: totalPerPlayer,
        description: '${session.gameMode.icon} Quota iniziale ($lives vite × ${_currencyFormat.format(lifeValue)})',
        createdBy: createdBy,
        handId: hand.id,
      );
    }

    final newHand = hand.copyWith(
      playerLives: playerLives,
      lifeValue: lifeValue,
      lifePot: totalPot,
      needsLifeSetup: false,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Giocatore perde una vita
  Future<void> _loseLife(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer == null) return;

    final currentLives = hand.playerLives[myPlayer.id] ?? 0;
    if (currentLives <= 0) return;

    // Aggiorna solo le vite (i soldi sono già nel piatto dall'inizio)
    final newLives = Map<String, int>.from(hand.playerLives);
    newLives[myPlayer.id] = currentLives - 1;

    final newHand = hand.copyWith(
      playerLives: newLives,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Richiedi una vita da un altro giocatore
  Future<void> _requestLife(
      GameSession session, ActiveHand hand, String targetPlayerId) async {
    final dbService = context.read<DatabaseService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer == null) return;

    final request = PendingLifeRequest(
      id: _uuid.v4(),
      fromPlayerId: myPlayer.id,
      toPlayerId: targetPlayerId,
      createdAt: DateTime.now(),
    );

    final newHand = hand.copyWith(pendingLifeRequest: request);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Conferma la cessione di una vita
  Future<void> _confirmLifeTransfer(
      GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final request = hand.pendingLifeRequest;
    if (request == null) return;

    final fromLives = hand.playerLives[request.toPlayerId] ?? 0;
    final toLives = hand.playerLives[request.fromPlayerId] ?? 0;

    if (fromLives <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Non hai vite da cedere!'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      // Cancella la richiesta
      final newHand = hand.copyWith(clearPendingLifeRequest: true);
      await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
      return;
    }

    // Trasferisci la vita
    final newLives = Map<String, int>.from(hand.playerLives);
    newLives[request.toPlayerId] = fromLives - 1;
    newLives[request.fromPlayerId] = toLives + 1;

    final newHand = hand.copyWith(
      playerLives: newLives,
      clearPendingLifeRequest: true,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Rifiuta la richiesta di vita
  Future<void> _rejectLifeRequest(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final newHand = hand.copyWith(clearPendingLifeRequest: true);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Rientrano tutti (pari con ultimi 2 giocatori a 1 vita)
  /// Solo chi ha 0 vite riprende 1 vita, chi ne ha già 1 rimane così
  /// I soldi rimangono nel piatto (sono già stati pagati all'inizio)
  Future<void> _reenterAll(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();

    final newLives = Map<String, int>.from(hand.playerLives);

    // Conta quanti giocatori sono morti (0 vite) e devono rientrare
    final deadPlayers = hand.playerOrder
        .where((id) => (hand.playerLives[id] ?? 0) == 0)
        .toList();

    // Solo i giocatori morti riprendono 1 vita
    for (final playerId in deadPlayers) {
      newLives[playerId] = 1;
    }

    final newHand = hand.copyWith(
      playerLives: newLives,
    );

    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${deadPlayers.length} giocatori sono rientrati con 1 vita!'),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  /// Il vincitore prende tutto il piatto
  Future<void> _claimVictory(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();

    final winnerId = hand.winnerId;
    if (winnerId == null) return;

    // Trasferisci tutto il piatto al vincitore
    if (hand.lifePot > 0) {
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: '_piatto_vita_',
        toPlayerId: winnerId,
        amount: hand.lifePot,
        description: '${session.gameMode.icon} Vittoria finale!',
        createdBy: authService.currentUser?.uid ?? 'anonymous',
        handId: hand.id,
      );
    }

    // Termina la mano
    await dbService.endActiveHand(sessionId: session.id);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '🎉 ${_getPlayerById(session, winnerId).name} ha vinto ${_currencyFormat.format(hand.lifePot)}!'),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  /// Termina la mano (solo admin)
  Future<void> _endHand(GameSession session) async {
    final dbService = context.read<DatabaseService>();
    await dbService.endActiveHand(sessionId: session.id);
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
        final gameIcon = session.gameMode.icon;
        final gameName = session.gameMode.displayName;

        // Se non c'è una mano attiva
        if (hand == null) {
          return _buildNoActiveHand(session, isAdmin, gameIcon, gameName);
        }

        // Se l'admin deve configurare le vite
        if (hand.needsLifeSetup) {
          return _buildSetupLivesView(session, hand, isAdmin, gameIcon, gameName);
        }

        // Se il gioco è finito
        if (hand.isGameOver) {
          return _buildGameOverView(session, hand, isAdmin, gameIcon, gameName);
        }

        // Gioco in corso
        return _buildGameView(session, hand, isAdmin, gameIcon, gameName);
      },
    );
  }

  Widget _buildNoActiveHand(GameSession session, bool isAdmin, String gameIcon,
      String gameName) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(gameIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(gameName),
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
                Text(gameIcon, style: const TextStyle(fontSize: 60))
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
                      ? 'Inizia una nuova partita quando tutti sono pronti'
                      : 'Aspetta che l\'admin inizi la partita...',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 32),
                if (isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _startNewHand(session),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Inizia Partita'),
                  ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetupLivesView(GameSession session, ActiveHand hand,
      bool isAdmin, String gameIcon, String gameName) {
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(gameIcon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(gameName),
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
                    'L\'amministratore sta configurando le vite e il valore...',
                    style: GoogleFonts.lato(
                      fontSize: 14,
                      color: AppTheme.cream.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Admin configura le vite
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(gameIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(gameName),
          ],
        ),
      ),
      body: ChristmasBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('❤️', style: const TextStyle(fontSize: 60))
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(),
                const SizedBox(height: 24),
                Text(
                  'Configura le Vite',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                const SizedBox(height: 12),
                Text(
                  'Imposta il numero di vite e il valore di ogni vita',
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
                        // Numero vite
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Vite per giocatore',
                                style: GoogleFonts.lato(color: AppTheme.cream),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                final current =
                                    int.tryParse(_livesController.text) ?? 3;
                                if (current > 1) {
                                  _livesController.text = '${current - 1}';
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.remove_circle_outline,
                                  color: AppTheme.gold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _livesController.text,
                                style: GoogleFonts.lato(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.gold,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                final current =
                                    int.tryParse(_livesController.text) ?? 3;
                                if (current < 10) {
                                  _livesController.text = '${current + 1}';
                                  setState(() {});
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline,
                                  color: AppTheme.gold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Valore vita
                        TextField(
                          controller: _lifeValueController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lato(
                            color: AppTheme.gold,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Valore di ogni vita',
                            labelStyle: GoogleFonts.lato(
                              color: AppTheme.cream.withValues(alpha: 0.7),
                            ),
                            prefixText: '€ ',
                            prefixStyle: GoogleFonts.lato(
                              color: AppTheme.gold,
                              fontSize: 32,
                            ),
                            hintText: '0,50',
                            hintStyle: GoogleFonts.lato(
                              color: AppTheme.gold.withValues(alpha: 0.3),
                              fontSize: 32,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Riepilogo
                        Builder(
                          builder: (context) {
                            final lives = int.tryParse(_livesController.text) ?? 3;
                            final lifeValue = double.tryParse(
                                  _lifeValueController.text.replaceAll(',', '.'),
                                ) ?? 0;
                            final totalPerPlayer = lifeValue * lives;
                            final totalPot = totalPerPlayer * session.players.length;
                            
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Riepilogo',
                                    style: GoogleFonts.lato(
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${session.players.length} giocatori × $lives vite × ${_currencyFormat.format(lifeValue)}',
                                    style: GoogleFonts.lato(
                                      color: AppTheme.cream.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Ogni giocatore paga: ${_currencyFormat.format(totalPerPlayer)}',
                                    style: GoogleFonts.lato(
                                      color: AppTheme.cream,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Piatto totale: ${_currencyFormat.format(totalPot)}',
                                    style: GoogleFonts.lato(
                                      color: AppTheme.gold,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _setupLives(session, hand),
                            icon: const Icon(Icons.check),
                            label: const Text('Inizia Partita'),
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
        ),
      ),
    );
  }

  Widget _buildGameOverView(GameSession session, ActiveHand hand, bool isAdmin,
      String gameIcon, String gameName) {
    final winnerId = hand.winnerId!;
    final winner = _getPlayerById(session, winnerId);
    final myPlayer = _getCurrentUserPlayer(session);
    final isWinner = myPlayer?.id == winnerId;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(gameIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(gameName),
          ],
        ),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.undo, color: AppTheme.accentRed),
              onPressed: () => _showCancelHandDialog(session, hand),
              tooltip: 'Annulla Mano',
            ),
        ],
      ),
      body: ChristmasBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🏆', style: TextStyle(fontSize: 80))
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .scale(),
                const SizedBox(height: 24),
                Text(
                  isWinner ? 'Hai Vinto!' : 'Partita Finita!',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                const SizedBox(height: 16),
                Text(
                  winner.name,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    color: AppTheme.cream,
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Vince ${_currencyFormat.format(hand.lifePot)}',
                    style: GoogleFonts.lato(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.gold,
                    ),
                  ),
                ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 32),
                if (isWinner || isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _claimVictory(session, hand),
                    icon: const Icon(Icons.celebration),
                    label: Text(isWinner
                        ? 'Riscuoti la Vincita!'
                        : 'Conferma Vittoria'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                  ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameView(GameSession session, ActiveHand hand, bool isAdmin,
      String gameIcon, String gameName) {
    final myPlayer = _getCurrentUserPlayer(session);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(gameIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(gameName),
          ],
        ),
        actions: [
          // Piatto
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
                  'Piatto: ${_currencyFormat.format(hand.lifePot)}',
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
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () => _showEndHandDialog(session),
              tooltip: 'Termina Mano',
            ),
          ],
        ],
      ),
      body: ChristmasBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info vita
              Card(
                color: AppTheme.gold.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Text(
                            'Valore Vita',
                            style: GoogleFonts.lato(
                              color: AppTheme.cream.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _currencyFormat.format(hand.lifeValue),
                            style: GoogleFonts.lato(
                              color: AppTheme.gold,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 32),
                      Column(
                        children: [
                          Text(
                            'In Gioco',
                            style: GoogleFonts.lato(
                              color: AppTheme.cream.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '${hand.playersWithLives.length} giocatori',
                            style: GoogleFonts.lato(
                              color: AppTheme.cream,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(duration: 300.ms),

              const SizedBox(height: 16),

              // Richiesta vita pendente
              if (hand.pendingLifeRequest != null)
                _buildPendingLifeRequest(session, hand),

              // Lista giocatori con vite
              _buildPlayersList(session, hand),

              const SizedBox(height: 24),

              // Le mie azioni (vivo o morto che sia, ma non se c'è una richiesta pendente)
              if (myPlayer != null && hand.pendingLifeRequest == null)
                _buildMyActions(session, hand, myPlayer),

              // Bottone rientro tutti (solo se condizione soddisfatta)
              if (hand.canReenterAll && isAdmin)
                _buildReenterAllButton(session, hand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingLifeRequest(GameSession session, ActiveHand hand) {
    final request = hand.pendingLifeRequest!;
    final requester = _getPlayerById(session, request.fromPlayerId);
    final target = _getPlayerById(session, request.toPlayerId);
    final myPlayer = _getCurrentUserPlayer(session);
    final isTarget = myPlayer?.id == request.toPlayerId;

    return Card(
      color: AppTheme.gold.withValues(alpha: 0.2),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, color: AppTheme.accentRed),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.lato(color: AppTheme.cream),
                      children: [
                        TextSpan(
                          text: requester.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.gold),
                        ),
                        const TextSpan(text: ' chiede una vita a '),
                        TextSpan(
                          text: target.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.gold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (isTarget) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectLifeRequest(session, hand),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentRed,
                        side: const BorderSide(color: AppTheme.accentRed),
                      ),
                      child: const Text('Rifiuta'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _confirmLifeTransfer(session, hand),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: AppTheme.darkGreen,
                      ),
                      child: const Text('Cedi Vita'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildPlayersList(GameSession session, ActiveHand hand) {
    final myPlayer = _getCurrentUserPlayer(session);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Giocatori',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 12),
            ...hand.playerOrder.map((playerId) {
              final player = _getPlayerById(session, playerId);
              final lives = hand.playerLives[playerId] ?? 0;
              final isMe = myPlayer?.id == playerId;
              final isAlive = lives > 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe
                      ? Colors.blue.withValues(alpha: 0.1)
                      : isAlive
                          ? AppTheme.darkGreen.withValues(alpha: 0.3)
                          : AppTheme.accentRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMe
                        ? Colors.blue.withValues(alpha: 0.5)
                        : isAlive
                            ? Colors.transparent
                            : AppTheme.accentRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: isAlive
                          ? AppTheme.gold.withValues(alpha: 0.2)
                          : AppTheme.accentRed.withValues(alpha: 0.2),
                      child: Text(
                        player.name[0].toUpperCase(),
                        style: GoogleFonts.lato(
                          color: isAlive ? AppTheme.gold : AppTheme.accentRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.name + (isMe ? ' (Tu)' : ''),
                            style: GoogleFonts.lato(
                              color: isAlive
                                  ? AppTheme.cream
                                  : AppTheme.cream.withValues(alpha: 0.5),
                              fontWeight:
                                  isMe ? FontWeight.bold : FontWeight.normal,
                              decoration: isAlive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          if (!isAlive)
                            Text(
                              'Eliminato',
                              style: GoogleFonts.lato(
                                color: AppTheme.accentRed,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Cuori per le vite
                    Row(
                      children: List.generate(
                        lives,
                        (i) => Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            Icons.favorite,
                            color: AppTheme.accentRed,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildMyActions(
      GameSession session, ActiveHand hand, Player myPlayer) {
    final myLives = hand.playerLives[myPlayer.id] ?? 0;
    final isAlive = myLives > 0;
    
    // Solo i giocatori morti possono chiedere vite ai vivi (che hanno almeno 1 vita)
    final othersWithLives = hand.playersWithLives
        .where((id) => id != myPlayer.id && (hand.playerLives[id] ?? 0) >= 1)
        .toList();

    return Card(
      color: AppTheme.primaryGreen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Le tue azioni',
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              myLives > 0 
                  ? 'Hai $myLives ${myLives == 1 ? "vita" : "vite"}'
                  : 'Sei eliminato! Puoi chiedere una vita a qualcuno.',
              style: GoogleFonts.lato(
                color: isAlive 
                    ? AppTheme.cream.withValues(alpha: 0.7)
                    : AppTheme.accentRed,
              ),
            ),
            const SizedBox(height: 16),

            // Perdi una vita (solo se vivo)
            if (isAlive)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _loseLife(session, hand),
                  icon: const Icon(Icons.heart_broken, color: AppTheme.accentRed),
                  label: Text(
                    'Perdi una vita',
                    style: GoogleFonts.lato(color: AppTheme.accentRed),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.accentRed),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),

            // Chiedi una vita (solo se morto e ci sono giocatori con più di 1 vita)
            if (!isAlive && othersWithLives.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Chiedi una vita a:',
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.darkGreen.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                dropdownColor: AppTheme.primaryGreen,
                hint: Text(
                  'Seleziona un giocatore...',
                  style: GoogleFonts.lato(color: AppTheme.cream.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.gold),
                items: othersWithLives.map((playerId) {
                  final player = _getPlayerById(session, playerId);
                  final lives = hand.playerLives[playerId] ?? 0;
                  return DropdownMenuItem<String>(
                    value: playerId,
                    child: Row(
                      children: [
                        const Icon(Icons.favorite, size: 16, color: AppTheme.accentRed),
                        const SizedBox(width: 8),
                        Text(
                          '${player.name} ($lives ${lives == 1 ? "vita" : "vite"})',
                          style: GoogleFonts.lato(color: AppTheme.cream),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (playerId) {
                  if (playerId != null) {
                    _requestLife(session, hand, playerId);
                  }
                },
              ),
            ],
            
            // Messaggio se morto ma nessuno ha vite da cedere
            if (!isAlive && othersWithLives.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.accentRed, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nessun altro giocatore è rimasto in gioco',
                        style: GoogleFonts.lato(
                          color: AppTheme.accentRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReenterAllButton(GameSession session, ActiveHand hand) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: AppTheme.gold.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.refresh, color: AppTheme.gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pari! Gli ultimi 2 giocatori hanno entrambi 1 vita.',
                      style: GoogleFonts.lato(color: AppTheme.cream),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _reenterAll(session, hand),
                  icon: const Icon(Icons.group_add),
                  label: const Text('Rientrano tutti con 1 vita'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.darkGreen,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale();
  }

  void _showEndHandDialog(GameSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          'Terminare la partita?',
          style: GoogleFonts.playfairDisplay(color: AppTheme.gold),
        ),
        content: Text(
          'Sei sicuro di voler terminare la partita corrente?',
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annulla', style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _endHand(session);
            },
            child: const Text('Termina'),
          ),
        ],
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
                'Annullare la partita?',
                style: GoogleFonts.playfairDisplay(color: AppTheme.accentRed),
              ),
            ),
          ],
        ),
        content: Text(
          'Questa azione annullerà la partita corrente e TUTTI i movimenti economici effettuati durante questa partita verranno eliminati.\n\nLa situazione economica tornerà allo stato precedente.',
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
            child: const Text('Sì, annulla partita'),
          ),
        ],
      ),
    );
  }
}


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

/// Schermata per gestire una partita a Sette e Mezzo
class SetteEMezzoScreen extends StatefulWidget {
  final String sessionId;
  final GameMode? initialGameMode;

  const SetteEMezzoScreen({
    super.key, 
    required this.sessionId,
    this.initialGameMode,
  });

  @override
  State<SetteEMezzoScreen> createState() => _SetteEMezzoScreenState();
}

class _SetteEMezzoScreenState extends State<SetteEMezzoScreen> {
  final _uuid = const Uuid();
  final _currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
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

  bool _isDealer(GameSession session, ActiveHand hand) {
    final myPlayer = _getCurrentUserPlayer(session);
    return myPlayer?.id == hand.dealerId;
  }

  /// Ottiene il GameMode corrente (dalla mano attiva o da initialGameMode)
  GameMode _getGameMode(GameSession session) {
    if (session.activeHand != null) {
      return GameMode(
        type: session.activeHand!.gameType,
        variantId: session.activeHand!.variantId,
      );
    }
    return widget.initialGameMode ?? const GameMode(type: GameType.setteEMezzo);
  }

  /// Avvia una nuova mano di Sette e Mezzo
  Future<void> _startNewHand(GameSession session, String? variantId) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    final playerOrder = session.players.map((p) => p.id).toList();
    final playerStatus = <String, String>{};
    
    for (final playerId in playerOrder) {
      playerStatus[playerId] = 'waiting';
    }

    // Il mazziere NON è impostato di default - deve essere scelto
    final isOneVsOne = variantId == SetteEMezzoVariant.unoVsUnoConPiatto.name;

    final hand = ActiveHand(
      id: _uuid.v4(),
      gameType: GameType.setteEMezzo,
      variantId: variantId,
      createdAt: DateTime.now(),
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      playerOrder: playerOrder,
      playerStatus: playerStatus,
      dealerId: null, // Nessun mazziere iniziale - deve essere scelto
      dealerPot: 0,
      needsDealerPotSetup: isOneVsOne,
    );

    await dbService.startActiveHand(sessionId: session.id, hand: hand);
  }

  /// Il mazziere imposta il valore iniziale del piatto
  /// L'importo viene diviso tra tutti i giocatori e scalato da ognuno
  Future<void> _setDealerPot(GameSession session, ActiveHand hand, double amount) async {
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.enterValidAmountGreaterThan0),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    final createdBy = authService.currentUser?.uid ?? 'anonymous';
    
    // Dividi il piatto tra tutti i giocatori
    final players = session.players;
    final amountPerPlayer = amount / players.length;
    
    // Crea un movimento per ogni giocatore verso il piatto
    for (final player in players) {
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: player.id,
        toPlayerId: '_piatto_',
        amount: amountPerPlayer,
        description: '7½ - Quota piatto iniziale',
        createdBy: createdBy,
        handId: hand.id, // Associa il movimento alla mano corrente
      );
    }
    
    final newHand = hand.copyWith(
      dealerPot: amount,
      needsDealerPotSetup: false,
    );
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Richiedi di diventare mazziere
  Future<void> _requestDealerChange(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer == null || myPlayer.id == hand.dealerId) return;

    final newHand = hand.copyWith(pendingDealerRequest: myPlayer.id);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Accetta il cambio mazziere (solo mazziere corrente)
  Future<void> _acceptDealerChange(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (hand.pendingDealerRequest == null) return;

    final isOneVsOne = hand.isSetteEMezzoOneVsOne;
    final oldDealerId = hand.dealerId;
    final newDealerId = hand.pendingDealerRequest;

    // In modalità 1v1, il piatto va al mazziere uscente
    if (isOneVsOne && hand.dealerPot > 0 && oldDealerId != null) {
      // Crea movimento dal piatto al mazziere uscente
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: '_piatto_',
        toPlayerId: oldDealerId,
        amount: hand.dealerPot,
        description: '7½ - Piatto al mazziere uscente',
        createdBy: authService.currentUser?.uid ?? 'anonymous',
        handId: hand.id,
      );
    }

    final newHand = hand.copyWith(
      dealerId: newDealerId,
      dealerPot: 0,
      clearPendingDealerRequest: true,
      needsDealerPotSetup: isOneVsOne, // Il nuovo mazziere deve impostare il piatto
    );
    
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Rifiuta il cambio mazziere
  Future<void> _rejectDealerChange(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final newHand = hand.copyWith(clearPendingDealerRequest: true);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Modalità Mazziere vs Tutti: giocatore punta
  Future<void> _playerBet(GameSession session, ActiveHand hand, String playerId, double amount) async {
    final dbService = context.read<DatabaseService>();
    
    final newBets = Map<String, double>.from(hand.currentPhaseBets);
    newBets[playerId] = (newBets[playerId] ?? 0) + amount;
    
    final newHand = hand.copyWith(currentPhaseBets: newBets);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Modalità Mazziere vs Tutti: mazziere decide i pagamenti
  Future<void> _dealerPayPlayer(GameSession session, ActiveHand hand, String playerId, double amount) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (hand.dealerId == null) return;
    
    await dbService.addMovement(
      sessionId: session.id,
      fromPlayerId: hand.dealerId!,
      toPlayerId: playerId,
      amount: amount,
      description: '7½ - Mazziere paga',
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      handId: hand.id,
    );
    
    // Rimuovi la puntata del giocatore
    final newBets = Map<String, double>.from(hand.currentPhaseBets);
    newBets.remove(playerId);
    
    final newHand = hand.copyWith(currentPhaseBets: newBets);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Modalità Mazziere vs Tutti: mazziere prende dal giocatore
  Future<void> _dealerTakeFromPlayer(GameSession session, ActiveHand hand, String playerId, double amount) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (hand.dealerId == null) return;
    
    await dbService.addMovement(
      sessionId: session.id,
      fromPlayerId: playerId,
      toPlayerId: hand.dealerId!,
      amount: amount,
      description: '7½ - Giocatore paga mazziere',
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      handId: hand.id,
    );
    
    // Rimuovi la puntata del giocatore
    final newBets = Map<String, double>.from(hand.currentPhaseBets);
    newBets.remove(playerId);
    
    final newHand = hand.copyWith(currentPhaseBets: newBets);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Modalità Mazziere vs Tutti: mazziere sballa - paga tutti
  Future<void> _dealerBusts(GameSession session, ActiveHand hand) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (hand.dealerId == null) return;
    
    for (final entry in hand.currentPhaseBets.entries) {
      if (entry.key == hand.dealerId) continue;
      
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: hand.dealerId!,
        toPlayerId: entry.key,
        amount: entry.value,
        description: '7½ - Mazziere sballa',
        createdBy: authService.currentUser?.uid ?? 'anonymous',
        handId: hand.id,
      );
    }
    
    // Reset puntate
    final newHand = hand.copyWith(currentPhaseBets: {});
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Modalità 1v1: giocatore paga al piatto (mazziere)
  Future<void> _playerPaysToPot(GameSession session, ActiveHand hand, double amount) async {
    final dbService = context.read<DatabaseService>();
    
    final newPot = hand.dealerPot + amount;
    final newHand = hand.copyWith(dealerPot: newPot);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    
    // Registra il movimento
    final authService = context.read<AuthService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer != null && hand.dealerId != null) {
      await dbService.addMovement(
        sessionId: session.id,
        fromPlayerId: myPlayer.id,
        toPlayerId: '_piatto_',
        amount: amount,
        description: '7½ - Paga al piatto',
        createdBy: authService.currentUser?.uid ?? 'anonymous',
        handId: hand.id,
      );
    }
  }

  /// Modalità 1v1: giocatore richiede soldi dal piatto
  Future<void> _playerRequestsFromPot(GameSession session, ActiveHand hand, double amount) async {
    final dbService = context.read<DatabaseService>();
    final myPlayer = _getCurrentUserPlayer(session);
    if (myPlayer == null) return;
    
    final pendingPayment = PendingPayment(
      id: _uuid.v4(),
      fromPlayerId: '_piatto_',
      toPlayerId: myPlayer.id,
      amount: amount,
      direction: PaymentDirection.playerRequestsFromDealer,
      createdAt: DateTime.now(),
    );
    
    final newPendingPayments = [...hand.pendingPayments, pendingPayment];
    final newHand = hand.copyWith(pendingPayments: newPendingPayments);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Mazziere conferma il pagamento
  Future<void> _confirmPendingPayment(GameSession session, ActiveHand hand, PendingPayment payment) async {
    final dbService = context.read<DatabaseService>();
    final authService = context.read<AuthService>();
    
    if (payment.amount > hand.dealerPot) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.insufficientPot),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }
    
    // Esegui il pagamento
    await dbService.addMovement(
      sessionId: session.id,
      fromPlayerId: '_piatto_',
      toPlayerId: payment.toPlayerId,
      amount: payment.amount,
      description: '7½ - Pagamento dal piatto',
      createdBy: authService.currentUser?.uid ?? 'anonymous',
      handId: hand.id,
    );
    
    // Rimuovi il pagamento pending e aggiorna il piatto
    final newPendingPayments = hand.pendingPayments.where((p) => p.id != payment.id).toList();
    final newPot = hand.dealerPot - payment.amount;
    
    // Se il piatto va a 0, si deve dichiarare un nuovo mazziere
    final needsNewDealer = newPot <= 0;
    
    final newHand = hand.copyWith(
      pendingPayments: newPendingPayments,
      dealerPot: newPot > 0 ? newPot : 0,
      needsDealerPotSetup: needsNewDealer,
      dealerId: needsNewDealer ? null : hand.dealerId, // Reset mazziere se piatto a 0
    );
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
    
    if (needsNewDealer && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.potExhausted),
          backgroundColor: AppTheme.gold,
        ),
      );
    }
  }

  /// Mazziere rifiuta il pagamento
  Future<void> _rejectPendingPayment(GameSession session, ActiveHand hand, PendingPayment payment) async {
    final dbService = context.read<DatabaseService>();
    
    final newPendingPayments = hand.pendingPayments.where((p) => p.id != payment.id).toList();
    final newHand = hand.copyWith(pendingPayments: newPendingPayments);
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  /// Termina la mano
  Future<void> _endHand(GameSession session) async {
    final dbService = context.read<DatabaseService>();
    await dbService.endActiveHand(sessionId: session.id);
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
                    const Icon(Icons.error_outline, size: 60, color: AppTheme.accentRed),
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
        final isOneVsOne = hand.isSetteEMezzoOneVsOne;
        
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('7️⃣', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(isOneVsOne ? '1 vs 1' : AppLocalizations.of(context)!.variantMazziereVsTutti),
              ],
            ),
            actions: [
              if (isOneVsOne)
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
                        '${AppLocalizations.of(context)!.pot}: ${_currencyFormat.format(hand.dealerPot)}',
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
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: () => _showEndHandDialog(session),
                  tooltip: AppLocalizations.of(context)!.endHand,
                ),
              ],
            ],
          ),
          body: ChristmasBackground(
            child: isOneVsOne
                ? _buildOneVsOneView(session, hand)
                : _buildDealerVsAllView(session, hand),
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
            const Text('7️⃣', style: TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context)!.gameModeSetteEMezzo),
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
                const Text('7️⃣', style: TextStyle(fontSize: 60))
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
                ).animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms),
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
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.mode(_getGameMode(session).getVariantDisplayName(context) ?? AppLocalizations.of(context)!.variantClassico),
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppTheme.gold.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ).animate()
                  .fadeIn(delay: 500.ms, duration: 400.ms),
                const SizedBox(height: 32),
                if (isAdmin)
                  ElevatedButton.icon(
                    onPressed: () => _startNewHand(session, _getGameMode(session).variantId),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(AppLocalizations.of(context)!.startHand),
                  ).animate()
                    .fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDealerVsAllView(GameSession session, ActiveHand hand) {
    final isDealer = _isDealer(session, hand);
    final myPlayer = _getCurrentUserPlayer(session);
    final dealerPlayer = hand.dealerId != null ? _getPlayerById(session, hand.dealerId!) : null;

    // Se non c'è mazziere, mostra la selezione
    if (hand.dealerId == null) {
      return _buildSelectDealerView(session, hand);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Mazziere
          _buildDealerHeader(session, hand, dealerPlayer),
          
          const SizedBox(height: 16),
          
          // Richiesta cambio mazziere pendente
          if (hand.pendingDealerRequest != null)
            _buildPendingDealerRequest(session, hand),
          
          // Puntate dei giocatori
          _buildPlayerBets(session, hand),
          
          const SizedBox(height: 24),
          
          // Azioni
          if (isDealer) ...[
            _buildDealerActions(session, hand),
          ] else if (myPlayer != null && !isDealer) ...[
            _buildPlayerActions(session, hand, myPlayer),
          ],
          
          // Bottone per diventare mazziere
          if (myPlayer != null && !isDealer && hand.pendingDealerRequest == null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: OutlinedButton.icon(
                onPressed: () => _requestDealerChange(session, hand),
                icon: const Icon(Icons.swap_horiz, color: AppTheme.gold),
                label: Text(
                  AppLocalizations.of(context)!.wantToBeDealer,
                  style: GoogleFonts.lato(color: AppTheme.gold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.gold),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOneVsOneView(GameSession session, ActiveHand hand) {
    final isDealer = _isDealer(session, hand);
    final myPlayer = _getCurrentUserPlayer(session);
    final dealerPlayer = hand.dealerId != null ? _getPlayerById(session, hand.dealerId!) : null;

    // Se non c'è mazziere, mostra la selezione
    if (hand.dealerId == null) {
      return _buildSelectDealerView(session, hand);
    }

    // Se il mazziere deve impostare il piatto
    if (hand.needsDealerPotSetup) {
      return _buildSetupPotView(session, hand, isDealer);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Mazziere + Piatto
          _buildDealerHeader(session, hand, dealerPlayer),
          
          const SizedBox(height: 16),
          
          // Richiesta cambio mazziere pendente
          if (hand.pendingDealerRequest != null)
            _buildPendingDealerRequest(session, hand),
          
          // Pagamenti pendenti (per mazziere)
          if (isDealer && hand.pendingPayments.isNotEmpty)
            _buildPendingPayments(session, hand),
          
          const SizedBox(height: 24),
          
          // Azioni giocatore
          if (myPlayer != null && !isDealer)
            _buildOneVsOnePlayerActions(session, hand),
          
          // Bottone per diventare mazziere
          if (myPlayer != null && !isDealer && hand.pendingDealerRequest == null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: OutlinedButton.icon(
                onPressed: () => _requestDealerChange(session, hand),
                icon: const Icon(Icons.swap_horiz, color: AppTheme.gold),
                label: Text(
                  AppLocalizations.of(context)!.wantToBeDealer,
                  style: GoogleFonts.lato(color: AppTheme.gold),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.gold),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDealerHeader(GameSession session, ActiveHand hand, Player? dealerPlayer) {
    return Card(
      color: AppTheme.gold.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Text('🎴', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.dealer,
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    dealerPlayer?.name ?? AppLocalizations.of(context)!.none,
                    style: GoogleFonts.playfairDisplay(
                      color: AppTheme.gold,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (hand.isSetteEMezzoOneVsOne) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    AppLocalizations.of(context)!.pot,
                    style: GoogleFonts.lato(
                      color: AppTheme.cream.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _currencyFormat.format(hand.dealerPot),
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  /// Vista per selezionare un nuovo mazziere
  Widget _buildSelectDealerView(GameSession session, ActiveHand hand) {
    final myPlayer = _getCurrentUserPlayer(session);
    
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
            ).animate()
              .fadeIn(duration: 400.ms)
              .scale(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.whoIsDealer,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate()
              .fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.playerMustDeclareDealer,
              style: GoogleFonts.lato(
                fontSize: 14,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate()
              .fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 32),
            if (myPlayer != null)
              ElevatedButton.icon(
                onPressed: () => _becomeDealer(session, hand, myPlayer.id),
                icon: const Icon(Icons.casino),
                label: Text(AppLocalizations.of(context)!.imTheDealer),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ).animate()
                .fadeIn(delay: 600.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  /// Vista per il mazziere per impostare il piatto iniziale
  Widget _buildSetupPotView(GameSession session, ActiveHand hand, bool isDealer) {
    final dealerPlayer = hand.dealerId != null ? _getPlayerById(session, hand.dealerId!) : null;
    
    if (!isDealer) {
      // Non sono il mazziere - aspetto
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
                child: const Icon(Icons.hourglass_empty, size: 50, color: AppTheme.gold),
              ).animate()
                .fadeIn(duration: 400.ms)
                .scale(),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)!.waitingForDealer,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.gold,
                ),
              ).animate()
                .fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 12),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                  children: [
                    TextSpan(
                      text: AppLocalizations.of(context)!.dealerSettingPot(dealerPlayer?.name ?? AppLocalizations.of(context)!.dealer),
                      ),
                  ],
                ),
              ).animate()
                .fadeIn(delay: 400.ms, duration: 400.ms),
            ],
          ),
        ),
      );
    }

    // Sono il mazziere - imposto il piatto
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
              child: const Text('💰', style: TextStyle(fontSize: 50)),
            ).animate()
              .fadeIn(duration: 400.ms)
              .scale(),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.setPot,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ).animate()
              .fadeIn(delay: 200.ms, duration: 400.ms),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.youAreDealer,
              style: GoogleFonts.lato(
                fontSize: 14,
                color: AppTheme.cream.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate()
              .fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                    AmountKeypad(controller: _amountController),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final amount = double.tryParse(
                            _amountController.text.replaceAll(',', '.'),
                          );
                          if (amount != null && amount > 0) {
                            _setDealerPot(session, hand, amount);
                            _amountController.clear();
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
                        label: Text(AppLocalizations.of(context)!.confirmPot),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate()
              .fadeIn(delay: 600.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }

  /// Diventa mazziere (quando non ce n'è uno)
  Future<void> _becomeDealer(GameSession session, ActiveHand hand, String playerId) async {
    final dbService = context.read<DatabaseService>();
    final newHand = hand.copyWith(
      dealerId: playerId,
      needsDealerPotSetup: true,
    );
    await dbService.updateActiveHand(sessionId: session.id, hand: newHand);
  }

  Widget _buildPendingDealerRequest(GameSession session, ActiveHand hand) {
    final requestingPlayer = _getPlayerById(session, hand.pendingDealerRequest!);
    final isCurrentDealer = _isDealer(session, hand);

    return Card(
      color: AppTheme.gold.withValues(alpha: 0.2),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.swap_horiz, color: AppTheme.gold),
                const SizedBox(width: 12),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.lato(color: AppTheme.cream),
                      children: [
                        TextSpan(
                          text: AppLocalizations.of(context)!.wantsToBeDealer(requestingPlayer.name),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (isCurrentDealer) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _rejectDealerChange(session, hand),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accentRed,
                        side: const BorderSide(color: AppTheme.accentRed),
                      ),
                      child: Text(AppLocalizations.of(context)!.reject),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptDealerChange(session, hand),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: AppTheme.darkGreen,
                      ),
                      child: Text(AppLocalizations.of(context)!.accept),
                    ),
                  ),
                ],
              ),
              if (hand.isSetteEMezzoOneVsOne && hand.dealerPot > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    AppLocalizations.of(context)!.potWillBeAssigned(_currencyFormat.format(hand.dealerPot)),
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildPlayerBets(GameSession session, ActiveHand hand) {
    final bets = hand.currentPhaseBets;
    if (bets.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.hourglass_empty, size: 40, color: AppTheme.cream.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)!.noBetsYet,
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.bets,
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 12),
            ...bets.entries.map((entry) {
              final player = _getPlayerById(session, entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.gold.withValues(alpha: 0.2),
                      child: Text(
                        player.name[0].toUpperCase(),
                        style: GoogleFonts.lato(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        player.name,
                        style: GoogleFonts.lato(color: AppTheme.cream),
                      ),
                    ),
                    Text(
                      _currencyFormat.format(entry.value),
                      style: GoogleFonts.lato(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
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

  Widget _buildDealerActions(GameSession session, ActiveHand hand) {
    return Card(
      color: AppTheme.primaryGreen,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.dealerManagement,
              style: GoogleFonts.playfairDisplay(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Lista giocatori con puntate per gestire pagamenti
            if (hand.currentPhaseBets.isNotEmpty) ...[
              Text(
                AppLocalizations.of(context)!.decideForEachPlayer,
                style: GoogleFonts.lato(
                  color: AppTheme.cream.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...hand.currentPhaseBets.entries.map((entry) {
                final player = _getPlayerById(session, entry.key);
                return Card(
                  color: AppTheme.darkGreen.withValues(alpha: 0.5),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              player.name,
                              style: GoogleFonts.lato(
                                color: AppTheme.cream,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _currencyFormat.format(entry.value),
                              style: GoogleFonts.lato(
                                color: AppTheme.gold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _dealerPayPlayer(session, hand, entry.key, entry.value),
                                icon: const Icon(Icons.arrow_upward, size: 16, color: AppTheme.accentRed),
                                label: Text(AppLocalizations.of(context)!.pay, style: GoogleFonts.lato(fontSize: 12, color: AppTheme.accentRed)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppTheme.accentRed),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _dealerTakeFromPlayer(session, hand, entry.key, entry.value),
                                icon: const Icon(Icons.arrow_downward, size: 16),
                                label: Text(AppLocalizations.of(context)!.take, style: GoogleFonts.lato(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.gold,
                                  foregroundColor: AppTheme.darkGreen,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            
            const SizedBox(height: 16),
            
            // Mazziere sballa
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: hand.currentPhaseBets.isNotEmpty 
                    ? () => _dealerBusts(session, hand) 
                    : null,
                icon: const Icon(Icons.close, color: AppTheme.accentRed),
                label: Text(
                  AppLocalizations.of(context)!.iBustedPayAll,
                  style: GoogleFonts.lato(color: AppTheme.accentRed),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.accentRed),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerActions(GameSession session, ActiveHand hand, Player myPlayer) {
    final myBet = hand.currentPhaseBets[myPlayer.id] ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.yourBet,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ),
                const Spacer(),
                if (myBet > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _currencyFormat.format(myBet),
                      style: GoogleFonts.lato(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
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
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.lato(color: AppTheme.gold, fontSize: 18),
                    decoration: InputDecoration(
                      prefixText: '€ ',
                      prefixStyle: GoogleFonts.lato(color: AppTheme.gold),
                      hintText: AppLocalizations.of(context)!.amountPlaceholder,
                      hintStyle: GoogleFonts.lato(color: AppTheme.gold.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
                    if (amount != null && amount > 0) {
                      _playerBet(session, hand, myPlayer.id, amount);
                      _amountController.clear();
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: Text(AppLocalizations.of(context)!.bet),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AmountKeypad(controller: _amountController),
          ],
        ),
      ),
    );
  }

  Widget _buildOneVsOnePlayerActions(GameSession session, ActiveHand hand) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.yourActions,
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.lato(color: AppTheme.gold, fontSize: 18),
              decoration: InputDecoration(
                prefixText: '€ ',
                prefixStyle: GoogleFonts.lato(color: AppTheme.gold),
                hintText: AppLocalizations.of(context)!.amountPlaceholder,
                hintStyle: GoogleFonts.lato(color: AppTheme.gold.withValues(alpha: 0.3)),
              ),
            ),
            const SizedBox(height: 12),
            AmountKeypad(controller: _amountController),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
                      if (amount != null && amount > 0) {
                        _playerPaysToPot(session, hand, amount);
                        _amountController.clear();
                      }
                    },
                    icon: const Icon(Icons.arrow_upward, color: AppTheme.accentRed),
                    label: Text(AppLocalizations.of(context)!.iPay, style: GoogleFonts.lato(color: AppTheme.accentRed)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.accentRed),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
                      if (amount != null && amount > 0) {
                        _playerRequestsFromPot(session, hand, amount);
                        _amountController.clear();
                      }
                    },
                    icon: const Icon(Icons.arrow_downward),
                    label: Text(AppLocalizations.of(context)!.iRequest),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.darkGreen,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.requestNeedsConfirmation,
              style: GoogleFonts.lato(
                color: AppTheme.cream.withValues(alpha: 0.5),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingPayments(GameSession session, ActiveHand hand) {
    return Card(
      color: AppTheme.gold.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions, color: AppTheme.gold),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.pendingRequests,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...hand.pendingPayments.map((payment) {
              final player = _getPlayerById(session, payment.toPlayerId);
              return Card(
                color: AppTheme.darkGreen.withValues(alpha: 0.5),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: GoogleFonts.lato(color: AppTheme.cream),
                                children: [
                                  TextSpan(
                                    text: AppLocalizations.of(context)!.requests(player.name, _currencyFormat.format(payment.amount)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _rejectPendingPayment(session, hand, payment),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.accentRed,
                                side: const BorderSide(color: AppTheme.accentRed),
                              ),
                              child: Text(AppLocalizations.of(context)!.reject),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: payment.amount <= hand.dealerPot
                                  ? () => _confirmPendingPayment(session, hand, payment)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.gold,
                                foregroundColor: AppTheme.darkGreen,
                              ),
                              child: Text(AppLocalizations.of(context)!.confirm),
                            ),
                          ),
                        ],
                      ),
                      if (payment.amount > hand.dealerPot)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            AppLocalizations.of(context)!.insufficientPot,
                            style: GoogleFonts.lato(
                              color: AppTheme.accentRed,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showEndHandDialog(GameSession session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          AppLocalizations.of(context)!.terminateHand,
          style: GoogleFonts.playfairDisplay(color: AppTheme.gold),
        ),
        content: Text(
          AppLocalizations.of(context)!.terminateHandConfirm,
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel, style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _endHand(session);
            },
            child: Text(AppLocalizations.of(context)!.terminate),
          ),
        ],
      ),
    );
  }

  void _showCancelHandDialog(GameSession session, ActiveHand hand) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.accentRed),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.cancelHandQuestion,
                style: GoogleFonts.playfairDisplay(color: AppTheme.accentRed),
              ),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.of(context)!.cancelHandWarning,
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.noKeepIt, style: GoogleFonts.lato(color: AppTheme.cream)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelHand(session, hand);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
            ),
            child: Text(AppLocalizations.of(context)!.yesCancelHand),
          ),
        ],
      ),
    );
  }
}


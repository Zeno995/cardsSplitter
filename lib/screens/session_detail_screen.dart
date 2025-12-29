import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../models/game_mode.dart';
import '../models/movement.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'add_movement_screen.dart';
import 'settlements_screen.dart';
import 'play_hand_screen.dart';
import 'select_game_mode_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailScreen({super.key, required this.sessionId});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _lastKnownPlayerId; // Per tracciare se l'utente è stato sostituito
  bool _hasShownReplacedDialog = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isAdmin(GameSession session, String? userId) {
    return session.adminId == userId;
  }

  Player? _getCurrentPlayer(GameSession session, String? userId) {
    if (userId == null) return null;
    try {
      return session.players.firstWhere((p) => p.userId == userId);
    } catch (_) {
      return null;
    }
  }

  void _checkIfPlayerReplaced(GameSession session, String? userId) {
    if (userId == null || _hasShownReplacedDialog) return;
    
    final currentPlayer = _getCurrentPlayer(session, userId);
    
    // Se avevamo un player ID salvato e ora non troviamo più il nostro utente
    if (_lastKnownPlayerId != null && currentPlayer == null) {
      // Controlla se il vecchio player esiste ancora ma con un altro userId
      final oldPlayer = session.players.where((p) => p.id == _lastKnownPlayerId).firstOrNull;
      if (oldPlayer != null && oldPlayer.userId != userId) {
        // Siamo stati sostituiti!
        _hasShownReplacedDialog = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showReplacedDialog();
        });
      }
    }
    
    // Aggiorna l'ultimo player ID conosciuto
    if (currentPlayer != null) {
      _lastKnownPlayerId = currentPlayer.id;
    }
  }

  void _showReplacedDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Row(
          children: [
            const Icon(Icons.swap_horiz, color: AppTheme.gold),
            const SizedBox(width: 12),
            Text(
              l10n.spotTaken,
              style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
            ),
          ],
        ),
        content: Text(
          l10n.anotherUserTookYourSpot,
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }

  void _shareSession(GameSession session) {
    final l10n = AppLocalizations.of(context)!;
    final shareText = l10n.joinSessionText(session.name, session.shareCode);
    
    Share.share(shareText);
  }

  void _copyCode(String code) {
    final l10n = AppLocalizations.of(context)!;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.codeCopied),
        backgroundColor: AppTheme.primaryGreen,
      ),
    );
  }

  Future<void> _startNewHand(GameSession session) async {
    // Mostra la selezione del gioco
    final selectedGameMode = await Navigator.push<GameMode>(
      context,
      MaterialPageRoute(
        builder: (_) => const SelectGameModeScreen(),
      ),
    );
    
    if (selectedGameMode != null && mounted) {
      // Naviga alla schermata di gioco con la modalità selezionata
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayHandScreen(
            sessionId: session.id,
            initialGameMode: selectedGameMode,
          ),
        ),
      );
    }
  }

  Future<void> _deleteSession(GameSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          l10n.deleteSession,
          style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
        ),
        content: Text(
          l10n.deleteSessionConfirm(session.name),
          style: GoogleFonts.lato(color: AppTheme.cream),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: GoogleFonts.lato(color: AppTheme.gold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final dbService = context.read<DatabaseService>();
      await dbService.deleteSession(session.id);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = context.watch<AuthService>();
    final dbService = context.read<DatabaseService>();
    final userId = authService.currentUser?.uid;

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
                      l10n.sessionNotFound,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        color: AppTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.goBack),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Controlla se l'utente è stato sostituito
        _checkIfPlayerReplaced(session, userId);

        final isAdmin = _isAdmin(session, userId);
        final currentPlayer = _getCurrentPlayer(session, userId);

        return Scaffold(
          appBar: AppBar(
            title: Text(session.name),
            actions: [
              IconButton(
                onPressed: () => _shareSession(session),
                icon: const Icon(Icons.share),
                tooltip: l10n.share,
              ),
              if (isAdmin)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  color: AppTheme.primaryGreen,
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteSession(session);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, color: AppTheme.accentRed),
                          const SizedBox(width: 8),
                          Text(
                            l10n.deleteSession,
                            style: GoogleFonts.lato(color: AppTheme.accentRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.gold,
              labelColor: AppTheme.gold,
              unselectedLabelColor: AppTheme.cream.withValues(alpha: 0.5),
              labelStyle: GoogleFonts.lato(fontWeight: FontWeight.bold),
              tabs: [
                Tab(text: l10n.balances),
                Tab(text: l10n.movements),
                Tab(text: l10n.players),
              ],
            ),
          ),
          body: ChristmasBackground(
            child: Column(
              children: [
                // Codice sessione e mano attiva
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      // Mano attiva (se presente)
                      if (session.activeHand != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                GameMode(type: session.activeHand!.gameType).icon,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.handInProgress(GameMode(type: session.activeHand!.gameType).getDisplayName(context)),
                                style: GoogleFonts.playfairDisplay(
                                  color: AppTheme.gold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(color: AppTheme.gold.withValues(alpha: 0.2)),
                      ],
                      // Codice
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${l10n.code}: ',
                            style: GoogleFonts.lato(color: AppTheme.cream.withValues(alpha: 0.7)),
                          ),
                          Text(
                            session.shareCode,
                            style: GoogleFonts.lato(
                              color: AppTheme.gold,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => _copyCode(session.shareCode),
                            icon: const Icon(Icons.copy, size: 18),
                            color: AppTheme.gold,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.2, end: 0),

                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _BalancesTab(session: session),
                      _MovementsTab(session: session, isAdmin: isAdmin),
                      _PlayersTab(session: session, isAdmin: isAdmin),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: session.isActive
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.extended(
                      heroTag: 'settlements',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettlementsScreen(session: session),
                        ),
                      ),
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.darkGreen,
                      icon: const Icon(Icons.calculate),
                      label: Text(l10n.calculate),
                    ),
                    const SizedBox(height: 12),
                    // Bottone per nuova mano o mano in corso
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: session.activeHand != null
                          // Mano in corso - continua
                          ? FloatingActionButton.extended(
                              heroTag: 'play',
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PlayHandScreen(
                                    sessionId: session.id,
                                    initialGameMode: GameMode(type: session.activeHand!.gameType),
                                  ),
                                ),
                              ),
                              backgroundColor: AppTheme.gold,
                              foregroundColor: AppTheme.darkGreen,
                              icon: Text(
                                GameMode(type: session.activeHand!.gameType).icon,
                                style: const TextStyle(fontSize: 20),
                              ),
                              label: Text(l10n.currentHand),
                            )
                          // Nuova mano - scegli gioco
                          : FloatingActionButton.extended(
                              heroTag: 'play',
                              onPressed: () => _startNewHand(session),
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: AppTheme.cream,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(l10n.newHand),
                            ),
                    ),
                    // Movimento manuale (sempre disponibile per admin)
                    if (isAdmin)
                      FloatingActionButton.extended(
                        heroTag: 'add',
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddMovementScreen(
                              session: session,
                              currentPlayerId: currentPlayer?.id,
                              isAdmin: isAdmin,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.movement),
                      ),
                  ],
                ).animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1))
              : null,
        );
      },
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final GameSession session;

  const _BalancesTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final balances = session.calculateBalances();
    final sortedPlayers = session.players.toList()
      ..sort((a, b) {
        final balanceA = balances[a.id] ?? 0;
        final balanceB = balances[b.id] ?? 0;
        return balanceB.compareTo(balanceA);
      });

    if (sortedPlayers.isEmpty) {
      return Center(
        child: Text(
          l10n.noPlayers,
          style: GoogleFonts.lato(color: AppTheme.cream.withValues(alpha: 0.5)),
        ),
      );
    }

    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedPlayers.length,
      itemBuilder: (context, index) {
        final player = sortedPlayers[index];
        final balance = balances[player.id] ?? 0;
        final isPositive = balance >= 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isPositive
                        ? Colors.green.withValues(alpha: 0.2)
                        : AppTheme.accentRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Center(
                    child: Text(
                      player.name[0].toUpperCase(),
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isPositive ? Colors.green : AppTheme.accentRed,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            player.name,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.cream,
                            ),
                          ),
                          if (player.isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.gold.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Admin',
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
                      Text(
                        isPositive ? l10n.mustReceive : l10n.mustGive,
                        style: GoogleFonts.lato(
                          fontSize: 12,
                          color: AppTheme.cream.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  currencyFormat.format(balance.abs()),
                  style: GoogleFonts.lato(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : AppTheme.accentRed,
                  ),
                ),
              ],
            ),
          ),
        ).animate()
          .fadeIn(duration: 200.ms)
          .slideX(begin: 0.05, end: 0);
      },
    );
  }
}

class _MovementsTab extends StatelessWidget {
  final GameSession session;
  final bool isAdmin;

  const _MovementsTab({required this.session, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final movements = session.movements.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (movements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.swap_horiz,
              size: 60,
              color: AppTheme.gold.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noMovements,
              style: GoogleFonts.lato(color: AppTheme.cream.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');
    final dateFormat = DateFormat('dd/MM HH:mm');

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: movements.length,
      itemBuilder: (context, index) {
        final movement = movements[index];
        final fromName = _getDisplayName(movement.fromPlayerId, session);
        final toName = _getDisplayName(movement.toPlayerId, session);
        final gameTag = _getGameTag(movement);

        return Dismissible(
          key: Key(movement.id),
          direction: isAdmin ? DismissDirection.endToStart : DismissDirection.none,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppTheme.accentRed,
            child: const Icon(Icons.delete, color: AppTheme.cream),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.primaryGreen,
                title: Text(
                  l10n.deleteMovement,
                  style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
                ),
                content: Text(
                  l10n.deleteMovementConfirm,
                  style: GoogleFonts.lato(color: AppTheme.cream),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.cancel, style: GoogleFonts.lato(color: AppTheme.gold)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                    child: Text(l10n.delete),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) {
            context.read<DatabaseService>().removeMovement(
              sessionId: session.id,
              movement: movement,
            );
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              fromName,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accentRed,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 16,
                                color: AppTheme.gold,
                              ),
                            ),
                            Text(
                              toName,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        currencyFormat.format(movement.amount),
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.gold,
                        ),
                      ),
                    ],
                  ),
                  if (movement.description != null && movement.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      movement.description!,
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: AppTheme.cream.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateFormat.format(movement.createdAt),
                        style: GoogleFonts.lato(
                          fontSize: 10,
                          color: AppTheme.cream.withValues(alpha: 0.4),
                        ),
                      ),
                      if (gameTag != null)
                        Text(
                          gameTag,
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.gold.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ).animate()
            .fadeIn(duration: 200.ms)
            .slideX(begin: 0.05, end: 0),
        );
      },
    );
  }

  /// Ottiene il nome da visualizzare per un player ID
  String _getDisplayName(String playerId, GameSession session) {
    switch (playerId) {
      case '_bestia_pot_':
        return 'Bestia';
      case '_piatto_':
        return 'Piatto';
      case '_piatto_vita_':
        return 'Piatto';
      default:
        return session.getPlayerName(playerId) ?? '?';
    }
  }

  /// Ottiene il tag del gioco basandosi sulla descrizione del movimento
  String? _getGameTag(Movement movement) {
    final desc = movement.description;
    if (desc == null || desc.isEmpty) return null;
    
    if (desc.contains('🦁') || desc.contains('Bestia')) {
      return 'Bestia';
    } else if (desc.contains('7½') || desc.contains('7️⃣') || desc.contains('Sette e mezzo')) {
      return '7½';
    } else if (desc.contains('🐦') || desc.contains('Cucù')) {
      return 'Cucù';
    } else if (desc.contains('3️⃣1️⃣') || desc.contains('31')) {
      return '31';
    } else if (desc.contains('🎰') || desc.contains('Las Vegas')) {
      return 'Las Vegas';
    } else if (desc.contains('🎴')) {
      return 'Libera';
    }
    return null;
  }
}

class _PlayersTab extends StatelessWidget {
  final GameSession session;
  final bool isAdmin;

  const _PlayersTab({required this.session, required this.isAdmin});

  Future<void> _generateJoinCode(BuildContext context, Player player) async {
    final l10n = AppLocalizations.of(context)!;
    final dbService = context.read<DatabaseService>();
    
    try {
      final joinCode = await dbService.generatePlayerJoinCode(
        sessionId: session.id,
        player: player,
      );
      
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.primaryGreen,
            title: Text(
              l10n.inviteCodeGenerated,
              style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.shareCodeToJoinAs(player.name),
                  style: GoogleFonts.lato(color: AppTheme.cream),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.gold),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        joinCode,
                        style: GoogleFonts.lato(
                          color: AppTheme.gold,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: joinCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.codeCopied),
                              backgroundColor: AppTheme.primaryGreen,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, color: AppTheme.gold),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.codeUserEntersAsPlayer,
                  style: GoogleFonts.lato(
                    color: AppTheme.cream.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.close, style: GoogleFonts.lato(color: AppTheme.gold)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.error}: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _removePlayer(BuildContext context, Player player) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          l10n.deletePlayer,
          style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deletePlayerConfirm(player.name),
              style: GoogleFonts.lato(color: AppTheme.cream),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.accentRed.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.warningMovementsDeleted,
                      style: GoogleFonts.lato(
                        color: AppTheme.accentRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel, style: GoogleFonts.lato(color: AppTheme.gold)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await context.read<DatabaseService>().removePlayer(
        sessionId: session.id,
        player: player,
        deleteMovements: true,
      );
    }
  }

  void _showPlayerOptions(BuildContext context, Player player) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.primaryGreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.cream.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              player.name,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.cream,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              player.isLinkedToUser ? l10n.linkedToAccount : l10n.notLinkedToAccount,
              style: GoogleFonts.lato(
                fontSize: 12,
                color: AppTheme.cream.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.link, color: AppTheme.gold),
              title: Text(
                player.joinCode != null ? l10n.viewInviteCode : l10n.generateInviteCode,
                style: GoogleFonts.lato(color: AppTheme.cream),
              ),
              subtitle: Text(
                player.isLinkedToUser 
                    ? l10n.generateCodeToReplace
                    : l10n.generateCodeToLetSomeoneJoin,
                style: GoogleFonts.lato(
                  fontSize: 11,
                  color: AppTheme.cream.withValues(alpha: 0.5),
                ),
              ),
              onTap: () async {
                // Salva il context del Navigator prima di chiudere il bottom sheet
                final navigatorContext = Navigator.of(context).context;
                Navigator.pop(context);
                if (player.joinCode != null) {
                  _showExistingJoinCode(navigatorContext, player);
                } else {
                  await _generateJoinCode(navigatorContext, player);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.accentRed),
              title: Text(
                l10n.deletePlayer,
                style: GoogleFonts.lato(color: AppTheme.accentRed),
              ),
              subtitle: Text(
                l10n.alsoRemovesMovements,
                style: GoogleFonts.lato(
                  fontSize: 11,
                  color: AppTheme.accentRed.withValues(alpha: 0.7),
                ),
              ),
              onTap: () async {
                // Salva il context del Navigator prima di chiudere il bottom sheet
                final navigatorContext = Navigator.of(context).context;
                Navigator.pop(context);
                await _removePlayer(navigatorContext, player);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showExistingJoinCode(BuildContext context, Player player) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          l10n.activeInviteCode,
          style: GoogleFonts.playfairDisplay(color: AppTheme.cream),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.codeToJoinAs(player.name),
              style: GoogleFonts.lato(color: AppTheme.cream),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.gold),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    player.joinCode!,
                    style: GoogleFonts.lato(
                      color: AppTheme.gold,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: player.joinCode!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.codeCopied),
                          backgroundColor: AppTheme.primaryGreen,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, color: AppTheme.gold),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await context.read<DatabaseService>().removePlayerJoinCode(
                sessionId: session.id,
                player: player,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.codeInvalidated),
                    backgroundColor: AppTheme.primaryGreen,
                  ),
                );
              }
            },
            child: Text(l10n.invalidateCode, style: GoogleFonts.lato(color: AppTheme.accentRed)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close, style: GoogleFonts.lato(color: AppTheme.gold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final players = session.players.toList()
      ..sort((a, b) => a.isAdmin ? -1 : (b.isAdmin ? 1 : a.name.compareTo(b.name)));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  backgroundColor: player.isAdmin
                      ? AppTheme.gold.withValues(alpha: 0.2)
                      : player.isLinkedToUser 
                          ? Colors.green.withValues(alpha: 0.2)
                          : AppTheme.accentRed.withValues(alpha: 0.2),
                  child: Text(
                    player.name[0].toUpperCase(),
                    style: GoogleFonts.playfairDisplay(
                      fontWeight: FontWeight.bold,
                      color: player.isAdmin 
                          ? AppTheme.gold 
                          : player.isLinkedToUser 
                              ? Colors.green 
                              : AppTheme.accentRed,
                    ),
                  ),
                ),
                if (player.hasActiveJoinCode)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryGreen, width: 2),
                      ),
                      child: const Icon(Icons.link, size: 8, color: AppTheme.primaryGreen),
                    ),
                  ),
              ],
            ),
            title: Text(
              player.name,
              style: GoogleFonts.playfairDisplay(
                fontWeight: FontWeight.bold,
                color: AppTheme.cream,
              ),
            ),
            subtitle: Text(
              player.isAdmin 
                  ? l10n.administrator 
                  : player.isLinkedToUser 
                      ? l10n.linked 
                      : player.hasActiveJoinCode 
                          ? l10n.activeInvite 
                          : l10n.notLinked,
              style: GoogleFonts.lato(
                fontSize: 12,
                color: player.hasActiveJoinCode 
                    ? AppTheme.gold.withValues(alpha: 0.7)
                    : AppTheme.cream.withValues(alpha: 0.5),
              ),
            ),
            trailing: isAdmin && !player.isAdmin
                ? IconButton(
                    onPressed: () => _showPlayerOptions(context, player),
                    icon: const Icon(Icons.more_vert),
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  )
                : null,
          ),
        ).animate()
          .fadeIn(duration: 200.ms)
          .slideX(begin: 0.05, end: 0);
      },
    );
  }
}


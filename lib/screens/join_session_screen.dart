import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'session_detail_screen.dart';

class JoinSessionScreen extends StatefulWidget {
  final String? shareCode;
  
  const JoinSessionScreen({super.key, this.shareCode});

  @override
  State<JoinSessionScreen> createState() => _JoinSessionScreenState();
}

class _JoinSessionScreenState extends State<JoinSessionScreen> {
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLoading = false;
  bool _isPlayerInviteCode = false;

  @override
  void initState() {
    super.initState();
    if (widget.shareCode != null) {
      _codeController.text = widget.shareCode!;
      _checkCodeType();
    }
    final user = context.read<AuthService>().currentUser;
    if (user != null && !user.isAnonymous) {
      _nicknameController.text = user.displayName ?? '';
    }
    _codeController.addListener(_checkCodeType);
  }

  void _checkCodeType() {
    final code = _codeController.text.trim().toUpperCase();
    final isPlayerCode = code.startsWith('P') && code.length >= 2;
    if (isPlayerCode != _isPlayerInviteCode) {
      setState(() {
        _isPlayerInviteCode = isPlayerCode;
      });
    }
  }

  @override
  void dispose() {
    _codeController.removeListener(_checkCodeType);
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _joinSession() async {
    final l10n = AppLocalizations.of(context)!;
    if (_codeController.text.trim().isEmpty) {
      _showError(l10n.enterSessionCode);
      return;
    }
    
    final code = _codeController.text.trim().toUpperCase();
    
    // Se è un codice di invito per giocatore (inizia con P)
    if (code.startsWith('P')) {
      await _joinAsExistingPlayer(code);
      return;
    }
    
    // Altrimenti è un codice sessione normale
    if (_nicknameController.text.trim().isEmpty) {
      _showError(l10n.enterYourNickname);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final dbService = context.read<DatabaseService>();
      
      // Se l'utente non è autenticato, fai il login anonimo
      if (authService.currentUser == null) {
        await authService.signInAnonymously();
      }
      
      // Cerca la sessione
      final session = await dbService.getSessionByShareCode(code);
      
      if (session == null) {
        _showError(l10n.sessionNotFound);
        return;
      }
      
      if (!session.isActive) {
        _showError(l10n.sessionClosed);
        return;
      }
      
      // Controlla se esiste già un giocatore con lo stesso nickname
      final nickname = _nicknameController.text.trim();
      final nicknameExists = session.players.any(
        (p) => p.name.toLowerCase() == nickname.toLowerCase(),
      );
      
      if (nicknameExists) {
        _showError(l10n.nicknameExists);
        return;
      }
      
      // Crea SEMPRE un nuovo giocatore (con un nuovo userId)
      final user = authService.currentUser;
      final userId = user?.uid;
      final isUserLoggedIn = user != null && !user.isAnonymous;
      await dbService.joinSession(
        sessionId: session.id,
        playerName: nickname,
        userId: userId,
        isUserLoggedIn: isUserLoggedIn,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(sessionId: session.id),
          ),
        );
      }
    } catch (e) {
      _showError('Errore: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _joinAsExistingPlayer(String joinCode) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final dbService = context.read<DatabaseService>();
      
      // Se l'utente non è autenticato, fai il login anonimo
      if (authService.currentUser == null) {
        await authService.signInAnonymously();
      }
      
      // Cerca la sessione tramite il codice di invito del giocatore
      final result = await dbService.getSessionByPlayerJoinCode(joinCode);
      
      if (result == null) {
        _showError(l10n.inviteCodeInvalid);
        return;
      }
      
      final session = result.session;
      final player = result.player;
      
      if (!session.isActive) {
        _showError(l10n.sessionClosed);
        return;
      }
      
      final user = authService.currentUser;
      final userId = user?.uid;
      final isUserLoggedIn = user != null && !user.isAnonymous;
      
      // Collega l'utente al giocatore esistente (sostituisce qualsiasi associazione precedente)
      await dbService.linkUserToPlayer(
        sessionId: session.id,
        player: player,
        userId: userId!,
        isUserLoggedIn: isUserLoggedIn,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.welcomePlayer(player.name)),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(sessionId: session.id),
          ),
        );
      }
    } catch (e) {
      _showError('Errore: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.accentRed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.joinTitle),
      ),
      body: ChristmasBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.group_add_outlined,
                  size: 60,
                  color: AppTheme.gold,
                ).animate()
                  .fadeIn(duration: 400.ms)
                  .scale(),
                
                const SizedBox(height: 24),
                
                Text(
                  l10n.joinExistingSession,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cream,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ).animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 40),
                
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _codeController,
                          style: GoogleFonts.lato(
                            color: AppTheme.cream,
                            fontSize: 20,
                            letterSpacing: 4,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: _isPlayerInviteCode ? l10n.playerInviteCode : l10n.sessionCode,
                            hintText: l10n.sessionCodeHint,
                            prefixIcon: Icon(
                              _isPlayerInviteCode ? Icons.person_add : Icons.key,
                              color: AppTheme.gold,
                            ),
                          ),
                        ),
                        
                        if (_isPlayerInviteCode) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: AppTheme.gold, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.personalInviteCodeInfo,
                                    style: GoogleFonts.lato(
                                      color: AppTheme.gold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 20),
                          
                          TextField(
                            controller: _nicknameController,
                            style: GoogleFonts.lato(color: AppTheme.cream),
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: l10n.yourNickname,
                              hintText: l10n.howYouWantToBeCalled,
                              prefixIcon: const Icon(Icons.person, color: AppTheme.gold),
                            ),
                          ),
                        ],
                        
                        const SizedBox(height: 32),
                        
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _joinSession,
                          icon: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.cream,
                                  ),
                                )
                              : Icon(_isPlayerInviteCode ? Icons.person_add : Icons.login),
                          label: Text(_isLoading 
                              ? l10n.joining 
                              : _isPlayerInviteCode 
                                  ? l10n.linkToPlayer 
                                  : l10n.enterSession),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 24),
                
                Text(
                  l10n.askCreatorForCode,
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: AppTheme.cream.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ).animate()
                  .fadeIn(delay: 600.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



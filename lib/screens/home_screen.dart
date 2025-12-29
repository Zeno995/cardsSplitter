import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/session.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'create_session_screen.dart';
import 'session_detail_screen.dart';
import 'join_session_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _handleCreateSession(BuildContext context, bool isLoggedIn) {
    if (isLoggedIn) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CreateSessionScreen(),
        ),
      );
    } else {
      // Se non loggato, mostra la schermata di login
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const LoginScreen(returnToCreateSession: true),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = context.watch<AuthService>();
    final dbService = context.read<DatabaseService>();
    final user = authService.currentUser;
    // Un utente è considerato "loggato" solo se non è anonimo
    final isFullyLoggedIn = user != null && !user.isAnonymous;

    return Scaffold(
      body: ChristmasBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.hello,
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              color: AppTheme.cream.withValues(alpha: 0.7),
                            ),
                          ),
                          Text(
                            isFullyLoggedIn 
                                ? (user.displayName ?? user.email?.split('@').first ?? l10n.player)
                                : l10n.guest,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.gold,
                            ),
                          ),
                        ],
                      ).animate()
                        .fadeIn(duration: 500.ms)
                        .slideX(begin: -0.2, end: 0),
                    ),
                    if (isFullyLoggedIn)
                      IconButton(
                        onPressed: () => authService.signOut(),
                        icon: const Icon(Icons.logout, color: AppTheme.gold),
                        tooltip: l10n.logout,
                      ).animate()
                        .fadeIn(delay: 300.ms, duration: 500.ms)
                    else
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.login, color: AppTheme.gold),
                        label: Text(
                          l10n.login,
                          style: GoogleFonts.lato(color: AppTheme.gold),
                        ),
                      ).animate()
                        .fadeIn(delay: 300.ms, duration: 500.ms),
                  ],
                ),
              ),
              
              // Azioni rapide
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.add_circle_outline,
                        title: l10n.newSession,
                        color: AppTheme.accentRed,
                        onTap: () => _handleCreateSession(context, isFullyLoggedIn),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.group_add_outlined,
                        title: l10n.join,
                        color: AppTheme.gold,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const JoinSessionScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ).animate()
                  .fadeIn(delay: 200.ms, duration: 500.ms)
                  .slideY(begin: 0.2, end: 0),
              ),
              
              const SizedBox(height: 24),
              
              // Titolo lista (solo se loggato con account completo)
              if (isFullyLoggedIn) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.casino, color: AppTheme.gold, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        l10n.yourSessions,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.cream,
                        ),
                      ),
                    ],
                  ),
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 500.ms),
                
                const SizedBox(height: 16),
                
                // Lista sessioni
                Expanded(
                  child: StreamBuilder<List<GameSession>>(
                    stream: dbService.streamUserSessions(user.uid),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppTheme.gold),
                        );
                      }
                      
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            '${l10n.error}: ${snapshot.error}',
                            style: GoogleFonts.lato(color: AppTheme.cream),
                          ),
                        );
                      }
                      
                      final sessions = snapshot.data ?? [];
                      
                      if (sessions.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.casino_outlined,
                                size: 80,
                                color: AppTheme.gold.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.noSessionsYet,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 18,
                                  color: AppTheme.cream.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.createNewSessionToStart,
                                style: GoogleFonts.lato(
                                  fontSize: 14,
                                  color: AppTheme.cream.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ).animate()
                            .fadeIn(delay: 600.ms, duration: 600.ms),
                        );
                      }
                      
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: sessions.length,
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          final isAdmin = session.adminId == user.uid;
                          return _SessionCard(session: session, isAdmin: isAdmin)
                            .animate()
                            .fadeIn(duration: 200.ms)
                            .slideX(begin: 0.05, end: 0);
                        },
                      );
                    },
                  ),
                ),
              ] else ...[
                // Messaggio per utenti non loggati
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.group_outlined,
                          size: 80,
                          color: AppTheme.gold.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.welcome,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.cream.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            l10n.joinExistingOrLoginToCreate,
                            style: GoogleFonts.lato(
                              fontSize: 14,
                              color: AppTheme.cream.withValues(alpha: 0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ).animate()
                      .fadeIn(delay: 400.ms, duration: 600.ms),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.cream,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final GameSession session;
  final bool isAdmin;

  const _SessionCard({required this.session, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm', locale == 'it' ? 'it_IT' : 'en_US');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SessionDetailScreen(sessionId: session.id),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: session.isActive 
                      ? AppTheme.accentRed.withValues(alpha: 0.2)
                      : AppTheme.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  session.isActive ? Icons.play_circle : Icons.check_circle,
                  color: session.isActive ? AppTheme.accentRed : AppTheme.gold,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            session.name,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.cream,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin 
                                ? AppTheme.gold.withValues(alpha: 0.2)
                                : AppTheme.primaryGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isAdmin ? l10n.admin : l10n.participant,
                            style: GoogleFonts.lato(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isAdmin ? AppTheme.gold : AppTheme.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.playersAndMovements(session.players.length, session.movements.length),
                      style: GoogleFonts.lato(
                        fontSize: 12,
                        color: AppTheme.cream.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      dateFormat.format(session.createdAt),
                      style: GoogleFonts.lato(
                        fontSize: 11,
                        color: AppTheme.gold.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppTheme.gold.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



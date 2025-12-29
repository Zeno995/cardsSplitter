import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
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
                            'Ciao,',
                            style: GoogleFonts.lato(
                              fontSize: 16,
                              color: AppTheme.cream.withValues(alpha: 0.7),
                            ),
                          ),
                          Text(
                            isFullyLoggedIn 
                                ? (user.displayName ?? user.email?.split('@').first ?? 'Giocatore')
                                : 'Ospite',
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
                        tooltip: 'Esci',
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
                          'Accedi',
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
                        title: 'Nuova Sessione',
                        color: AppTheme.accentRed,
                        onTap: () => _handleCreateSession(context, isFullyLoggedIn),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.group_add_outlined,
                        title: 'Unisciti',
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
                        'Le tue sessioni',
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
                            'Errore: ${snapshot.error}',
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
                                'Nessuna sessione ancora',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 18,
                                  color: AppTheme.cream.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Crea una nuova sessione per iniziare!',
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
                          return _SessionCard(session: session)
                            .animate(delay: Duration(milliseconds: 100 * index))
                            .fadeIn(duration: 400.ms)
                            .slideX(begin: 0.1, end: 0);
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
                          'Benvenuto!',
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
                            'Unisciti a una sessione esistente o accedi per crearne una nuova',
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

  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm', 'it_IT');
    
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
                    Text(
                      session.name,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.players.length} giocatori • ${session.movements.length} movimenti',
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



import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'session_detail_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthService>().currentUser;
    _nicknameController.text = user?.displayName ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    final l10n = AppLocalizations.of(context)!;
    if (_nameController.text.trim().isEmpty) {
      _showError(l10n.enterSessionName);
      return;
    }
    if (_nicknameController.text.trim().isEmpty) {
      _showError(l10n.enterYourNickname);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final dbService = context.read<DatabaseService>();
      final user = authService.currentUser!;

      final session = await dbService.createSession(
        name: _nameController.text.trim(),
        adminId: user.uid,
        adminName: _nicknameController.text.trim(),
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
      _showError(l10n.creationError(e.toString()));
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
        title: Text(l10n.newSessionTitle),
      ),
      body: ChristmasBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  size: 60,
                  color: AppTheme.gold,
                ).animate()
                  .fadeIn(duration: 400.ms)
                  .scale(),
                
                const SizedBox(height: 24),
                
                Text(
                  l10n.createNewGameSession,
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
                          controller: _nameController,
                          style: GoogleFonts.lato(color: AppTheme.cream),
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: l10n.sessionName,
                            hintText: l10n.sessionNameHint,
                            prefixIcon: const Icon(Icons.casino, color: AppTheme.gold),
                          ),
                        ),
                        
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
                        
                        const SizedBox(height: 32),
                        
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _createSession,
                          icon: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.cream,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: Text(_isLoading ? l10n.creating : l10n.createSession),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 24),
                
                Text(
                  l10n.afterCreatingYouCanShare,
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



import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/game_mode.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';
import 'session_detail_screen.dart';
import 'select_game_mode_screen.dart';

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isLoading = false;
  GameMode _selectedGameMode = const GameMode(type: GameType.libera);

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

  Future<void> _selectGameMode() async {
    final result = await Navigator.push<GameMode>(
      context,
      MaterialPageRoute(
        builder: (_) => SelectGameModeScreen(initialMode: _selectedGameMode),
      ),
    );
    
    if (result != null) {
      setState(() => _selectedGameMode = result);
    }
  }

  Future<void> _createSession() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('Inserisci un nome per la sessione');
      return;
    }
    if (_nicknameController.text.trim().isEmpty) {
      _showError('Inserisci il tuo nickname');
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
        gameMode: _selectedGameMode,
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
      _showError('Errore nella creazione: $e');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuova Sessione'),
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
                  'Crea una nuova\nsessione di gioco',
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
                          decoration: const InputDecoration(
                            labelText: 'Nome sessione',
                            hintText: 'es. Tombola di Natale 2024',
                            prefixIcon: Icon(Icons.casino, color: AppTheme.gold),
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        TextField(
                          controller: _nicknameController,
                          style: GoogleFonts.lato(color: AppTheme.cream),
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Il tuo nickname',
                            hintText: 'Come vuoi essere chiamato',
                            prefixIcon: Icon(Icons.person, color: AppTheme.gold),
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Selettore modalità di gioco
                        InkWell(
                          onTap: _selectGameMode,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.darkGreen.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _selectedGameMode.icon,
                                  style: const TextStyle(fontSize: 28),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Modalità di gioco',
                                        style: GoogleFonts.lato(
                                          fontSize: 12,
                                          color: AppTheme.cream.withValues(alpha: 0.6),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedGameMode.displayName,
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.gold,
                                        ),
                                      ),
                                      if (_selectedGameMode.variantDisplayName != null)
                                        Text(
                                          _selectedGameMode.variantDisplayName!,
                                          style: GoogleFonts.lato(
                                            fontSize: 12,
                                            color: AppTheme.cream.withValues(alpha: 0.7),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppTheme.gold,
                                ),
                              ],
                            ),
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
                          label: Text(_isLoading ? 'Creazione...' : 'Crea Sessione'),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 24),
                
                Text(
                  'Dopo la creazione potrai condividere\nil link con i tuoi amici',
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



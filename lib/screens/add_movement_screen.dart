import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/session.dart';
import '../models/player.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../theme/app_theme.dart';

class AddMovementScreen extends StatefulWidget {
  final GameSession session;
  final String? currentPlayerId;
  final bool isAdmin;

  const AddMovementScreen({
    super.key,
    required this.session,
    this.currentPlayerId,
    this.isAdmin = false,
  });

  @override
  State<AddMovementScreen> createState() => _AddMovementScreenState();
}

class _AddMovementScreenState extends State<AddMovementScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  Player? _fromPlayer;
  Player? _toPlayer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-seleziona il giocatore corrente come "da"
    if (widget.currentPlayerId != null) {
      _fromPlayer = widget.session.players.firstWhere(
        (p) => p.id == widget.currentPlayerId,
        orElse: () => widget.session.players.first,
      );
    }
  }

  // Per i non-admin, il "da" è sempre fisso sul proprio giocatore
  bool get _canChangeFromPlayer => widget.isAdmin;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _addMovement() async {
    if (_fromPlayer == null || _toPlayer == null) {
      _showError('Seleziona entrambi i giocatori');
      return;
    }
    if (_fromPlayer!.id == _toPlayer!.id) {
      _showError('I giocatori devono essere diversi');
      return;
    }

    final amount = double.tryParse(
      _amountController.text.replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      _showError('Inserisci un importo valido');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final dbService = context.read<DatabaseService>();

      await dbService.addMovement(
        sessionId: widget.session.id,
        fromPlayerId: _fromPlayer!.id,
        toPlayerId: _toPlayer!.id,
        amount: amount,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        createdBy: authService.currentUser?.uid ?? 'anonymous',
      );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Movimento aggiunto!'),
            backgroundColor: AppTheme.primaryGreen,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuovo Movimento'),
      ),
      body: ChristmasBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registra un pagamento',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.cream,
                  ),
                  textAlign: TextAlign.center,
                ).animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: -0.2, end: 0),
                
                const SizedBox(height: 32),
                
                // Da chi
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.accentRed.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.arrow_upward,
                                color: AppTheme.accentRed,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Da chi (paga)',
                                style: GoogleFonts.lato(
                                  color: AppTheme.cream.withValues(alpha: 0.7),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (!_canChangeFromPlayer)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.gold.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Tu',
                                  style: GoogleFonts.lato(
                                    color: AppTheme.gold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_canChangeFromPlayer)
                          DropdownButtonFormField<Player>(
                            value: _fromPlayer,
                            decoration: const InputDecoration(
                              hintText: 'Seleziona giocatore',
                            ),
                            dropdownColor: AppTheme.primaryGreen,
                            style: GoogleFonts.lato(color: AppTheme.cream),
                            items: widget.session.players.map((player) {
                              return DropdownMenuItem(
                                value: player,
                                child: Text(player.name),
                              );
                            }).toList(),
                            onChanged: (value) => setState(() => _fromPlayer = value),
                          )
                        else
                          // Campo fisso per non-admin
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.darkGreen.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.cream.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              _fromPlayer?.name ?? 'Non assegnato',
                              style: GoogleFonts.lato(
                                color: AppTheme.cream,
                                fontSize: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideX(begin: -0.1, end: 0),
                
                // Freccia
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_downward,
                        color: AppTheme.gold,
                        size: 28,
                      ),
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .scale(),
                
                // A chi
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.arrow_downward,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'A chi (riceve)',
                              style: GoogleFonts.lato(
                                color: AppTheme.cream.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<Player>(
                          value: _toPlayer,
                          decoration: const InputDecoration(
                            hintText: 'Seleziona giocatore',
                          ),
                          dropdownColor: AppTheme.primaryGreen,
                          style: GoogleFonts.lato(color: AppTheme.cream),
                          items: widget.session.players
                              .where((p) => p.id != _fromPlayer?.id)
                              .map((player) {
                            return DropdownMenuItem(
                              value: player,
                              child: Text(player.name),
                            );
                          }).toList(),
                          onChanged: (value) => setState(() => _toPlayer = value),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0),
                
                const SizedBox(height: 24),
                
                // Importo
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Importo',
                          style: GoogleFonts.lato(
                            color: AppTheme.cream.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.lato(
                            color: AppTheme.gold,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            prefixText: '€ ',
                            prefixStyle: GoogleFonts.lato(
                              color: AppTheme.gold,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                            hintText: '0.00',
                            hintStyle: GoogleFonts.lato(
                              color: AppTheme.gold.withValues(alpha: 0.3),
                              fontSize: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
                
                const SizedBox(height: 16),
                
                // Descrizione
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _descriptionController,
                      style: GoogleFonts.lato(color: AppTheme.cream),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descrizione (opzionale)',
                        hintText: 'es. Vittoria a poker',
                        prefixIcon: Icon(Icons.note, color: AppTheme.gold),
                      ),
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 500.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0),
                
                const SizedBox(height: 32),
                
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _addMovement,
                  icon: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.cream,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Text(_isLoading ? 'Salvataggio...' : 'Salva Movimento'),
                ).animate()
                  .fadeIn(delay: 600.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



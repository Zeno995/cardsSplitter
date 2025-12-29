import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';

/// Widget che mostra un tastierino per aggiungere rapidamente importi
/// ai campi di testo. I valori disponibili sono: 10c, 20c, 50c, 1€, 2€, 5€
class AmountKeypad extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onChanged;
  
  const AmountKeypad({
    super.key,
    required this.controller,
    this.onChanged,
  });

  void _addAmount(double amount) {
    final currentText = controller.text.replaceAll(',', '.');
    final currentValue = double.tryParse(currentText) ?? 0;
    final newValue = currentValue + amount;
    controller.text = newValue.toStringAsFixed(2);
    onChanged?.call();
  }

  void _clearAmount() {
    controller.clear();
    onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.quickAdd,
              style: GoogleFonts.lato(
                color: AppTheme.cream.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _clearAmount,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear,
                      size: 14,
                      color: AppTheme.accentRed.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.clear,
                      style: GoogleFonts.lato(
                        color: AppTheme.accentRed.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Riga centesimi
        Row(
          children: [
            Expanded(
              child: _AmountButton(
                label: '10c',
                amount: 0.10,
                onTap: () => _addAmount(0.10),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AmountButton(
                label: '20c',
                amount: 0.20,
                onTap: () => _addAmount(0.20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AmountButton(
                label: '50c',
                amount: 0.50,
                onTap: () => _addAmount(0.50),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Riga euro
        Row(
          children: [
            Expanded(
              child: _AmountButton(
                label: '1€',
                amount: 1.0,
                onTap: () => _addAmount(1.0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AmountButton(
                label: '2€',
                amount: 2.0,
                onTap: () => _addAmount(2.0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AmountButton(
                label: '5€',
                amount: 5.0,
                onTap: () => _addAmount(5.0),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AmountButton extends StatelessWidget {
  final String label;
  final double amount;
  final VoidCallback onTap;

  const _AmountButton({
    required this.label,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.gold.withValues(alpha: 0.2),
                AppTheme.gold.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.gold.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.lato(
                color: AppTheme.gold,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


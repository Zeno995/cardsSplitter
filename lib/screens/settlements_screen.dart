import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/session.dart';
import '../services/debt_solver_service.dart';
import '../theme/app_theme.dart';

class SettlementsScreen extends StatelessWidget {
  final GameSession session;

  const SettlementsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final debtSolver = DebtSolverService();
    final settlements = debtSolver.calculateSettlements(session);
    final currencyFormat = NumberFormat.currency(locale: 'it_IT', symbol: '€');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settleDebts),
      ),
      body: ChristmasBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.gold.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.calculate,
                        size: 40,
                        color: AppTheme.gold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.optimalSolution,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.cream,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.minTransfersToSettle,
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        color: AppTheme.cream.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ).animate()
                .fadeIn(duration: 500.ms)
                .slideY(begin: -0.2, end: 0),

              // Lista trasferimenti
              Expanded(
                child: settlements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 80,
                              color: Colors.green.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.allGood,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.noDebtsToSettle,
                              style: GoogleFonts.lato(
                                fontSize: 14,
                                color: AppTheme.cream.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ).animate()
                          .fadeIn(delay: 300.ms, duration: 500.ms)
                          .scale(),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: settlements.length,
                        itemBuilder: (context, index) {
                          final settlement = settlements[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  // Numero
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppTheme.gold.withValues(alpha: 0.2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.gold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  
                                  // Da -> A
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppTheme.accentRed.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                settlement.fromPlayerName,
                                                style: GoogleFonts.lato(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.accentRed,
                                                ),
                                              ),
                                            ),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(horizontal: 8),
                                              child: Icon(
                                                Icons.arrow_forward,
                                                size: 20,
                                                color: AppTheme.gold,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                settlement.toPlayerName,
                                                style: GoogleFonts.lato(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.owesTo,
                                          style: GoogleFonts.lato(
                                            fontSize: 11,
                                            color: AppTheme.cream.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Importo
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.gold.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppTheme.gold.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      currencyFormat.format(settlement.amount),
                                      style: GoogleFonts.lato(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.gold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ).animate()
                            .fadeIn(duration: 200.ms)
                            .slideX(begin: 0.05, end: 0);
                        },
                      ),
              ),

              // Footer
              if (settlements.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.gold.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppTheme.gold,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.transfersNeeded(settlements.length),
                              style: GoogleFonts.lato(
                                fontSize: 14,
                                color: AppTheme.cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate()
                  .fadeIn(delay: Duration(milliseconds: 100 * settlements.length + 200), duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}



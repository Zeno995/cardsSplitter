import '../models/session.dart';
import '../models/debt_settlement.dart';

class DebtSolverService {
  /// Calcola la soluzione ottimale per saldare tutti i debiti
  /// usando un algoritmo greedy che minimizza il numero di transazioni
  List<DebtSettlement> calculateSettlements(GameSession session) {
    final balances = session.calculateBalances();
    final settlements = <DebtSettlement>[];
    
    // Separa creditori e debitori
    final debtors = <String, double>{}; // chi deve dare soldi (bilancio negativo)
    final creditors = <String, double>{}; // chi deve ricevere soldi (bilancio positivo)
    
    balances.forEach((playerId, balance) {
      if (balance < -0.01) {
        debtors[playerId] = -balance; // convertiamo in positivo
      } else if (balance > 0.01) {
        creditors[playerId] = balance;
      }
    });
    
    // Ordina per importo (dal più grande al più piccolo)
    final sortedDebtors = debtors.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedCreditors = creditors.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    // Algoritmo greedy per minimizzare le transazioni
    int debtorIndex = 0;
    int creditorIndex = 0;
    
    while (debtorIndex < sortedDebtors.length && 
           creditorIndex < sortedCreditors.length) {
      final debtor = sortedDebtors[debtorIndex];
      final creditor = sortedCreditors[creditorIndex];
      
      final amount = debtor.value < creditor.value 
          ? debtor.value 
          : creditor.value;
      
      if (amount > 0.01) {
        settlements.add(DebtSettlement(
          fromPlayerId: debtor.key,
          fromPlayerName: session.getPlayerName(debtor.key) ?? 'Sconosciuto',
          toPlayerId: creditor.key,
          toPlayerName: session.getPlayerName(creditor.key) ?? 'Sconosciuto',
          amount: _roundToTwoDecimals(amount),
        ));
      }
      
      // Aggiorna i valori rimanenti
      sortedDebtors[debtorIndex] = MapEntry(
        debtor.key, 
        debtor.value - amount,
      );
      sortedCreditors[creditorIndex] = MapEntry(
        creditor.key, 
        creditor.value - amount,
      );
      
      // Passa al prossimo se il debito/credito è stato saldato
      if (sortedDebtors[debtorIndex].value < 0.01) {
        debtorIndex++;
      }
      if (sortedCreditors[creditorIndex].value < 0.01) {
        creditorIndex++;
      }
    }
    
    return settlements;
  }
  
  double _roundToTwoDecimals(double value) {
    return (value * 100).round() / 100;
  }
}




# Cards Splitter 🎄

App Flutter per gestire i conti dei giochi natalizi. Tieni traccia di debiti e crediti tra giocatori e calcola automaticamente la soluzione ottimale per saldare tutti i conti!

## Funzionalità

- ✅ **Autenticazione**: Login con Google o Email/Password
- ✅ **Sessioni di gioco**: Crea sessioni e invita amici con un codice
- ✅ **Tracking movimenti**: Registra pagamenti tra giocatori in tempo reale
- ✅ **Calcolo automatico**: Algoritmo che minimizza i trasferimenti per saldare i debiti
- ✅ **Multi-piattaforma**: iOS e Android

## Setup

### 1. Prerequisiti

- Flutter SDK (>=3.7.2)
- Firebase account
- Xcode (per iOS)
- Android Studio (per Android)

### 2. Configurazione Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Crea un nuovo progetto
3. Abilita **Authentication** con i provider:
   - Email/Password
   - Google
   - Anonymous (per ospiti)
4. Crea un database **Cloud Firestore** in modalità production
5. Configura le regole di sicurezza (vedi sotto)

### 3. FlutterFire CLI

```bash
# Installa FlutterFire CLI
dart pub global activate flutterfire_cli

# Configura Firebase nel progetto
flutterfire configure
```

Questo comando genererà automaticamente il file `lib/firebase_options.dart` con le tue credenziali.

### 4. Regole Firestore

Vai su Firestore > Rules e aggiungi:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Sessioni
    match /sessions/{sessionId} {
      // Chiunque autenticato può leggere sessioni
      allow read: if request.auth != null;
      
      // Solo l'admin può creare, modificare ed eliminare
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && 
        request.auth.uid == resource.data.adminId;
    }
  }
}
```

### 5. Configurazione Google Sign-In

#### iOS
Aggiungi il `GoogleService-Info.plist` in `ios/Runner/`

Nel file `ios/Runner/Info.plist`, aggiungi:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string><!-- REVERSED_CLIENT_ID dal GoogleService-Info.plist --></string>
    </array>
  </dict>
</array>
```

#### Android
Aggiungi `google-services.json` in `android/app/`

Nel file `android/app/build.gradle.kts`, verifica che sia presente:
```kotlin
plugins {
    id("com.google.gms.google-services")
}
```

### 6. Esecuzione

```bash
# Installa dipendenze
flutter pub get

# Esegui su iOS
flutter run -d ios

# Esegui su Android
flutter run -d android
```

## Struttura del Progetto

```
lib/
├── main.dart                 # Entry point
├── firebase_options.dart     # Config Firebase (generato)
├── models/
│   ├── player.dart          # Modello giocatore
│   ├── movement.dart        # Modello movimento
│   ├── session.dart         # Modello sessione
│   └── debt_settlement.dart # Modello soluzione debiti
├── services/
│   ├── auth_service.dart    # Autenticazione
│   ├── database_service.dart # Operazioni Firestore
│   └── debt_solver_service.dart # Algoritmo saldo debiti
├── screens/
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── create_session_screen.dart
│   ├── join_session_screen.dart
│   ├── session_detail_screen.dart
│   ├── add_movement_screen.dart
│   └── settlements_screen.dart
└── theme/
    └── app_theme.dart       # Tema natalizio
```

## Come Funziona

1. **Admin crea sessione**: L'utente registrato crea una nuova sessione di gioco
2. **Condivisione codice**: Viene generato un codice univoco (es. `ABC12345`)
3. **Ospiti si uniscono**: Gli amici inseriscono il codice e un nickname
4. **Registrazione movimenti**: Durante il gioco si registrano i pagamenti
5. **Calcolo finale**: L'algoritmo calcola i trasferimenti minimi per saldare

## Algoritmo Debt Solver

L'algoritmo utilizza un approccio greedy per minimizzare il numero di transazioni:

1. Calcola il bilancio netto di ogni giocatore
2. Separa creditori (bilancio positivo) e debitori (bilancio negativo)
3. Ordina entrambi per importo decrescente
4. Abbina iterativamente il più grande debitore con il più grande creditore
5. Risultato: numero minimo di trasferimenti per saldare tutti i debiti

## Licenza

MIT License

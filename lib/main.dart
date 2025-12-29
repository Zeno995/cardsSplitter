import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/join_session_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  await initializeDateFormatting('it_IT', null);
  
  runApp(const CardsSplitterApp());
}

class CardsSplitterApp extends StatelessWidget {
  const CardsSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        Provider(create: (_) => DatabaseService()),
      ],
      child: MaterialApp(
        title: 'Cards Splitter',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('it'),
        ],
        home: const AuthWrapper(),
        onGenerateRoute: (settings) {
          // Deep link handling per join session
          final uri = Uri.tryParse(settings.name ?? '');
          if (uri != null && uri.pathSegments.isNotEmpty) {
            if (uri.pathSegments.first == 'join') {
              final code = uri.pathSegments.length > 1 
                  ? uri.pathSegments[1] 
                  : uri.queryParameters['code'];
              if (code != null) {
                return MaterialPageRoute(
                  builder: (_) => JoinSessionScreen(shareCode: code),
                );
              }
            }
          }
          return null;
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    
    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: ChristmasBackground(
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              ),
            ),
          );
        }
        
        // Mostra sempre la HomeScreen, indipendentemente dallo stato di login
        return const HomeScreen();
      },
    );
  }
}

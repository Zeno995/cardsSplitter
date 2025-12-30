import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colori natalizi eleganti
  static const Color primaryGreen = Color(0xFF1B4332);
  static const Color accentRed = Color(0xFFB91C1C);
  static const Color gold = Color(0xFFD4AF37);
  static const Color cream = Color(0xFFFDF8F3);
  static const Color darkGreen = Color(0xFF0D1F17);
  static const Color lightGold = Color(0xFFF5E6C8);
  
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkGreen,
      primaryColor: primaryGreen,
      colorScheme: const ColorScheme.dark(
        primary: gold,
        secondary: accentRed,
        surface: primaryGreen,
        onPrimary: darkGreen,
        onSecondary: cream,
        onSurface: cream,
      ),
      textTheme: GoogleFonts.playfairDisplayTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            color: gold,
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
          displayMedium: TextStyle(
            color: cream,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
          headlineMedium: TextStyle(
            color: cream,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: cream,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: cream,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: cream,
            fontSize: 14,
          ),
        ),
      ).apply(
        bodyColor: cream,
        displayColor: gold,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.playfairDisplay(
          color: gold,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: gold),
      ),
      cardTheme: CardTheme(
        color: primaryGreen.withValues(alpha: 0.8),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: gold.withValues(alpha: 0.3), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentRed,
          foregroundColor: cream,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.playfairDisplay(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: gold,
          side: const BorderSide(color: gold, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.playfairDisplay(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkGreen.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold.withValues(alpha: 0.5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: gold.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: gold, width: 2),
        ),
        labelStyle: GoogleFonts.lato(color: cream.withValues(alpha: 0.7)),
        hintStyle: GoogleFonts.lato(color: cream.withValues(alpha: 0.5)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accentRed,
        foregroundColor: cream,
      ),
      dividerTheme: DividerThemeData(
        color: gold.withValues(alpha: 0.3),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: primaryGreen,
        contentTextStyle: GoogleFonts.lato(color: cream),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// Decorazione per sfondo natalizio
class ChristmasBackground extends StatelessWidget {
  final Widget child;
  
  const ChristmasBackground({super.key, required this.child});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.darkGreen,
            AppTheme.primaryGreen,
            AppTheme.darkGreen,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Pattern decorativo
          Positioned.fill(
            child: CustomPaint(
              painter: _SnowflakePatternPainter(),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _SnowflakePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.gold.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;
    
    // Disegna pattern decorativo sottile
    for (int i = 0; i < 20; i++) {
      for (int j = 0; j < 30; j++) {
        if ((i + j) % 3 == 0) {
          canvas.drawCircle(
            Offset(
              i * size.width / 20,
              j * size.height / 30,
            ),
            3,
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}




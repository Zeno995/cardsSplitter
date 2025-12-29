import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'create_session_screen.dart';

class LoginScreen extends StatefulWidget {
  final bool returnToCreateSession;
  
  const LoginScreen({super.key, this.returnToCreateSession = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    if (widget.returnToCreateSession) {
      // Sostituisci la schermata di login con la creazione sessione
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CreateSessionScreen(),
        ),
      );
    } else {
      // Torna indietro alla home
      Navigator.pop(context);
    }
  }

  Future<void> _handleEmailAuth() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Inserisci email e password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      if (_isLogin) {
        await authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      } else {
        await authService.registerWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );
      }
      if (mounted) _onLoginSuccess();
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await context.read<AuthService>().signInWithGoogle();
      if (mounted) _onLoginSuccess();
    } catch (e) {
      _showError(e.toString());
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
      appBar: widget.returnToCreateSession 
          ? AppBar(
              title: const Text('Accedi per creare'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: ChristmasBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: widget.returnToCreateSession ? 20 : 60),
                
                // Logo e titolo
                Icon(
                  Icons.casino_outlined,
                  size: 80,
                  color: AppTheme.gold,
                ).animate()
                  .fadeIn(duration: 600.ms)
                  .scale(delay: 200.ms),
                
                const SizedBox(height: 24),
                
                Text(
                  'Cards Splitter',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.gold,
                  ),
                  textAlign: TextAlign.center,
                ).animate()
                  .fadeIn(delay: 300.ms, duration: 600.ms)
                  .slideY(begin: 0.3, end: 0),
                
                const SizedBox(height: 8),
                
                Text(
                  'Gestisci i conti dei tuoi giochi natalizi',
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: AppTheme.cream.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).animate()
                  .fadeIn(delay: 500.ms, duration: 600.ms),
                
                const SizedBox(height: 60),
                
                // Form
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _isLogin ? 'Accedi' : 'Registrati',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.lato(color: AppTheme.cream),
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined, color: AppTheme.gold),
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: GoogleFonts.lato(color: AppTheme.cream),
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline, color: AppTheme.gold),
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleEmailAuth,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.cream,
                                  ),
                                )
                              : Text(_isLogin ? 'Accedi' : 'Registrati'),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        TextButton(
                          onPressed: () => setState(() => _isLogin = !_isLogin),
                          child: Text(
                            _isLogin
                                ? 'Non hai un account? Registrati'
                                : 'Hai già un account? Accedi',
                            style: GoogleFonts.lato(color: AppTheme.gold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate()
                  .fadeIn(delay: 700.ms, duration: 600.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 24),
                
                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: AppTheme.gold.withValues(alpha: 0.3))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'oppure',
                        style: GoogleFonts.lato(
                          color: AppTheme.cream.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppTheme.gold.withValues(alpha: 0.3))),
                  ],
                ).animate()
                  .fadeIn(delay: 900.ms, duration: 600.ms),
                
                const SizedBox(height: 24),
                
                // Google Sign In
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continua con Google'),
                ).animate()
                  .fadeIn(delay: 1000.ms, duration: 600.ms)
                  .slideY(begin: 0.2, end: 0),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



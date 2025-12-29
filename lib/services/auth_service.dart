import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  
  User? get currentUser => _auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Login con Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      notifyListeners();
      return userCredential;
    } catch (e) {
      debugPrint('Errore login Google: $e');
      rethrow;
    }
  }

  // Login con Email e Password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return userCredential;
    } catch (e) {
      debugPrint('Errore login email: $e');
      rethrow;
    }
  }

  // Registrazione con Email e Password
  Future<UserCredential?> registerWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return userCredential;
    } catch (e) {
      debugPrint('Errore registrazione: $e');
      rethrow;
    }
  }

  // Login Anonimo (per ospiti)
  Future<UserCredential?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      notifyListeners();
      return userCredential;
    } catch (e) {
      debugPrint('Errore login anonimo: $e');
      rethrow;
    }
  }

  // Logout
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    notifyListeners();
  }

  // Aggiorna il nome utente
  Future<void> updateDisplayName(String name) async {
    await currentUser?.updateDisplayName(name);
    notifyListeners();
  }
}



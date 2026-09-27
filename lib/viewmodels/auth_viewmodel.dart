import 'package:flutter/foundation.dart';
import '../services/supabase_service.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel({SupabaseService? service}) : _service = service ?? SupabaseService();

  final SupabaseService _service;

  bool isSignUp = true;
  bool isLoading = false;
  String? errorMessage;

  // Fields for sign up form
  String email = '';
  String password = '';
  String confirmPassword = '';

  void toggleMode() {
    isSignUp = !isSignUp;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> signUp(String emailArg, String passwordArg) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final res = await _service.signUp(email: emailArg, password: passwordArg);
      if (res.user == null) {
        errorMessage = 'Sign up failed';
        return false;
      }

      // If signUp didn't create an active session, attempt to sign in to force session creation.
      if (res.session == null) {
        final signInRes = await _service.signIn(email: emailArg, password: passwordArg);
        if (signInRes.user == null || signInRes.session == null) {
          errorMessage = 'Sign up succeeded but signing in to create a session failed.';
          return false;
        }
      }

      // Success and session available
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String emailArg, String passwordArg) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final res = await _service.signIn(email: emailArg, password: passwordArg);
      if (res.user == null) {
        errorMessage = 'Sign in failed';
        return false;
      }
      return true;
    } catch (e) {
      errorMessage = e.toString();
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Sends an SMS OTP to [phone]. Also creates the user account with email/password if necessary.

  /// Returns whether the user with [userId] has a completed profile in the 'profiles' table.
  Future<bool> hasCompletedProfile(String userId) async {
    try {
      return await _service.hasProfile(userId);
    } catch (e) {
      // On error, default to false and surface message
      errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }
}

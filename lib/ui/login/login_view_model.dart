import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../error_message.dart';

class LoginViewModel extends ChangeNotifier {
  LoginViewModel({required this._repository});

  final AuthRepository _repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Returns `true` when the user is logged in and the token is stored.
  Future<bool> login(String username, String password) async {
    if (_isLoading) return false;

    final user = username.trim();
    if (user.isEmpty || password.isEmpty) {
      _errorMessage = 'Please enter your username and password.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.login(username: user, password: password);
      return true;
    } catch (e) {
      _errorMessage = errorMessageFor(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }
}

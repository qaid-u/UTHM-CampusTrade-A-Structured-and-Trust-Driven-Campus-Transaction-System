import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'database_service.dart';

class AuthService extends ChangeNotifier {
  AuthService._();

  static final AuthService instance = AuthService._();

  UserModel? _currentUser;
  UserModel? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<String?> login(String email, String password) async {
    final user = DatabaseService.instance.findUserByEmail(email.trim());
    if (user == null || user.password != password) {
      return 'Invalid email or password.';
    }
    _currentUser = user;
    notifyListeners();
    return null;
  }

  Future<String?> register({
    required String name,
    required String studentId,
    required String email,
    required String phone,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    if (name.trim().length < 3) return 'Name must be at least 3 characters.';
    if (!RegExp(r'^[A-Za-z]{1,4}\d{6,}$').hasMatch(studentId.trim())) {
      return 'Use a valid UTHM-style student ID, e.g. CB220101.';
    }
    if (!cleanEmail.endsWith('@student.uthm.edu.my')) {
      return 'Use your @student.uthm.edu.my email.';
    }
    if (!RegExp(r'^\d{9,12}$').hasMatch(phone.trim())) {
      return 'Enter a valid Malaysian phone number without spaces.';
    }
    if (password.length < 8) return 'Password must be at least 8 characters.';
    if (DatabaseService.instance.findUserByEmail(cleanEmail) != null) {
      return 'This email is already registered.';
    }

    final user = UserModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      studentId: studentId.trim().toUpperCase(),
      email: cleanEmail,
      phone: phone.trim(),
      password: password,
    );
    await DatabaseService.instance.addUser(user);
    _currentUser = user;
    notifyListeners();
    return null;
  }

  void refreshCurrentUser() {
    if (_currentUser == null) return;
    _currentUser = DatabaseService.instance.findUser(_currentUser!.id);
    notifyListeners();
  }

  void logout() {
    _currentUser = null;
    notifyListeners();
  }
}

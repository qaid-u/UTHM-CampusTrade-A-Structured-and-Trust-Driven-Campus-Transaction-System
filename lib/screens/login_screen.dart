import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/feedback_helper.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _studentId = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _studentId,
                decoration: const InputDecoration(labelText: "Student ID"),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Password"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: Text(_loading ? "Loading..." : "Login"),
              ),

              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
                child: const Text("Create account"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    // Validate input
    if (_studentId.text.trim().isEmpty) {
      FeedbackHelper.showError(context, "Please enter your Student ID");
      return;
    }

    if (_password.text.trim().isEmpty) {
      FeedbackHelper.showError(context, "Please enter your password");
      return;
    }

    setState(() => _loading = true);

    try {
      final error = await AuthService.instance.login(
        studentId: _studentId.text.trim(),
        password: _password.text.trim(),
      );

      // Check if widget is still mounted before calling setState
      if (!mounted) return;

      setState(() => _loading = false);

      if (error != null) {
        // Show specific error messages
        if (error.contains('user-not-found') ||
            error.contains('wrong-password')) {
          FeedbackHelper.showError(
            context,
            "Invalid Student ID or password. Please try again.",
          );
        } else if (error.contains('network')) {
          FeedbackHelper.showError(
            context,
            "Network error. Please check your internet connection.",
          );
        } else {
          FeedbackHelper.showError(context, "Login failed: $error");
        }
      } else {
        FeedbackHelper.showSuccess(context, "Welcome back!");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      FeedbackHelper.showError(context, "An unexpected error occurred");
    }
  }
}

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/feedback_helper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _studentId = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Register")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field(_name, "Full Name"),
              _field(_studentId, "Student ID"),
              _field(_phone, "Phone Number"),
              _field(_password, "Password", obscure: true),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _loading ? null : _register,
                child: Text(_loading ? "Creating..." : "Register"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool obscure = false}) {
    return TextFormField(
      controller: c,
      obscureText: obscure,
      decoration: InputDecoration(labelText: label),
      validator: (v) => v == null || v.isEmpty ? "Required" : null,
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      FeedbackHelper.showWarning(
        context,
        "Please fill in all fields correctly",
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final error = await AuthService.instance.register(
        name: _name.text.trim(),
        studentId: _studentId.text.trim(),
        phone: _phone.text.trim(),
        password: _password.text.trim(),
      );

      // Check if widget is still mounted before calling setState
      if (!mounted) return;

      setState(() => _loading = false);

      if (error != null) {
        // Show specific error messages
        if (error.contains('email-already-in-use') ||
            error.contains('Student ID')) {
          FeedbackHelper.showError(
            context,
            "This Student ID is already registered. Please login instead.",
          );
        } else if (error.contains('weak-password')) {
          FeedbackHelper.showError(
            context,
            "Password is too weak. Use at least 6 characters.",
          );
        } else if (error.contains('network')) {
          FeedbackHelper.showError(
            context,
            "Network error. Please check your internet connection.",
          );
        } else {
          FeedbackHelper.showError(context, "Registration failed: $error");
        }
        return;
      }

      // Success
      FeedbackHelper.showSuccess(context, "Account created successfully!");

      // Navigate back to login
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      FeedbackHelper.showError(context, "An unexpected error occurred");
    }
  }
}

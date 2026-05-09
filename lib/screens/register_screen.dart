import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/custom_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _studentId = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _studentId.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _field(_name, 'Full name', Icons.badge_rounded),
                _field(_studentId, 'Student ID', Icons.school_rounded),
                _field(_email, 'UTHM student email', Icons.mail_rounded),
                _field(
                  _phone,
                  'Phone number',
                  Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                _field(
                  _password,
                  'Password',
                  Icons.lock_rounded,
                  obscure: true,
                ),
                const SizedBox(height: 16),
                CustomButton(
                  label: 'Register',
                  icon: Icons.check_circle_rounded,
                  onPressed: _register,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Required field.' : null,
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final error = await AuthService.instance.register(
      name: _name.text,
      studentId: _studentId.text,
      email: _email.text,
      phone: _phone.text,
      password: _password.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

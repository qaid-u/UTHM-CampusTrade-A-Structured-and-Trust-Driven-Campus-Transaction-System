import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/custom_button.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: 'aina@student.uthm.edu.my');
  final _password = TextEditingController(text: 'password123');
  late final AnimationController _pulse;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.94,
      upperBound: 1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ScaleTransition(
                    scale: _pulse,
                    child: const CircleAvatar(
                      radius: 44,
                      backgroundColor: Color(0xFF0B2D5B),
                      child: Icon(
                        Icons.storefront_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'UTHMCampus Trade',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0B2D5B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Safe campus buying, selling, and trading.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Student email',
                      prefixIcon: Icon(Icons.mail_rounded),
                    ),
                    validator: (value) {
                      if (value == null ||
                          !value.endsWith('@student.uthm.edu.my')) {
                        return 'Use your @student.uthm.edu.my email.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_rounded),
                    ),
                    validator: (value) => (value ?? '').length < 8
                        ? 'Password must be at least 8 characters.'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  CustomButton(
                    label: _loading ? 'Signing in...' : 'Login',
                    icon: Icons.login_rounded,
                    onPressed: _loading ? null : _login,
                  ),
                  const SizedBox(height: 12),
                  CustomButton(
                    label: 'Create student account',
                    icon: Icons.person_add_alt_1_rounded,
                    isSecondary: true,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final error = await AuthService.instance.login(_email.text, _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/media_feedback_service.dart';
import '../theme/app_theme.dart';
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
  void dispose() {
    _studentId.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.08),
              const _AnimatedLoginLogo(),
              const SizedBox(height: 18),
              Text(
                "UTHM Campus Trade",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "A structured and trust-driven campus transaction system",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
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
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.05),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    // Validate input
    if (_studentId.text.trim().isEmpty) {
      MediaFeedbackService.instance.playError();
      FeedbackHelper.showError(context, "Please enter your Student ID");
      return;
    }

    if (_password.text.trim().isEmpty) {
      MediaFeedbackService.instance.playError();
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
        MediaFeedbackService.instance.playError();
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
        MediaFeedbackService.instance.playSuccess();
        FeedbackHelper.showSuccess(context, "Welcome back!");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      MediaFeedbackService.instance.playError();
      FeedbackHelper.showError(context, "An unexpected error occurred");
    }
  }
}

class _AnimatedLoginLogo extends StatelessWidget {
  const _AnimatedLoginLogo();

  static const _logoPath = 'assets/images/uthm_campustrade_logo.png';

  @override
  Widget build(BuildContext context) {
    final logoSize = (MediaQuery.sizeOf(context).width * 0.34).clamp(
      96.0,
      148.0,
    );

    // Interactive media element: logo entrance uses a lightweight fade/scale.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0);
        final scale = 0.88 + (0.12 * opacity);

        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        width: logoSize,
        height: logoSize,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.softBlue,
        ),
        clipBehavior: Clip.antiAlias,
        // UTHM CampusTrade branding shown on the login entry point.
        child: Image.asset(
          _logoPath,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.storefront_rounded,
              size: 56,
              color: AppColors.electricBlue,
            );
          },
        ),
      ),
    );
  }
}

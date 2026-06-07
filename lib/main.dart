import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_config_service.dart';
import 'services/auth_service.dart';
import 'services/fcm_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const CampusTradeApp());

  _initializeOptionalServices();
}

Future<void> _initializeOptionalServices() async {
  // Optional startup services run after first paint so network delays cannot
  // leave the app on a blank native screen.
  try {
    await AppConfigService.instance.load();
  } catch (e) {
    debugPrint('App config initialization failed (non-fatal): $e');
  }

  try {
    await FCMService.instance.initialize();
  } catch (e) {
    debugPrint('FCM initialization failed (non-fatal): $e');
  }

  try {
    await SubscriptionService.instance.init();
  } catch (e) {
    debugPrint('Subscription init failed (non-fatal): $e');
  }
}

class CampusTradeApp extends StatelessWidget {
  const CampusTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: FCMService.instance.navigatorKey,
      theme: AppTheme.light,
      home: const AuthGate(),
      builder: (context, child) {
        return Scaffold(body: child ?? const SizedBox());
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () {}, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return const MainShell();
      },
    );
  }
}

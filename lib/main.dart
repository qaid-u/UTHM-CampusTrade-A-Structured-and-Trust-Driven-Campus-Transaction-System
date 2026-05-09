import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.load();
  runApp(const CampusTradeApp());
}

class CampusTradeApp extends StatelessWidget {
  const CampusTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UTHMCampus Trade',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0B2D5B),
          primary: const Color(0xFF0B2D5B),
          secondary: const Color(0xFF1BA86D),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5EAF1)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E2EC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E2EC)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: AuthService.instance,
        builder: (context, _) {
          return AuthService.instance.isLoggedIn
              ? const MainShell()
              : const LoginScreen();
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'screens/auth_gate.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadApiBaseUrl();
  runApp(const RoutePumpApp());
}

class RoutePumpApp extends StatelessWidget {
  const RoutePumpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoutePump mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9), // Slate 100
        cardColor: const Color(0xFFFFFFFF), // White
        primaryColor: const Color(0xFF059669), // Emerald green
        hintColor: const Color(0xFF1E3A8A), // Navy blue
        fontFamily: 'Outfit',
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

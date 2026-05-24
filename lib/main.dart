// main.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LimpoApp());
}

class LimpoApp extends StatefulWidget {
  const LimpoApp({super.key});

  @override
  State<LimpoApp> createState() => _LimpoAppState();
}

class _LimpoAppState extends State<LimpoApp> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeApp());
  }

  Future<void> _initializeApp() async {
    // Request all runtime permissions up-front
    await [
      Permission.microphone,
      Permission.phone,
      Permission.contacts,
      Permission.sms,
    ].request();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Limpo Assistant',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}
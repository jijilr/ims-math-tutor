import 'package:flutter/material.dart';
import 'screens/tutor_home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InteractiveMathTutorApp());
}

class InteractiveMathTutorApp extends StatelessWidget {
  const InteractiveMathTutorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Interactive Math Tutor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF1A1A1A),
          outline: Color(0xFFE5E5E5),
          error: Color(0xFFDC2626),
        ),
      ),
      home: const TutorHomeScreen(),
    );
  }
}

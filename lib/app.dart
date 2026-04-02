import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/screens/login_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTSP Audio Mixer',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const LoginScreen(),
    );
  }
}

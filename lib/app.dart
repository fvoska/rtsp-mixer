import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RTSP Audio Mixer',
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Text('RTSP Audio Mixer'),
        ),
      ),
    );
  }
}

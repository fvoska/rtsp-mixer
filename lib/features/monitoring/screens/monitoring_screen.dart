import 'package:flutter/material.dart';

/// Placeholder monitoring screen for Phase 2.
///
/// Will be replaced with audio streaming controls, volume sliders,
/// and audio level meters in Phase 2.
class MonitoringScreen extends StatelessWidget {
  const MonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoring'),
      ),
      body: const Center(
        child: Text('Audio streaming coming in Phase 2'),
      ),
    );
  }
}

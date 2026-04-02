import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';

void main() {
  AppLogger.instance.init();
  appLog('APP', 'Starting RTSP Audio Mixer');
  runApp(const ProviderScope(child: App()));
}

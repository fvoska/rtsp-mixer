import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AppLogger.instance.init();
  appLog('APP', 'Starting RTSP Audio Mixer');
  runApp(const ProviderScope(child: App()));
}

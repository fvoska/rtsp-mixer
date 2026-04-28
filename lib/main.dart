import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/logging/app_logger.dart';
import 'core/services/foreground_service.dart';
import 'core/services/local_notifications.dart';

void main() {
  FlutterForegroundTask.initCommunicationPort();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  AppLogger.instance.init();
  ForegroundServiceManager.init();
  // ignore: unawaited_futures
  LocalNotificationsManager.init();
  appLog('APP', 'Starting RTSP Mixer');
  runApp(const ProviderScope(child: App()));
}

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../logging/app_logger.dart';

/// Manages the 5-minute camera-offline alert channel (D-04).
/// - Idempotent init (mirrors ForegroundServiceManager pattern)
/// - Uses `baby_monitor_alert` channel at Importance.max for heads-up display
/// - Skips full-screen intent (Android 14 restricts FSI to calling/alarm apps)
/// - POST_NOTIFICATIONS permission is already granted by MonitoringScreen.initState
///   (covers both FGS and alert channels — app-wide grant)
class LocalNotificationsManager {
  LocalNotificationsManager._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Register the Android channel + plugin. Safe to call multiple times.
  /// Call from main() alongside ForegroundServiceManager.init().
  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Windows: `flutter_local_notifications` v21+ requires explicit
      // initialization settings when the plugin loads on Windows, otherwise
      // every show()/cancel() throws "must be initialized before use". The
      // GUID is a stable random identifier for the notification activation
      // callback; appUserModelId mirrors the Android/macOS bundle ID.
      const windowsInit = WindowsInitializationSettings(
        appName: 'RTSP Mixer',
        appUserModelId: 'tech.voska.rtsp_mixer',
        guid: '9b5e3f8a-7c4d-4a2e-bf91-8d6c5e4f3a2b',
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          windows: windowsInit,
        ),
      );
      const channel = AndroidNotificationChannel(
        'baby_monitor_alert',
        'Camera Offline Alerts',
        description: 'Fires when a camera has been offline for 5 minutes',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _initialized = true;
      appLog('NOTIF',
          'LocalNotificationsManager initialized (channel=baby_monitor_alert)');
    } catch (e) {
      // Defensive: never let init failures block app startup.
      appLog('NOTIF', 'init failed: $e');
    }
  }

  /// Fire a heads-up notification for one camera (D-04).
  /// Notification ID is derived from cameraId.hashCode — subsequent
  /// fires for the same camera overwrite the previous notification.
  static Future<void> fireAlert({
    required String cameraId,
    required String cameraName,
  }) async {
    try {
      await init();
      appLog('NOTIF', 'Fire alert for $cameraName ($cameraId)');
      const details = AndroidNotificationDetails(
        'baby_monitor_alert',
        'Camera Offline Alerts',
        channelDescription:
            'Fires when a camera has been offline for 5 minutes',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        autoCancel: true,
        ongoing: false,
        ticker: 'Camera offline',
      );
      const windowsDetails = WindowsNotificationDetails(
        scenario: WindowsNotificationScenario.alarm,
      );
      await _plugin.show(
        id: cameraId.hashCode,
        title: 'Camera offline: $cameraName',
        body: 'No audio for 5 minutes. Tap to check.',
        notificationDetails: const NotificationDetails(
          android: details,
          windows: windowsDetails,
        ),
      );
    } catch (e) {
      // Defensive: never let notification failures kill the monitoring loop.
      appLog('NOTIF', 'fireAlert failed for $cameraName: $e');
    }
  }

  /// Dismiss a previously-fired alert (called if camera recovers fast enough
  /// that the user hasn't dismissed the notification themselves).
  static Future<void> cancelAlert(String cameraId) async {
    try {
      appLog('NOTIF', 'Cancel alert for $cameraId');
      await _plugin.cancel(id: cameraId.hashCode);
    } catch (e) {
      appLog('NOTIF', 'cancelAlert failed for $cameraId: $e');
    }
  }
}

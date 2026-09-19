// ignore_for_file: avoid_print
import 'dart:io' show Platform;

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../logging/app_logger.dart';

/// Top-level callback entry point for the foreground service.
/// Must be annotated to survive tree-shaking in release builds.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MonitoringTaskHandler());
}

/// Manages the foreground service lifecycle for overnight audio monitoring.
/// Handles init, start, stop, and notification updates.
class ForegroundServiceManager {
  static bool _initialized = false;

  /// Which of the two long-running features currently need the service.
  /// One Android service carries both: monitoring (media playback) and
  /// host mode (microphone). The service type is fixed at start, so when
  /// the second feature joins and needs a type the running service lacks,
  /// the service is restarted with the union — a brief notification
  /// flicker, versus Android 14+ denying microphone access to a service
  /// that was started as media-playback only.
  static bool _monitorActive = false;
  static bool _hostActive = false;
  static Set<ForegroundServiceTypes> _runningTypes = {};
  static String _monitorTitle = 'Listening';
  static String _monitorText = 'Monitoring';
  static String _hostName = 'Phone camera';

  /// Buttons for the monitor's notification (pause toggles mute-all).
  static const _monitorButtons = [
    NotificationButton(id: 'pause', text: 'Pause'),
    NotificationButton(id: 'stop', text: 'Stop'),
  ];

  /// Buttons for the host-only notification.
  static const _hostButtons = [
    NotificationButton(id: 'stop_host', text: 'Stop sharing'),
  ];

  static Set<ForegroundServiceTypes> get _neededTypes => {
        if (_monitorActive || !_hostActive) ForegroundServiceTypes.mediaPlayback,
        if (_hostActive) ForegroundServiceTypes.microphone,
      };

  /// Initialize FlutterForegroundTask options. Call once during app startup
  /// or before first use. Safe to call multiple times (idempotent).
  ///
  /// On non-Android platforms (Windows desktop, macOS, web) the foreground
  /// service layer is unsupported — this returns immediately so the rest of
  /// the app keeps running with media_kit audio only. Per CLAUDE.md
  /// "Defensive error handling — prefer degraded functionality over crash."
  static void init() {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_initialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'baby_monitor_service',
        channelName: 'Roomtone',
        channelDescription: 'Audio monitoring is active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
    appLog('FGS', 'Foreground service options initialized');
  }

  /// Branding for the ongoing-monitoring notification.
  ///
  /// NOTE on the API surface: `AndroidNotificationOptions` in
  /// flutter_foreground_task 9.2.2 exposes NO icon or accent-colour field —
  /// verified against the installed pub-cache source, not assumed. The icon
  /// travels on `startService(notificationIcon:)` instead, and it is addressed
  /// by the name of an AndroidManifest `<meta-data>` entry pointing at a
  /// drawable, not by a resource path. If the lookup fails, the plugin's
  /// native side catches it and falls back to the app icon, so a wrong name
  /// degrades the notification's look and never its behaviour.
  static const _notificationIcon = NotificationIcon(
    metaDataName: 'com.rtspmixer.notification.icon',
    backgroundColor: Color(0xFF3FBFAD),
  );

  /// Start the foreground service with camera names in the notification.
  ///
  /// [title] defaults to the healthy copy; callers that already know the
  /// session's health should pass the status-derived title (see
  /// `sessionNotificationTitle`) so the very first notification doesn't claim
  /// "Listening" over a camera that failed to open.
  static Future<void> start(
    List<String> cameraNames, {
    String title = 'Listening',
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      appLog('FGS',
          'Foreground service unsupported on this platform — skipping start');
      return;
    }
    init();
    final notificationText = 'Monitoring: ${cameraNames.join(", ")}';
    _monitorActive = true;
    _monitorTitle = title;
    _monitorText = notificationText;
    await _ensureRunning(
      title: title,
      text: notificationText,
      buttons: _monitorButtons,
    );
    appLog('FGS', 'Foreground service started: $notificationText');
  }

  /// Start (or fold into the running service) the host-mode notification.
  /// Host mode captures the microphone, so the service must carry the
  /// `microphone` type — Android 14+ blocks background mic access
  /// otherwise. The manifest declares `mediaPlayback|microphone`; the
  /// actual types requested here are always a subset of that.
  static Future<void> startHost(String hostName) async {
    if (kIsWeb || !Platform.isAndroid) {
      appLog('FGS', 'Foreground service unsupported on this platform — host '
          'mode runs without it');
      return;
    }
    init();
    _hostActive = true;
    _hostName = hostName;
    if (_monitorActive) {
      // Monitoring owns the notification copy; only the type may change.
      await _ensureRunning(
        title: _monitorTitle,
        text: _monitorText,
        buttons: _monitorButtons,
      );
    } else {
      await _ensureRunning(
        title: _hostTitle,
        text: _hostText,
        buttons: _hostButtons,
      );
    }
    appLog('FGS', 'Host mode foreground service active');
  }

  static String get _hostTitle => 'Sharing microphone';
  static String get _hostText => 'This phone is a camera: "$_hostName"';

  /// Host mode ended. Keeps the service when monitoring still needs it.
  static Future<void> stopHost() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _hostActive = false;
    if (_monitorActive) {
      appLog('FGS', 'Host stopped — monitoring keeps the service');
      return;
    }
    await FlutterForegroundTask.stopService();
    _runningTypes = {};
    appLog('FGS', 'Foreground service stopped (host)');
  }

  /// Start the service with the currently needed types, restarting it when
  /// the running instance lacks one of them. Idempotent for the same set.
  static Future<void> _ensureRunning({
    required String title,
    required String text,
    required List<NotificationButton> buttons,
  }) async {
    final needed = _neededTypes;
    final running = await FlutterForegroundTask.isRunningService;
    if (running && _runningTypes.containsAll(needed)) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
        notificationIcon: _notificationIcon,
        notificationButtons: buttons,
      );
      return;
    }
    if (running) {
      appLog('FGS',
          'Restarting service to add types ${needed.difference(_runningTypes).map((t) => t.rawValue)}');
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        appLog('FGS', 'stopService before restart failed (continuing): $e');
      }
    }
    await FlutterForegroundTask.startService(
      serviceId: 256,
      serviceTypes: needed.toList(),
      notificationTitle: title,
      notificationText: text,
      notificationIcon: _notificationIcon,
      notificationButtons: buttons,
      callback: startCallback,
    );
    _runningTypes = needed;
  }

  /// Update the notification text and title, e.g. when connection status
  /// changes. [title] defaults to the healthy copy for callers that only have
  /// text to say; status-aware callers pass `sessionNotificationTitle`.
  static Future<void> updateNotification({
    required String text,
    String title = 'Listening',
    List<NotificationButton>? notificationButtons,
  }) async {
    // Silent no-op on non-Android — this is a high-frequency caller and
    // logging every skip would spam.
    if (kIsWeb || !Platform.isAndroid) return;
    appLog('FGS', 'Notification update: $text');
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      // Re-supplied on every update: the plugin rebuilds the notification from
      // what it is handed, so omitting this would silently revert the small
      // icon to the app icon on the first status change.
      notificationIcon: _notificationIcon,
      notificationButtons: notificationButtons,
    );
  }

  /// Stop the foreground service. Releases wake lock and WiFi lock.
  ///
  /// When host mode is still sharing the microphone the service is kept and
  /// its notification flips to the host copy instead — stopping it would
  /// silently kill the nursery phone's stream.
  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _monitorActive = false;
    if (_hostActive) {
      appLog('FGS', 'Monitoring stopped — host mode keeps the service');
      try {
        await FlutterForegroundTask.updateService(
          notificationTitle: _hostTitle,
          notificationText: _hostText,
          notificationIcon: _notificationIcon,
          notificationButtons: _hostButtons,
        );
      } catch (e) {
        appLog('FGS', 'host notification handover failed (continuing): $e');
      }
      return;
    }
    await FlutterForegroundTask.stopService();
    _runningTypes = {};
    appLog('FGS', 'Foreground service stopped');
  }

  /// Whether the foreground service is currently running.
  static Future<bool> get isRunning {
    if (kIsWeb || !Platform.isAndroid) return Future.value(false);
    return FlutterForegroundTask.isRunningService;
  }
}

/// TaskHandler callback that runs inside the foreground **service isolate**.
/// Players live in the main isolate — this handler only receives
/// notification actions and forwards them via sendDataToMain.
///
/// NOTE: appLog() does NOT work here (different isolate). Use print()
/// for debugging — visible in `adb logcat -s flutter`.
class MonitoringTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    print('[FGS] TaskHandler.onStart (starter=$starter)');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    print('[FGS] TaskHandler.onDestroy (isTimeout=$isTimeout)');
  }

  @override
  void onNotificationButtonPressed(String id) {
    print('[FGS] Notification button pressed: $id');
    if (id == 'pause' || id == 'stop' || id == 'stop_host') {
      FlutterForegroundTask.sendDataToMain(id);
    }
  }

  @override
  void onNotificationPressed() {
    print('[FGS] Notification body pressed');
  }
}

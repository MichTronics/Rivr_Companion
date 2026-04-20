import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the Android foreground-service isolate.
/// Must be a top-level function so it can be passed across isolate boundaries.
@pragma('vm:entry-point')
void rivrForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_RivrTaskHandler());
}

/// Minimal task handler — all real work stays in the main isolate.
/// The foreground service exists solely to keep the process alive on Android.
class _RivrTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

/// Call once at app startup (before runApp).
void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'rivr_connection',
      channelName: 'Rivr Mesh Connection',
      channelDescription:
          'Keeps the mesh connection and data upload active in the background.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWifiLock: true,
    ),
  );
}

/// Start (or update) the foreground service with [statusText] in the notification.
Future<void> startForegroundService(String statusText) async {
  final isRunning = await FlutterForegroundTask.isRunningService;
  if (isRunning) {
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Rivr Companion',
      notificationText: statusText,
    );
  } else {
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Rivr Companion',
      notificationText: statusText,
      callback: rivrForegroundCallback,
    );
  }
}

/// Stop the foreground service (called on disconnect).
Future<void> stopForegroundService() async {
  await FlutterForegroundTask.stopService();
}

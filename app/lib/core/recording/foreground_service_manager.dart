import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages foreground service for background recording
class ForegroundServiceManager {
  static bool _isInitialized = false;
  static bool _isRunning = false;

  /// Initialize the foreground service
  static Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'replay_recording_channel',
        channelName: 'Recording Service',
        channelDescription: 'This notification appears when Replay is recording audio.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    _isInitialized = true;
  }

  /// Start the foreground service
  static Future<bool> start() async {
    if (kIsWeb || !_isInitialized) return false;

    // Android-specific: request battery optimization exemption
    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    }

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Recording in progress',
      notificationText: 'Tap to return to the app',
      callback: startCallback,
    );

    if (result is ServiceRequestSuccess) {
      _isRunning = true;
    }

    return result is ServiceRequestSuccess;
  }

  /// Update the notification with current recording time
  static Future<void> updateNotification(Duration elapsed) async {
    if (!_isRunning || kIsWeb) return;

    final hours = elapsed.inHours;
    final minutes = elapsed.inMinutes.remainder(60);
    final seconds = elapsed.inSeconds % 60;

    final timeString = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}'
        : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Recording in progress',
      notificationText: 'Duration: $timeString - Tap to return to the app',
    );
  }

  /// Stop the foreground service
  static Future<bool> stop() async {
    if (!_isRunning || kIsWeb) return false;

    final result = await FlutterForegroundTask.stopService();
    if (result is ServiceRequestSuccess) {
      _isRunning = false;
    }
    return result is ServiceRequestSuccess;
  }

  /// Check if service is running
  static bool get isRunning => _isRunning;
}

/// Callback function for foreground task
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(RecordingTaskHandler());
}

/// Task handler for the foreground service
class RecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Called when the task starts
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Called periodically based on interval (every 5 seconds)
    // We don't need to do anything here as the notification is updated manually
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Called when the task is destroyed
  }

  @override
  void onNotificationButtonPressed(String id) {
    // Called when notification button is pressed
  }

  @override
  void onNotificationPressed() {
    // Called when notification itself is pressed
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // Called when notification is dismissed
  }
}

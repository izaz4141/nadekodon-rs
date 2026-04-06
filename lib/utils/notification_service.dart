import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:rinf/rinf.dart';
// ignore: implementation_imports
import 'package:flutter_local_notifications_linux/src/model/hint.dart';
import 'package:window_manager/window_manager.dart';

@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse details) async {
  final actionId = details.actionId;
  final payload = details.payload;

  if (payload != null) {
    final SendPort? sendPort = IsolateNameServer.lookupPortByName(
      NotificationService.notificationPortName,
    );

    if (sendPort != null) {
      // Main isolate is alive, send action to it
      sendPort.send([actionId, payload]);
    } else {
      // Main isolate is dead, initialize Rust and handle directly
      initializeRust(assignRustSignal);
      await _handleAction(actionId, payload);
    }
  }
}

Future<void> _handleAction(String? actionId, String? payload) async {
  // Handle default action (opening the app)
  if (actionId == null || actionId == 'Open' || actionId == 'View') {
    await _bringAppToForeground();
    return;
  }

  // Parse payload
  String id = payload ?? '';
  String? path;

  if (payload != null && payload.startsWith('{')) {
    try {
      final data = jsonDecode(payload);
      id = data['id'] ?? '';
      path = data['path'];
    } catch (_) {
      // Fallback to treating payload as ID if JSON parsing fails
      id = payload;
    }
  }

  if (id.isEmpty) return;

  // Handle specific actions
  switch (actionId) {
    case 'open_file':
      if (path != null) {
        await openFile(path);
      }
      break;
    case 'pause':
      PauseDownload(id: id).sendSignalToRust();
      break;
    case 'resume':
      ResumeDownload(id: id).sendSignalToRust();
      break;
    case 'cancel':
      CancelDownload(id: id).sendSignalToRust();
      break;
  }
}

Future<void> _bringAppToForeground() async {
  if (kIsWeb) return;
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }
}

class NotificationService {
  static const String notificationPortName = 'notification_action_port';
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Timer? _pollTimer;
  StreamSubscription? _signalSubscription;
  ReceivePort? _port;

  final Map<String, String> _runningDownloads = {};
  final Set<String> _stoppedDownloads = {};

  Future<void> init() async {
    if (_isInitialized) return;

    // Register port for background communication
    IsolateNameServer.removePortNameMapping(notificationPortName);
    _port = ReceivePort();
    IsolateNameServer.registerPortWithName(
      _port!.sendPort,
      notificationPortName,
    );
    _port!.listen((dynamic data) async {
      if (data is List && data.length == 2) {
        final actionId = data[0] as String?;
        final payload = data[1] as String;
        await _handleAction(actionId, payload);
      }
    });

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
          defaultActionName: 'View',
          defaultIcon: AssetsLinuxIcon('assets/icons/nadeko-don-128.png'),
        );

    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'Nadeko~don',
          appUserModelId: 'id.glicole.nadekodon',
          guid: '2c336594-33b6-4f6b-8ab1-1234567890ab',
          iconPath: 'assets/icons/nadeko-don-128.png',
        );
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          linux: kIsWeb ? null : initializationSettingsLinux,
          windows: kIsWeb ? null : initializationSettingsWindows,
        );

    await flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (NotificationResponse details) async {
        final actionId = details.actionId;
        final payload = details.payload;

        if (payload != null) {
          await _handleAction(actionId, payload);
        }
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'download_channel',
        'Downloads',
        description: 'Show download progress',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      );

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    }

    _isInitialized = true;
  }

  void startListening() {
    if (_pollTimer != null) return;

    init();

    // Poll every second ONLY for Running downloads
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      GetDownloadList(
        anchorId: null,
        before: 0,
        after: 100,
        statuses: ["Running", "Seeding"],
        tag: 2, // Notification tag
        searchQuery: null,
        sortBy: 0,
        ascending: false,
      ).sendSignalToRust();
    });

    _signalSubscription = DownloadList.rustSignalStream.listen((signal) {
      if (signal.message.tag == 2) {
        _updateNotifications(signal.message.list);
      }
    });
  }

  void stopListening() {
    IsolateNameServer.removePortNameMapping(notificationPortName);
    _port?.close();
    _port = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _signalSubscription?.cancel();
    _signalSubscription = null;
    cancelAll();
  }

  Future<void> _updateNotifications(List<DownloadGlance> items) async {
    final currentRunningIds = <String>{};

    for (final item in items) {
      final id = item.id;
      final name = item.name;

      currentRunningIds.add(id);
      _runningDownloads[id] = name;
      _stoppedDownloads.remove(id);

      final notificationId = id.hashCode;
      final total = (item.totalSize?.toBigInt())?.toInt() ?? 0;
      final downloaded = (item.downloaded.toBigInt()).toInt();
      final progress = (total > 0) ? (downloaded / total * 100).toInt() : 0;
      final speedStr = item.state == "Seeding"
          ? "${formatBytes(item.uspeed?.toInt() ?? 0)}/s"
          : "${formatBytes(item.dspeed.toInt())}/s";

      await showDownloadNotification(
        id: notificationId,
        title: name,
        progress: progress,
        speed: speedStr,
        status: item.state == "Running"
            ? DownloadStatus.running
            : DownloadStatus.seeding,
        payload: jsonEncode({'id': id}),
      );
    }

    // Check for items that were running but are no longer in the list
    final disappearedIds = _runningDownloads.keys
        .where((id) => !currentRunningIds.contains(id))
        .toList();

    for (final id in disappearedIds) {
      if (_stoppedDownloads.contains(id)) continue;

      // It just stopped running. Check its final status.
      _checkFinalStatus(id);

      // Mark as stopped so we don't keep checking it
      _stoppedDownloads.add(id);
      _runningDownloads.remove(id);
    }
  }

  Future<void> _checkFinalStatus(String id) async {
    final completer = Completer<void>();
    StreamSubscription? subscription;

    // Send request
    GetDownloadDetails(id: id).sendSignalToRust();

    // Listen for response
    subscription = DownloadDetails.rustSignalStream.listen((signal) {
      if (signal.message.id == id) {
        final item = signal.message;
        final status = parseDownloadStatus(item.state);
        final name = item.name;
        final notificationId = id.hashCode;

        showDownloadNotification(
          id: notificationId,
          title: name,
          progress:
              (item.totalSize != null &&
                  item.totalSize!.toBigInt() > BigInt.zero)
              ? (item.downloaded.toBigInt().toDouble() /
                        item.totalSize!.toBigInt().toDouble() *
                        100)
                    .toInt()
              : 0,
          speed: "", // No speed for stopped items
          status: status,
          payload: jsonEncode({'id': id, 'path': item.dest}),
        );

        subscription?.cancel();
        completer.complete();
      }
    });

    // Timeout to clean up if no response
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        subscription?.cancel();
      }
    });
  }

  Future<void> showDownloadNotification({
    required int id,
    required String title,
    required int progress,
    required String speed,
    required DownloadStatus status,
    required String? payload,
  }) async {
    if (!_isInitialized) await init();

    final isRunning =
        status == DownloadStatus.running || status == DownloadStatus.seeding;
    final isCompleted = status == DownloadStatus.completed;
    final isFailed = status == DownloadStatus.failed;
    final isPaused = status == DownloadStatus.paused;
    final isCancelled = status == DownloadStatus.cancelled;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux) && isRunning) {
      return;
    }

    // Android Notification Details
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'download_channel',
          'Downloads',
          channelDescription: 'Show download progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: isRunning,
          maxProgress: 100,
          progress: progress,
          ongoing: isRunning, // Only running is ongoing
          autoCancel: false, // Don't auto-cancel on tap
          playSound: false,
          enableVibration: false,
          actions: <AndroidNotificationAction>[
            if (isCompleted)
              const AndroidNotificationAction(
                'open_file',
                'Open',
                showsUserInterface: false,
              ),
            if (isRunning)
              const AndroidNotificationAction(
                'pause',
                'Pause',
                showsUserInterface: false,
              ),
            if (isPaused)
              const AndroidNotificationAction(
                'resume',
                'Resume',
                showsUserInterface: false,
              ),
            if (isRunning || isPaused)
              const AndroidNotificationAction(
                'cancel',
                'Cancel',
                showsUserInterface: false,
              ),
          ],
        );

    // Linux Notification Details
    final LinuxNotificationDetails linuxPlatformChannelSpecifics =
        LinuxNotificationDetails(
          category: LinuxNotificationCategory.transfer,
          urgency: LinuxNotificationUrgency.low,
          suppressSound: true,
          transient: false, // Changed to false so it stays in control center
          customHints: [
            if (isRunning)
              LinuxNotificationCustomHint(
                name: 'value',
                value: LinuxHintInt32Value(progress),
              ),
          ],
          actions: <LinuxNotificationAction>[
            if (isCompleted)
              const LinuxNotificationAction(key: 'open_file', label: 'Open'),
            if (isRunning)
              const LinuxNotificationAction(key: 'pause', label: 'Pause'),
            if (isPaused)
              const LinuxNotificationAction(key: 'resume', label: 'Resume'),
            if (isRunning || isPaused)
              const LinuxNotificationAction(key: 'cancel', label: 'Cancel'),
          ],
        );

    final WindowsNotificationDetails windowsPlatformChannelSpecifics =
        WindowsNotificationDetails(
          progressBars: [
            if (isRunning)
              WindowsProgressBar(
                id: id.toString(),
                status: status == DownloadStatus.running
                    ? 'Downloading'
                    : 'Seeding',
                value: progress / 100,
              ),
          ],
          actions: <WindowsAction>[
            if (isCompleted)
              const WindowsAction(arguments: 'open_file', content: 'Open'),
            if (isRunning)
              const WindowsAction(arguments: 'pause', content: 'Pause'),
            if (isPaused)
              const WindowsAction(arguments: 'resume', content: 'Resume'),
            if (isRunning || isPaused)
              const WindowsAction(arguments: 'cancel', content: 'Cancel'),
          ],
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      linux: linuxPlatformChannelSpecifics,
      windows: windowsPlatformChannelSpecifics,
    );

    String body = '';
    if (isRunning) {
      body = '$progress% • $speed';
    } else if (isCompleted) {
      body = 'Download completed';
    } else if (isFailed) {
      body = 'Download failed';
    } else if (isPaused) {
      body = 'Paused • $progress%';
    } else if (isCancelled) {
      body = 'Download cancelled';
    }

    await flutterLocalNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

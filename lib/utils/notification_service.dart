import 'dart:async';
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:rinf/rinf.dart';
import 'package:flutter_local_notifications_linux/src/model/hint.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse details) {
  // Initialize Rust for background isolate
  initializeRust(assignRustSignal);

  final actionId = details.actionId;
  final payload = details.payload;

  if (payload != null && actionId != null) {
    final id = payload;
    switch (actionId) {
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
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Timer? _pollTimer;
  StreamSubscription? _signalSubscription;

  final Map<String, String> _runningDownloads = {};
  final Set<String> _stoppedDownloads = {};

  Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

    final LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(
          defaultActionName: 'Open',
          defaultIcon: AssetsLinuxIcon('assets/icons/nadeko-don.png'),
        );

    final WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: 'Nadeko~don',
          appUserModelId: 'id.glicole.nadekodon',
          guid: '2c336594-33b6-4f6b-8ab1-1234567890ab',
          iconPath: 'assets/icons/nadeko-don.png',
        );
    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          linux: initializationSettingsLinux,
          windows: initializationSettingsWindows,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        final actionId = details.actionId;
        final payload = details.payload;

        if (payload != null && actionId != null) {
          final id = payload;
          switch (actionId) {
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
      },
    );

    if (Platform.isAndroid) {
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
        statuses: ["Running"],
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
      final speedStr = "${formatBytes(item.speed.toInt())}/s";

      await showDownloadNotification(
        id: notificationId,
        title: name,
        progress: progress,
        speed: speedStr,
        status: DownloadStatus.running,
        payload: id,
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
          payload: id,
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

    final isRunning = status == DownloadStatus.running;
    final isCompleted = status == DownloadStatus.completed;
    final isFailed = status == DownloadStatus.failed;
    final isPaused = status == DownloadStatus.paused;

    // Android Notification Details
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'download_channel',
          'Downloads',
          channelDescription: 'Show download progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: progress,
          ongoing: isRunning, // Only running is ongoing
          autoCancel: false, // Don't auto-cancel on tap
          playSound: false,
          enableVibration: false,
          actions: <AndroidNotificationAction>[
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
          transient: isRunning, // Transient if running (updates frequently)
          customHints: [
            LinuxNotificationCustomHint('value', LinuxHintInt16Value(progress)),
          ],
          actions: <LinuxNotificationAction>[
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
            WindowsProgressBar(
              id: id.toString(),
              status: 'Downloading',
              value: progress / 100,
            ),
          ],
          actions: <WindowsAction>[
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
    }

    await flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }
}

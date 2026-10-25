import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> initialize() async {
    if (_ready) return;

    tz_data.initializeTimeZones();
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      // Keep the app usable if the device cannot report its timezone.
      tz.setLocalLocation(tz.UTC);
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_notebook'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final allowed =
          await android?.requestNotificationsPermission() ?? false;
      if (!allowed) return false;
      return true;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'note_reminders',
      'Напоминания',
      channelDescription: 'Напоминания о сохранённых заметках',
      icon: 'ic_stat_notebook',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  Future<void> showTestNotification() async {
    await initialize();
    if (!await _requestPermission()) {
      throw StateError('Уведомления запрещены. Разрешите их в настройках телефона.');
    }
    await _plugin.show(
      id: -1,
      title: 'Проверка блокнота',
      body: 'Локальные уведомления работают без интернета.',
      notificationDetails: _details,
    );
  }

  /// Returns false when Android can only schedule an approximate alarm.
  Future<bool> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    await initialize();
    if (!at.isAfter(DateTime.now())) {
      throw ArgumentError('Время напоминания уже прошло.');
    }

    final permissionGranted = await _requestPermission();
    if (!permissionGranted) {
      throw StateError(
        'Разрешите уведомления в настройках телефона, чтобы получать напоминания.',
      );
    }

    var scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      var exactAllowed =
          await android?.canScheduleExactNotifications() ?? false;
      if (!exactAllowed) {
        await android?.requestExactAlarmsPermission();
        exactAllowed =
            await android?.canScheduleExactNotifications() ?? false;
      }
      if (!exactAllowed) {
        scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
      }
    }

    await _plugin.zonedSchedule(
      id: id,
      title: title.isEmpty ? 'Напоминание из блокнота' : title,
      body: body.isEmpty ? 'Откройте заметку, которую сохранили.' : body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: _details,
      androidScheduleMode: scheduleMode,
      payload: id.toString(),
    );
    final pending = await _plugin.pendingNotificationRequests();
    if (!pending.any((request) => request.id == id)) {
      throw StateError('Система не подтвердила создание напоминания.');
    }
    return scheduleMode == AndroidScheduleMode.exactAllowWhileIdle;
  }

  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id: id);
  }
}

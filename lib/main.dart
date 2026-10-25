import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await initializeBackgroundService();

  runApp(const PedometerApp());
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
    'pedometer_foreground_channel',
    'Шагомер Фоновый Сервис',
    description: 'Удержание счетчика шагов активным в фоне',
    importance: Importance.low,
  );

  const AndroidNotificationChannel goalChannel = AndroidNotificationChannel(
    'pedometer_goal_channel',
    'Цели шагов',
    description: 'Уведомления о достижении ежедневной цели шагов',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  final androidPlugin = flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(serviceChannel);
  await androidPlugin?.createNotificationChannel(goalChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'pedometer_foreground_channel',
      initialNotificationTitle: 'Шагомер активен',
      initialNotificationContent: 'Считаем шаги в фоне...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin backgroundNotifications =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
  await backgroundNotifications.initialize(initializationSettings);

  Pedometer.stepCountStream.listen((StepCount event) async {
    int totalSystemSteps = event.steps;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    int baseSteps = prefs.getInt('base_steps') ?? -1;
    if (baseSteps == -1 || totalSystemSteps < baseSteps) {
      baseSteps = totalSystemSteps;
      await prefs.setInt('base_steps', baseSteps);
    }

    int currentSteps = totalSystemSteps - baseSteps;
    int finalSteps = currentSteps < 0 ? 0 : currentSteps;
    int dailyGoal = prefs.getInt('daily_goal') ?? 5000;
    bool goalNotified = prefs.getBool('goal_notified') ?? false;

    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        service.setForegroundNotificationInfo(

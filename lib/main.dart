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
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:url_launcher/url_launcher.dart';

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
          title: 'Шагомер: $finalSteps из $dailyGoal шагов',
          content: 'Прогресс: ${(finalSteps * 0.75 / 1000).toStringAsFixed(2)} км',
        );
      }
    }

    if (finalSteps >= dailyGoal && !goalNotified) {
      await prefs.setBool('goal_notified', true);

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'pedometer_goal_channel',
        'Цели шагов',
        channelDescription: 'Уведомления о достижении ежедневной цели шагов',
        importance: Importance.max,
        priority: Priority.max,
        ticker: 'Цель выполнена!',
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await backgroundNotifications.show(
        0,
        '🎉 Цель выполнена!',
        'Поздравляем! Вы прошли уже $finalSteps шагов (цель: $dailyGoal)!',
        platformChannelSpecifics,
      );
    }
  });

  service.on('stopService').listen((event) {
    service.stopSelf();
  });
}

class PedometerApp extends StatelessWidget {
  const PedometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Шагомер',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const PedometerScreen(),
    );
  }
}

class PedometerScreen extends StatefulWidget {
  const PedometerScreen({super.key});

  @override
  State<PedometerScreen> createState() => _PedometerScreenState();
}

class _PedometerScreenState extends State<PedometerScreen> {
  int _selectedIndex = 0;

  late Stream<StepCount> _stepCountStream;
  String _status = 'Ожидание первых шагов...';
  int _steps = 0;
  int _savedBaseSteps = -1;
  bool _hasPermission = false;
  int _dailyGoal = 5000;

  String _startDateStr = '-';
  String _startTimeStr = '-';
  
  List<MapEntry<String, int>> _history = [];
  bool _goalAchievedShown = false;

  String _cityName = 'Москва';
  String _weatherInfo = 'Загрузка...';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

  final MapController _mapController = MapController();
  LatLng? _currentPosition;
  List<LatLng> _routePoints = [];
  bool _isLocating = false;
  final loc.Location _locationService = loc.Location();
  StreamSubscription<loc.LocationData>? _locationSubscription;

  @override
  void initState() {
    super.initState();
    _initApp();
    _loadCityAndWeather();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initApp() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.activityRecognition,
      Permission.notification,
      Permission.location,
    ].request();

    bool activityGranted = statuses[Permission.activityRecognition]?.isGranted ?? false;
    bool notifGranted = statuses[Permission.notification]?.isGranted ?? false;

    await _loadSavedData();
    await _loadSavedRoute();

    if (activityGranted) {
      setState(() => _hasPermission = true);
      _initPedometer();

      if (notifGranted) {
        try {
          final service = FlutterBackgroundService();
          bool isRunning = await service.isRunning();
          if (!isRunning) {
            await service.startService();
          }
        } catch (_) {}
      }
    } else {
      setState(() => _status = 'Нет разрешения на датчик');
    }

    _initLocationTracking();
  }

  Future<void> _initLocationTracking() async {
    bool serviceEnabled = await _locationService.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _locationService.requestService();
      if (!serviceEnabled) return;
    }

    loc.PermissionStatus permissionGranted = await _locationService.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _locationService.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) return;
    }

    try {
      loc.LocationData locData = await _locationService.getLocation();
      if (locData.latitude != null && locData.longitude != null) {
        LatLng pos = LatLng(locData.latitude!, locData.longitude!);
        setState(() {
          _currentPosition = pos;
          if (_routePoints.isEmpty) {
            _routePoints.add(pos);
          }
        });
      }
    } catch (_) {}

    _locationSubscription = _locationService.onLocationChanged.listen((loc.LocationData currentLoc) {
      if (currentLoc.latitude != null && currentLoc.longitude != null) {
        LatLng newPoint = LatLng(currentLoc.latitude!, currentLoc.longitude!);
        setState(() {
          _currentPosition = newPoint;
          if (_routePoints.isEmpty) {
            _routePoints.add(newPoint);
            _saveRoute();
          } else {
            final Distance distance = const Distance();
            double meters = distance.as(LengthUnit.Meter, _routePoints.last, newPoint);
            if (meters >= 3) {
              _routePoints.add(newPoint);
              _saveRoute();
            }
          }
        });
      }
    });
  }

  Future<void> _loadSavedRoute() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> savedPoints = prefs.getStringList('route_points') ?? [];
    List<LatLng> loaded = [];
    for (String p in savedPoints) {
      final parts = p.split(',');
      if (parts.length == 2) {
        double? lat = double.tryParse(parts[0]);
        double? lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          loaded.add(LatLng(lat, lng));
        }
      }
    }
    if (mounted) {
      setState(() {
        _routePoints = loaded;
        if (_routePoints.isNotEmpty) {
          _currentPosition = _routePoints.last;
        }
      });
    }
  }

  Future<void> _saveRoute() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> toSave =
        _routePoints.map((p) => '${p.latitude},${p.longitude}').toList();
    await prefs.setStringList('route_points', toSave);
  }

  Future<void> _openYandexMapsWithTraffic() async {
    HapticFeedback.mediumImpact();
    LatLng target = _currentPosition ?? (_routePoints.isNotEmpty ? _routePoints.last : const LatLng(55.7558, 37.6173));
    
    final Uri yandexUrl = Uri.parse('yandexmaps://maps.yandex.ru/?ll=${target.longitude},${target.latitude}&z=16&l=map,trf,trfe');
    final Uri yandexWebUrl = Uri.parse('https://yandex.ru/maps/?ll=${target.longitude},${target.latitude}&z=16&l=map,trf,trfe');

    try {
      if (await canLaunchUrl(yandexUrl)) {
        await launchUrl(yandexUrl);
      } else {
        await launchUrl(yandexWebUrl, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть Яндекс.Карты')),
        );
      }
    }
  }

  Future<void> _centerOnUser() async {
    HapticFeedback.lightImpact();
    setState(() => _isLocating = true);

    try {
      loc.LocationData locData = await _locationService.getLocation();
      if (locData.latitude != null && locData.longitude != null) {
        LatLng pos = LatLng(locData.latitude!, locData.longitude!);
        setState(() {
          _currentPosition = pos;
        });
        _mapController.move(pos, 17.0);
      }
    } catch (_) {
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 17.0);
      }
    }

    if (mounted) {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _clearRoute() async {
    HapticFeedback.mediumImpact();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('route_points');
    setState(() {
      _routePoints = _currentPosition != null ? [_currentPosition!] : [];
    });
  }

  Future<void> _loadCityAndWeather() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String savedCity = prefs.getString('user_city') ?? 'Москва';
    setState(() {
      _cityName = savedCity;
    });
    await _fetchWeatherForCity(savedCity);
  }

  Future<void> _fetchWeatherForCity(String cityName) async {
    try {
      final geoResponse = await http.get(
        Uri.parse('https://geocoding-api.open-meteo.com/v1/search?name=$cityName&count=1&language=ru&format=json')
      ).timeout(const Duration(seconds: 5));

      if (geoResponse.statusCode == 200) {
        final geoData = json.decode(geoResponse.body);
        if (geoData['results'] != null && geoData['results'].isNotEmpty) {
          final lat = geoData['results'][0]['latitude'];
          final lon = geoData['results'][0]['longitude'];
          final realName = geoData['results'][0]['name'];

          final weatherResponse = await http.get(
            Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code')
          ).timeout(const Duration(seconds: 5));

          if (weatherResponse.statusCode == 200) {
            final weatherData = json.decode(weatherResponse.body);
            final temp = weatherData['current']['temperature_2m'];
            final code = weatherData['current']['weather_code'];

            setState(() {
              _cityName = realName;
              _weatherInfo = '$realName, ${temp.round()}°C,${_getWeatherDescription(code)}';
              _weatherIcon = _getWeatherIcon(code);
            });
            return;
          }
        }
      }
      setState(() {
        _weatherInfo = '$cityName, не найдено';
      });
    } catch (_) {
      setState(() {
        _weatherInfo = '$cityName, ошибка сети';
      });
    }
  }

  String _getWeatherDescription(int code) {
    if (code == 0) return 'Ясно';
    if (code >= 1 && code <= 3) return 'Облачно';
    if (code >= 51 && code <= 67) return 'Дождь';
    if (code >= 71 && code <= 77) return 'Снег';
    return 'Пасмурно';
  }

  IconData _getWeatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_rounded;
    if (code >= 1 && code <= 3) return Icons.cloud_rounded;
    if (code >= 51 && code <= 67) return Icons.water_drop_rounded;
    if (code >= 71 && code <= 77) return Icons.ac_unit_rounded;
    return Icons.cloud_outlined;
  }

  void _showCityPickerDialog() {
    TextEditingController cityController = TextEditingController(text: _cityName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF23232F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Выбрать город', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: cityController,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Введите название города',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF4B2B)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              String newCity = cityController.text.trim();
              if (newCity.isNotEmpty) {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_city', newCity);
                setState(() {
                  _cityName = newCity;
                  _weatherInfo = 'Загрузка...';
                });
                _fetchWeatherForCity(newCity);
              }
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Найти', style: TextStyle(color: Color(0xFFFF4B2B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    final now = DateTime.now();
    final dateFormatted = DateFormat('dd.MM.yyyy').format(now);
    final timeFormatted = DateFormat('HH:mm').format(now);

    String savedDate = prefs.getString('start_date') ?? '';
    if (savedDate.isEmpty) {
      await prefs.setString('start_date', dateFormatted);
      await prefs.setString('start_time', timeFormatted);
      savedDate = dateFormatted;
    }

    setState(() {
      _savedBaseSteps = prefs.getInt('base_steps') ?? -1;
      _startDateStr = savedDate;
      _startTimeStr = prefs.getString('start_time') ?? timeFormatted;
      _dailyGoal = prefs.getInt('daily_goal') ?? 5000;
      _goalAchievedShown = prefs.getBool('goal_notified') ?? false;
    });
    
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Set<String> keys = prefs.getKeys();
    List<MapEntry<String, int>> loadedHistory = [];

    for (String key in keys) {
      if (key.startsWith('day_steps_')) {
        String dateStr = key.replaceFirst('day_steps_', '');
        int stepsCount = prefs.getInt(key) ?? 0;
        loadedHistory.add(MapEntry(dateStr, stepsCount));
      }
    }

    loadedHistory.sort((a, b) => b.key.compareTo(a.key));

    setState(() {
      _history = loadedHistory;
    });
  }

  void _initPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream.listen((StepCount event) async {
      if (!mounted) return;
      
      int totalSystemSteps = event.steps;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      if (_savedBaseSteps == -1) {
        _savedBaseSteps = prefs.getInt('base_steps') ?? -1;
        if (_savedBaseSteps == -1) {
          _savedBaseSteps = totalSystemSteps;
          await prefs.setInt('base_steps', _savedBaseSteps);
        }
      }

      if (totalSystemSteps < _savedBaseSteps) {
        _savedBaseSteps = totalSystemSteps;
        await prefs.setInt('base_steps', _savedBaseSteps);
      }

      int currentSteps = totalSystemSteps - _savedBaseSteps;
      int finalSteps = currentSteps < 0 ? 0 : currentSteps;

      bool alreadyNotified = prefs.getBool('goal_notified') ?? false;

      if (finalSteps >= _dailyGoal && !_goalAchievedShown && !alreadyNotified) {
        _goalAchievedShown = true;
        await prefs.setBool('goal_notified', true);
        HapticFeedback.vibrate();
        _showGoalNotification();
        _showGoalAchievedDialog();
      }

      setState(() {
        _steps = finalSteps;
        _status = 'Счетчик активен';
      });
    }).onError((error) {
      setState(() => _status = 'Датчик шагов недоступен');
    });
  }

  Future<void> _showGoalNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'pedometer_goal_channel',
      'Цели шагов',
      channelDescription: 'Уведомления о достижении ежедневной цели шагов',
      importance: Importance.max,
      priority: Priority.max,
      ticker: 'Цель выполнена!',
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      '🎉 Цель выполнена!',
      'Поздравляем! Вы прошли уже $_dailyGoal шагов сегодня!',
      platformChannelSpecifics,
    );
  }

  void _showEditGoalDialog() {
    TextEditingController goalController = TextEditingController(text: _dailyGoal.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF23232F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Изменить цель шагов', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: goalController,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: 'Введите число шагов',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF4B2B)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color:

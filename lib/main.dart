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
  int _selectedIndex = 0; // 0 - Шагомер, 1 - Карта маршрутов

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

  // Переменные для карты и маршрутов
  final MapController _mapController = MapController();
  LatLng? _currentPosition = const LatLng(55.7558, 37.6173); // Москва по умолчанию
  List<LatLng> _routePoints = [];
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _initApp();
    _loadCityAndWeather();
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

  // Кнопка «Найти меня» на карте
  Future<void> _centerOnUser() async {
    HapticFeedback.lightImpact();
    setState(() => _isLocating = true);

    var status = await Permission.location.request();
    if (status.isGranted) {
      if (_currentPosition != null) {
        _mapController.move(_currentPosition!, 17.0);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Включите разрешение на геолокацию в настройках')),
        );
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
              _weatherInfo = '$realName, ${temp.round()}°C, ${_getWeatherDescription(code)}';
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
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              int? newGoal = int.tryParse(goalController.text);
              if (newGoal != null && newGoal > 0) {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setInt('daily_goal', newGoal);
                await prefs.setBool('goal_notified', false);
                setState(() {
                  _dailyGoal = newGoal;
                  _goalAchievedShown = false;
                });
              }
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Сохранить', style: TextStyle(color: Color(0xFFFF4B2B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showGoalAchievedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF23232F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.military_tech_rounded, color: Color(0xFFFF4B2B), size: 32),
            SizedBox(width: 10),
            Text('Цель выполнена!', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'Поздравляем! Вы прошли уже $_dailyGoal шагов сегодня!',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Круто!', style: TextStyle(color: Color(0xFFFF4B2B), fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetCounter() async {
    if (_steps > 0 || _routePoints.length > 1) {
      SystemSound.play(SystemSoundType.click);
      HapticFeedback.mediumImpact();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateFormatted = DateFormat('dd.MM.yyyy').format(now);
      final timeFormatted = DateFormat('HH:mm').format(now);

      String dayKey = 'day_steps_$dateFormatted';
      int existingSteps = prefs.getInt(dayKey) ?? 0;
      await prefs.setInt(dayKey, existingSteps + _steps);

      await prefs.setInt('base_steps', -1);
      await prefs.setBool('goal_notified', false);
      await prefs.remove('route_points');

      setState(() {
        _savedBaseSteps = -1;
        _steps = 0;
        _startDateStr = dateFormatted;
        _startTimeStr = timeFormatted;
        _goalAchievedShown = false;
        _routePoints = _currentPosition != null ? [_currentPosition!] : [];
      });
      await prefs.setString('start_date', dateFormatted);
      await prefs.setString('start_time', timeFormatted);

      await _loadHistory();
    }
  }

  Future<void> _showCalendarPicker() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFF4B2B),
              onPrimary: Color(0xFF16161E),
              surface: Color(0xFF23232F),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1C1C26),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      String formattedDate = DateFormat('dd.MM.yyyy').format(pickedDate);
      String dayKey = 'day_steps_$formattedDate';
      int stepsForDay = prefs.getInt(dayKey) ?? 0;

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF23232F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Статистика за $formattedDate',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: Text(
            'Пройдено шагов: $stepsForDay',
            style: const TextStyle(color: Color(0xFFFF4B2B), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ОК', style: TextStyle(color: Color(0xFFFF4B2B), fontSize: 16)),
            ),
          ],
        ),
      );
    }
  }

  double _calculateRouteDistanceMeters() {
    if (_routePoints.length < 2) return 0;
    const Distance distance = Distance();
    double total = 0;
    for (int i = 0; i < _routePoints.length - 1; i++) {
      total += distance.as(LengthUnit.Meter, _routePoints[i], _routePoints[i + 1]);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF13131A), Color(0xFF1C1C26)],
          ),
        ),
        child: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildPedometerView(),
              _buildMapView(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161E),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            HapticFeedback.selectionClick();
            setState(() => _selectedIndex = index);
            if (index == 1 && _currentPosition != null) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _mapController.move(_currentPosition!, 16.5);
              });
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00FF87),
          unselectedItemColor: Colors.white54,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_walk_rounded),
              label: 'Шагомер',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_rounded),
              label: 'Карта и маршрут',
            ),
          ],
        ),
      ),
    );
  }

  // ЭКРАН 1: ШАГОМЕР
  Widget _buildPedometerView() {
    int distanceMeters = (_steps * 0.75).round();
    double distanceKm = distanceMeters / 1000;
    int calories = (_steps * 0.04).round();
    double progress = (_steps / _dailyGoal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _showCityPickerDialog,
                child: Row(
                  children: [
                    Icon(_weatherIcon, color: const Color(0xFF60EFFF), size: 20),
                    const SizedBox(width: 6),
                    Text(
                      _weatherInfo,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_rounded, size: 12, color: Colors.white54),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _showEditGoalDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23232F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFF4B2B).withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Цель: $_dailyGoal',
                        style: const TextStyle(color: Color(0xFFFF4B2B), fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_rounded, size: 12, color: Color(0xFFFF4B2B)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 190,
                height: 190,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 9,
                  backgroundColor: const Color(0xFFFF4B2B).withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00FF87)),
                ),
              ),
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF23232F), Color(0xFF16161E)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF16161E),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.directions_walk_rounded, size: 30, color: Color(0xFF00FF87)),
                        const SizedBox(height: 2),
                        Text(
                          '$_steps',
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'ШАГОВ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          Row(
            children: [
              Expanded(
                child: _buildUltramatic3DCard(
                  Icons.route_rounded, 
                  'Дистанция', 
                  '${distanceKm.toStringAsFixed(2)} км',
                  '($distanceMeters м)',
                  const Color(0xFF00FF87),
                  const Color(0xFF60EFFF)
                )
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildUltramatic3DCard(
                  Icons.local_fire_department_rounded, 
                  'Калории', 
                  '$calories ккал',
                  '',
                  const Color(0xFFFF512F),
                  const Color(0xFFFF416C)
                )
              ),
            ],
          ),

          GestureDetector(
            onTap: _showCalendarPicker,
            child: Container(
              height: 120,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF23232F),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFF4B2B).withOpacity(0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.6),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: const Color(0xFFFF4B2B).withOpacity(0.12),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'График активности (нажмите для календаря)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF4B2B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFF4B2B).withOpacity(0.4)),
                        ),
                        child: const Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFFFF4B2B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _history.isEmpty
                        ? const Center(child: Text('Нет данных для графика', style: TextStyle(color: Colors.white38, fontSize: 12)))
                        : BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _history.map((e) => e.value.toDouble()).fold(10000.0, (prev, element) => element > prev ? element : prev) * 1.2,
                              barTouchData: BarTouchData(enabled: false),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      int index = value.toInt();
                                      if (index >= 0 && index < _history.length) {
                                        String date = _history[index].key.substring(0, 5);
                                        return Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text(date, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                                        );
                                      }
                                      return const Text('');
                                    },
                                    reservedSize: 20,
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: _history.asMap().entries.map((entry) {
                                int index = entry.key;
                                int steps = entry.value.value;
                                return BarChartGroupData(
                                  x: index,
                                  barRods: [
                                    BarChartRodData(
                                      toY: steps.toDouble(),
                                      color: const Color(0xFFFF4B2B),
                                      width: 12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          
          Container(
            width: double.infinity,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF4B2B).withOpacity(0.5),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _hasPermission ? _resetCounter : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text(
                'СБРОСИТЬ СЧЕТЧИК',
                style: TextStyle(
                  fontSize: 14, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ЭКРАН 2: КАРТА И МАРШРУТЫ
  Widget _buildMapView() {
    final LatLng defaultCenter = _currentPosition ?? const LatLng(55.7558, 37.6173);
    final double gpsDistanceMeters = _calculateRouteDistanceMeters();
    final double gpsDistanceKm = gpsDistanceMeters / 1000;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: defaultCenter,
            initialZoom: 16.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.zhigomer.app',
            ),
            if (_routePoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 5.5,
                    color: const Color(0xFF00FF87),
                    borderStrokeWidth: 2.0,
                    borderColor: const Color(0xFF16161E),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_routePoints.length > 1)
                  Marker(
                    point: _routePoints.first,
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF00FF87),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(Icons.flag_rounded, color: Colors.black, size: 20),
                    ),
                  ),
                if (_currentPosition != null)
                  Marker(
                    point: _currentPosition!,
                    width: 48,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFF4B2B).withOpacity(0.28),
                      ),
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF4B2B),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF4B2B).withOpacity(0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        Positioned(
          top: 14,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C26).withOpacity(0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Карта и маршрут',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${gpsDistanceKm.toStringAsFixed(2)} км (${gpsDistanceMeters.round()} м)',
                      style: const TextStyle(color: Color(0xFF00FF87), fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _clearRoute,
                      tooltip: 'Очистить маршрут',
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF4B2B)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        Positioned(
          bottom: 20,
          right: 18,
          child: GestureDetector(
            onTap: _centerOnUser,
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4B2B).withOpacity(0.6),
                    blurRadius: 15,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: _isLocating
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Icon(Icons.my_location_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUltramatic3DCard(IconData icon, String title, String mainValue, String subValue, Color color1, Color color2) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF23232F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color1.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.6),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: color1.withOpacity(0.22),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color1, color2],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: color1.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mainValue,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                if (subValue.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      subValue,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

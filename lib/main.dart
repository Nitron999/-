import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart'; // Для красивого форматирования даты и времени

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PedometerApp());
}

class PedometerApp extends StatelessWidget {
  const PedometerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Zhigomer',
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
  late Stream<StepCount> _stepCountStream;
  String _status = 'Ожидание первых шагов...';
  int _steps = 0;
  int _savedBaseSteps = -1;
  int _currentTotalSteps = 0;
  bool _hasPermission = false;

  // Переменные для даты и времени старта
  String _startDateStr = '-';
  String _startTimeStr = '-';

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    PermissionStatus status = await Permission.activityRecognition.request();
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      await _loadSavedData();
      _initPedometer();
    } else {
      setState(() => _status = 'Нет разрешения на датчик');
    }
  }

  Future<void> _loadSavedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedBaseSteps = prefs.getInt('base_steps') ?? -1;
      _startDateStr = prefs.getString('start_date') ?? '-';
      _startTimeStr = prefs.getString('start_time') ?? '-';
    });
  }

  Future<void> _saveSessionData(int base) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    final now = DateTime.now();
    final dateFormatted = DateFormat('dd.MM.yyyy').format(now);
    final timeFormatted = DateFormat('HH:mm').format(now);

    await prefs.setInt('base_steps', base);
    await prefs.setString('start_date', dateFormatted);
    await prefs.setString('start_time', timeFormatted);

    setState(() {
      _savedBaseSteps = base;
      _startDateStr = dateFormatted;
      _startTimeStr = timeFormatted;
    });
  }

  void _initPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream.listen((StepCount event) {
      if (!mounted) return;
      
      _currentTotalSteps = event.steps;

      // Привязка точки отсчета и времени при первом запуске или сбросе
      if (_savedBaseSteps == -1 || _currentTotalSteps < _savedBaseSteps) {
        _saveSessionData(_currentTotalSteps);
      }

      setState(() {
        _steps = _currentTotalSteps - _savedBaseSteps;
        _status = 'Счетчик активен';
      });
    }).onError((error) {
      setState(() => _status = 'Датчик шагов недоступен');
    });
  }

  void _resetCounter() {
    if (_currentTotalSteps > 0) {
      _saveSessionData(_currentTotalSteps);
      setState(() {
        _steps = 0;
        _status = 'Сброшено. Начинаем заново...';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int distanceMeters = (_steps * 0.75).round();
    double distanceKm = distanceMeters / 1000;
    int calories = (_steps * 0.04).round();

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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'PEDOMETER',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF00FF87), Color(0xFF60EFFF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF87).withOpacity(0.3),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF16161E),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.directions_walk_rounded, size: 48, color: Color(0xFF00FF87)),
                            const SizedBox(height: 10),
                            Text(
                              '$_steps',
                              style: const TextStyle(
                                fontSize: 64,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'STEPS',
                              style: TextStyle(
                                fontSize: 16,
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
                  
                  const SizedBox(height: 30),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 30),

                  // Карточки статистики: Дистанция + Калории
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          Icons.route_rounded, 
                          'Distance', 
                          '${distanceKm.toStringAsFixed(2)} km\n$distanceMeters m', 
                          const Color(0xFF60EFFF)
                        )
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          Icons.local_fire_department_rounded, 
                          'Calories', 
                          '$calories kcal\n', 
                          const Color(0xFFFF512F)
                        )
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),

                  // Карточки времени и даты старта движения
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          Icons.calendar_today_rounded, 
                          'Start Date', 
                          _startDateStr, 
                          const Color(0xFF00FF87)
                        )
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          Icons.access_time_rounded, 
                          'Start Time', 
                          _startTimeStr, 
                          const Color(0xFFFFA500)
                        )
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 30),
                  
                  ElevatedButton(
                    onPressed: _hasPermission ? _resetCounter : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A35),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 60),
                      elevation: 0,
                    ),
                    child: const Text(
                      'RESET STEP COUNTER',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF23232F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 14, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

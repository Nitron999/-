import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';

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
  late Stream<StepCount> _stepCountStream;
  String _status = 'Ожидание первых шагов...';
  int _steps = 0;
  int _savedBaseSteps = -1;
  int _currentTotalSteps = 0;
  bool _hasPermission = false;

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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Шапка
                const Text(
                  'ШАГОМЕР',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
                
                // Главный круг со счетчиком
                Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF00FF87), Color(0xFF60EFFF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF87).withOpacity(0.25),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF16161E),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.directions_walk_rounded, size: 36, color: Color(0xFF00FF87)),
                          const SizedBox(height: 4),
                          Text(
                            '$_steps',
                            style: const TextStyle(
                              fontSize: 50,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'ШАГОВ',
                            style: TextStyle(
                              fontSize: 13,
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
                
                Text(
                  _status,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),

                // Карточки статистики (Дистанция и Калории)
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        Icons.route_rounded, 
                        'Дистанция', 
                        '${distanceKm.toStringAsFixed(2)} км\n$distanceMeters м', 
                        const Color(0xFF60EFFF)
                      )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        Icons.local_fire_department_rounded, 
                        'Калории', 
                        '$calories ккал\n', 
                        const Color(0xFFFF512F)
                      )
                    ),
                  ],
                ),

                // Карточки времени (Дата и Время старта)
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        Icons.calendar_today_rounded, 
                        'Дата старта', 
                        _startDateStr, 
                        const Color(0xFF00FF87)
                      )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        Icons.access_time_rounded, 
                        'Время старта', 
                        _startTimeStr, 
                        const Color(0xFFFFA500)
                      )
                    ),
                  ],
                ),
                
                // Кнопка сброса
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF4B2B).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _hasPermission ? _resetCounter : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'СБРОСИТЬ СЧЕТЧИК',
                      style: TextStyle(
                        fontSize: 15, 
                        fontWeight: FontWeight.bold, 
                        letterSpacing: 1.1,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF23232F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.2),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

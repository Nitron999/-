import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

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
  String _status = 'Запуск датчиков...';
  int _steps = 0;
  int _savedBaseSteps = -1;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    PermissionStatus status = await Permission.activityRecognition.request();
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      await _loadBaseSteps();
      _initPedometer();
    } else {
      setState(() => _status = 'Нет разрешения на датчик');
    }
  }

  Future<void> _loadBaseSteps() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedBaseSteps = prefs.getInt('base_steps') ?? -1;
    });
  }

  Future<void> _saveBaseSteps(int base) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('base_steps', base);
    setState(() {
      _savedBaseSteps = base;
    });
  }

  void _initPedometer() {
    _stepCountStream = Pedometer.stepCountStream;
    _stepCountStream.listen((StepCount event) {
      if (!mounted) return;
      
      int totalBootSteps = event.steps;

      // Если точка отсчета еще не сохранена или телефон перезагружался
      if (_savedBaseSteps == -1 || totalBootSteps < _savedBaseSteps) {
        _saveBaseSteps(totalBootSteps);
      }

      setState(() {
        _steps = totalBootSteps - _savedBaseSteps;
        _status = 'Счетчик активен';
      });
    }).onError((error) {
      setState(() => _status = 'Датчик шагов не найден');
    });
  }

  void _resetCounter() {
    setState(() {
      _savedBaseSteps = -1;
      _steps = 0;
      _status = 'Сброшено. Начинаем заново...';
    });
    // Искусственно триггерим датчик обнулением
    Pedometer.stepCountStream.first.then((event) {
      _saveBaseSteps(event.steps);
    });
  }

  @override
  Widget build(BuildContext context) {
    double distanceKm = (_steps * 0.75) / 1000;
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
                    'ШАГОМЕР 3000',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  
                  // Главный круг с шагами
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
                              'ШАГОВ',
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

                  // Карточки статистики
                  Row(
                    children: [
                      Expanded(child: _buildStatCard(Icons.route_rounded, 'Дистанция', '${distanceKm.toStringAsFixed(2)} км', const Color(0xFF60EFFF))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildStatCard(Icons.local_fire_department_rounded, 'Калории', '$calories ккал', const Color(0xFFFF512F))),
                    ],
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Кнопка сброса
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
                      'СБРОСИТЬ СЧЕТЧИК',
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
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
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

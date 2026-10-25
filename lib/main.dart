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
  
  // Список истории за последние дни
  List<MapEntry<String, int>> _history = [];

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

    // Сортируем по дате (свежие сверху)
    loadedHistory.sort((a, b) => b.key.compareTo(a.key));

    setState(() {
      _history = loadedHistory;
    });
  }

  Future<void> _saveSessionData(int base, {int finalSteps = 0}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    final now = DateTime.now();
    final dateFormatted = DateFormat('dd.MM.yyyy').format(now);
    final timeFormatted = DateFormat('HH:mm').format(now);

    // Если завершаем день/сбрасываем, сохраняем в историю текущего дня
    if (finalSteps > 0) {
      String dayKey = 'day_steps_$dateFormatted';
      int existingSteps = prefs.getInt(dayKey) ?? 0;
      await prefs.setInt(dayKey, existingSteps + finalSteps);
    }

    await prefs.setInt('base_steps', base);
    await prefs.setString('start_date', dateFormatted);
    await prefs.setString('start_time', timeFormatted);

    setState(() {
      _savedBaseSteps = base;
      _startDateStr = dateFormatted;
      _startTimeStr = timeFormatted;
    });
    
    await _loadHistory();
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
      _saveSessionData(_currentTotalSteps, finalSteps: _steps);
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
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: Colors.white,
                  ),
                ),
                
                // Главный круг со счетчиком
                Container(
                  width: 180,
                  height: 180,
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
                        blurRadius: 15,
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

                // Карточки статистики (Дистанция и Калории)
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        Icons.route_rounded, 
                        'Дистанция', 
                        '${distanceKm.toStringAsFixed(2)} км ($distanceMeters м)', 
                        const Color(0xFF60EFFF)
                      )
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildStatCard(
                        Icons.local_fire_department_rounded, 
                        'Калории', 
                        '$calories ккал', 
                        const Color(0xFFFF512F)
                      )
                    ),
                  ],
                ),

                // Блок истории по дням
                Container(
                  height: 100,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF23232F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Статистика по дням',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _history.isEmpty
                            ... ? const Center(child: Text('Нет сохраненных дней', style: TextStyle(color: Colors.white38, fontSize: 12)))
                            : ListView.builder(
                                itemCount: _history.length,
                                itemBuilder: (context, index) {
                                  final item = _history[index];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(item.key, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                                        Text('${item.value} шаг.', style: const TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold, fontSize: 13)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                
                // Кнопка сброса
                Container(
                  width: double.infinity,
                  height: 48,
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
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF23232F),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

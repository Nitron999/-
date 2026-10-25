import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;

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
  bool _hasPermission = false;
  int _dailyGoal = 10000;

  String _startDateStr = '-';
  String _startTimeStr = '-';
  
  List<MapEntry<String, int>> _history = [];
  bool _goalAchievedShown = false;

  String _weatherInfo = 'Загрузка погоды...';
  IconData _weatherIcon = Icons.wb_sunny_rounded;

  @override
  void initState() {
    super.initState();
    _initApp();
    _fetchWeather();
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

  Future<void> _fetchWeather() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.open-meteo.com/v1/forecast?latitude=55.7522&current=temperature_2m,weather_code&timezone=Europe%2FMoscow')
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final code = data['current']['weather_code'];
        
        setState(() {
          _weatherInfo = '${temp.round()}°C, ${_getWeatherDescription(code)}';
          _weatherIcon = _getWeatherIcon(code);
        });
      }
    } catch (_) {
      setState(() {
        _weatherInfo = 'Погода недоступна';
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
      _dailyGoal = prefs.getInt('daily_goal') ?? 10000;
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

    loadedHistory.sort((a, b) => a.key.compareTo(b.key));

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

      if (_savedBaseSteps == -1) {
        _savedBaseSteps = totalSystemSteps;
        await prefs.setInt('base_steps', _savedBaseSteps);
      }

      if (totalSystemSteps < _savedBaseSteps) {
        _savedBaseSteps = totalSystemSteps;
        await prefs.setInt('base_steps', _savedBaseSteps);
      }

      int currentSteps = totalSystemSteps - _savedBaseSteps;
      int finalSteps = currentSteps < 0 ? 0 : currentSteps;

      if (finalSteps >= _dailyGoal && !_goalAchievedShown) {
        _goalAchievedShown = true;
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

  // Окно изменения ежедневной цели
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
              borderSide: const BorderSide(color: Color(0xFF00FF87)),
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
                setState(() {
                  _dailyGoal = newGoal;
                });
              }
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Сохранить', style: TextStyle(color: Color(0xFF00FF87), fontWeight: FontWeight.bold)),
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
            Icon(Icons.military_tech_rounded, color: Color(0xFF00FF87), size: 32),
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
            child: const Text('Круто!', style: TextStyle(color: Color(0xFF00FF87), fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _resetCounter() async {
    if (_steps > 0) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final dateFormatted = DateFormat('dd.MM.yyyy').format(now);
      final timeFormatted = DateFormat('HH:mm').format(now);

      String dayKey = 'day_steps_$dateFormatted';
      int existingSteps = prefs.getInt(dayKey) ?? 0;
      await prefs.setInt(dayKey, existingSteps + _steps);

      await prefs.setInt('base_steps', -1);
      setState(() {
        _savedBaseSteps = -1;
        _steps = 0;
        _startDateStr = dateFormatted;
        _startTimeStr = timeFormatted;
        _goalAchievedShown = false;
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
              primary: Color(0xFF00FF87),
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
            style: const TextStyle(color: Color(0xFF00FF87), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ОК', style: TextStyle(color: Color(0xFF00FF87), fontSize: 16)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    int distanceMeters = (_steps * 0.75).round();
    double distanceKm = distanceMeters / 1000;
    int calories = (_steps * 0.04).round();
    
    double progress = (_steps / _dailyGoal).clamp(0.0, 1.0);

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
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Шапка с погодой и кликабельной целью
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(_weatherIcon, color: const Color(0xFF60EFFF), size: 20),
                        const SizedBox(width: 6),
                        Text(
                          _weatherInfo,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: _showEditGoalDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF23232F),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Цель: $_dailyGoal',
                              style: const TextStyle(color: Color(0xFF00FF87), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_rounded, size: 12, color: Color(0xFF00FF87)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Главный цветной переливающийся круг со счетчиком
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 9,
                        backgroundColor: Colors.white12,
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
                          colors: [Color(0xFF00FF87), Color(0xFF60EFFF)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00FF87).withOpacity(0.35),
                            blurRadius: 25,
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

                // Карточки статистики
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
                    const SizedBox(width: 12),
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

                // График активности по дням с вызовом календаря
                GestureDetector(
                  onTap: _showCalendarPicker,
                  child: Container(
                    height: 130,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF23232F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF00FF87).withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'График активности (нажмите для календаря)',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                            ),
                            Icon(Icons.calendar_month_rounded, size: 16, color: Color(0xFF00FF87)),
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
                                            color: const Color(0xFF00FF87),
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
          Icon(icon, color: iconColor, size: 26),
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

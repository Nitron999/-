import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart' as geo;

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
  String _status = 'Ожидание первых шагов...';
  int _steps = 0;
  int _savedBaseSteps = -1;
  int _currentTotalSteps = 0;
  bool _hasPermission = false;

  LatLng _currentLocation = const LatLng(55.751244, 37.618423);
  final MapController _mapController = MapController();
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    PermissionStatus status = await Permission.activityRecognition.request();
    await Permission.location.request();
    
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      await _loadBaseSteps();
      _initPedometer();
    } else {
      setState(() => _status = 'Нет разрешения на датчик');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLocating = false);
        return;
      }

      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          setState(() => _isLocating = false);
          return;
        }
      }

      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLocating = false;
      });

      _mapController.move(_currentLocation, 16.0);
    } catch (e) {
      setState(() => _isLocating = false);
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
      
      _currentTotalSteps = event.steps;

      if (_savedBaseSteps == -1 || _currentTotalSteps < _savedBaseSteps) {
        _saveBaseSteps(_currentTotalSteps);
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
      _saveBaseSteps(_currentTotalSteps);
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
                    'ШАГОМЕР 3000',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
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
                      const SizedBox(width: 16),
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
                  
                  const SizedBox(height: 24),
                  
                  Container(
                    height: 250,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF23232F),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                        options: MapOptions(
                            initialCenter: _currentLocation,
                            initialZoom: 15.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.zhigomer.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _currentLocation,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(
                                    Icons.location_on, 
                                    color: Colors.redAccent, 
                                    size: 40
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            backgroundColor: const Color(0xFF16161E),
                            foregroundColor: const Color(0xFF00FF87),
                            elevation: 4,
                            onPressed: _isLocating ? null : _getCurrentLocation,
                            child: _isLocating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF00FF87),
                                    ),
                                  )
                                : const Icon(Icons.my_location, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3),
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

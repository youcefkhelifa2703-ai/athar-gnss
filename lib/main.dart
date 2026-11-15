import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const AtharGarminApp());
}

class AtharGarminApp extends StatelessWidget {
  const AtharGarminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Athar Garmin Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        primaryColor: const Color(0xFFF59E0B),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: GarminMainScreen(),
      ),
    );
  }
}

class WaypointModel {
  final String name;
  final double lat;
  final double lon;
  final double alt;

  WaypointModel({required this.name, required this.lat, required this.lon, required this.alt});

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon, 'alt': alt};
  factory WaypointModel.fromJson(Map<String, dynamic> j) => WaypointModel(
        name: j['name'],
        lat: j['lat'],
        lon: j['lon'],
        alt: (j['alt'] ?? 0).toDouble(),
      );
}

class GarminMainScreen extends StatefulWidget {
  const GarminMainScreen({super.key});

  @override
  State<GarminMainScreen> createState() => _GarminMainScreenState();
}

class _GarminMainScreenState extends State<GarminMainScreen> {
  final MapController _mapController = MapController();
  LatLng _currentLatLng = const LatLng(35.5541, 6.1742);
  double _speedKmh = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;
  double _heading = 0.0;
  String _satStatus = 'جاري البحث عن GNSS...';

  bool _isTopoMap = true;
  bool _isRecording = false;
  bool _isSimulatorMode = false;
  Timer? _simTimer;

  final List<LatLng> _trackPoints = [];
  List<WaypointModel> _waypoints = [];
  WaypointModel? _activeTarget;

  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _initGnssAndSensors();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    final wpRaw = prefs.getString('garmin_waypoints');
    if (wpRaw != null) {
      final List decoded = jsonDecode(wpRaw);
      setState(() {
        _waypoints = decoded.map((e) => WaypointModel.fromJson(e)).toList();
      });
    }
  }

  Future<void> _saveWaypoints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('garmin_waypoints', jsonEncode(_waypoints.map((e) => e.toJson()).toList()));
  }

  Future<void> _initGnssAndSensors() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _satStatus = 'GPS مغلق في الهاتف');
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position pos) {
      if (_isSimulatorMode) return;
      _onNewLocation(
        LatLng(pos.latitude, pos.longitude),
        pos.speed * 3.6,
        pos.altitude,
        pos.accuracy,
        'GNSS متصل (±${pos.accuracy.toStringAsFixed(1)}م)',
      );
    });

    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null && !_isSimulatorMode) {
        setState(() => _heading = event.heading!);
      }
    });
  }

  void _onNewLocation(LatLng point, double speed, double alt, double acc, String status) {
    setState(() {
      _currentLatLng = point;
      _speedKmh = speed.clamp(0, 999);
      _altitude = alt;
      _accuracy = acc;
      _satStatus = status;
      if (_isRecording) {
        _trackPoints.add(point);
      }
    });
  }

  // وضع المحاكاة الاحترافي مثل أجهزة Garmin (لتجربة الملاحة في أي مكان)
  void _toggleSimulator() {
    setState(() {
      _isSimulatorMode = !_isSimulatorMode;
      if (_isSimulatorMode) {
        _satStatus = 'وضع المحاكاة نشط (GPS SIM)';
        _simTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          final rad = _heading * math.pi / 180;
          final newLat = _currentLatLng.latitude + (0.00012 * math.cos(rad));
          final newLon = _currentLatLng.longitude + (0.00012 * math.sin(rad));
          final nextPt = LatLng(newLat, newLon);
          _onNewLocation(nextPt, 48.5, _altitude + 1.2, 1.0, 'وضع المحاكاة (GPS SIM)');
          _mapController.move(nextPt, _mapController.camera.zoom);
        });
      } else {
        _simTimer?.cancel();
        _satStatus = 'عودة للاستقبال الفضائي الحقيقي...';
      }
    });
  }

  void _markWaypointDialog() {
    final controller = TextEditingController(text: 'نقطة ${_waypoints.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('تثبيت نقطة إحداثيات', style: TextStyle(color: Color(0xFFF59E0B))),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'اسم النقطة (مثال: القمة، السيارة، المعسكر)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
              onPressed: () {
                setState(() {
                  _waypoints.add(WaypointModel(
                    name: controller.text.trim().isEmpty ? 'نقطة' : controller.text.trim(),
                    lat: _currentLatLng.latitude,
                    lon: _currentLatLng.longitude,
                    alt: _altitude,
                  ));
                });
                _saveWaypoints();
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _openWaypointsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111827),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📌 النقاط المحفوظة (Waypoints)',
                  style: TextStyle(color: Color(0xFFF59E0B), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: _waypoints.isEmpty
                    ? const Center(child: Text('لا توجد نقاط محفوظة بعد'))
                    : ListView.builder(
                        itemCount: _waypoints.length,
                        itemBuilder: (_, i) {
                          final wp = _waypoints[i];
                          return ListTile(
                            title: Text(wp.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('${wp.lat.toStringAsFixed(5)}, ${wp.lon.toStringAsFixed(5)}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                                  onPressed: () {
                                    setState(() => _activeTarget = wp);
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('توجيه'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                                  onPressed: () {
                                    setState(() {
                                      if (_activeTarget == wp) _activeTarget = null;
                                      _waypoints.removeAt(i);
                                    });
                                    _saveWaypoints();
                                    Navigator.pop(ctx);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportGpxFile() async {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="AtharGarminPro">');
    for (final w in _waypoints) {
      buffer.writeln('  <wpt lat="${w.lat}" lon="${w.lon}"><ele>${w.alt}</ele><name>${w.name}</name></wpt>');
    }
    if (_trackPoints.isNotEmpty) {
      buffer.writeln('  <trk><name>AtharTrack</name><trkseg>');
      for (final p in _trackPoints) {
        buffer.writeln('    <trkpt lat="${p.latitude}" lon="${p.longitude}"></trkpt>');
      }
      buffer.writeln('  </trkseg></trk>');
    }
    buffer.writeln('</gpx>');

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Athar_Garmin_${DateTime.now().millisecondsSinceEpoch}.gpx');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path)], text: 'ملف مسار وإحداثيات Garmin GPX');
  }

  double _totalTrackMeters() {
    if (_trackPoints.length < 2) return 0;
    const Distance dist = Distance();
    double sum = 0;
    for (int i = 1; i < _trackPoints.length; i++) {
      sum += dist.as(LengthUnit.Meter, _trackPoints[i - 1], _trackPoints[i]);
    }
    return sum;
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetDist = _activeTarget == null
        ? 0.0
        : const Distance().as(LengthUnit.Meter, _currentLatLng, LatLng(_activeTarget!.lat, _activeTarget!.lon));
    final targetBearing = _activeTarget == null
        ? 0.0
        : const Distance().bearing(_currentLatLng, LatLng(_activeTarget!.lat, _activeTarget!.lon));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: const Text('ATHAR GARMIN PRO',
            style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.greenAccent),
            ),
            alignment: Alignment.center,
            child: Text(_satStatus, style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
          ),
        ],
      ),
      body: Column(
        children: [
          // النصف العلوي: الخريطة التفاعلية
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _currentLatLng,
                    initialZoom: 14.0,
                    onTap: (_, tappedPoint) {
                      if (_isSimulatorMode) {
                        setState(() {
                          _heading = const Distance().bearing(_currentLatLng, tappedPoint);
                          _currentLatLng = tappedPoint;
                        });
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _isTopoMap
                          ? 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png'
                          : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.athar.gnss',
                    ),
                    // خط المسار المسجل باللون الأحمر
                    if (_trackPoints.length > 1)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: _trackPoints, color: Colors.redAccent, strokeWidth: 4.0),
                        ],
                      ),
                    // خط التوجيه المباشر نحو الهدف باللون الأخضر
                    if (_activeTarget != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: [_currentLatLng, LatLng(_activeTarget!.lat, _activeTarget!.lon)],
                            color: Colors.greenAccent,
                            strokeWidth: 3.0,
                          ),
                        ],
                      ),
                    // علامات النقاط وموقع المستخدم
                    MarkerLayer(
                      markers: [
                        ..._waypoints.map((w) => Marker(
                              point: LatLng(w.lat, w.lon),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: Colors.greenAccent, size: 36),
                            )),
                        Marker(
                          point: _currentLatLng,
                          width: 44,
                          height: 44,
                          child: Transform.rotate(
                            angle: _heading * math.pi / 180,
                            child: const Icon(Icons.navigation, color: Color(0xFFF59E0B), size: 36),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // بطاقة التوجيه نحو الهدف
                if (_activeTarget != null)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xE6111827),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.greenAccent),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('الهدف: ${_activeTarget!.name}',
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          Text('المسافة: ${targetDist.toStringAsFixed(0)} م | السمت: ${targetBearing.toStringAsFixed(0)}°',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),

                // أزرار التحكم الجانبية
                Positioned(
                  top: 10,
                  left: 10,
                  child: Column(
                    children: [
                      _mapBtn('🎯 موقعي', () => _mapController.move(_currentLatLng, 16)),
                      const SizedBox(height: 6),
                      _mapBtn(_isTopoMap ? '🗺️ شوارع' : '⛰️ طبوغرافية', () => setState(() => _isTopoMap = !_isTopoMap)),
                      const SizedBox(height: 6),
                      _mapBtn('📌 النقاط (${_waypoints.length})', _openWaypointsSheet),
                      const SizedBox(height: 6),
                      _mapBtn(_isSimulatorMode ? '⏹️ إيقاف المحاكي' : '🎮 محاكي GPS', _toggleSimulator,
                          active: _isSimulatorMode),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // النصف السفلي: لوحة عدادات Garmin
          Container(
            color: const Color(0xFF111827),
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFF090D16), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    'LAT: ${_currentLatLng.latitude.toStringAsFixed(6)}°  |  LON: ${_currentLatLng.longitude.toStringAsFixed(6)}°',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFF59E0B), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _hudCell('السرعة كم/س', _speedKmh.toStringAsFixed(1)),
                    const SizedBox(width: 6),
                    _hudCell('الارتفاع (م)', _altitude.toStringAsFixed(0)),
                    const SizedBox(width: 6),
                    _hudCell('البوصلة', '${_heading.toStringAsFixed(0)}°'),
                    const SizedBox(width: 6),
                    _hudCell('المسار', '${_totalTrackMeters().toStringAsFixed(0)} م'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
                        onPressed: _markWaypointDialog,
                        child: const Text('📍 تثبيت نقطة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isRecording ? Colors.redAccent : Colors.greenAccent,
                          foregroundColor: _isRecording ? Colors.white : Colors.black,
                        ),
                        onPressed: () => setState(() => _isRecording = !_isRecording),
                        child: Text(_isRecording ? '⏹️ إيقاف' : '⏺️ تسجيل أثر',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF334155), foregroundColor: Colors.white),
                        onPressed: _exportGpxFile,
                        child: const Text('💾 تصدير GPX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
  

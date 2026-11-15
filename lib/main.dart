import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

void main() {
  runApp(const AtharGnssApp());
}

class AtharGnssApp extends StatelessWidget {
  const AtharGnssApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'بوصلة الأثر GNSS',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        primaryColor: const Color(0xFFF59E0B),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: TacticalDashboard(),
      ),
    );
  }
}

class TacticalDashboard extends StatefulWidget {
  const TacticalDashboard({super.key});

  @override
  State<TacticalDashboard> createState() => _TacticalDashboardState();
}

class _TacticalDashboardState extends State<TacticalDashboard>
    with SingleTickerProviderStateMixin {
  Position? _currentPosition;
  Position? _savedAnchor; // نقطة الانطلاق / العودة (خيط الأثر)
  final List<Position> _breadcrumbTrail = [];
  double _heading = 0.0;
  String _statusMessage = 'جاري البحث عن الأقمار الصناعية...';
  StreamSubscription<Position>? _posSub;
  StreamSubscription<CompassEvent>? _compassSub;
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _initSensors();
  }

  Future<void> _initSensors() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _statusMessage = 'يرجى تفعيل GPS في الهاتف');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = 'تم رفض صلاحية الموقع');
        return;
      }
    }

    // الاستماع المستمر لشريحة الأقمار الصناعية بأعلى دقة ممكنة (بدون إنترنت)
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    _posSub = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position pos) {
      setState(() {
        _currentPosition = pos;
        _statusMessage = 'متصل بالأقمار الصناعية (دقة ±${pos.accuracy.toStringAsFixed(1)}م)';
        if (_savedAnchor != null) {
          _breadcrumbTrail.add(pos);
        }
      });
    });

    _compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      if (event.heading != null) {
        setState(() => _heading = event.heading!);
      }
    });
  }

  void _toggleAnchor() {
    if (_currentPosition == null) return;
    setState(() {
      if (_savedAnchor == null) {
        _savedAnchor = _currentPosition;
        _breadcrumbTrail.clear();
        _breadcrumbTrail.add(_currentPosition!);
      } else {
        _savedAnchor = null;
        _breadcrumbTrail.clear();
      }
    });
  }

  void _copyEncryptedBeacon() {
    if (_currentPosition == null) return;
    final code =
        'ATHAR-DZ:${_currentPosition!.latitude.toStringAsFixed(6)},${_currentPosition!.longitude.toStringAsFixed(6)}|ALT:${_currentPosition!.altitude.toStringAsFixed(0)}m';
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFF59E0B),
        content: Text(
          'تم نسخ رمز الإحداثيات للمشاركة بدون إنترنت (SMS): $code',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  double _distanceToAnchor() {
    if (_currentPosition == null || _savedAnchor == null) return 0;
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _savedAnchor!.latitude,
      _savedAnchor!.longitude,
    );
  }

  double _bearingToAnchor() {
    if (_currentPosition == null || _savedAnchor == null) return 0;
    return Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _savedAnchor!.latitude,
      _savedAnchor!.longitude,
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _compassSub?.cancel();
    _radarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speedKmh = ((_currentPosition?.speed ?? 0) * 3.6).clamp(0, 999);
    final altitude = _currentPosition?.altitude ?? 0;
    final accuracy = _currentPosition?.accuracy ?? 0;
    final distBack = _distanceToAnchor();
    final bearingBack = _bearingToAnchor();
    final relativeAngle = ((bearingBack - _heading) * math.pi / 180);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.satellite_alt, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text(
              'بوصلة الأثر GNSS',
              style: TextStyle(
                color: Color(0xFFF59E0B),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_location, color: Color(0xFFF59E0B)),
            tooltip: 'نسخ إحداثيات SMS',
            onPressed: _copyEncryptedBeacon,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // شريط حالة الأقمار الصناعية
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.radar, color: Colors.greenAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // رادار البوصلة وسهم العودة للأثر
            SizedBox(
              height: 240,
              width: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  RotationTransition(
                    turns: _radarController,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            const Color(0xFFF59E0B).withOpacity(0.0),
                            const Color(0xFFF59E0B).withOpacity(0.25),
                          ],
                        ),
                        border: Border.all(color: const Color(0xFF334155), width: 2),
                      ),
                    ),
                  ),
                  // حلقات الرادار
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                  ),
                  // اتجاه الشمال المغناطيسي
                  Transform.rotate(
                    angle: -_heading * math.pi / 180,
                    child: const Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'N شمال',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // سهم العودة إلى نقطة البداية إذا تم تفعيل خيط الأثر
                  if (_savedAnchor != null)
                    Transform.rotate(
                      angle: relativeAngle,
                      child: const Icon(
                        Icons.navigation,
                        size: 72,
                        color: Colors.greenAccent,
                      ),
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_heading.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        const Text('السمت / الاتجاه', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // بطاقات القياس الفوري من القمر الصناعي
            Row(
              children: [
                _metricCard('السرعة', '${speedKmh.toStringAsFixed(1)} كم/س', Icons.speed),
                const SizedBox(width: 10),
                _metricCard('الارتفاع', '${altitude.toStringAsFixed(0)} م', Icons.terrain),
                const SizedBox(width: 10),
                _metricCard('الدقة', '±${accuracy.toStringAsFixed(1)} م', Icons.gps_fixed),
              ],
            ),
            const SizedBox(height: 14),

            // بطاقة الإحداثيات الحرفية
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الإحداثيات المباشرة (WGS84):',
                      style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    _currentPosition == null
                        ? 'في انتظار قفل القمر الصناعي...'
                        : 'خط العرض: ${_currentPosition!.latitude.toStringAsFixed(6)}°\nخط الطول:  ${_currentPosition!.longitude.toStringAsFixed(6)}°',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // زر تفعيل/إيقاف خيط العودة (Trackback)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _savedAnchor == null ? const Color(0xFFF59E0B) : Colors.redAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _toggleAnchor,
                icon: Icon(_savedAnchor == null ? Icons.pin_drop : Icons.stop_circle),
                label: Text(
                  _savedAnchor == null
                      ? 'تثبيت نقطة الانطلاق (بدء خيط العودة)'
                      : 'العودة للنقطة: ${distBack.toStringAsFixed(0)} متر (إلغاء)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFFF59E0B), size: 22),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

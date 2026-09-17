import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'app_config.dart';

// ─── Data models ─────────────────────────────────────────────────────────────

class _RepLocation {
  final int userId;
  final String name;
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime recordedAt;
  final String type;

  const _RepLocation({
    required this.userId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.recordedAt,
    this.type = 'check_in',
  });

  factory _RepLocation.fromJson(Map<String, dynamic> j) => _RepLocation(
        userId: (j['user_id'] as num).toInt(),
        name: j['sales_rep_name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        accuracy: (j['accuracy'] as num).toDouble(),
        recordedAt: DateTime.parse(j['recorded_at'] as String),
        type: (j['type'] ?? 'check_in').toString(),
      );

  /// Returns true if the last ping was within the past 15 minutes and not checked out.
  bool get isOnline {
    if (type.toLowerCase() == 'check_out') return false;
    final now = DateTime.now();
    final diff = recordedAt.isUtc ? now.toUtc().difference(recordedAt) : now.difference(recordedAt.toLocal());
    return !diff.isNegative && diff.inMinutes < 15;
  }

  String get lastSeenLabel {
    final now = DateTime.now();
    final diff = recordedAt.isUtc ? now.toUtc().difference(recordedAt) : now.difference(recordedAt.toLocal());
    if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _RepTask {
  final int id;
  final int userId;
  final String repName;
  final String doctorName;
  final String clinicName;
  final String clinicAddress;
  final String taskCategory;
  final String taskBasis;
  final String area;
  final String notes;
  final String status;
  final LatLng destinationLatLng;
  List<LatLng> routePoints = [];
  double distanceMeters = 0.0;
  Color color;
  int rank = 0;

  _RepTask({
    required this.id,
    required this.userId,
    required this.repName,
    required this.doctorName,
    required this.clinicName,
    required this.clinicAddress,
    required this.taskCategory,
    required this.taskBasis,
    this.area = '',
    required this.notes,
    required this.status,
    required this.destinationLatLng,
    this.color = const Color(0xFF00A86B),
  });

  String get formattedDistance {
    if (distanceMeters <= 0) return '0 m';
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get rankLabel {
    if (rank == 1) return '#1 NEAREST';
    if (rank == 2) return '#2';
    if (rank == 3) return '#3';
    return '#$rank';
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class AdminLiveTrackingScreen extends StatefulWidget {
  final int? initialRepId;
  final String? initialRepName;

  const AdminLiveTrackingScreen({
    super.key,
    this.initialRepId,
    this.initialRepName,
  });

  @override
  State<AdminLiveTrackingScreen> createState() =>
      _AdminLiveTrackingScreenState();
}

class _AdminLiveTrackingScreenState extends State<AdminLiveTrackingScreen> {
  static const _emerald = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _darkText = Color(0xFF1B4332);

  final MapController _mapController = MapController();
  List<_RepLocation> _reps = [];
  List<Map<String, dynamic>> _rawTasks = [];
  List<_RepTask> _repTasks = [];
  bool _loading = true;
  String _error = '';
  Timer? _refreshTimer;

  // Which rep is selected in the panel (null = all reps)
  _RepLocation? _selected;
  _RepTask? _selectedTask;
  double _mapRotation = 0.0;

  void _rotateToNorth() {
    setState(() => _mapRotation = 0.0);
    _mapController.rotate(0.0);
  }

  // Distinct colours for up to 10 reps
  static const _repColors = [
    Color(0xFF00A86B),
    Color(0xFF2563EB),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFFDC2626),
    Color(0xFF0891B2),
    Color(0xFF4F46E5),
    Color(0xFFEA580C),
    Color(0xFF059669),
    Color(0xFF9333EA),
  ];

  Color _colorFor(int index) => _repColors[index % _repColors.length];

  @override
  void initState() {
    super.initState();
    _fetchLocationsAndTasks();
    // Refresh live locations and tasks every 15 seconds
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _fetchLocationsAndTasks(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ── Polyline decoding ──────────────────────────────────────────────────────

  List<LatLng> _decodePolylineString(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;
    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  List<LatLng> _getLiveRepPolylinePoints(_RepTask task, LatLng repPos) {
    if (task.routePoints.isEmpty) {
      return [repPos, task.destinationLatLng];
    }
    final pts = List<LatLng>.from(task.routePoints);
    if (pts.isNotEmpty) {
      pts[0] = repPos;
    }
    return pts;
  }

  Future<Map<String, dynamic>> _fetchSingleRoute(
      double srcLat, double srcLng, double destLat, double destLng) async {
    final straightDist =
        Geolocator.distanceBetween(srcLat, srcLng, destLat, destLng);
    String waypointStr = '';
    if (straightDist > 80000) {
      final m1Lat = srcLat + (destLat - srcLat) * 0.33;
      final m1Lng = srcLng + (destLng - srcLng) * 0.33;
      final m2Lat = srcLat + (destLat - srcLat) * 0.66;
      final m2Lng = srcLng + (destLng - srcLng) * 0.66;
      waypointStr = ';$m1Lng,$m1Lat;$m2Lng,$m2Lat';
    }

    final urls = [
      'https://router.project-osrm.org/route/v1/driving/$srcLng,$srcLat$waypointStr;$destLng,$destLat?overview=full&geometries=polyline',
      'https://routing.openstreetmap.de/routed-car/route/v1/driving/$srcLng,$srcLat$waypointStr;$destLng,$destLat?overview=full&geometries=polyline',
      'https://router.project-osrm.org/route/v1/driving/$srcLng,$srcLat;$destLng,$destLat?overview=full&geometries=geojson',
    ];

    for (final urlStr in urls) {
      try {
        final res = await http.get(
          Uri.parse(urlStr),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          List<LatLng> parsedPoints = [];
          num? dist;

          if (data['code'] == 'Ok' &&
              data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            final route = data['routes'][0];
            dist = route['distance'] as num?;

            if (route['geometry'] is String) {
              parsedPoints = _decodePolylineString(route['geometry'] as String);
            } else if (route['geometry'] is Map &&
                route['geometry']['coordinates'] != null) {
              final coords = route['geometry']['coordinates'] as List;
              parsedPoints = coords
                  .map((c) =>
                      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
                  .toList();
            }
          }

          if (parsedPoints.isNotEmpty) {
            return {
              'points': parsedPoints,
              'distance': (dist ?? straightDist).toDouble(),
              'isRoad': true,
            };
          }
        }
      } catch (_) {}
    }

    // Straight-line fallback
    return {
      'points': [LatLng(srcLat, srcLng), LatLng(destLat, destLng)],
      'distance': straightDist,
      'isRoad': false,
    };
  }

  // ── API ────────────────────────────────────────────────────────────────────

  Future<void> _fetchLocationsAndTasks() async {
    List<_RepLocation> fetchedReps = [];
    List<Map<String, dynamic>> fetchedTasks = [];

    // 1. Fetch live locations
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base/backend/get_live_locations.php');
        final res = await http
            .get(url, headers: AppConfig.headers)
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            fetchedReps = (data['reps'] as List? ?? [])
                .map((e) => _RepLocation.fromJson(e as Map<String, dynamic>))
                .toList();
            break;
          }
        }
      } catch (_) {}
    }

    // 2. Fetch all user tasks
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base/backend/get_user_tasks.php?all=1');
        final res = await http
            .get(url, headers: AppConfig.headers)
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final rawList = data['tasks'];
            if (rawList != null) {
              fetchedTasks = (rawList as List).cast<Map<String, dynamic>>();
            }
            break;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _reps = fetchedReps;
        _rawTasks = fetchedTasks;
        _loading = false;
        _error = fetchedReps.isEmpty && fetchedTasks.isEmpty
            ? 'No tracking data available.'
            : '';
      });

      // Handle initial rep selection if provided via widget
      if (_selected == null && widget.initialRepId != null) {
        final found = _reps.firstWhere(
          (r) => r.userId == widget.initialRepId,
          orElse: () => _reps.isNotEmpty
              ? _reps.first
              : _RepLocation(
                  userId: 0,
                  name: '',
                  lat: 0,
                  lng: 0,
                  accuracy: 0,
                  recordedAt: DateTime.fromMicrosecondsSinceEpoch(0)),
        );
        if (found.userId != 0) {
          _selected = found;
        }
      } else if (_selected != null) {
        _selected = _reps.firstWhere(
          (r) => r.userId == _selected!.userId,
          orElse: () => _selected!,
        );
      }

      await _buildRepTasksWithRoutes();
    }
  }

  Future<void> _buildRepTasksWithRoutes() async {
    final List<_RepTask> tasksList = [];

    // Filter only ongoing / pending tasks
    final activeTasks = _rawTasks.where((t) {
      final s = (t['status'] ?? 'pending').toString().toLowerCase();
      return s != 'completed';
    }).toList();

    for (final t in activeTasks) {
      final lat = (t['clinic_lat'] as num?)?.toDouble();
      final lng = (t['clinic_lng'] as num?)?.toDouble();
      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        final repUserId = (t['user_id'] as num?)?.toInt() ?? 0;
        final repName = (t['sales_rep_name'] ?? '').toString();

        // Match rep by userId or name
        final repIndex = _reps.indexWhere(
          (r) =>
              (repUserId != 0 && r.userId == repUserId) ||
              (repName.isNotEmpty &&
                  r.name.toLowerCase() == repName.toLowerCase()),
        );

        final repColor = repIndex >= 0 ? _colorFor(repIndex) : _emerald;

        tasksList.add(_RepTask(
          id: (t['id'] as num?)?.toInt() ?? 0,
          userId: repUserId,
          repName: repName.isNotEmpty
              ? repName
              : (repIndex >= 0 ? _reps[repIndex].name : 'Sales Rep'),
          doctorName: (t['doctor_name'] ?? '').toString(),
          clinicName: (t['clinic_name'] ?? '').toString(),
          clinicAddress: (t['clinic_address'] ?? '').toString(),
          taskCategory: (t['task_category'] ?? '').toString(),
          taskBasis: (t['task_basis'] ?? 'Daily').toString(),
          area: (t['area'] ?? '').toString(),
          notes: (t['notes'] ?? '').toString(),
          status: (t['status'] ?? 'pending').toString(),
          destinationLatLng: LatLng(lat, lng),
          color: repColor,
        ));
      }
    }

    // Compute route lines and distances from rep's current position to each task destination
    final routeFutures = tasksList.map((task) async {
      final repIndex = _reps.indexWhere(
        (r) =>
            (task.userId != 0 && r.userId == task.userId) ||
            r.name.toLowerCase() == task.repName.toLowerCase(),
      );

      if (repIndex >= 0) {
        final rep = _reps[repIndex];
        final res = await _fetchSingleRoute(
          rep.lat,
          rep.lng,
          task.destinationLatLng.latitude,
          task.destinationLatLng.longitude,
        );
        task.routePoints = res['points'] as List<LatLng>;
        task.distanceMeters = res['distance'] as double;
      }
    }).toList();

    await Future.wait(routeFutures);

    // Group and sort tasks by distance per rep
    final Map<int, List<_RepTask>> tasksByRep = {};
    for (final task in tasksList) {
      tasksByRep.putIfAbsent(task.userId, () => []).add(task);
    }

    for (final entry in tasksByRep.entries) {
      entry.value.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      for (int i = 0; i < entry.value.length; i++) {
        entry.value[i].rank = i + 1;
      }
    }

    if (mounted) {
      setState(() {
        _repTasks = tasksList;
      });

      if (_selected != null) {
        _fitMapToSelectedRep(_selected!);
      }
    }
  }

  void _focusRep(_RepLocation rep) {
    setState(() {
      _selected = rep;
      _selectedTask = null;
    });
    _fitMapToSelectedRep(rep);
  }

  void _fitMapToSelectedRep(_RepLocation rep) {
    final repTasks = _repTasks
        .where((t) =>
            (t.userId != 0 && t.userId == rep.userId) ||
            t.repName.toLowerCase() == rep.name.toLowerCase())
        .toList();

    if (repTasks.isEmpty) {
      _mapController.move(LatLng(rep.lat, rep.lng), 15.0);
      return;
    }

    final List<double> lats = [rep.lat];
    final List<double> lngs = [rep.lng];

    for (final t in repTasks) {
      lats.add(t.destinationLatLng.latitude);
      lngs.add(t.destinationLatLng.longitude);
      if (t.routePoints.isNotEmpty) {
        final mid = t.routePoints.length ~/ 2;
        lats.add(t.routePoints[mid].latitude);
        lngs.add(t.routePoints[mid].longitude);
      }
    }

    final minLat = lats.reduce((a, b) => a < b ? a : b);
    final maxLat = lats.reduce((a, b) => a > b ? a : b);
    final minLng = lngs.reduce((a, b) => a < b ? a : b);
    final maxLng = lngs.reduce((a, b) => a > b ? a : b);

    if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
      _mapController.move(LatLng(minLat, minLng), 14.0);
    } else {
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds:
                LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
            padding: const EdgeInsets.fromLTRB(40, 90, 40, 240),
          ),
        );
      } catch (_) {
        _mapController.move(LatLng(rep.lat, rep.lng), 13.0);
      }
    }
  }

  void _showTaskDetailSheet(_RepTask task) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: task.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_hospital_rounded,
                      color: task.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.clinicName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _darkText),
                      ),
                      Text(
                        'Assigned to ${task.repName}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: task.color),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: task.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    task.formattedDistance,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: task.color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (task.area.isNotEmpty) ...[
              _taskInfoTile(Icons.location_city_rounded, 'Area / Division', task.area.toUpperCase()),
              const SizedBox(height: 8),
            ],
            _taskInfoTile(Icons.person_rounded, 'Doctor', task.doctorName),
            const SizedBox(height: 8),
            _taskInfoTile(Icons.category_rounded, 'Category & Basis',
                '${task.taskCategory} • ${task.taskBasis}'),
            const SizedBox(height: 8),
            _taskInfoTile(
                Icons.location_on_rounded,
                'Address',
                task.clinicAddress.isNotEmpty
                    ? task.clinicAddress
                    : 'Lat: ${task.destinationLatLng.latitude.toStringAsFixed(4)}, Lng: ${task.destinationLatLng.longitude.toStringAsFixed(4)}'),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              _taskInfoTile(Icons.note_alt_rounded, 'Notes', task.notes),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _selectedTask = task);
                  _mapController.move(task.destinationLatLng, 16.0);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: task.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                label: const Text('Focus on Destination',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskInfoTile(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B))),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _darkText)),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF5),
      body: Stack(
        children: [
          // ── Map ────────────────────────────────────────────────────────────
          _buildMap(),

          // ── Top bar ────────────────────────────────────────────────────────
          _buildTopBar(context),

          // ── Rep list panel (bottom sheet style) ────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildRepPanel(),
          ),

          // ── Loading / error overlay ────────────────────────────────────────
          if (_loading)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: _emerald),
              ),
            ),
          if (_error.isNotEmpty && !_loading)
            Positioned(
              top: 100,
              left: 24,
              right: 24,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Map layer ──────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final center = _reps.isNotEmpty
        ? LatLng(_reps.first.lat, _reps.first.lng)
        : const LatLng(13.0827, 80.2707); // default Chennai

    // Filter tasks based on selected rep or show all
    final displayedTasks = _selected != null
        ? _repTasks
            .where((t) =>
                (t.userId != 0 && t.userId == _selected!.userId) ||
                t.repName.toLowerCase() == _selected!.name.toLowerCase())
            .toList()
        : _repTasks;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 12.0,
        initialRotation: 0.0,
        minZoom: 3.0,
        maxZoom: 18.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) {
            if (_mapRotation != 0.0) {
              setState(() {
                _mapRotation = 0.0;
              });
            }
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.medsafe.medsafelifescience',
        ),

        // ── Route Polylines from Sales Reps to Task Destinations ──
        if (displayedTasks.isNotEmpty)
          PolylineLayer(
            polylines: [
              // Outer contrast border
              for (final task in displayedTasks)
                () {
                  final rep = _reps.firstWhere(
                    (r) => (task.userId != 0 && r.userId == task.userId) || r.name.toLowerCase() == task.repName.toLowerCase(),
                    orElse: () => _RepLocation(userId: 0, name: '', lat: 0, lng: 0, accuracy: 0, recordedAt: DateTime.now()),
                  );
                  final repPos = rep.userId != 0 ? LatLng(rep.lat, rep.lng) : task.destinationLatLng;
                  return Polyline(
                    points: _getLiveRepPolylinePoints(task, repPos),
                    strokeWidth: _selectedTask == task ? 10.0 : 7.5,
                    color: Colors.black.withValues(alpha: 0.35),
                  );
                }(),
              // Inner colored route stroke
              for (final task in displayedTasks)
                () {
                  final rep = _reps.firstWhere(
                    (r) => (task.userId != 0 && r.userId == task.userId) || r.name.toLowerCase() == task.repName.toLowerCase(),
                    orElse: () => _RepLocation(userId: 0, name: '', lat: 0, lng: 0, accuracy: 0, recordedAt: DateTime.now()),
                  );
                  final repPos = rep.userId != 0 ? LatLng(rep.lat, rep.lng) : task.destinationLatLng;
                  return Polyline(
                    points: _getLiveRepPolylinePoints(task, repPos),
                    strokeWidth: _selectedTask == task ? 6.5 : 4.5,
                    color: task.color,
                  );
                }(),
            ],
          ),

        // ── Task Destination Markers ──
        if (displayedTasks.isNotEmpty)
          MarkerLayer(
            markers: displayedTasks.map((task) {
              final isSelected = _selectedTask == task;
              final isNearest = task.rank == 1;

              return Marker(
                point: task.destinationLatLng,
                width: isNearest ? 94 : 82,
                height: isNearest ? 96 : 84,
                child: GestureDetector(
                  onTap: () => _showTaskDetailSheet(task),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Distance & Rank badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: task.color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.white,
                              width: isSelected ? 2 : 1),
                          boxShadow: [
                            BoxShadow(
                                color: task.color.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Text(
                          isNearest
                              ? '★ ${task.formattedDistance}'
                              : '${task.rankLabel} • ${task.formattedDistance}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Clinic bubble
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF1B4332).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          task.clinicName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.location_on_rounded,
                        color: task.color,
                        size: isNearest ? 32 : 26,
                        shadows: const [
                          Shadow(
                              color: Colors.black38,
                              blurRadius: 4,
                              offset: Offset(0, 2))
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

        // ── Sales Rep Current Location Markers ──
        MarkerLayer(
          markers: _reps.asMap().entries.map((entry) {
            final i = entry.key;
            final rep = entry.value;
            final col = _colorFor(i);
            final isSelected = _selected?.userId == rep.userId;

            return Marker(
              point: LatLng(rep.lat, rep.lng),
              width: isSelected ? 80 : 64,
              height: isSelected ? 92 : 74,
              child: GestureDetector(
                onTap: () => _focusRep(rep),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name bubble with online indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: isSelected ? col : col.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: col.withValues(alpha: 0.45),
                            blurRadius: isSelected ? 10 : 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: rep.isOnline
                                  ? Colors.white
                                  : Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            rep.name.split(' ').first, // first name only
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isSelected ? 10 : 9,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Pin icon
                    Icon(
                      rep.isOnline
                          ? Icons.person_pin_circle_rounded
                          : Icons.location_off_rounded,
                      color: rep.isOnline ? col : Colors.grey,
                      size: isSelected ? 38 : 30,
                      shadows: [
                        Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    final onlineCount = _reps.where((r) => r.isOnline).length;
    final totalTasksCount = _repTasks.length;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: _emeraldDark),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration:
                  const BoxDecoration(color: _emerald, shape: BoxShape.circle),
              child: const Icon(Icons.alt_route_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selected != null
                        ? '${_selected!.name} Live Route'
                        : 'Live Tracking & Routes',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _darkText,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _selected != null
                        ? '${_repTasks.where((t) => t.userId == _selected!.userId).length} Task Destinations'
                        : '$onlineCount/${_reps.length} Reps Online • $totalTasksCount Active Tasks',
                    style:
                        const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                  ),
                ],
              ),
            ),
            if (_selected != null) ...[
              GestureDetector(
                onTap: () {
                  setState(() {
                    _selected = null;
                    _selectedTask = null;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('All Reps',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569))),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // Compass Reset Button (visible when rotated)
            GestureDetector(
              onTap: _rotateToNorth,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _mapRotation.abs() > 1 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _mapRotation.abs() > 1 ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: -(_mapRotation * (3.141592653589793 / 180.0)),
                      child: const Icon(Icons.explore_rounded, size: 16, color: Color(0xFFEF4444)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${((_mapRotation.round() % 360 + 360) % 360)}°',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Refresh button
            GestureDetector(
              onTap: () {
                setState(() => _loading = true);
                _fetchLocationsAndTasks();
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 18, color: _emeraldDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Rep list & Tasks panel ──────────────────────────────────────────────────

  Widget _buildRepPanel() {
    if (_reps.isEmpty && !_loading) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'No location data yet.\nReps will appear here once they open the app.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF52796F), fontSize: 13),
          ),
        ),
      );
    }

    final selectedRepTasks = _selected != null
        ? _repTasks
            .where((t) =>
                (t.userId != 0 && t.userId == _selected!.userId) ||
                t.repName.toLowerCase() == _selected!.name.toLowerCase())
            .toList()
        : <_RepTask>[];

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Selected Rep Task Destinations Strip ──
          if (_selected != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.alt_route_rounded,
                      size: 16, color: _colorFor(_reps.indexOf(_selected!))),
                  const SizedBox(width: 6),
                  Text(
                    '${_selected!.name} — ${selectedRepTasks.length} Task Destinations',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _darkText),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _fitMapToSelectedRep(_selected!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD1FAE5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_out_map_rounded,
                              size: 12, color: _emerald),
                          SizedBox(width: 3),
                          Text('Fit Routes',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _emerald)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selectedRepTasks.isNotEmpty)
              SizedBox(
                height: 76,
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  scrollDirection: Axis.horizontal,
                  itemCount: selectedRepTasks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final task = selectedRepTasks[i];
                    final isSelected = _selectedTask == task;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedTask = task);
                        _mapController.move(task.destinationLatLng, 16.0);
                      },
                      child: Container(
                        width: 170,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? task.color.withValues(alpha: 0.15)
                              : const Color(0xFFF8FFFE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isSelected
                                  ? task.color
                                  : const Color(0xFFD1FAE5),
                              width: isSelected ? 1.5 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  task.rank == 1
                                      ? '★ NEAREST'
                                      : '#${task.rank}',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: task.color),
                                ),
                                Text(
                                  task.formattedDistance,
                                  style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1B4332)),
                                ),
                              ],
                            ),
                            Text(
                              task.clinicName,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _darkText),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Dr. ${task.doctorName}',
                              style: const TextStyle(
                                  fontSize: 9.5, color: Color(0xFF52796F)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No active tasks assigned to this rep.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              ),
            const Divider(height: 12, color: Color(0xFFE2E8F0)),
          ],

          // ── Header for Sales Reps ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                const Text(
                  'Sales Representatives',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _darkText,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_reps.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _emeraldDark,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Auto-refresh 15s',
                  style:
                      TextStyle(fontSize: 10, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),

          // ── Reps List ──
          Flexible(
            child: ListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shrinkWrap: true,
              itemCount: _reps.length,
              itemBuilder: (context, i) {
                final rep = _reps[i];
                final col = _colorFor(i);
                final isSelected = _selected?.userId == rep.userId;
                final repTasksCount = _repTasks
                    .where((t) =>
                        (t.userId != 0 && t.userId == rep.userId) ||
                        t.repName.toLowerCase() == rep.name.toLowerCase())
                    .length;

                return GestureDetector(
                  onTap: () => _focusRep(rep),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? col.withValues(alpha: 0.08)
                          : const Color(0xFFF8FFFE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? col.withValues(alpha: 0.5)
                            : const Color(0xFFE2F0E8),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: col.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: col.withValues(alpha: 0.4),
                                width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              rep.name.isNotEmpty
                                  ? rep.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: col,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Name + Tasks count
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rep.name,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _darkText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: col.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$repTasksCount Tasks Active',
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: col),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    rep.lastSeenLabel,
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        color: Colors.grey.shade400),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Online badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: rep.isOnline
                                ? const Color(0xFFD1FAE5)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: rep.isOnline
                                      ? _emerald
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rep.isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: rep.isOnline
                                      ? _emeraldDark
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

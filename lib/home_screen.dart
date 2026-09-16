import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models/user_model.dart';
import 'data/product_data.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';
import 'login_screen.dart';
import 'product_list_screen.dart';
import 'product_detail_screen.dart';
import 'order_now_screen.dart';
import 'task_screen.dart';
import 'admin_sales_rep_list_screen.dart';
import 'admin_attendance_history_screen.dart';
import 'admin_task_performance_screen.dart';
import 'admin_pdf_reports_screen.dart';
import 'package:intl/intl.dart';
import 'app_config.dart';
import 'widgets/task_map_verification_modal.dart';

// Base URL from central config — change AppConfig to switch between ngrok/local
String get _kWampBase => AppConfig.baseUrl;

// ─── Mapped Task Model for Multi-Route Comparison ───────────────────────────

class MappedTask {
  final int? taskId;
  final String doctorName;
  final String clinicName;
  final String clinicAddress;
  final String taskCategory;
  final String taskBasis;
  final LatLng destinationLatLng;
  final String notes;
  String status;
  List<LatLng> routePoints;
  double distanceMeters;
  bool isRoadRoute;
  int rank; // 1 = Nearest, 2 = 2nd nearest, 3 = 3rd nearest...
  Color color;

  MappedTask({
    this.taskId,
    required this.doctorName,
    required this.clinicName,
    required this.clinicAddress,
    required this.taskCategory,
    required this.taskBasis,
    required this.destinationLatLng,
    this.notes = '',
    this.status = 'pending',
    List<LatLng>? routePoints,
    this.distanceMeters = 0.0,
    this.isRoadRoute = false,
    this.rank = 0,
    this.color = const Color(0xFF00A86B),
  }) : routePoints = routePoints ?? [];

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

class HomeScreen extends StatefulWidget {
  final User user;
  final String token;

  const HomeScreen({
    super.key,
    required this.user,
    required this.token,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String _currentView = 'dashboard';
  String _adminTab = 'reps'; // 'reps' or 'tasks'
  bool _productsExpanded = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final MapController _mapController = MapController();
  Position? _currentPosition;
  bool _isLoading = true;
  String _statusMessage = 'Initializing location services...';
  bool _hasPermission = false;

  // User tasks for Dashboard
  List<Map<String, dynamic>> _userTasks = [];
  bool _loadingUserTasks = false;
  String _selectedAdminTaskRepFilter = 'All Sales Reps';
  DateTime? _selectedCompletionDate;

  // Admin Tasks DB Date Range Filter
  DateTime? _adminTasksFromDate;
  DateTime? _adminTasksToDate;
  DateTime? _adminTasksAppliedFromDate;
  DateTime? _adminTasksAppliedToDate;

  bool _taskMatchesDate(Map<String, dynamic> task, DateTime? date) {
    if (date == null) return true;
    final targetStr = DateFormat('yyyy-MM-dd').format(date);

    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    if (checkoutDate.isNotEmpty && checkoutDate == targetStr) return true;

    final createdAt = (task['created_at'] ?? '').toString().trim();
    if (createdAt.length >= 10 && createdAt.substring(0, 10) == targetStr) return true;

    final updatedAt = (task['updated_at'] ?? '').toString().trim();
    if (updatedAt.length >= 10 && updatedAt.substring(0, 10) == targetStr) return true;

    final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();
    if (checkedOutAt.length >= 10 && checkedOutAt.substring(0, 10) == targetStr) return true;

    return false;
  }

  List<Map<String, dynamic>> get _dateFilteredUserTasks {
    if (_selectedCompletionDate == null) return _userTasks;
    return _userTasks.where((t) => _taskMatchesDate(t, _selectedCompletionDate)).toList();
  }

  List<String> get _adminTaskRepNames {
    final set = <String>{};
    for (var t in _userTasks) {
      final name = (t['sales_rep_name'] ?? '').toString().trim();
      if (name.isNotEmpty) set.add(name);
    }
    return ['All Sales Reps', ...set.toList()..sort()];
  }

  List<Map<String, dynamic>> get _filteredAdminTasks {
    if (_selectedAdminTaskRepFilter == 'All Sales Reps') {
      return _userTasks;
    }
    final filtered = _userTasks.where((t) {
      final name = (t['sales_rep_name'] ?? '').toString().trim();
      return name.toLowerCase() == _selectedAdminTaskRepFilter.toLowerCase();
    }).toList();
    return filtered.isNotEmpty ? filtered : _userTasks;
  }

  // Track map zoom
  double _zoom = 15.0;

  // Pulse animation for current location marker
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Stream subscription for real-time location updates
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _locationStreamFallbackTimer;

  // Services
  final _authService = AuthService();
  final _storageService = StorageService();

  // ── Task / Destination ────────────────────────────────────────────────────
  LatLng? _destinationLatLng;
  String _destinationName = '';
  String _destinationAddress = '';
  String _assignedDoctor = '';
  String _taskBasis = '';
  bool _showRoute = false;
  List<LatLng> _routePoints = [];
  double _distanceMeters = 0.0;

  // ── Multi-Task Route Comparison ───────────────────────────────────────────
  List<MappedTask> _mappedTasks = [];
  bool _showMultiRoute = false;
  MappedTask? _selectedMappedTask;
  Position? _lastRouteFetchPosition;
  bool _isFetchingRoutes = false;
  bool _autoFollowUser = true;

  // ── Sales Rep Direction Heading ───────────────────────────────────────────
  double _deviceHeading = 0.0;

  // ── Automatic Checkout Tracking (5-meter radius for 60 continuous seconds) ──
  final Map<int, DateTime> _taskProximityEntryTimes = {};
  final Set<int> _inFlightAutoCheckouts = {};
  int? _activeTaskId;
  Timer? _destinationTickerTimer;

  DateTime? _parseDestinationReachedAt(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == 'null' || str == '0000-00-00 00:00:00') return null;
    return DateTime.tryParse(str);
  }

  /// Calculates elapsed seconds since reaching the 15-meter destination radius.
  /// Returns null if no active task or destination has not yet been confirmed reached.
  int? get _activeTaskDestinationElapsedSeconds {
    if (widget.user.isAdmin) return null;

    Map<String, dynamic>? activeTask;
    for (final t in _userTasks) {
      final s = (t['status'] ?? 'pending').toString().toLowerCase();
      if (s == 'in_progress' || s == 'started') {
        activeTask = t;
        break;
      }
    }
    if (activeTask == null) return null;

    final reachedStr = activeTask['destination_reached_at'];
    final reachedDt = _parseDestinationReachedAt(reachedStr);
    if (reachedDt == null) return null;

    final now = DateTime.now();
    final diff = now.difference(reachedDt).inSeconds;
    return diff >= 0 ? diff : 0;
  }

  /// Formats elapsed seconds strictly as MM:SS (e.g. 00:01, 00:30, 01:30, 04:59, 05:00)
  static String formatElapsedMMSS(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatElapsedMMSS(int totalSeconds) => formatElapsedMMSS(totalSeconds);

  Color _getRankColor(int rank) {
    const palette = [
      Color(0xFF00A86B), // #1 Nearest: Emerald Green
      Color(0xFF2563EB), // #2 2nd: Royal Blue
      Color(0xFFD97706), // #3 3rd: Amber / Gold Orange
      Color(0xFF7C3AED), // #4 4th: Violet
      Color(0xFFEA580C), // #5 5th: Deep Orange
      Color(0xFF0D9488), // #6 6th: Teal
      Color(0xFFDB2777), // #7 7th: Pink
      Color(0xFF4F46E5), // #8 8th: Indigo
      Color(0xFF059669), // #9 9th: Mint Emerald
      Color(0xFF9333EA), // #10 10th: Purple
      Color(0xFFCA8A04), // #11 11th: Mustard
      Color(0xFFE11D48), // #12 12th: Rose Red
    ];
    if (rank >= 1 && rank <= palette.length) {
      return palette[rank - 1];
    }
    return palette[(rank - 1) % palette.length];
  }

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

  Future<Map<String, dynamic>> _fetchSingleRoute(double srcLat, double srcLng, double destLat, double destLng) async {
    final straightDist = Geolocator.distanceBetween(srcLat, srcLng, destLat, destLng);
    String waypointStr = '';
    if (straightDist > 80000) {
      final m1Lat = srcLat + (destLat - srcLat) * 0.33;
      final m1Lng = srcLng + (destLng - srcLng) * 0.33;
      final m2Lat = srcLat + (destLat - srcLat) * 0.66;
      final m2Lng = srcLng + (destLng - srcLng) * 0.66;
      waypointStr = ';$m1Lng,$m1Lat;$m2Lng,$m2Lat';
    }

    final urls = [
      '$_kWampBase/backend/get_route.php?src_lat=$srcLat&src_lng=$srcLng&dest_lat=$destLat&dest_lng=$destLng',
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
        ).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          List<LatLng> parsedPoints = [];
          num? dist;

          if (data['code'] == 'Ok' && data['routes'] != null && (data['routes'] as List).isNotEmpty) {
            final route = data['routes'][0];
            dist = route['distance'] as num?;
            final geom = route['geometry'];
            if (geom is String) {
              parsedPoints = _decodePolylineString(geom);
            } else if (geom is Map && geom['coordinates'] != null) {
              final coords = geom['coordinates'] as List;
              parsedPoints = coords.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
            }
          } else if (data['success'] == true && data['points'] != null) {
            final coords = data['points'] as List;
            dist = data['distance'] as num?;
            parsedPoints = coords.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
          }

          if (parsedPoints.isNotEmpty && parsedPoints.length > 2) {
            return {
              'points': parsedPoints,
              'distance': dist != null ? dist.toDouble() : straightDist,
              'isRoad': true,
            };
          }
        }
      } catch (_) {}
    }

    return {
      'points': [LatLng(srcLat, srcLng), LatLng(destLat, destLng)],
      'distance': straightDist,
      'isRoad': false,
    };
  }

  Future<void> _fetchRoute() async {
    if (_currentPosition == null || _destinationLatLng == null) return;

    final start = _currentPosition!;
    final end   = _destinationLatLng!;

    final res = await _fetchSingleRoute(start.latitude, start.longitude, end.latitude, end.longitude);
    if (mounted) {
      setState(() {
        _routePoints = res['points'] as List<LatLng>;
        _distanceMeters = res['distance'] as double;
      });
    }
  }

  List<LatLng> _getLivePolylinePoints(MappedTask task, LatLng currentPos) {
    if (task.routePoints.isEmpty) {
      return [currentPos, task.destinationLatLng];
    }
    final rawPoints = task.routePoints;
    if (rawPoints.length <= 1) {
      return [currentPos, task.destinationLatLng];
    }

    // Find the closest point index on the pre-calculated road route to current position
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < rawPoints.length; i++) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        rawPoints[i].latitude,
        rawPoints[i].longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closestIdx = i;
      }
    }

    // Dynamically connect current GPS location to the remaining forward route
    final remaining = rawPoints.sublist(closestIdx);
    return [currentPos, ...remaining];
  }

  List<LatLng> _getLiveSingleRoutePoints(LatLng currentPos, LatLng dest) {
    if (_routePoints.isEmpty) {
      return [currentPos, dest];
    }
    int closestIdx = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < _routePoints.length; i++) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        _routePoints[i].latitude,
        _routePoints[i].longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closestIdx = i;
      }
    }
    final remaining = _routePoints.sublist(closestIdx);
    return [currentPos, ...remaining];
  }

  double _getEffectiveHeading(LatLng currentLatLng) {
    if (_deviceHeading > 0) return _deviceHeading;

    // Fallback: calculate bearing toward the active task destination
    LatLng? target;
    if (_selectedMappedTask != null) {
      target = _selectedMappedTask!.destinationLatLng;
    } else if (_mappedTasks.isNotEmpty) {
      target = _mappedTasks.first.destinationLatLng;
    } else if (_destinationLatLng != null) {
      target = _destinationLatLng;
    }

    if (target != null && (target.latitude != currentLatLng.latitude || target.longitude != currentLatLng.longitude)) {
      final dLng = (target.longitude - currentLatLng.longitude) * (math.pi / 180.0);
      final lat1 = currentLatLng.latitude * (math.pi / 180.0);
      final lat2 = target.latitude * (math.pi / 180.0);
      final y = math.sin(dLng) * math.cos(lat2);
      final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
      final brng = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
      return brng;
    }
    return 0.0;
  }

  Future<void> _fetchMultiRoutes(List<MappedTask> tasks, {bool shouldFitBounds = true}) async {
    if (tasks.isEmpty || _isFetchingRoutes) return;
    _isFetchingRoutes = true;

    try {
      if (_currentPosition == null) {
        try {
          _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
        } catch (_) {}
      }

      _lastRouteFetchPosition = _currentPosition;

      final srcLat = _currentPosition?.latitude ?? 0.0;
      final srcLng = _currentPosition?.longitude ?? 0.0;

      if (srcLat == 0.0 && srcLng == 0.0) {
        for (int i = 0; i < tasks.length; i++) {
          tasks[i].rank = i + 1;
          tasks[i].color = _getRankColor(i + 1);
        }
        if (mounted) {
          setState(() {
            _mappedTasks = tasks;
            _showMultiRoute = true;
            _selectedMappedTask = null;
          });
          if (shouldFitBounds) {
            _fitMapToAllMappedTasks(tasks);
          }
        }
        return;
      }

      // Fetch road route and calculate real distance for each task concurrently
      final futures = tasks.map((task) async {
        final destLat = task.destinationLatLng.latitude;
        final destLng = task.destinationLatLng.longitude;
        final result = await _fetchSingleRoute(srcLat, srcLng, destLat, destLng);
        task.routePoints = result['points'] as List<LatLng>;
        task.distanceMeters = result['distance'] as double;
        task.isRoadRoute = result['isRoad'] as bool;
      }).toList();

      await Future.wait(futures);

      // SORT ALL TASKS FROM NEAREST TO FARTHEST
      tasks.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      // Assign rank 1..N and distinct theme colors
      for (int i = 0; i < tasks.length; i++) {
        tasks[i].rank = i + 1;
        tasks[i].color = _getRankColor(i + 1);
      }

      if (mounted) {
        setState(() {
          _mappedTasks = tasks;
          _showMultiRoute = true;
          // Preserve currently selected task navigation if one was already chosen
          if (_selectedMappedTask != null) {
            final found = tasks.firstWhere(
              (m) =>
                  (m.taskId != null && m.taskId == _selectedMappedTask!.taskId) ||
                  (m.clinicName.toLowerCase() == _selectedMappedTask!.clinicName.toLowerCase() &&
                   m.doctorName.toLowerCase() == _selectedMappedTask!.doctorName.toLowerCase()),
              orElse: () => tasks.first,
            );
            _selectedMappedTask = found;
            _destinationLatLng = found.destinationLatLng;
            _destinationName = found.clinicName;
            _destinationAddress = found.clinicAddress;
            _assignedDoctor = found.doctorName;
            _taskBasis = found.taskBasis;
            _distanceMeters = found.distanceMeters;
          } else if (tasks.isNotEmpty) {
            _destinationLatLng = tasks.first.destinationLatLng;
            _destinationName = tasks.first.clinicName;
            _destinationAddress = tasks.first.clinicAddress;
            _assignedDoctor = tasks.first.doctorName;
            _taskBasis = tasks.first.taskBasis;
            _distanceMeters = tasks.first.distanceMeters;
          }
        });
        if (shouldFitBounds) {
          _fitMapToAllMappedTasks(tasks);
        }
      }
    } finally {
      _isFetchingRoutes = false;
    }
  }

  void _fitMapToAllMappedTasks(List<MappedTask> tasks) {
    if (tasks.isEmpty) return;
    try {
      final List<double> allLats = [];
      final List<double> allLngs = [];

      if (_currentPosition != null) {
        allLats.add(_currentPosition!.latitude);
        allLngs.add(_currentPosition!.longitude);
      }

      for (final t in tasks) {
        allLats.add(t.destinationLatLng.latitude);
        allLngs.add(t.destinationLatLng.longitude);
        if (t.routePoints.isNotEmpty) {
          final mid = t.routePoints.length ~/ 2;
          allLats.add(t.routePoints[mid].latitude);
          allLngs.add(t.routePoints[mid].longitude);
        }
      }

      final minLat = allLats.reduce((a, b) => a < b ? a : b);
      final maxLat = allLats.reduce((a, b) => a > b ? a : b);
      final minLng = allLngs.reduce((a, b) => a < b ? a : b);
      final maxLng = allLngs.reduce((a, b) => a > b ? a : b);

      if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
        _mapController.move(LatLng(minLat, minLng), 14.0);
      } else {
        final bounds = LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        );

        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(40, 90, 40, 240),
          ),
        );
      }
    } catch (_) {
      if (tasks.isNotEmpty) {
        _mapController.move(tasks.first.destinationLatLng, 13.0);
      }
    }
  }

  /// Synchronize all ongoing tasks (up to 3 or more) to the map simultaneously
  /// for route comparison, distance calculation, and nearest-first ranking.
  Future<void> _syncOngoingTasksToMap({
    MappedTask? focusTask,
    List<MappedTask>? newAssignedTasks,
  }) async {
    final List<MappedTask> combined = [];
    final Set<String> seenKeys = {};

    String makeKey(double lat, double lng, String clinic, String doctor) =>
        '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}_${clinic.trim().toLowerCase()}_${doctor.trim().toLowerCase()}';

    // 1. Add any newly assigned tasks
    if (newAssignedTasks != null) {
      for (final t in newAssignedTasks) {
        final key = makeKey(
          t.destinationLatLng.latitude,
          t.destinationLatLng.longitude,
          t.clinicName,
          t.doctorName,
        );
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          combined.add(t);
        }
      }
    }

    // 2. Add ongoing tasks from _userTasks
    final ongoing = _userTasks.where((t) {
      final s = (t['status'] ?? 'pending').toString().toLowerCase();
      return s != 'completed';
    }).toList();

    for (final t in ongoing) {
      final lat = (t['clinic_lat'] as num?)?.toDouble();
      final lng = (t['clinic_lng'] as num?)?.toDouble();
      if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
        final clinic = (t['clinic_name'] ?? '').toString();
        final doc = (t['doctor_name'] ?? '').toString();
        final key = makeKey(lat, lng, clinic, doc);
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          combined.add(MappedTask(
            taskId: (t['id'] as num?)?.toInt(),
            doctorName: doc,
            clinicName: clinic,
            clinicAddress: (t['clinic_address'] ?? '').toString(),
            taskCategory: (t['task_category'] ?? '').toString(),
            taskBasis: (t['task_basis'] ?? 'Daily').toString(),
            notes: (t['notes'] ?? '').toString(),
            status: (t['status'] ?? 'pending').toString(),
            destinationLatLng: LatLng(lat, lng),
          ));
        }
      }
    }

    if (combined.isEmpty && focusTask != null) {
      combined.add(focusTask);
    }

    if (combined.isNotEmpty) {
      if (mounted) {
        setState(() {
          _showMultiRoute = true;
          _showRoute = true;
        });
      }
      await _fetchMultiRoutes(combined);
      if (focusTask != null && mounted) {
        final found = _mappedTasks.firstWhere(
          (m) =>
              m.clinicName.toLowerCase() == focusTask.clinicName.toLowerCase() &&
              m.doctorName.toLowerCase() == focusTask.doctorName.toLowerCase(),
          orElse: () => _mappedTasks.first,
        );
        setState(() => _selectedMappedTask = found);
      }
    }
  }

  Future<void> _recordAttendance(String type, {String? notes}) async {
    if (widget.user.isAdmin) return;
    
    Position? pos = _currentPosition;
    if (pos == null) {
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}
    }

    final double lat = pos?.latitude ?? 0.0;
    final double lng = pos?.longitude ?? 0.0;

    final body = jsonEncode({
      'user_id':        widget.user.id,
      'sales_rep_name': widget.user.name,
      'type':           type,
      'lat':            lat,
      'lng':            lng,
      'address':        pos != null ? 'Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}' : '',
      'notes':          notes ?? (type == 'check_in' ? 'App check-in' : 'App check-out'),
    });

    final bases = AppConfig.allHosts;
    for (final base in bases) {
      try {
        final res = await http.post(
          Uri.parse('$base/backend/save_attendance.php'),
          headers: AppConfig.headers,
          body: body,
        ).timeout(const Duration(seconds: 5));
        final parsed = json.decode(res.body);
        debugPrint('[Attendance] $type saved via $base → ${res.statusCode}: ${parsed['message'] ?? parsed}');
        if (parsed['success'] == true) return; // success — stop trying
      } catch (e) {
        debugPrint('[Attendance] $type failed on $base: $e');
      }
    }
  }


  // ─── Step 1: Dashboard Back Button with Checkout Confirmation ───────────
  Future<void> _showDashboardBackConfirmationDialog() async {
    final shouldCheckout = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFEDD5)),
                      ),
                      child: const Icon(Icons.logout_rounded, color: Color(0xFFEA580C), size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check Out',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Confirm session sign out',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Are you sure you want to Check Out and log out of the application?',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF475569),
                          side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00A86B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Check Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shouldCheckout == true) {
      await _signOut();
    }
  }

  // ─── Step 2: Distance-based dynamic zoom calculation (Google Maps style) ───
  double _calculateDynamicZoom(double distanceMeters) {
    if (distanceMeters <= 0) return 16.0;
    if (distanceMeters > 15000) return 12.0;
    if (distanceMeters > 8000) return 13.0;
    if (distanceMeters > 4000) return 14.0;
    if (distanceMeters > 2000) return 15.0;
    if (distanceMeters > 1000) return 15.8;
    if (distanceMeters > 500) return 16.5;
    if (distanceMeters > 150) return 17.2;
    if (distanceMeters > 50) return 17.8;
    return 18.0;
  }

  // ─── Real API logout ───────────────────────────────────────────────────────
  Future<void> _signOut() async {
    // Stop background location updates before recording checkout
    _positionStreamSubscription?.cancel();
    _locationStreamFallbackTimer?.cancel();
    _stopLocationPushTimer();

    // Record checkout location if sales rep
    if (!widget.user.isAdmin) {
      await _recordAttendance('check_out', notes: 'Logged out / Checked out from app');
    }

    // Close the drawer or any overlay first
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }

    // Call API (best-effort — we clear local data regardless)
    await _authService.logout(token: widget.token);
    await _storageService.clearAll();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (route) => false,
    );
  }
  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _darkText = Color(0xFF1E293B);
  static const _darkSubtext = Color(0xFF475569);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: false);

    _pulseAnimation = Tween<double>(begin: 8.0, end: 24.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _initLocationService();
    _fetchUserTasks();
    _destinationTickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeTaskDestinationElapsedSeconds != null) {
        setState(() {});
      }
    });
    // Check for pending tasks after a short delay so the map renders first
    Future.delayed(const Duration(milliseconds: 1200), _checkPendingTasks);
  }

  Future<void> _fetchUserTasks({DateTime? fromDate, DateTime? toDate}) async {
    setState(() => _loadingUserTasks = true);
    final repNameEncoded = Uri.encodeComponent(widget.user.name);

    final useFrom = fromDate ?? _adminTasksAppliedFromDate;
    final useTo = toDate ?? _adminTasksAppliedToDate;
    String dateParams = '';
    if (useFrom != null) {
      dateParams += '&from_date=${DateFormat('yyyy-MM-dd').format(useFrom)}';
    }
    if (useTo != null) {
      dateParams += '&to_date=${DateFormat('yyyy-MM-dd').format(useTo)}';
    }

    // For non-admin: match by user_id AND sales_rep_name; for admin: fetch all
    final relativePath = (widget.user.isAdmin || widget.user.id == 0)
        ? '/backend/get_user_tasks.php?all=1$dateParams'
        : '/backend/get_user_tasks.php?user_id=${widget.user.id}&sales_rep_name=$repNameEncoded$dateParams';

    // Try the configured server IP first, then common local addresses
    final bases = AppConfig.allHosts;

    for (final base in bases) {
      try {
        final url = Uri.parse('$base$relativePath');
        debugPrint('[Tasks] Trying: $url');
        final response = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 6));
        debugPrint('[Tasks] Status: ${response.statusCode}  Body: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            final rawList = data['tasks'];
            final list = rawList != null
                ? (rawList as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[];
            debugPrint('[Tasks] Fetched ${list.length} tasks from $base');
            if (mounted) {
              setState(() {
                _userTasks = list;
                _loadingUserTasks = false;
              });
              if (!widget.user.isAdmin) {
                final inProg = list.firstWhere(
                  (t) => (t['status'] ?? '').toString().toLowerCase() == 'in_progress',
                  orElse: () => <String, dynamic>{},
                );
                if (inProg.isNotEmpty && inProg['id'] != null) {
                  final actId = (inProg['id'] as num).toInt();
                  if (_activeTaskId != actId || _locationPushTimer == null || !_locationPushTimer!.isActive) {
                    _startLocationPushTimer(actId);
                  }
                } else {
                  _stopLocationPushTimer();
                }
                _syncOngoingTasksToMap();
              }
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('[Tasks] Error from $base: $e');
      }
    }
    debugPrint('[Tasks] All hosts failed — no tasks loaded.');
    if (mounted) setState(() => _loadingUserTasks = false);
  }

  void _showNotInClinicDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.location_off_rounded, color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 10),
            Text(
              'Location Alert',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B)),
            ),
          ],
        ),
        content: const Text(
          "You are not in the Doctor's Clinic",
          style: TextStyle(fontSize: 15, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A86B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              color: valueColor ?? const Color(0xFF1E293B),
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _showOvertimeReasonDialog({
    required String doctorName,
    required String clinicName,
    required String reachedTime,
    required int overtimeSeconds,
  }) async {
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final destinationName = clinicName.isNotEmpty && clinicName != 'N/A'
        ? (doctorName.isNotEmpty && doctorName != 'N/A' ? '$clinicName (Dr. $doctorName)' : clinicName)
        : (doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Destination Clinic');
    final totalElapsedSeconds = 300 + math.max(0, overtimeSeconds).toInt();
    final elapsedMMSS = _formatElapsedMMSS(totalElapsedSeconds);
    final overtimeMMSS = _formatElapsedMMSS(math.max(0, overtimeSeconds).toInt());

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.timer_off_rounded, color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'OVERTIME',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFFDC2626), letterSpacing: 0.5),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Destination details box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, color: Color(0xFFDC2626), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Destination: $destinationName',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF991B1B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, color: Color(0xFFFCA5A5)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('Target Time:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7F1D1D))),
                          Text('05:00', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF7F1D1D))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Elapsed Time:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7F1D1D))),
                          Text(elapsedMMSS, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF7F1D1D))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Overtime:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFDC2626))),
                          Text('+$overtimeMMSS', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFFDC2626))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Reason for Overtime',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Enter reason for overtime (Mandatory)...',
                    hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFCBD5E1))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
                    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter the overtime reason.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, reasonController.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('FORCE STOP', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }

  void _showTaskCompletionSummaryDialog({
    required String doctorName,
    required String clinicName,
    required String destinationReachedAt,
    required String completedAt,
    required double finalDistanceMeters,
    required String completionResult,
    required int overtimeDurationSeconds,
  }) {
    if (!mounted) return;
    final isOvertime = (completionResult.toLowerCase() == 'overtime');
    final otMin = overtimeDurationSeconds ~/ 60;
    final otSec = overtimeDurationSeconds % 60;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isOvertime ? const Color(0xFFFFFBEB) : const Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOvertime ? Icons.check_circle_outline_rounded : Icons.check_circle_rounded,
                      color: isOvertime ? const Color(0xFFD97706) : const Color(0xFF047857),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Task Completed',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B)),
                        ),
                        Text(
                          'Dr. $doctorName • $clinicName',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _summaryRow('Destination Reached', destinationReachedAt.isNotEmpty ? destinationReachedAt : 'Recorded'),
                    const Divider(height: 14, color: Color(0xFFE2E8F0)),
                    _summaryRow('Target Duration', '05:00 (5 Minutes)'),
                    const Divider(height: 14, color: Color(0xFFE2E8F0)),
                    _summaryRow('Task Completed At', completedAt),
                    const Divider(height: 14, color: Color(0xFFE2E8F0)),
                    _summaryRow('Final Distance', '${finalDistanceMeters.toStringAsFixed(1)} m (<= 15m)'),
                    const Divider(height: 14, color: Color(0xFFE2E8F0)),
                    _summaryRow(
                      'Target Result',
                      isOvertime
                          ? 'WITH OVERTIME (+${otMin.toString().padLeft(2, '0')}:${otSec.toString().padLeft(2, '0')})'
                          : 'WITHIN TARGET',
                      valueColor: isOvertime ? const Color(0xFFD97706) : const Color(0xFF047857),
                      isBold: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A86B),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markTaskCompleted(Map<String, dynamic> task) async {
    final taskId = (task['id'] as num?)?.toInt() ?? 0;
    if (taskId == 0) return;

    final destLat = (task['clinic_lat'] as num?)?.toDouble();
    final destLng = (task['clinic_lng'] as num?)?.toDouble();

    if (destLat == null || destLng == null || destLat == 0.0 || destLng == 0.0) {
      _showNotInClinicDialog();
      return;
    }

    // 1. Get current mobile GPS location using Geolocator
    Position? position;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showNotInClinicDialog();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showNotInClinicDialog();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showNotInClinicDialog();
        return;
      }

      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        return _currentPosition ??
            Position(
              latitude: 0.0,
              longitude: 0.0,
              timestamp: DateTime.now(),
              accuracy: 0.0,
              altitude: 0.0,
              altitudeAccuracy: 0.0,
              heading: 0.0,
              headingAccuracy: 0.0,
              speed: 0.0,
              speedAccuracy: 0.0,
            );
      });
    } catch (_) {
      position = _currentPosition;
    }

    if (position == null || (position.latitude == 0.0 && position.longitude == 0.0)) {
      position = _currentPosition;
    }

    if (position == null || (position.latitude == 0.0 && position.longitude == 0.0)) {
      _showNotInClinicDialog();
      return;
    }

    // 2. Calculate distance between current mobile location & task destination location
    final distanceMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      destLat,
      destLng,
    );

    // 3. Strict 15-meter radius validation (15.0m or less allowed; 15.01m or more blocked)
    if (distanceMeters > AppConfig.destinationRadiusMeters) {
      // Location Invalid -> DO NOT complete task, show popup
      _showNotInClinicDialog();
      return;
    }

    // 4. Location Valid (<= 15.0 meters) -> Check 5-minute destination target timer
    String? overtimeReason;
    final destReachedStr = (task['destination_reached_at'] ?? '').toString().trim();
    final targetDeadlineStr = (task['target_deadline_at'] ?? '').toString().trim();
    DateTime? deadlineDt;
    if (targetDeadlineStr.isNotEmpty) {
      deadlineDt = DateTime.tryParse(targetDeadlineStr);
    } else if (destReachedStr.isNotEmpty) {
      final rDt = DateTime.tryParse(destReachedStr);
      if (rDt != null) {
        deadlineDt = rDt.add(const Duration(seconds: 300));
      }
    }

    final now = DateTime.now();
    if (deadlineDt != null && now.isAfter(deadlineDt)) {
      final otDiff = now.difference(deadlineDt).inSeconds;
      overtimeReason = await _showOvertimeReasonDialog(
        doctorName: (task['doctor_name'] ?? 'Doctor').toString(),
        clinicName: (task['clinic_name'] ?? 'Clinic').toString(),
        reachedTime: destReachedStr,
        overtimeSeconds: otDiff,
      );
      if (overtimeReason == null) {
        // User cancelled overtime reason input
        return;
      }
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final dtStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    final payload = {
      'task_id': taskId,
      'user_id': widget.user.id,
      'sales_rep_name': widget.user.name,
      'status': 'completed',
      'checkout_type': 'MANUAL',
      'checkout_lat': position.latitude,
      'checkout_lng': position.longitude,
      'destination_lat': destLat,
      'destination_lng': destLng,
      'destination_distance_meters': distanceMeters,
      'checkout_date': dateStr,
      'checkout_time': timeStr,
      'checkout_datetime': dtStr,
      'stable_duration_seconds': 0,
      if (overtimeReason != null && overtimeReason.isNotEmpty)
        'overtime_reason': overtimeReason,
    };

    bool completedSuccessfully = false;
    Map<String, dynamic>? completionData;

    for (final base in AppConfig.allHosts) {
      try {
        final res = await http.post(
          Uri.parse('$base/backend/update_task_status.php'),
          headers: AppConfig.headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 6));
        final data = json.decode(res.body);
        if (data['success'] == true) {
          completedSuccessfully = true;
          completionData = data;
          _stopLocationPushTimer();
          break;
        } else if (data['overtime_reason_required'] == true) {
          // Backend requested overtime reason
          final otDiff = (data['overtime_seconds'] as num?)?.toInt() ?? 1;
          final reason = await _showOvertimeReasonDialog(
            doctorName: (task['doctor_name'] ?? 'Doctor').toString(),
            clinicName: (task['clinic_name'] ?? 'Clinic').toString(),
            reachedTime: (data['destination_reached_at'] ?? destReachedStr).toString(),
            overtimeSeconds: otDiff,
          );
          if (reason != null && reason.isNotEmpty) {
            payload['overtime_reason'] = reason;
            final retryRes = await http.post(
              Uri.parse('$base/backend/update_task_status.php'),
              headers: AppConfig.headers,
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 6));
            final retryData = json.decode(retryRes.body);
            if (retryData['success'] == true) {
              completedSuccessfully = true;
              completionData = retryData;
              _stopLocationPushTimer();
              break;
            }
          } else {
            return;
          }
        } else if (data['message'] != null && data['message'].toString().contains("Doctor's Clinic")) {
          _showNotInClinicDialog();
          return;
        }
      } catch (_) {}
    }

    if (completedSuccessfully && mounted) {
      _stopLocationPushTimer();
      _fetchUserTasks();

      final resDestReached = (completionData?['destination_reached_at'] ?? destReachedStr).toString();
      final resCompTime = (completionData?['checked_out_at'] ?? dtStr).toString();
      final resFinalDist = (completionData?['final_distance_meters'] as num?)?.toDouble() ?? distanceMeters;
      final resCompResult = (completionData?['completion_result'] ?? (overtimeReason != null ? 'overtime' : 'within_target')).toString();
      final resOtDuration = (completionData?['overtime_duration_seconds'] as num?)?.toInt() ?? 0;

      _showTaskCompletionSummaryDialog(
        doctorName: (task['doctor_name'] ?? 'Doctor').toString(),
        clinicName: (task['clinic_name'] ?? 'Clinic').toString(),
        destinationReachedAt: resDestReached,
        completedAt: resCompTime,
        finalDistanceMeters: resFinalDist,
        completionResult: resCompResult,
        overtimeDurationSeconds: resOtDuration,
      );
    } else if (!completedSuccessfully && mounted) {
      _showNotInClinicDialog();
    }
  }

  // ── Automatic Checkout: 15.0-meter destination radius for 60 continuous seconds ──

  void _checkAutoCheckoutStability(Position position) {
    if (widget.user.isAdmin) return;

    // Filter out noisy inaccurate readings (> 30m accuracy)
    if (position.accuracy > 30.0) return;

    final now = DateTime.now();
    final pendingTasksToMonitor = <int, LatLng>{};

    for (final mt in _mappedTasks) {
      if (mt.taskId != null && (mt.status.toLowerCase() == 'pending' || mt.status.toLowerCase() == 'in_progress')) {
        pendingTasksToMonitor[mt.taskId!] = mt.destinationLatLng;
      }
    }

    for (final ut in _userTasks) {
      final tid = (ut['id'] as num?)?.toInt();
      final status = (ut['status'] ?? 'pending').toString().toLowerCase();
      final lat = (ut['clinic_lat'] as num?)?.toDouble();
      final lng = (ut['clinic_lng'] as num?)?.toDouble();
      if (tid != null && (status == 'pending' || status == 'in_progress') && lat != null && lng != null) {
        pendingTasksToMonitor.putIfAbsent(tid, () => LatLng(lat, lng));
      }
    }

    for (final entry in pendingTasksToMonitor.entries) {
      final taskId = entry.key;
      final dest = entry.value;
      final dist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        dest.latitude,
        dest.longitude,
      );

      // Strict 15.0m check
      if (dist <= AppConfig.destinationRadiusMeters) {
        // Sales Rep is within 15-meter radius
        if (!_taskProximityEntryTimes.containsKey(taskId)) {
          _taskProximityEntryTimes[taskId] = now;
          debugPrint('[AutoCheckout] Task #$taskId entered 15m radius (${dist.toStringAsFixed(2)}m) at $now');
        } else {
          final elapsed = now.difference(_taskProximityEntryTimes[taskId]!).inSeconds;
          debugPrint('[AutoCheckout] Task #$taskId within 15m (${dist.toStringAsFixed(2)}m) for $elapsed/${AppConfig.autoCheckoutStableSeconds}s');
          if (elapsed >= AppConfig.autoCheckoutStableSeconds) {
            if (!_inFlightAutoCheckouts.contains(taskId)) {
              _inFlightAutoCheckouts.add(taskId);
              _performAutoCheckout(taskId, dest, position, dist);
            }
          }
        }
      } else {
        // Sales Rep moved outside 15-meter radius -> RESET stability timer for this task
        if (_taskProximityEntryTimes.containsKey(taskId)) {
          debugPrint('[AutoCheckout] Task #$taskId moved outside 15m (${dist.toStringAsFixed(2)}m) -> Timer RESET');
          _taskProximityEntryTimes.remove(taskId);
        }
      }
    }
  }

  Future<void> _performAutoCheckout(
    int taskId,
    LatLng destination,
    Position position,
    double distanceMeters,
  ) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);
    final dtStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    // Retrieve clinic name for user confirmation
    String clinicName = 'Destination';
    for (final mt in _mappedTasks) {
      if (mt.taskId == taskId) {
        clinicName = mt.clinicName;
        break;
      }
    }
    if (clinicName == 'Destination') {
      for (final ut in _userTasks) {
        if ((ut['id'] as num?)?.toInt() == taskId) {
          clinicName = (ut['clinic_name'] ?? 'Destination').toString();
          break;
        }
      }
    }

    final payload = {
      'task_id': taskId,
      'user_id': widget.user.id,
      'sales_rep_name': widget.user.name,
      'checkout_lat': position.latitude,
      'checkout_lng': position.longitude,
      'destination_lat': destination.latitude,
      'destination_lng': destination.longitude,
      'destination_distance_meters': distanceMeters,
      'checkout_date': dateStr,
      'checkout_time': timeStr,
      'checkout_datetime': dtStr,
      'checkout_type': 'AUTO',
      'status': 'completed',
      'stable_duration_seconds': 60,
    };

    bool success = false;
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base/backend/update_task_status.php');
        final res = await http
            .post(url, headers: AppConfig.headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 6));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['success'] == true) {
            success = true;
            debugPrint('[AutoCheckout] Task #$taskId auto-checkout recorded on $base: ${data['message']}');
            break;
          }
        }
      } catch (e) {
        debugPrint('[AutoCheckout] Failed on $base: $e');
      }
    }

    if (success) {
      _taskProximityEntryTimes.remove(taskId);
      if (_activeTaskId == taskId) {
        _stopLocationPushTimer();
      }
      if (mounted) {
        setState(() {
          // Update mapped tasks status
          for (final mt in _mappedTasks) {
            if (mt.taskId == taskId) {
              mt.status = 'completed';
            }
          }
          // Update user tasks list
          for (final ut in _userTasks) {
            if ((ut['id'] as num?)?.toInt() == taskId) {
              ut['status'] = 'completed';
              ut['checkout_type'] = 'AUTO';
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto Checked Out: $clinicName\nCompleted after 60 seconds at destination.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFF00A86B),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );

        _fetchUserTasks();
      }
    } else {
      // Allow retry in subsequent 60s window if network fails
      _inFlightAutoCheckouts.remove(taskId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Lifecycle] App resumed on ${defaultTargetPlatform.name}. Syncing active tasks & tracking state.');
      if (!widget.user.isAdmin && mounted) {
        _fetchUserTasks();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _positionStreamSubscription?.cancel();
    _locationStreamFallbackTimer?.cancel();
    _locationPushTimer?.cancel();
    _destinationTickerTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _checkPendingTasks() async {
    // Skip for dev user or admin — admin has no tasks
    if (widget.user.id == 0 || widget.user.isAdmin) return;
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse(
            '$base/backend/get_pending_tasks.php?user_id=${widget.user.id}');
        final response =
            await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final tasks = data['tasks'] as List? ?? [];
          if (tasks.isNotEmpty && mounted) {
            _showPendingTaskDialog(tasks.first);
            return;
          }
        }
      } catch (_) {
        // Silent fail
      }
    }
  }

  void _showPendingTaskDialog(Map<String, dynamic> task) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.pending_actions_rounded,
                color: Color(0xFF00A86B), size: 26),
            SizedBox(width: 10),
            Text('Pending Task',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You have an unfinished task. What would you like to do?',
                style: TextStyle(color: Color(0xFF52796F))),
            const SizedBox(height: 16),
            _pendingInfoRow(
                Icons.local_hospital_rounded, task['doctor_name'] ?? ''),
            const SizedBox(height: 6),
            _pendingInfoRow(
                Icons.business_rounded, task['clinic_name'] ?? ''),
            const SizedBox(height: 6),
            _pendingInfoRow(
                Icons.calendar_today_rounded, task['task_basis'] ?? ''),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showCreateTaskOptionDialog(task);
            },
            child: const Text('Create New Task',
                style: TextStyle(color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Resume pending task — restore all ongoing tasks with this as focus
              final lat = (task['clinic_lat'] as num?)?.toDouble();
              final lng = (task['clinic_lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final focus = MappedTask(
                  taskId: (task['id'] as num?)?.toInt(),
                  doctorName: task['doctor_name'] ?? '',
                  clinicName: task['clinic_name'] ?? '',
                  clinicAddress: task['clinic_address'] ?? '',
                  taskCategory: task['task_category'] ?? '',
                  taskBasis: task['task_basis'] ?? 'Daily',
                  notes: task['notes'] ?? '',
                  status: task['status'] ?? 'pending',
                  destinationLatLng: LatLng(lat, lng),
                );
                setState(() => _currentView = 'map');
                _syncOngoingTasksToMap(focusTask: focus);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A86B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continue Task'),
          ),
        ],
      ),
    );
  }

  void _showCreateTaskOptionDialog(Map<String, dynamic> pendingTask) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.add_task_rounded, color: Color(0xFF00A86B), size: 26),
            SizedBox(width: 10),
            Text('Create Task', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select how you would like to create your new task:',
              style: TextStyle(color: Color(0xFF52796F), fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openTaskScreen(existingTask: pendingTask);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF047857),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.file_copy_rounded, size: 20),
              label: const Text(
                'Create Task from Existing',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openTaskScreen();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00A86B),
                side: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
              label: const Text(
                'Complete New Task',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00A86B)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13))),
      ],
    );
  }

  Future<void> _initLocationService() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Checking permissions...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Location services are disabled. Please enable GPS.';
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Location permissions are denied.';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Location permissions are permanently denied. Please enable them in settings.';
        });
        return;
      }

      setState(() {
        _hasPermission = true;
        _statusMessage = 'Acquiring high-accuracy GPS signal...';
      });

      // 1. Immediately try to use the last known position to populate the UI without waiting
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          setState(() {
            _currentPosition = lastKnown;
            _isLoading = false;
          });
          _mapController.move(LatLng(lastKnown.latitude, lastKnown.longitude), _zoom);
        }
      } catch (_) {}

      // 2. Start continuous live location streaming immediately
      _startContinuousLocationStream();

      // 3. Obtain high-accuracy initial fix with timeout
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );
        if (mounted) {
          _handleLivePositionUpdate(position);
          setState(() {
            _isLoading = false;
            _statusMessage = 'Location acquired successfully';
          });
        }
      } catch (_) {
        if (mounted && _currentPosition == null) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Connecting to GPS stream...';
          });
        }
      }

      // Record Login Check-In for Sales Reps
      if (!widget.user.isAdmin && _currentPosition != null) {
        _recordAttendance('check_in', notes: 'Login Check-In at location');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Error occurred: $e';
        });
      }
    }
  }

  void _startContinuousLocationStream() {
    _positionStreamSubscription?.cancel();

    // Build platform-optimized location settings for continuous live navigation
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // Instant response to every meter of movement
        forceLocationManager: false,
        intervalDuration: const Duration(milliseconds: 1000), // Fast 1-second interval
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    // Listen to continuous high-accuracy location changes with live moving tracking
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) => _handleLivePositionUpdate(position),
      onError: (error) {
        debugPrint('[LocationStream] Error: $error');
      },
    );

    // Dedicated backup GPS polling timer to guarantee continuous position stream updates every 1 second
    _locationStreamFallbackTimer?.cancel();
    _locationStreamFallbackTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 2),
        );
        _handleLivePositionUpdate(pos);
      } catch (_) {}
    });
  }

  void _handleLivePositionUpdate(Position position) {
    if (!mounted) return;

    // Validate GPS readings: ignore invalid/out-of-bounds coordinates
    if (position.latitude == 0.0 && position.longitude == 0.0) {
      return;
    }
    if (position.latitude < -90.0 || position.latitude > 90.0 ||
        position.longitude < -180.0 || position.longitude > 180.0) {
      return;
    }
    // Filter out extreme inaccuracies (> 100m) if a reliable position is already known
    if (_currentPosition != null && position.accuracy > 100.0) {
      return;
    }

    setState(() {
      _currentPosition = position;
      _isLoading = false;
      _hasPermission = true;

      // Live update distances & rankings for all assigned mapped tasks dynamically
      if (_mappedTasks.isNotEmpty) {
        for (final t in _mappedTasks) {
          t.distanceMeters = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            t.destinationLatLng.latitude,
            t.destinationLatLng.longitude,
          );
        }
        _mappedTasks.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
        for (int i = 0; i < _mappedTasks.length; i++) {
          _mappedTasks[i].rank = i + 1;
          _mappedTasks[i].color = _getRankColor(i + 1);
        }

        if (_selectedMappedTask != null) {
          final updatedSelected = _mappedTasks.firstWhere(
            (m) =>
                (m.taskId != null && m.taskId == _selectedMappedTask!.taskId) ||
                (m.clinicName.toLowerCase() == _selectedMappedTask!.clinicName.toLowerCase() &&
                 m.doctorName.toLowerCase() == _selectedMappedTask!.doctorName.toLowerCase()),
            orElse: () => _selectedMappedTask!,
          );
          _destinationLatLng = updatedSelected.destinationLatLng;
          _destinationName = updatedSelected.clinicName;
          _destinationAddress = updatedSelected.clinicAddress;
          _assignedDoctor = updatedSelected.doctorName;
          _taskBasis = updatedSelected.taskBasis;
          _distanceMeters = updatedSelected.distanceMeters;
        } else {
          _destinationLatLng = _mappedTasks.first.destinationLatLng;
          _destinationName = _mappedTasks.first.clinicName;
          _destinationAddress = _mappedTasks.first.clinicAddress;
          _assignedDoctor = _mappedTasks.first.doctorName;
          _taskBasis = _mappedTasks.first.taskBasis;
          _distanceMeters = _mappedTasks.first.distanceMeters;
        }
      } else if (_destinationLatLng != null) {
        _distanceMeters = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          _destinationLatLng!.latitude,
          _destinationLatLng!.longitude,
        );
      }
    });

    // Live heading orientation for marker direction
    if (position.heading > 0) {
      _deviceHeading = position.heading;
    }

    // Dynamic zoom adjustment based on actual distance to destination (Step 2)
    if (_autoFollowUser && (_distanceMeters > 0 || _destinationLatLng != null)) {
      final targetZoom = _calculateDynamicZoom(_distanceMeters);
      // Smoothly adapt zoom level without sudden jumps or micro-oscillations
      if ((targetZoom - _zoom).abs() >= 0.15) {
        _zoom = _zoom + (targetZoom - _zoom) * 0.35;
      }
    }

    // Smoothly move map camera with user when auto-follow is active
    if (_autoFollowUser) {
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        _zoom,
      );
    }

    // Check auto checkout stability only for sales reps
    if (!widget.user.isAdmin) {
      _checkAutoCheckoutStability(position);

      // Immediate push to backend upon entering strict <= 15.0m destination radius for active task
      for (final t in _userTasks) {
        final s = (t['status'] ?? '').toString().toLowerCase();
        if (s == 'in_progress' || s == 'started') {
          final cLat = (t['clinic_lat'] as num?)?.toDouble();
          final cLng = (t['clinic_lng'] as num?)?.toDouble();
          final tid = (t['id'] as num?)?.toInt();
          final reached = t['destination_reached_at'];
          if (tid != null && cLat != null && cLng != null && (reached == null || reached.toString().trim().isEmpty)) {
            final dist = Geolocator.distanceBetween(position.latitude, position.longitude, cLat, cLng);
            if (dist <= AppConfig.destinationRadiusMeters) {
              _pushLocationToDB(position, taskId: tid);
            }
          }
        }
      }
    }

    // Debounced road route re-calculation (only after travelling > 35 meters)
    if (_showMultiRoute && _mappedTasks.isNotEmpty) {
      final lastPos = _lastRouteFetchPosition;
      final shouldRefresh = lastPos == null ||
          Geolocator.distanceBetween(
                lastPos.latitude,
                lastPos.longitude,
                position.latitude,
                position.longitude,
              ) > 35.0;

      if (shouldRefresh && !_isFetchingRoutes) {
        _fetchMultiRoutes(_mappedTasks, shouldFitBounds: false);
      }
    } else if (_showRoute && _destinationLatLng != null) {
      final lastPos = _lastRouteFetchPosition;
      final shouldRefresh = lastPos == null ||
          Geolocator.distanceBetween(
                lastPos.latitude,
                lastPos.longitude,
                position.latitude,
                position.longitude,
              ) > 35.0;

      if (shouldRefresh && !_isFetchingRoutes) {
        _fetchRoute();
      }
    }
  }

  void _reCenter() {
    if (_currentPosition != null) {
      setState(() => _autoFollowUser = true);
      _mapController.move(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        _zoom,
      );
    }
  }

  void _rotateToNorth() {
    _mapController.rotate(0.0);
  }

  // Fit the map so both the rep's current location and the destination
  // are visible with comfortable padding.
  void _fitMapToBoth(double srcLat, double srcLng, double dstLat, double dstLng, {List<LatLng>? routePoints}) {
    try {
      final List<double> allLats = [srcLat, dstLat];
      final List<double> allLngs = [srcLng, dstLng];

      if (routePoints != null && routePoints.isNotEmpty) {
        final mid = routePoints.length ~/ 2;
        allLats.add(routePoints[mid].latitude);
        allLngs.add(routePoints[mid].longitude);
      }

      final minLat = allLats.reduce((a, b) => a < b ? a : b);
      final maxLat = allLats.reduce((a, b) => a > b ? a : b);
      final minLng = allLngs.reduce((a, b) => a < b ? a : b);
      final maxLng = allLngs.reduce((a, b) => a > b ? a : b);

      if ((maxLat - minLat).abs() < 0.0005 && (maxLng - minLng).abs() < 0.0005) {
        _mapController.move(LatLng(minLat, minLng), 15.0);
      } else {
        final bounds = LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        );
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.fromLTRB(48, 100, 48, 240),
          ),
        );
      }
    } catch (_) {
      _mapController.move(LatLng(dstLat, dstLng), 14.0);
    }
  }

  // ── Periodic GPS Location Tracking (~10s interval, only while task is in_progress) ──
  Timer? _locationPushTimer;

  void _startLocationPushTimer(int taskId) {
    _locationPushTimer?.cancel();
    _activeTaskId = taskId;
    // Push initial location immediately
    if (_currentPosition != null && _currentPosition!.latitude != 0.0) {
      _pushLocationToDB(_currentPosition!, taskId: taskId);
    }
    _locationPushTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_activeTaskId == null || widget.user.isAdmin) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
        ).timeout(const Duration(seconds: 5), onTimeout: () => _currentPosition ?? Position(
          latitude: 0.0, longitude: 0.0, timestamp: DateTime.now(),
          accuracy: 0.0, altitude: 0.0, altitudeAccuracy: 0.0,
          heading: 0.0, headingAccuracy: 0.0, speed: 0.0, speedAccuracy: 0.0,
        ));
        if (pos.latitude != 0.0 && pos.longitude != 0.0 && _activeTaskId != null) {
          _pushLocationToDB(pos, taskId: _activeTaskId!);
        }
      } catch (_) {
        if (_currentPosition != null && _currentPosition!.latitude != 0.0 && _activeTaskId != null) {
          _pushLocationToDB(_currentPosition!, taskId: _activeTaskId!);
        }
      }
    });
  }

  void _stopLocationPushTimer() {
    _locationPushTimer?.cancel();
    _locationPushTimer = null;
    _activeTaskId = null;
  }

  Future<void> _pushLocationToDB(Position position, {required int taskId}) async {
    if (position.latitude == 0.0 && position.longitude == 0.0) return;
    final body = jsonEncode({
      'user_id':        widget.user.id,
      'sales_rep_name': widget.user.name,
      'task_id':        taskId,
      'lat':            position.latitude,
      'lng':            position.longitude,
      'accuracy':       position.accuracy,
    });
    for (final base in AppConfig.allHosts) {
      try {
        final res = await http
            .post(
              Uri.parse('$base/backend/push_location.php'),
              headers: AppConfig.headers,
              body: body,
            )
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['success'] == true && mounted) {
            setState(() {
              for (final ut in _userTasks) {
                if ((ut['id'] as num?)?.toInt() == taskId) {
                  if (data['destination_reached_at'] != null) {
                    ut['destination_reached_at'] = data['destination_reached_at'];
                  }
                  if (data['target_deadline_at'] != null) {
                    ut['target_deadline_at'] = data['target_deadline_at'];
                  }
                  if (data['target_duration_seconds'] != null) {
                    ut['target_duration_seconds'] = data['target_duration_seconds'];
                  }
                  if (data['is_inside_destination'] != null) {
                    ut['is_inside_destination'] = data['is_inside_destination'];
                  }
                  if (data['time_inside_destination_seconds'] != null) {
                    ut['time_inside_destination_seconds'] = data['time_inside_destination_seconds'];
                  }
                  if (data['distance_meters'] != null) {
                    ut['destination_distance_meters'] = data['distance_meters'];
                  }
                }
              }
            });
          }
          break;
        }
      } catch (_) {}
    }
  }

  Future<void> _startTask(Map<String, dynamic> task) async {
    final taskId = (task['id'] as num?)?.toInt() ?? 0;
    if (taskId == 0) return;

    // 1. Verify GPS service & permissions
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enable GPS / Location Services on your device to start task.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission is required to start task.'),
              backgroundColor: const Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location permissions are permanently denied. Please enable in App Settings.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    // 2. Fetch REAL GPS coordinates
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      pos = _currentPosition;
    }

    if (pos == null || (pos.latitude == 0.0 && pos.longitude == 0.0)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to get accurate GPS location. Please check your signal and try again.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return;
    }

    // 3. Call update_task_status.php with status = 'in_progress'
    final payload = {
      'task_id': taskId,
      'user_id': widget.user.id,
      'sales_rep_name': widget.user.name,
      'status': 'in_progress',
      'lat': pos.latitude,
      'lng': pos.longitude,
    };

    bool started = false;
    for (final base in AppConfig.allHosts) {
      try {
        final res = await http.post(
          Uri.parse('$base/backend/update_task_status.php'),
          headers: AppConfig.headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 6));
        final data = json.decode(res.body);
        if (data['success'] == true) {
          started = true;
          break;
        }
      } catch (_) {}
    }

    if (started) {
      _startLocationPushTimer(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Task Started! Live GPS tracking active.'),
            backgroundColor: const Color(0xFF00A86B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        _fetchUserTasks();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to start task. Please try again.'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _openTaskScreen({Map<String, dynamic>? existingTask}) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => TaskScreen(
          salesRep: widget.user,
          repLat: _currentPosition?.latitude,
          repLng: _currentPosition?.longitude,
          existingTask: existingTask,
        ),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );

    if (result != null && mounted) {
      final assignedList = result['assignedTasks'] as List?;
      final List<MappedTask> mappedList = [];
      if (assignedList != null && assignedList.isNotEmpty) {
        for (final item in assignedList) {
          final lat = (item['clinicLat'] as num?)?.toDouble() ?? 0.0;
          final lng = (item['clinicLng'] as num?)?.toDouble() ?? 0.0;
          if (lat != 0.0 && lng != 0.0) {
            mappedList.add(MappedTask(
              doctorName: item['doctorName'] ?? '',
              clinicName: item['clinicName'] ?? '',
              clinicAddress: item['clinicAddress'] ?? '',
              taskCategory: item['taskCategory'] ?? '',
              taskBasis: item['taskBasis'] ?? 'Daily',
              notes: item['notes'] ?? '',
              destinationLatLng: LatLng(lat, lng),
            ));
          }
        }
      } else {
        // Legacy single task fallback
        final clinicLat = (result['clinicLat'] as num?)?.toDouble() ?? 0.0;
        final clinicLng = (result['clinicLng'] as num?)?.toDouble() ?? 0.0;
        if (clinicLat != 0.0 && clinicLng != 0.0) {
          mappedList.add(MappedTask(
            doctorName: result['doctorName'] as String? ?? '',
            clinicName: result['clinicName'] as String? ?? '',
            clinicAddress: result['clinicAddress'] as String? ?? '',
            taskCategory: result['taskCategory'] as String? ?? '',
            taskBasis: result['taskBasis'] as String? ?? 'Daily',
            notes: result['notes'] as String? ?? '',
            destinationLatLng: LatLng(clinicLat, clinicLng),
          ));
        }
      }

      setState(() {
        _currentView = 'map';
        _showMultiRoute = true;
      });

      _syncOngoingTasksToMap(newAssignedTasks: mappedList);
      _fetchUserTasks();

      final count = mappedList.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.alt_route_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  count == 1
                      ? '1 Task assigned! Route shown on map.'
                      : '$count Tasks assigned! Comparing all $count routes on map.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF00A86B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _showDashboardBackConfirmationDialog();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: widget.user.isAdmin
            ? null
            : Drawer(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    DrawerHeader(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [_emeraldPrimary, _emeraldDark],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.medical_services_rounded, color: Colors.white, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            widget.user.name,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            widget.user.email,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.dashboard_rounded, color: _emeraldPrimary),
                      title: const Text('Dashboard'),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentView = 'dashboard');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.map_rounded, color: _emeraldPrimary),
                      title: const Text('Live Tracking / Map'),
                      onTap: () {
                        Navigator.pop(context);
                        setState(() => _currentView = 'map');
                        _syncOngoingTasksToMap();
                      },
                    ),
                    // ── Our Products expandable submenu (Step 4: Clean, White text, No White boxes) ──
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2B1D),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1B4332)),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          key: const PageStorageKey('products_tile'),
                          leading: const Icon(Icons.inventory_2_outlined, color: Colors.white),
                          title: const Text(
                            'Our Products',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                          ),
                          trailing: AnimatedRotation(
                            turns: _productsExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                          ),
                          onExpansionChanged: (expanded) {
                            setState(() => _productsExpanded = expanded);
                          },
                          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          children: [
                            _buildDrawerCategoryExpansionTile(
                              categoryName: 'General',
                              categoryKey: 'general',
                              icon: Icons.medication_rounded,
                              color: const Color(0xFF00A86B),
                            ),
                            _buildDrawerCategoryExpansionTile(
                              categoryName: 'Orthopedic',
                              categoryKey: 'orthopedic',
                              icon: Icons.accessibility_new_rounded,
                              color: const Color(0xFF6A1B9A),
                            ),
                            _buildDrawerCategoryExpansionTile(
                              categoryName: 'Gastroenterology',
                              categoryKey: 'gastroenterology',
                              icon: Icons.medical_services_rounded,
                              color: const Color(0xFF2E7D32),
                            ),
                            _buildDrawerCategoryExpansionTile(
                              categoryName: 'Neurology',
                              categoryKey: 'neurology',
                              icon: Icons.psychology_rounded,
                              color: const Color(0xFF1565C0),
                            ),
                            _buildDrawerCategoryExpansionTile(
                              categoryName: 'Gynecology',
                              categoryKey: 'gynecology',
                              icon: Icons.favorite_rounded,
                              color: const Color(0xFFAD1457),
                            ),
                            ListTile(
                              contentPadding: const EdgeInsets.only(left: 32, right: 16),
                              title: const Text(
                                'All Products Catalog',
                                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.white70),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ProductListScreen(categoryName: 'All Products'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.task_alt_rounded, color: _emeraldPrimary),
                      title: const Text('Task'),
                      onTap: () {
                        Navigator.pop(context);
                        _openTaskScreen();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.insights_rounded, color: _emeraldPrimary),
                      title: const Text('My Performance'),
                      onTap: () {
                        Navigator.pop(context);
                        _showSalesRepPerformanceModal(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.settings_rounded, color: _emeraldPrimary),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: _emeraldPrimary),
                      title: const Text('About Us'),
                      onTap: () {
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.shopping_cart_checkout_rounded, color: _emeraldPrimary),
                      title: const Text('Order Now'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => OrderNowScreen(salesRep: widget.user),
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.login_rounded, color: _emeraldPrimary),
                      title: const Text('Check In'),
                      onTap: () async {
                        Navigator.pop(context);
                        await _recordAttendance('check_in', notes: 'Manual Check-In from Drawer');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text('Check-In recorded with current location!'),
                                ],
                              ),
                              backgroundColor: _emeraldPrimary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                      title: const Text('Check Out'),
                      onTap: _showDashboardBackConfirmationDialog,
                    ),
                  ],
                ),
              ),
        body: widget.user.isAdmin
            ? _buildAdminDashboard(context)
            : (_currentView == 'dashboard'
                ? _buildSalesDashboard(context)
                : _buildSalesMapView(context)),
      ),
    );
  }

  Widget _buildSalesMapView(BuildContext context) {
    final currentLatLng = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(0, 0);

    return Stack(
      children: [
        // ── The Map View (Sales Rep Only) ──
        if (_hasPermission && _currentPosition != null)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentLatLng,
              initialZoom: _zoom,
              initialRotation: 0.0,
              minZoom: 3.0,
              maxZoom: 18.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (position, hasGesture) {
                if (hasGesture) {
                  _autoFollowUser = false;
                  if (position.zoom != null) {
                    _zoom = position.zoom!;
                  }
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medsafe.medsafelifescience',
              ),

              // ── Multiple Routes Polylines (Separate selected route or all routes) ──
              if (_showMultiRoute && _mappedTasks.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Outer outline border for contrast
                    for (final task in (_selectedMappedTask != null ? [_selectedMappedTask!] : _mappedTasks))
                      Polyline(
                        points: _getLivePolylinePoints(task, currentLatLng),
                        strokeWidth: _selectedMappedTask != null ? 10.0 : 8.0,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                    // Inner colored stroke
                    for (final task in (_selectedMappedTask != null ? [_selectedMappedTask!] : _mappedTasks))
                      Polyline(
                        points: _getLivePolylinePoints(task, currentLatLng),
                        strokeWidth: _selectedMappedTask != null ? 6.5 : 5.0,
                        color: task.color,
                      ),
                  ],
                )
              else if (_showRoute && _destinationLatLng != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _getLiveSingleRoutePoints(currentLatLng, _destinationLatLng!),
                      strokeWidth: 9.0,
                      color: const Color(0xFF1E3A8A),
                    ),
                    Polyline(
                      points: _getLiveSingleRoutePoints(currentLatLng, _destinationLatLng!),
                      strokeWidth: 5.5,
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),

              // ── Source Marker (Google Maps Navigation Cursor with Live 360° Movement) ──
              MarkerLayer(
                markers: [
                  Marker(
                    point: currentLatLng,
                    width: 90,
                    height: 96,
                    child: Builder(
                      builder: (context) {
                        final effectiveHeading = _getEffectiveHeading(currentLatLng);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // "You (Source)" badge pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B4332),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: const Text(
                                '📍 You (Source)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Google Maps Navigation Cursor Puck with Live 360° Heading & Movement
                            SizedBox(
                              width: 66,
                              height: 66,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Outer pulsing accuracy halo
                                  AnimatedBuilder(
                                    animation: _pulseAnimation,
                                    builder: (context, child) {
                                      return Container(
                                        width: _pulseAnimation.value * 1.5,
                                        height: _pulseAnimation.value * 1.5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _emeraldPrimary.withValues(
                                            alpha: (0.40 - (_pulseController.value * 0.35)).clamp(0.0, 1.0),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  // Live 360° Rotating Navigation Cone Beam & Cursor Arrow
                                  Transform.rotate(
                                    angle: (effectiveHeading * (math.pi / 180.0)),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Forward Navigation Beam Cone (Google Maps style)
                                        CustomPaint(
                                          size: const Size(66, 66),
                                          painter: _GoogleMapsHeadingBeamPainter(
                                            color: _emeraldPrimary,
                                          ),
                                        ),
                                        // Outer Google Maps White Bezel Ring
                                        Container(
                                          width: 32,
                                          height: 32,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black38,
                                                blurRadius: 6,
                                                spreadRadius: 0.5,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Inner Vibrant Navigation Core with 3D Arrow Cursor
                                        Container(
                                          width: 25,
                                          height: 25,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Color(0xFF00C853),
                                                Color(0xFF047857),
                                              ],
                                            ),
                                          ),
                                          child: Center(
                                            child: Transform.translate(
                                              offset: const Offset(0, -1),
                                              child: const Icon(
                                                Icons.navigation_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),

              // ── Destination Markers (Separate Selected Task Destination or All Tasks) ──
              if (_showMultiRoute && _mappedTasks.isNotEmpty)
                MarkerLayer(
                  markers: (_selectedMappedTask != null ? [_selectedMappedTask!] : _mappedTasks).map((task) {
                    final isNearest = task.rank == 1;
                    final isSelected = _selectedMappedTask == task;
                    return Marker(
                      point: task.destinationLatLng,
                      width: isSelected || isNearest ? 100 : 80,
                      height: isSelected || isNearest ? 104 : 84,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_selectedMappedTask == task) {
                              _selectedMappedTask = null;
                              _fitMapToAllMappedTasks(_mappedTasks);
                            } else {
                              _selectedMappedTask = task;
                              _fitMapToBoth(
                                currentLatLng.latitude,
                                currentLatLng.longitude,
                                task.destinationLatLng.latitude,
                                task.destinationLatLng.longitude,
                                routePoints: task.routePoints,
                              );
                            }
                          });
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Rank & Distance badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: task.color,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white,
                                  width: isNearest || isSelected ? 2 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: task.color.withValues(alpha: 0.45),
                                    blurRadius: isNearest || isSelected ? 8 : 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isNearest) ...[
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isNearest ? 'NEAREST • ${task.formattedDistance}' : '${task.rankLabel} • ${task.formattedDistance}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Clinic Name bubble
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B4332).withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                task.clinicName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.location_on_rounded,
                              color: task.color,
                              size: isSelected ? 40 : (isNearest ? 36 : 30),
                              shadows: const [
                                Shadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                )
              else if (_showRoute && _destinationLatLng != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _destinationLatLng!,
                      width: 60,
                      height: 64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF1B4332), borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              _destinationName,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 34),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

        if (_isLoading)
          Container(
            color: Colors.white,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: _emeraldPrimary),
                  const SizedBox(height: 16),
                  Text(_statusMessage, style: const TextStyle(color: _darkSubtext, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),

        // ── Top Bar with Menu & Dashboard Switcher (Sales Rep Only) ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white, width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: _emeraldPrimary, shape: BoxShape.circle),
                  child: const Icon(Icons.medical_services_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.user.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.dashboard_rounded, color: _emeraldPrimary),
                  tooltip: 'Dashboard View',
                  onPressed: () => setState(() => _currentView = 'dashboard'),
                ),
                IconButton(
                  icon: const Icon(Icons.menu, color: _darkText),
                  tooltip: 'Menu',
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ],
            ),
          ),
        ),

        // ── North-Up Indicator & Reset Controller (Top-Right) ──
        Positioned(
          top: MediaQuery.of(context).padding.top + 72,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compass Rose Button (Resets/Locks to North)
              GestureDetector(
                onTap: _rotateToNorth,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.0,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Red North needle
                              CustomPaint(
                                size: const Size(10, 14),
                                painter: _CompassNeedlePainter(const Color(0xFFEF4444), isNorth: true),
                              ),
                              // Gray South needle
                              CustomPaint(
                                size: const Size(10, 14),
                                painter: _CompassNeedlePainter(const Color(0xFF94A3B8), isNorth: false),
                              ),
                            ],
                          ),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              // Fixed North badge
              GestureDetector(
                onTap: _rotateToNorth,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.explore_rounded,
                        size: 11,
                        color: Color(0xFF047857),
                      ),
                      SizedBox(width: 2),
                      Text(
                        '0° N',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 15-Meter Destination Elapsed Timer (MM:SS) ──
              if (_activeTaskDestinationElapsedSeconds != null) ...[
                Builder(
                  builder: (context) {
                    final elapsed = _activeTaskDestinationElapsedSeconds!;
                    final isOvertime = elapsed > 300;
                    final borderColor = isOvertime ? const Color(0xFFDC2626) : const Color(0xFF00A86B);
                    final shadowColor = isOvertime
                        ? const Color(0xFFDC2626).withValues(alpha: 0.25)
                        : const Color(0xFF00A86B).withValues(alpha: 0.20);
                    final iconColor = isOvertime ? const Color(0xFFDC2626) : const Color(0xFF047857);
                    final badgeText = isOvertime ? '15M • OVERTIME' : '15M • TARGET';

                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOvertime ? Icons.timer_off_rounded : Icons.timer_rounded,
                                size: 12,
                                color: iconColor,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                badgeText,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                  color: iconColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatElapsedMMSS(elapsed),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: isOvertime ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
                              fontFeatures: const [ui.FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),

        // ── Multi-Route Comparison Panel (3 Tasks) or Single Route Banner ──
        if (_showMultiRoute && _mappedTasks.isNotEmpty)
          Positioned(
            bottom: 20,
            left: 14,
            right: 14,
            child: _buildRouteComparisonPanel(),
          )
        else if (_showRoute && _destinationLatLng != null)
          Positioned(
            bottom: 90,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD1FAE5), width: 1.5),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE65100).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.directions_rounded, color: Color(0xFFE65100), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route to $_destinationName',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1B4332)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '$_taskBasis Task • Dr. $_assignedDoctor • ${(_distanceMeters / 1000).toStringAsFixed(1)} km${_destinationAddress.isNotEmpty ? ' • $_destinationAddress' : ''}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() { _showRoute = false; _destinationLatLng = null; });
                      _stopLocationPushTimer();
                    },
                    child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 20),
                  ),
                ],
              ),
            ),
          ),

        // ── Floating Action Buttons (Accessible in normal & multi-route mode) ──
        if (_currentPosition != null)
          Positioned(
            bottom: (_showMultiRoute && _mappedTasks.isNotEmpty) ? 225 : 24,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'task_fab',
                  onPressed: _openTaskScreen,
                  backgroundColor: const Color(0xFF1B4332),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.task_alt_rounded),
                ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'recenter_fab',
                  onPressed: _reCenter,
                  backgroundColor: _autoFollowUser ? _emeraldPrimary : const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  tooltip: _autoFollowUser ? 'Tracking your location' : 'Recenter / Follow my location',
                  child: Icon(_autoFollowUser ? Icons.my_location_rounded : Icons.location_searching_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRouteComparisonPanel() {
    final nearestTask = _mappedTasks.firstWhere((t) => t.rank == 1, orElse: () => _mappedTasks.first);
    final count = _mappedTasks.length;
    final isSelectedMode = _selectedMappedTask != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelectedMode ? _selectedMappedTask!.color.withValues(alpha: 0.4) : const Color(0xFFD1FAE5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isSelectedMode
                        ? [_selectedMappedTask!.color, _selectedMappedTask!.color.withValues(alpha: 0.8)]
                        : const [Color(0xFF00A86B), Color(0xFF047857)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSelectedMode ? Icons.navigation_rounded : Icons.alt_route_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isSelectedMode
                                ? _selectedMappedTask!.clinicName
                                : (count == 1 ? '1 Task Route' : '$count Tasks Route Comparison'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF1B4332)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelectedMode
                                ? _selectedMappedTask!.color.withValues(alpha: 0.15)
                                : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isSelectedMode
                                ? _selectedMappedTask!.formattedDistance
                                : 'Nearest: ${nearestTask.formattedDistance}',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: isSelectedMode ? _selectedMappedTask!.color : const Color(0xFF047857),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      isSelectedMode
                          ? 'Dr. ${_selectedMappedTask!.doctorName}${_selectedMappedTask!.taskCategory.isNotEmpty ? ' • ${_selectedMappedTask!.taskCategory}' : ''}'
                          : 'Source → Destinations (Sorted Nearest to Farthest)',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF52796F), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Fit All Routes / Show All button
              GestureDetector(
                onTap: () {
                  setState(() => _selectedMappedTask = null);
                  _fitMapToAllMappedTasks(_mappedTasks);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: !isSelectedMode ? const Color(0xFFD1FAE5) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !isSelectedMode ? const Color(0xFF047857) : const Color(0xFFD1FAE5),
                      width: !isSelectedMode ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.zoom_out_map_rounded,
                        size: 12,
                        color: !isSelectedMode ? const Color(0xFF047857) : const Color(0xFF00A86B),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        count == 1 ? 'Fit Route' : 'All $count Routes',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: !isSelectedMode ? const Color(0xFF047857) : const Color(0xFF00A86B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showMultiRoute = false;
                    _showRoute = false;
                    _destinationLatLng = null;
                    _selectedMappedTask = null;
                  });
                  _stopLocationPushTimer();
                },
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 16),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Horizontal Comparison Cards ──
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _mappedTasks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final task = _mappedTasks[index];
                final isNearest = task.rank == 1;
                final isSelected = _selectedMappedTask == task;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_selectedMappedTask == task) {
                        _selectedMappedTask = null;
                        _fitMapToAllMappedTasks(_mappedTasks);
                      } else {
                        _selectedMappedTask = task;
                        if (_currentPosition != null) {
                          _fitMapToBoth(
                            _currentPosition!.latitude,
                            _currentPosition!.longitude,
                            task.destinationLatLng.latitude,
                            task.destinationLatLng.longitude,
                            routePoints: task.routePoints,
                          );
                        } else {
                          _mapController.move(task.destinationLatLng, 15.0);
                        }
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: count <= 2 ? 210 : 180,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? task.color.withValues(alpha: 0.14)
                          : (isNearest ? const Color(0xFFF0FDF4) : Colors.white),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? task.color
                            : (isNearest ? const Color(0xFF00A86B) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 2.0 : (isNearest ? 1.8 : 1.0),
                      ),
                      boxShadow: isSelected || isNearest
                          ? [
                              BoxShadow(
                                color: (isSelected ? task.color : const Color(0xFF00A86B)).withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Top row: Rank badge + Distance
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: task.color,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isNearest) ...[
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isNearest ? '#1 NEAREST' : task.rankLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              task.formattedDistance,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: task.color,
                              ),
                            ),
                          ],
                        ),
                        // Clinic & Doctor
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.clinicName,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B4332),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Dr. ${task.doctorName}',
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        // Category tag or status
                        Row(
                          children: [
                            if (task.taskCategory.isNotEmpty)
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.white.withValues(alpha: 0.8) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    task.taskCategory,
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      color: isSelected ? task.color : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                              size: 14,
                              color: task.color,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerCategoryExpansionTile({
    required String categoryName,
    required String categoryKey,
    required IconData icon,
    required Color color,
  }) {
    final products = ProductData.getProductsByCategory(categoryKey);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('cat_$categoryKey'),
        tilePadding: const EdgeInsets.only(left: 20, right: 16),
        childrenPadding: const EdgeInsets.only(left: 24, right: 16, bottom: 8),
        title: Text(
          categoryName,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${products.length}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.white70),
          ],
        ),
        children: [
          ...products.map((product) => InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(product: product),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (product.genericName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            product.genericName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (product.packSize.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      product.packSize,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFA7F3D0),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white54),
                ],
              ),
            ),
          )),
          InkWell(
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductListScreen(categoryName: categoryName),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(top: 6, bottom: 4),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View All $categoryName Products',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesDashboard(BuildContext context) {
    final filteredTasks = _dateFilteredUserTasks;
    final ongoingTasks = filteredTasks.where((t) {
      final s = (t['status'] ?? 'pending').toString().toLowerCase();
      return s == 'pending' || s == 'in_progress' || s == 'started';
    }).toList();
    final completedTasks = filteredTasks.where((t) => (t['status'] ?? '') == 'completed').toList();

    return Container(
      color: const Color(0xFFF3FAF5),
      child: SafeArea(
        child: Column(
          children: [
            // ── Top Header Bar with Step 1 Back Button ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showDashboardBackConfirmationDialog,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _emeraldDark),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFD1FAE5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: _emeraldPrimary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${widget.user.name}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'Sales Representative Dashboard',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _emeraldDark),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openTaskScreen(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Assign Task', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.menu, color: _darkText),
                    tooltip: 'Menu',
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                ],
              ),
            ),

            // ── Segment Switcher (Dashboard vs Map) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD1FAE5)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _currentView = 'dashboard'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _currentView == 'dashboard' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dashboard_rounded, size: 18, color: _currentView == 'dashboard' ? Colors.white : _darkSubtext),
                              const SizedBox(width: 6),
                              Text('Dashboard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _currentView == 'dashboard' ? Colors.white : _darkSubtext)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentView = 'map';
                            _autoFollowUser = true;
                          });
                          _startContinuousLocationStream();
                          _syncOngoingTasksToMap();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _currentView == 'map' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.map_rounded, size: 18, color: _currentView == 'map' ? Colors.white : _darkSubtext),
                              const SizedBox(width: 6),
                              Text('Live Map', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _currentView == 'map' ? Colors.white : _darkSubtext)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Main Dashboard Scroll Content ──
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchUserTasks,
                color: _emeraldPrimary,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── 1. Watch Out Task Status Cards with Date Filter ──
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Task Completion',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText),
                            ),
                          ),
                          // Date filter selector
                          GestureDetector(
                            onTap: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedCompletionDate ?? now,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: _emeraldPrimary,
                                        onPrimary: Colors.white,
                                        onSurface: _darkText,
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedCompletionDate = picked;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _selectedCompletionDate != null ? const Color(0xFFD1FAE5) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _selectedCompletionDate != null ? _emeraldPrimary : const Color(0xFFCBD5E1),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 14,
                                    color: _selectedCompletionDate != null ? _emeraldDark : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _selectedCompletionDate != null
                                        ? DateFormat('dd-MM-yyyy').format(_selectedCompletionDate!)
                                        : 'Date: All ▼',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedCompletionDate != null ? _emeraldDark : const Color(0xFF334155),
                                    ),
                                  ),
                                  if (_selectedCompletionDate != null) ...[
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedCompletionDate = null;
                                        });
                                      },
                                      child: const Icon(Icons.close_rounded, size: 14, color: _emeraldDark),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _buildStatusMetricCard('Ongoing', '${ongoingTasks.length}', Icons.pending_actions_rounded, const Color(0xFFE65100), const Color(0xFFFFF3E0))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildStatusMetricCard('Completed', '${completedTasks.length}', Icons.check_circle_rounded, const Color(0xFF00A86B), const Color(0xFFE8F5E9))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildStatusMetricCard('Total Tasks', '${filteredTasks.length}', Icons.assignment_rounded, const Color(0xFF0284C7), const Color(0xFFE0F2FE))),
                        ],
                      ),
                      _buildSalesRepPerformanceCard(filteredTasks),

                      const SizedBox(height: 24),

                      // ── 2. Tasks Currently Going (Ongoing Tasks) ──
                      Row(
                        children: [
                          const Icon(Icons.directions_run_rounded, color: Color(0xFFE65100), size: 20),
                          const SizedBox(width: 6),
                          const Text('Tasks Currently Going', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                          const Spacer(),
                          if (ongoingTasks.isNotEmpty) ...[
                            ElevatedButton.icon(
                              onPressed: () {
                                final List<MappedTask> tasksToCompare = [];
                                for (final t in ongoingTasks) {
                                  final lat = (t['clinic_lat'] as num?)?.toDouble();
                                  final lng = (t['clinic_lng'] as num?)?.toDouble();
                                  if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
                                    tasksToCompare.add(MappedTask(
                                      taskId: (t['id'] as num?)?.toInt(),
                                      doctorName: t['doctor_name'] ?? '',
                                      clinicName: t['clinic_name'] ?? '',
                                      clinicAddress: t['clinic_address'] ?? '',
                                      taskCategory: t['task_category'] ?? '',
                                      taskBasis: t['task_basis'] ?? 'Daily',
                                      notes: t['notes'] ?? '',
                                      status: t['status'] ?? 'pending',
                                      destinationLatLng: LatLng(lat, lng),
                                    ));
                                  }
                                }
                                if (tasksToCompare.isNotEmpty) {
                                  setState(() {
                                    _currentView = 'map';
                                    _autoFollowUser = true;
                                  });
                                  _startContinuousLocationStream();
                                  _fetchMultiRoutes(tasksToCompare);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A86B),
                                foregroundColor: Colors.white,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.alt_route_rounded, size: 15),
                              label: Text(
                                ongoingTasks.length == 1 ? 'View Route' : 'Compare All (${ongoingTasks.length})',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text('${ongoingTasks.length} Pending', style: const TextStyle(fontSize: 12, color: Color(0xFFE65100), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (_loadingUserTasks)
                        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: _emeraldPrimary)))
                      else if (ongoingTasks.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: Column(
                            children: [
                              const Icon(Icons.task_alt_rounded, size: 36, color: Color(0xFF94A3B8)),
                              const SizedBox(height: 8),
                              Text(
                                _userTasks.isEmpty ? 'Could not load tasks' : 'No ongoing tasks for this date',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _userTasks.isEmpty
                                    ? 'Pull down to refresh or tap Retry below.'
                                    : 'Click "Assign Task" above to add new visit assignments.',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                textAlign: TextAlign.center,
                              ),
                              if (_userTasks.isEmpty) ...[
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _fetchUserTasks,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _emeraldPrimary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  ),
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Column(
                          children: ongoingTasks.map((task) => _buildOngoingTaskCard(task)).toList(),
                        ),

                      const SizedBox(height: 24),

                      // ── 3. Tasks Done (Completed Tasks) ──
                      Row(
                        children: [
                          const Icon(Icons.task_alt_rounded, color: Color(0xFF00A86B), size: 20),
                          const SizedBox(width: 6),
                          const Text('Tasks Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                          const Spacer(),
                          Text('${completedTasks.length} Completed', style: const TextStyle(fontSize: 12, color: Color(0xFF00A86B), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (completedTasks.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                          child: const Center(
                            child: Text('No completed tasks for this date.', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ),
                        )
                      else
                        Column(
                          children: completedTasks.map((task) => _buildCompletedTaskCard(task)).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDeadlineDisplay(dynamic rawDeadline) {
    if (rawDeadline == null) return '';
    final str = rawDeadline.toString().trim();
    if (str.isEmpty || str == 'null') return '';
    try {
      final dt = DateTime.parse(str.replaceAll(' ', 'T'));
      return DateFormat('dd-MM-yyyy hh:mm a').format(dt);
    } catch (_) {
      return str;
    }
  }

  Widget _buildSalesRepPerformanceCard(List<Map<String, dynamic>> tasks) {
    int completed = 0;
    int greenCount = 0;
    int redCount = 0;
    int overdueCount = 0;
    int totalPoints = 0;

    for (final t in tasks) {
      final status = (t['status'] ?? 'pending').toString().toLowerCase();
      final color = (t['color_category'] ?? '').toString().toUpperCase();
      final perfStatus = (t['performance_status'] ?? '').toString().toUpperCase();
      final pts = (t['points_earned'] as num?)?.toInt() ?? 0;
      totalPoints += pts;

      if (status == 'completed') {
        completed++;
        if (color == 'GREEN' || perfStatus.contains('ON TIME') || pts > 0) {
          greenCount++;
        } else {
          redCount++;
        }
      } else {
        if (perfStatus == 'OVERDUE' || color == 'RED') {
          overdueCount++;
        }
      }
    }

    final int onTimePct = completed > 0 ? ((greenCount / completed) * 100).round() : 100;
    final int score = (100 + (greenCount * 10) - (redCount * 5) - (overdueCount * 5)).clamp(0, 100);

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3D2E), Color(0xFF1B4332)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A86B).withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.insights_rounded, color: Color(0xFF4EFA8B), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Performance & Points',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Real-time metrics from assigned tasks',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFFB7E4C7)),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showSalesRepPerformanceModal(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Scorecard',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 14),
          Row(
            children: [
              // Score / 100
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0),
                    ),
                    const SizedBox(height: 3),
                    const Text('SCORE / 100', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF95D5B2))),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: Colors.white24),
              // Points
              Expanded(
                child: Column(
                  children: [
                    Text(
                      totalPoints >= 0 ? '+$totalPoints' : '$totalPoints',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: totalPoints >= 0 ? const Color(0xFF4EFA8B) : const Color(0xFFFF6B6B),
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text('POINTS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF95D5B2))),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: Colors.white24),
              // On-Time %
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '$onTimePct%',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0),
                    ),
                    const SizedBox(height: 3),
                    const Text('ON-TIME', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF95D5B2))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Badges row: Green on time, Red late, Overdue
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A86B).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4EFA8B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF4EFA8B)),
                      const SizedBox(width: 5),
                      Text(
                        '$greenCount On Time (+10)',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cancel_rounded, size: 12, color: Color(0xFFFF6B6B)),
                      const SizedBox(width: 5),
                      Text(
                        '$redCount Late (-5)',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              if (overdueCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF87171)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFFCA5A5)),
                      const SizedBox(width: 4),
                      Text(
                        '$overdueCount Overdue',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showSalesRepPerformanceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            int completed = 0;
            int greenCount = 0;
            int redCount = 0;
            int overdueCount = 0;
            int totalPoints = 0;

            for (final t in _userTasks) {
              final status = (t['status'] ?? 'pending').toString().toLowerCase();
              final color = (t['color_category'] ?? '').toString().toUpperCase();
              final perfStatus = (t['performance_status'] ?? '').toString().toUpperCase();
              final pts = (t['points_earned'] as num?)?.toInt() ?? 0;
              totalPoints += pts;

              if (status == 'completed') {
                completed++;
                if (color == 'GREEN' || perfStatus.contains('ON TIME') || pts > 0) {
                  greenCount++;
                } else {
                  redCount++;
                }
              } else {
                if (perfStatus == 'OVERDUE' || color == 'RED') {
                  overdueCount++;
                }
              }
            }

            final int onTimePct = completed > 0 ? ((greenCount / completed) * 100).round() : 100;
            final int score = (100 + (greenCount * 10) - (redCount * 5) - (overdueCount * 5)).clamp(0, 100);

            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.insights_rounded, color: Color(0xFF00A86B), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${widget.user.name} - Performance Scorecard',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                              ),
                              const Text('Evaluation: +10 pts on time • -5 pts late', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Summary Hero Card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF004D40), Color(0xFF00796B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Column(
                                    children: [
                                      Text('$score', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
                                      const Text('Score / 100', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB2DFDB))),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text(
                                        totalPoints >= 0 ? '+$totalPoints' : '$totalPoints',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          color: totalPoints >= 0 ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80),
                                        ),
                                      ),
                                      const Text('Total Points', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB2DFDB))),
                                    ],
                                  ),
                                  Column(
                                    children: [
                                      Text('$onTimePct%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
                                      const Text('On-Time %', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB2DFDB))),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white24, height: 1),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  Text('Total: ${_userTasks.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                  Text('On Time: $greenCount', style: const TextStyle(color: Color(0xFF69F0AE), fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text('Late: $redCount', style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text('Overdue: $overdueCount', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text('Task Evaluations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                        const SizedBox(height: 10),
                        if (_userTasks.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text('No task records found.', style: TextStyle(color: Color(0xFF94A3B8))),
                            ),
                          )
                        else
                          ..._userTasks.map((task) {
                            final status = (task['status'] ?? 'pending').toString().toLowerCase();
                            final isDone = status == 'completed';
                            final perfStatus = (task['performance_status'] ?? (isDone ? 'GREAT / ON TIME' : 'PENDING')).toString().toUpperCase();
                            final colorCat = (task['color_category'] ?? (isDone ? 'GREEN' : 'PENDING')).toString().toUpperCase();
                            final isGreen = colorCat == 'GREEN' || perfStatus.contains('ON TIME');
                            final pts = (task['points_earned'] as num?)?.toInt() ?? (isDone ? (isGreen ? 10 : -5) : 0);
                            final deadlineStr = _formatDeadlineDisplay(task['deadline_date_time'] ?? task['deadline']);
                            final duration = (task['total_duration'] ?? '').toString().trim();
                            final lateBy = (task['late_by'] ?? '').toString().trim();
                            final doctor = task['doctor_name'] ?? 'N/A';
                            final clinic = task['clinic_name'] ?? 'N/A';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isGreen
                                      ? const Color(0xFFA7F3D0)
                                      : (perfStatus == 'OVERDUE' || colorCat == 'RED' ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Dr. $doctor • $clinic',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isGreen
                                              ? const Color(0xFFE8F5E9)
                                              : (perfStatus == 'OVERDUE' || colorCat == 'RED' ? const Color(0xFFFFEBEE) : const Color(0xFFF1F5F9)),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          pts != 0 ? (pts > 0 ? '+$pts pts' : '$pts pts') : '0 pts',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: isGreen ? const Color(0xFF00A86B) : (pts < 0 ? const Color(0xFFD32F2F) : const Color(0xFF64748B)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isGreen
                                              ? const Color(0xFFE8F5E9)
                                              : (perfStatus == 'OVERDUE' ? const Color(0xFFFFEBEE) : const Color(0xFFFFF3E0)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          perfStatus,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isGreen
                                                ? const Color(0xFF00A86B)
                                                : (perfStatus == 'OVERDUE' ? const Color(0xFFD32F2F) : const Color(0xFFE65100)),
                                          ),
                                        ),
                                      ),
                                      if (deadlineStr.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text('Deadline: $deadlineStr', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                      ],
                                    ],
                                  ),
                                  if (duration.isNotEmpty || lateBy.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (duration.isNotEmpty)
                                          Text('Duration: $duration', style: const TextStyle(fontSize: 10.5, color: Color(0xFF0284C7), fontWeight: FontWeight.w500)),
                                        if (duration.isNotEmpty && lateBy.isNotEmpty)
                                          const Text(' • ', style: TextStyle(color: Color(0xFF94A3B8))),
                                        if (lateBy.isNotEmpty)
                                          Text('Late by: $lateBy', style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusMetricCard(String title, String count, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _darkSubtext), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildDestinationMonitoringCard(Map<String, dynamic> task, double? distanceMeters, bool isInProgress) {
    final isWithin15m = distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters;
    final destReachedStr = (task['destination_reached_at'] ?? '').toString().trim();
    final insideSec = (task['time_inside_destination_seconds'] as num?)?.toInt() ?? 0;

    DateTime? reachedDt;
    if (destReachedStr.isNotEmpty) {
      reachedDt = DateTime.tryParse(destReachedStr);
    }

    final now = DateTime.now();
    final bool hasReached = reachedDt != null;
    final int totalElapsedSeconds = hasReached ? math.max(0, now.difference(reachedDt).inSeconds).toInt() : 0;
    final bool isAtTarget = hasReached && totalElapsedSeconds == 300;
    final bool isOvertime = hasReached && totalElapsedSeconds > 300;
    final int overtimeSeconds = isOvertime ? (totalElapsedSeconds - 300) : 0;

    final elapsedMMSS = _formatElapsedMMSS(totalElapsedSeconds);
    final overtimeMMSS = _formatElapsedMMSS(overtimeSeconds);
    final inMin = insideSec ~/ 60;
    final inSec = insideSec % 60;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWithin15m
            ? (isOvertime ? const Color(0xFFFEF2F2) : const Color(0xFFF0FDF4))
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isWithin15m
              ? (isOvertime ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0))
              : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isWithin15m ? Icons.check_circle_rounded : Icons.radar_rounded,
                size: 16,
                color: isWithin15m ? (isOvertime ? const Color(0xFFDC2626) : const Color(0xFF047857)) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                'Destination Monitoring (15m)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isWithin15m ? (isOvertime ? const Color(0xFFDC2626) : const Color(0xFF047857)) : const Color(0xFF334155),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isWithin15m ? (isOvertime ? const Color(0xFFFEE2E2) : const Color(0xFFD1FAE5)) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isWithin15m ? 'WITHIN 15M' : 'OUTSIDE 15M',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: isWithin15m ? (isOvertime ? const Color(0xFFDC2626) : const Color(0xFF047857)) : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          if (isInProgress) ...[
            const SizedBox(height: 8),
            if (!hasReached)
              Row(
                children: const [
                  Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Text(
                    '5-Min Target: Awaiting entry within 15 meters',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isOvertime ? Icons.timer_off_rounded : Icons.timer_rounded,
                        size: 14,
                        color: isOvertime ? const Color(0xFFDC2626) : (isAtTarget ? const Color(0xFF0284C7) : const Color(0xFF047857)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Destination Timer: $elapsedMMSS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: isOvertime ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
                          fontFeatures: const [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOvertime
                              ? const Color(0xFFFEE2E2)
                              : (isAtTarget ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOvertime ? 'OVERTIME' : (isAtTarget ? 'TARGET REACHED' : 'TARGET ACTIVE'),
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isOvertime
                                ? const Color(0xFFDC2626)
                                : (isAtTarget ? const Color(0xFF0284C7) : const Color(0xFF047857)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Target: 05:00',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                      ),
                      if (isOvertime)
                        Text(
                          'Overtime: +$overtimeMMSS',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                        ),
                    ],
                  ),
                  if (insideSec > 0) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Time Inside Destination: ${inMin.toString().padLeft(2, '0')}:${inSec.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOngoingTaskCard(Map<String, dynamic> task) {
    final doctor = task['doctor_name'] ?? 'N/A';
    final clinic = task['clinic_name'] ?? 'N/A';
    final basis  = task['task_basis']  ?? 'Daily';
    final category = task['task_category'] ?? '';
    final address  = task['clinic_address'] ?? '';
    final taskId   = (task['id'] as num?)?.toInt() ?? 0;
    final lat      = (task['clinic_lat'] as num?)?.toDouble();
    final lng      = (task['clinic_lng'] as num?)?.toDouble();
    final taskStatus = (task['status'] ?? 'pending').toString().toLowerCase();
    final isInProgress = taskStatus == 'in_progress' || taskStatus == 'started';

    final deadlineStr = _formatDeadlineDisplay(task['deadline_date_time'] ?? task['deadline']);
    final perfStatus = (task['performance_status'] ?? '').toString().toUpperCase();
    final isOverdue = perfStatus == 'OVERDUE';
    final lateBy = (task['late_by'] ?? '').toString().trim();

    // Calculate real-time Source (GPS) to Destination distance in meters
    double? distanceMeters;
    if (_currentPosition != null && lat != null && lng != null && lat != 0.0 && lng != 0.0) {
      distanceMeters = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        lat,
        lng,
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isOverdue
              ? const Color(0xFFFCA5A5)
              : (isInProgress ? const Color(0xFF86EFAC) : const Color(0xFFFFD8A8)),
          width: isOverdue ? 1.5 : (isInProgress ? 1.4 : 1.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isInProgress ? const Color(0xFF00A86B).withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    const Icon(Icons.timelapse_rounded, size: 14, color: Color(0xFFE65100)),
                    const SizedBox(width: 4),
                    Text('$basis Task', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                  ],
                ),
              ),
              if (category.toString().isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                  child: Text(category.toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                ),
              ],
              const SizedBox(width: 8),
              // In-Progress / Pending Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isInProgress ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isInProgress ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isInProgress ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isInProgress ? 'In Progress' : 'Pending',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isInProgress ? const Color(0xFF15803D) : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // ── Live Source → Destination Distance in Meters (Refreshes every 1 sec) ──
              if (lat != null && lng != null && lat != 0.0 && lng != 0.0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                          ? const Color(0xFF00A86B)
                          : const Color(0xFF3B82F6),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                                ? const Color(0xFF00A86B)
                                : const Color(0xFF3B82F6))
                            .withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                            ? Icons.check_circle_rounded
                            : Icons.near_me_rounded,
                        size: 13,
                        color: distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                            ? const Color(0xFF047857)
                            : const Color(0xFF1D4ED8),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        distanceMeters != null
                            ? (distanceMeters < 1000
                                ? '${distanceMeters.toStringAsFixed(0)} m'
                                : '${(distanceMeters / 1000).toStringAsFixed(2)} km (${distanceMeters.toStringAsFixed(0)} m)')
                            : 'Locating...',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: distanceMeters != null && distanceMeters <= AppConfig.destinationRadiusMeters
                              ? const Color(0xFF047857)
                              : const Color(0xFF1D4ED8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 16, color: _emeraldPrimary),
              const SizedBox(width: 8),
              Text('Doctor: $doctor', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _darkText)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_city_rounded, size: 16, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Expanded(child: Text('Clinic: $clinic', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _darkSubtext))),
            ],
          ),
          if (address.toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(address.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ),
          ],

          // Deadline & Overdue Alert Row
          if (deadlineStr.isNotEmpty || isOverdue) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isOverdue ? const Color(0xFFFEE2E8) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isOverdue ? const Color(0xFFFCA5A5) : const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  Icon(
                    isOverdue ? Icons.alarm_off_rounded : Icons.schedule_rounded,
                    size: 14,
                    color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFF047857),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isOverdue
                          ? 'OVERDUE ${lateBy.isNotEmpty ? '• Late by $lateBy' : ''}'
                          : 'Target Deadline: $deadlineStr',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // ── Destination Monitoring (15m Radius & 5-Minute Live Target Timer) ──
          _buildDestinationMonitoringCard(task, distanceMeters, isInProgress),

          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final lat = (task['clinic_lat'] as num?)?.toDouble();
                    final lng = (task['clinic_lng'] as num?)?.toDouble();
                    if (lat != null && lng != null) {
                      final ongoingList = _userTasks.where((t) {
                        final s = (t['status'] ?? 'pending').toString().toLowerCase();
                        return s == 'pending' || s == 'in_progress' || s == 'started';
                      }).toList();
                      final List<MappedTask> tasksToCompare = [];
                      MappedTask? targetMapped;
                      for (final t in ongoingList) {
                        final tLat = (t['clinic_lat'] as num?)?.toDouble();
                        final tLng = (t['clinic_lng'] as num?)?.toDouble();
                        if (tLat != null && tLng != null && tLat != 0.0 && tLng != 0.0) {
                          final mapped = MappedTask(
                            taskId: (t['id'] as num?)?.toInt(),
                            doctorName: t['doctor_name'] ?? '',
                            clinicName: t['clinic_name'] ?? '',
                            clinicAddress: t['clinic_address'] ?? '',
                            taskCategory: t['task_category'] ?? '',
                            taskBasis: t['task_basis'] ?? 'Daily',
                            notes: t['notes'] ?? '',
                            status: (t['status'] ?? 'pending').toString(),
                            destinationLatLng: LatLng(tLat, tLng),
                          );
                          tasksToCompare.add(mapped);
                          if ((t['id'] == task['id'] && task['id'] != null) || (t['clinic_name'] == clinic && t['doctor_name'] == doctor)) {
                            targetMapped = mapped;
                          }
                        }
                      }
                      setState(() {
                        _destinationLatLng = LatLng(lat, lng);
                        _destinationName = clinic;
                        _destinationAddress = address;
                        _assignedDoctor = doctor;
                        _taskBasis = basis;
                        _showRoute = true;
                        _autoFollowUser = true;
                        _currentView = 'map';
                      });
                      _startContinuousLocationStream();
                      if (tasksToCompare.isNotEmpty) {
                        _fetchMultiRoutes(tasksToCompare).then((_) {
                          if (mounted && targetMapped != null) {
                            setState(() => _selectedMappedTask = targetMapped);
                          }
                        });
                      } else {
                        final single = MappedTask(
                          taskId: taskId != 0 ? taskId : null,
                          doctorName: doctor,
                          clinicName: clinic,
                          clinicAddress: address,
                          taskCategory: category,
                          taskBasis: basis,
                          destinationLatLng: LatLng(lat, lng),
                        );
                        _fetchMultiRoutes([single]);
                      }
                    } else {
                      setState(() {
                        _autoFollowUser = true;
                        _currentView = 'map';
                      });
                      _startContinuousLocationStream();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(isInProgress ? Icons.navigation_rounded : Icons.map_rounded, size: 16),
                  label: Text(isInProgress ? 'Navigate' : 'View Route', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              if (!isInProgress)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: taskId != 0 ? () => _startTask(task) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('OK / Start Task', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                )
              else
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: taskId != 0 ? () => _markTaskCompleted(task) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A86B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                    label: const Text('Mark Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedTaskCard(Map<String, dynamic> task) {
    final doctor = task['doctor_name'] ?? 'N/A';
    final clinic = task['clinic_name'] ?? 'N/A';
    final basis  = task['task_basis']  ?? 'Daily';
    final category = task['task_category'] ?? '';
    final address  = task['clinic_address'] ?? '';
    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    final createdAt = (task['created_at'] ?? '').toString().trim();
    final taskDate = checkoutDate.isNotEmpty ? checkoutDate : (createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt);
    final checkoutTime = (task['checkout_time'] ?? '').toString().trim();
    final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();
    final compTime = checkoutTime.isNotEmpty ? checkoutTime : (checkedOutAt.length >= 11 ? checkedOutAt.substring(11) : '');

    final checkoutType = (task['checkout_type'] ?? 'ONLINE').toString().toUpperCase().trim();
    final isOffline = checkoutType.contains('OFFLINE');

    final deadlineStr = _formatDeadlineDisplay(task['deadline_date_time'] ?? task['deadline']);
    final perfStatus = (task['performance_status'] ?? 'GREAT / ON TIME').toString().toUpperCase();
    final isLate = perfStatus.contains('LATE') || perfStatus.contains('BAD') || (task['points_earned'] != null && (task['points_earned'] as num) < 0);
    final isGreen = !isLate && (perfStatus.contains('ON TIME') || (task['color_category'] ?? '').toString().toUpperCase() == 'GREEN');
    final pointsEarned = (task['points_earned'] as num?)?.toInt() ?? (isLate ? -5 : 10);
    final duration = (task['total_duration'] ?? '').toString().trim();
    final lateBy = (task['late_by'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isGreen ? const Color(0xFFD1FAE5) : const Color(0xFFFECACA)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isGreen ? const Color(0xFFD1FAE5) : const Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isGreen ? Icons.check_rounded : Icons.schedule_rounded,
                  color: isGreen ? const Color(0xFF047857) : const Color(0xFFDC2626),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dr. $doctor • $clinic', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _darkText)),
                    const SizedBox(height: 2),
                    Text('$basis Task ${category.toString().isNotEmpty ? '• $category' : ''}', style: const TextStyle(fontSize: 11, color: _emeraldDark, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              // Points Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isGreen ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isGreen ? const Color(0xFFA7F3D0) : const Color(0xFFFCA5A5)),
                ),
                child: Text(
                  pointsEarned > 0 ? '+$pointsEarned pts' : '$pointsEarned pts',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: isGreen ? const Color(0xFF047857) : const Color(0xFFDC2626),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Checkout mode pill: ONLINE / OFFLINE (in RED if OFFLINE)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOffline ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isOffline ? const Color(0xFFFCA5A5) : const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                      size: 12,
                      color: isOffline ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOffline ? 'OFFLINE' : 'ONLINE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isOffline ? const Color(0xFFDC2626) : const Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Performance Status Pill & Metrics Row
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isGreen ? const Color(0xFFF0FDF4) : const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isGreen ? const Color(0xFFBBF7D0) : const Color(0xFFFECDD3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGreen ? const Color(0xFF00A86B) : const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    perfStatus,
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                if (duration.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 3),
                  Text('Duration: $duration', style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                ],
                if (lateBy.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text('Late: $lateBy', style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),

          if (address.isNotEmpty || taskDate.isNotEmpty || compTime.isNotEmpty || deadlineStr.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 8),
            Row(
              children: [
                if (taskDate.isNotEmpty) ...[
                  const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(taskDate, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                ],
                if (compTime.isNotEmpty) ...[
                  const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text('Time: $compTime', style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  const SizedBox(width: 10),
                ],
                if (deadlineStr.isNotEmpty) ...[
                  const Spacer(),
                  Text('Target: $deadlineStr', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ],
            ),
          ],

          // Destination Monitoring Completion Result Row
          if (task['completion_result'] != null && task['completion_result'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: task['completion_result'].toString().toLowerCase() == 'overtime'
                    ? const Color(0xFFFFFBEB)
                    : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: task['completion_result'].toString().toLowerCase() == 'overtime'
                      ? const Color(0xFFFDE68A)
                      : const Color(0xFFBBF7D0),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    task['completion_result'].toString().toLowerCase() == 'overtime'
                        ? Icons.timer_off_rounded
                        : Icons.check_circle_rounded,
                    size: 13,
                    color: task['completion_result'].toString().toLowerCase() == 'overtime'
                        ? const Color(0xFFD97706)
                        : const Color(0xFF047857),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    task['completion_result'].toString().toLowerCase() == 'overtime'
                        ? 'COMPLETED WITH OVERTIME (5m Target)'
                        : 'COMPLETED WITHIN 5M TARGET',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: task['completion_result'].toString().toLowerCase() == 'overtime'
                          ? const Color(0xFFD97706)
                          : const Color(0xFF047857),
                    ),
                  ),
                  const Spacer(),
                  if (task['final_distance_meters'] != null || task['destination_distance_meters'] != null) ...[
                    Text(
                      'Dist: ${((task['final_distance_meters'] ?? task['destination_distance_meters']) as num).toDouble().toStringAsFixed(1)}m',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAdminDashboard(BuildContext context) {
    return Container(
      color: const Color(0xFFF8FAFC),
      child: SafeArea(
        child: Column(
          children: [
            // Admin Header Bar with Sign Out & History Map
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _showDashboardBackConfirmationDialog,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _emeraldDark),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0x1A00A86B),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _emeraldPrimary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MedSafe Admin',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                        Text(
                          'Administrator Portal',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _emeraldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_rounded, color: _emeraldPrimary),
                    tooltip: 'Medical Rep PDF Reports',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AdminPdfReportsScreen(
                          initialTasks: _userTasks,
                        ),
                      ));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.map_rounded, color: _emeraldPrimary),
                    tooltip: 'Check-In & Check-Out History Map',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AdminAttendanceHistoryScreen(),
                      ));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                    tooltip: 'Check Out',
                    onPressed: _showDashboardBackConfirmationDialog,
                  ),
                ],
              ),
            ),

            // Segment Switcher: Sales Reps vs Task Performance vs All Tasks Database vs PDF Reports
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _adminTab = 'reps'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _adminTab == 'reps' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_rounded, size: 15, color: _adminTab == 'reps' ? Colors.white : _darkSubtext),
                                const SizedBox(width: 4),
                                Text('Sales Reps', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _adminTab == 'reps' ? Colors.white : _darkSubtext)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _adminTab = 'performance'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _adminTab == 'performance' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.insights_rounded, size: 15, color: _adminTab == 'performance' ? Colors.white : _darkSubtext),
                                const SizedBox(width: 4),
                                Text('Performance', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _adminTab == 'performance' ? Colors.white : _darkSubtext)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _adminTab = 'tasks');
                          _fetchUserTasks();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _adminTab == 'tasks' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.assignment_rounded, size: 15, color: _adminTab == 'tasks' ? Colors.white : _darkSubtext),
                                const SizedBox(width: 4),
                                Text('Tasks DB', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _adminTab == 'tasks' ? Colors.white : _darkSubtext)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _adminTab = 'reports'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _adminTab == 'reports' ? _emeraldPrimary : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.picture_as_pdf_rounded, size: 15, color: _adminTab == 'reports' ? Colors.white : _darkSubtext),
                                const SizedBox(width: 4),
                                Text('PDF Reports', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _adminTab == 'reports' ? Colors.white : _darkSubtext)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab Content
            Expanded(
              child: _adminTab == 'reps'
                  ? const AdminSalesRepListScreen()
                  : _adminTab == 'performance'
                      ? AdminTaskPerformanceScreen(initialTasks: _userTasks)
                      : _adminTab == 'reports'
                          ? AdminPdfReportsScreen(
                              isEmbedded: true,
                              initialTasks: _userTasks,
                            )
                          : RefreshIndicator(
                          onRefresh: () async {
                            await _fetchUserTasks();
                          },
                          color: _emeraldPrimary,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            child: () {
                              final currentFilteredTasks = _filteredAdminTasks;
                              final currentOngoing = currentFilteredTasks.where((t) => (t['status'] ?? 'pending') != 'completed').toList();
                              final currentCompleted = currentFilteredTasks.where((t) => (t['status'] ?? 'pending') == 'completed').toList();
                          final isFiltered = _adminTasksAppliedFromDate != null || _adminTasksAppliedToDate != null;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Summary Cards
                              Row(
                                children: [
                                  Expanded(child: _buildStatusMetricCard('Total Tasks', '${currentFilteredTasks.length}', Icons.assignment_rounded, const Color(0xFF0284C7), const Color(0xFFE0F2FE))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildStatusMetricCard('Ongoing', '${currentOngoing.length}', Icons.pending_actions_rounded, const Color(0xFFE65100), const Color(0xFFFFF3E0))),
                                  const SizedBox(width: 10),
                                  Expanded(child: _buildStatusMetricCard('Completed', '${currentCompleted.length}', Icons.check_circle_rounded, const Color(0xFF00A86B), const Color(0xFFE8F5E9))),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Date Range Filter Bar for Tasks DB Tab
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isFiltered ? _emeraldPrimary.withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
                                    width: isFiltered ? 1.5 : 1.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFECFDF5),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.date_range_rounded, size: 15, color: _emeraldDark),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'Filter by Date Range',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _darkText),
                                        ),
                                        const Spacer(),
                                        if (isFiltered || _adminTasksFromDate != null || _adminTasksToDate != null)
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _adminTasksFromDate = null;
                                                _adminTasksToDate = null;
                                                _adminTasksAppliedFromDate = null;
                                                _adminTasksAppliedToDate = null;
                                              });
                                              _fetchUserTasks();
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFEF2F2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFECACA)),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.clear_rounded, size: 12, color: Color(0xFFDC2626)),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Reset',
                                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _adminTasksFromDate ?? DateTime.now(),
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2035),
                                                builder: (context, child) => Theme(
                                                  data: Theme.of(context).copyWith(
                                                    colorScheme: const ColorScheme.light(
                                                      primary: _emeraldPrimary,
                                                      onPrimary: Colors.white,
                                                      onSurface: _darkText,
                                                    ),
                                                  ),
                                                  child: child!,
                                                ),
                                              );
                                              if (picked != null) {
                                                setState(() => _adminTasksFromDate = picked);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _adminTasksFromDate != null ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _adminTasksFromDate != null ? _emeraldPrimary : const Color(0xFFCBD5E1),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.calendar_today_rounded, size: 13, color: _adminTasksFromDate != null ? _emeraldDark : const Color(0xFF64748B)),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      _adminTasksFromDate != null ? DateFormat('dd/MM/yyyy').format(_adminTasksFromDate!) : 'From Date',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: _adminTasksFromDate != null ? _emeraldDark : const Color(0xFF64748B),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (_adminTasksFromDate != null)
                                                    GestureDetector(
                                                      onTap: () => setState(() => _adminTasksFromDate = null),
                                                      child: const Icon(Icons.close_rounded, size: 14, color: _emeraldDark),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _adminTasksToDate ?? _adminTasksFromDate ?? DateTime.now(),
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2035),
                                                builder: (context, child) => Theme(
                                                  data: Theme.of(context).copyWith(
                                                    colorScheme: const ColorScheme.light(
                                                      primary: _emeraldPrimary,
                                                      onPrimary: Colors.white,
                                                      onSurface: _darkText,
                                                    ),
                                                  ),
                                                  child: child!,
                                                ),
                                              );
                                              if (picked != null) {
                                                setState(() => _adminTasksToDate = picked);
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: _adminTasksToDate != null ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: _adminTasksToDate != null ? _emeraldPrimary : const Color(0xFFCBD5E1),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.event_available_rounded, size: 13, color: _adminTasksToDate != null ? _emeraldDark : const Color(0xFF64748B)),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Text(
                                                      _adminTasksToDate != null ? DateFormat('dd/MM/yyyy').format(_adminTasksToDate!) : 'To Date',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: _adminTasksToDate != null ? _emeraldDark : const Color(0xFF64748B),
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (_adminTasksToDate != null)
                                                    GestureDetector(
                                                      onTap: () => setState(() => _adminTasksToDate = null),
                                                      child: const Icon(Icons.close_rounded, size: 14, color: _emeraldDark),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: () {
                                            if (_adminTasksFromDate != null && _adminTasksToDate != null && _adminTasksFromDate!.isAfter(_adminTasksToDate!)) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: const Text('From Date cannot be after To Date.'),
                                                  backgroundColor: const Color(0xFFDC2626),
                                                  behavior: SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              );
                                              return;
                                            }
                                            if (_adminTasksFromDate == null && _adminTasksToDate == null) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: const Text('Please select From Date and/or To Date to filter.'),
                                                  backgroundColor: const Color(0xFF0F172A),
                                                  behavior: SnackBarBehavior.floating,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                              );
                                              return;
                                            }
                                            setState(() {
                                              _adminTasksAppliedFromDate = _adminTasksFromDate;
                                              _adminTasksAppliedToDate = _adminTasksToDate;
                                            });
                                            _fetchUserTasks(fromDate: _adminTasksFromDate, toDate: _adminTasksToDate);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _emeraldPrimary,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 1,
                                          ),
                                          child: const Text('Apply', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                    if (isFiltered) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0FDF4),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFA7F3D0)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.filter_list_rounded, size: 12, color: _emeraldDark),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                'Filtered: ${_adminTasksAppliedFromDate != null ? DateFormat('dd/MM/yyyy').format(_adminTasksAppliedFromDate!) : 'Beginning'} to ${_adminTasksAppliedToDate != null ? DateFormat('dd/MM/yyyy').format(_adminTasksAppliedToDate!) : 'Present'} (${currentFilteredTasks.length} task${currentFilteredTasks.length == 1 ? '' : 's'})',
                                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _emeraldDark),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  const Icon(Icons.storage_rounded, color: _emeraldDark, size: 18),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Tasks Database Records',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText),
                                  ),
                                  const Spacer(),
                                  // ── Sales Rep Filter Dropdown ──────────────────────────────────
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFECFDF5),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFA7F3D0)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        dropdownColor: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        elevation: 4,
                                        value: (_selectedAdminTaskRepFilter == 'All Sales Reps' || _adminTaskRepNames.contains(_selectedAdminTaskRepFilter))
                                            ? _selectedAdminTaskRepFilter
                                            : 'All Sales Reps',
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _emeraldDark, size: 18),
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        onChanged: (String? val) {
                                          setState(() {
                                            _selectedAdminTaskRepFilter = val ?? 'All Sales Reps';
                                          });
                                        },
                                        items: _adminTaskRepNames.map((rep) => DropdownMenuItem<String>(
                                          value: rep,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                rep == 'All Sales Reps' ? Icons.people_outline_rounded : Icons.person_rounded,
                                                size: 14,
                                                color: _emeraldDark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                rep,
                                                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        )).toList(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${currentFilteredTasks.length} Records',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _emeraldDark),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              if (_loadingUserTasks)
                                const Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Center(child: CircularProgressIndicator(color: _emeraldPrimary)),
                                )
                              else if (currentFilteredTasks.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.assignment_outlined, size: 40, color: Color(0xFF94A3B8)),
                                      const SizedBox(height: 10),
                                      Text(
                                        isFiltered
                                            ? 'No tasks found for the selected date range.'
                                            : (_selectedAdminTaskRepFilter == 'All Sales Reps'
                                                ? 'No tasks stored in tasks table yet.'
                                                : 'No tasks found for $_selectedAdminTaskRepFilter.'),
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      const Text('Assigned tasks will appear here in real-time.', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                                    ],
                                  ),
                                )
                              else
                                Column(
                                  children: currentFilteredTasks.map((t) => _buildAdminTaskRecordCard(t)).toList(),
                                ),
                            ],
                          );
                        }(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminTaskRecordCard(Map<String, dynamic> task) {
    final taskId     = (task['id'] as num?)?.toInt() ?? 0;
    final repName    = (task['sales_rep_name'] ?? '').toString().trim().isNotEmpty
        ? task['sales_rep_name'].toString().trim()
        : 'Sales Rep #${task['user_id'] ?? ''}';
    final doctor     = task['doctor_name'] ?? 'N/A';
    final clinic     = task['clinic_name'] ?? 'N/A';
    final basis      = task['task_basis']  ?? 'Daily';
    final category   = task['task_category'] ?? '';
    final address    = task['clinic_address'] ?? '';
    final notes      = (task['notes'] ?? '').toString().trim();
    final noteDisplay = notes.isNotEmpty ? notes : '—';
    final status     = (task['status'] ?? 'pending').toString().toLowerCase();
    final isDone     = status == 'completed';
    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    final createdAt  = (task['created_at'] ?? '').toString().trim();
    final taskDate   = checkoutDate.isNotEmpty ? checkoutDate : (createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt);

    final deadlineStr = _formatDeadlineDisplay(task['deadline_date_time'] ?? task['deadline']);
    final perfStatus = (task['performance_status'] ?? (isDone ? 'GREAT / ON TIME' : 'PENDING')).toString().toUpperCase();
    final isOverdue = perfStatus == 'OVERDUE';
    final isLate = perfStatus.contains('LATE') || perfStatus.contains('BAD') || (task['points_earned'] != null && (task['points_earned'] as num) < 0);
    final isGreen = !isLate && (perfStatus.contains('ON TIME') || (task['color_category'] ?? '').toString().toUpperCase() == 'GREEN');
    final pointsEarned = (task['points_earned'] as num?)?.toInt() ?? (isDone ? (isGreen ? 10 : -5) : 0);
    final duration = (task['total_duration'] ?? '').toString().trim();
    final lateBy = (task['late_by'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone
              ? (isGreen ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA))
              : (isOverdue ? const Color(0xFFFCA5A5) : const Color(0xFFFFD8A8)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: ID + Date + Status + Basis Chip + Points
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDone ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDone ? const Color(0xFFA7F3D0) : const Color(0xFFFFD8A8)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isDone ? Icons.check_circle_rounded : Icons.pending_actions_rounded, size: 13, color: isDone ? const Color(0xFF00A86B) : const Color(0xFFE65100)),
                    const SizedBox(width: 4),
                    Text(
                      '#$taskId • ${status.toUpperCase()}',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isDone ? const Color(0xFF00A86B) : const Color(0xFFE65100)),
                    ),
                  ],
                ),
              ),
              if (taskDate.isNotEmpty) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 11, color: Color(0xFF64748B)),
                    const SizedBox(width: 3),
                    Text(taskDate, style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
              const Spacer(),
              if (isDone || pointsEarned != 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isGreen ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pointsEarned > 0 ? '+$pointsEarned pts' : '$pointsEarned pts',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isGreen ? const Color(0xFF047857) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(6)),
                child: Text('$basis Task', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Performance Status Pill & Metrics Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isGreen
                  ? const Color(0xFFF0FDF4)
                  : (isOverdue || isLate ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isGreen
                    ? const Color(0xFFBBF7D0)
                    : (isOverdue || isLate ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isGreen
                        ? const Color(0xFF00A86B)
                        : (isOverdue || isLate ? const Color(0xFFEF4444) : const Color(0xFF64748B)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    perfStatus,
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                if (deadlineStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF64748B)),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text('Deadline: $deadlineStr', style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)), overflow: TextOverflow.ellipsis),
                  ),
                ],
                if (duration.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('⏱️ $duration', style: const TextStyle(fontSize: 10, color: Color(0xFF0284C7), fontWeight: FontWeight.w600)),
                ],
                if (lateBy.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('Late: $lateBy', style: const TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Row 2: Sales Rep & Task Note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD1FAE5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.badge_rounded, size: 14, color: _emeraldDark),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sales Rep: $repName',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _darkText),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_rounded, size: 14, color: Color(0xFF047857)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Note: $noteDisplay',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: notes.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                          color: notes.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Doctor & Clinic details
          Row(
            children: [
              const Icon(Icons.person_rounded, size: 15, color: Color(0xFF0284C7)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Doctor: Dr. $doctor', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _darkText)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.business_rounded, size: 15, color: Color(0xFF64748B)),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Clinic: $clinic', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _darkSubtext)),
                    if (address.toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(address.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (category.toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.category_rounded, size: 13, color: _emeraldDark),
                const SizedBox(width: 6),
                Text('Category: $category', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _emeraldDark)),
              ],
            ),
          ],
          if (createdAt.toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Created: $createdAt', style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          ],
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => TaskMapVerificationModal.show(context, task),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF047857),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              icon: const Icon(Icons.verified_outlined, size: 16),
              label: const Text(
                'Verify Map',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  final Color color;
  final bool isNorth;

  _CompassNeedlePainter(this.color, {required this.isNorth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isNorth) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isNorth != isNorth;
}

class _GoogleMapsHeadingBeamPainter extends CustomPainter {
  final Color color;

  _GoogleMapsHeadingBeamPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final beamColor = color;

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          beamColor.withValues(alpha: 0.50),
          beamColor.withValues(alpha: 0.20),
          beamColor.withValues(alpha: 0.0),
        ],
        [0.0, 0.65, 1.0],
      )
      ..style = PaintingStyle.fill;

    // 65-degree forward beam fan cone pointing straight up (heading direction)
    const sweepAngle = 65 * (math.pi / 180.0);
    const startAngle = -math.pi / 2 - sweepAngle / 2;

    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _GoogleMapsHeadingBeamPainter oldDelegate) =>
      oldDelegate.color != color;
}

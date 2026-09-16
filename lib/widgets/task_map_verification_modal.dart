import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../app_config.dart';
import '../services/map_url_service.dart';

class TaskMapVerificationModal extends StatefulWidget {
  final Map<String, dynamic> task;

  const TaskMapVerificationModal({super.key, required this.task});

  static Future<void> show(BuildContext context, Map<String, dynamic> task) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskMapVerificationModal(task: task),
    );
  }

  @override
  State<TaskMapVerificationModal> createState() => _TaskMapVerificationModalState();
}

class _TaskMapVerificationModalState extends State<TaskMapVerificationModal> {
  static const _emerald = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _darkText = Color(0xFF1B4332);

  final _mapController = MapController();
  final _urlController = TextEditingController();

  String _clinicName = '';
  String _doctorName = '';
  String _clinicAddress = '';
  String _salesRepName = '';
  String _notes = '';
  int _taskId = 0;
  String _deadline = '';
  String _startedAt = '';
  String _completedAt = '';
  String _performanceStatus = '';
  String _colorCategory = '';
  String _lateBy = '';
  int _pointsEarned = 0;
  String _totalDuration = '';
  String _taskStatus = '';
  String _completionResult = '';
  String _destinationReachedAt = '';
  String _overtimeReason = '';
  double? _finalDistanceMeters;

  LatLng? _actualClinicLatLng;
  LatLng? _searchedLatLng;
  bool _isSearching = false;
  String _searchError = '';

  bool _isCompared = false;
  double? _distanceMeters;

  @override
  void initState() {
    super.initState();
    _initTaskData();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _initTaskData() {
    final t = widget.task;
    _taskId = (t['id'] as num?)?.toInt() ?? 0;
    _clinicName = (t['clinic_name'] ?? 'Clinic').toString();
    _doctorName = (t['doctor_name'] ?? 'Doctor').toString();
    _clinicAddress = (t['clinic_address'] ?? '').toString();
    _salesRepName = (t['sales_rep_name'] ?? '').toString();
    _notes = (t['notes'] ?? '').toString();
    _taskStatus = (t['status'] ?? '').toString();

    _deadline = (t['deadline_date_time'] ?? t['deadline'] ?? '').toString();
    _startedAt = (t['started_at'] ?? '').toString();
    _completedAt = (t['completed_at'] ?? '').toString();
    _performanceStatus = (t['performance_status'] ?? '').toString();
    _colorCategory = (t['color_category'] ?? '').toString().toLowerCase();
    _lateBy = (t['late_by'] ?? '').toString();
    _pointsEarned = (t['points_earned'] as num?)?.toInt() ?? 0;
    _totalDuration = (t['total_duration'] ?? '').toString();
    _completionResult = (t['completion_result'] ?? '').toString();
    _destinationReachedAt = (t['destination_reached_at'] ?? '').toString();
    _overtimeReason = (t['overtime_reason'] ?? '').toString();
    _finalDistanceMeters = (t['final_distance_meters'] as num?)?.toDouble();

    final cLat = (t['clinic_lat'] as num?)?.toDouble();
    final cLng = (t['clinic_lng'] as num?)?.toDouble();

    if (cLat != null && cLng != null && cLat != 0.0 && cLng != 0.0) {
      _actualClinicLatLng = LatLng(cLat, cLng);
    } else {
      _fetchClinicCoordsFromDB(_clinicName);
    }
  }

  Future<void> _fetchClinicCoordsFromDB(String name) async {
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base/backend/get_data.php');
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final clinics = data['clinics'] as List? ?? [];
          for (final c in clinics) {
            if ((c['name'] ?? '').toString().trim().toLowerCase() == name.trim().toLowerCase()) {
              final lat = (c['lat'] as num?)?.toDouble() ?? 0.0;
              final lng = (c['lng'] as num?)?.toDouble() ?? 0.0;
              if (lat != 0.0 && lng != 0.0 && mounted) {
                setState(() {
                  _actualClinicLatLng = LatLng(lat, lng);
                });
                _mapController.move(_actualClinicLatLng!, 15.0);
                return;
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _searchMapUrl() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _searchError = 'Please paste or enter a Google Maps URL or coordinates.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = '';
      _isCompared = false;
      _distanceMeters = null;
    });

    final coords = await MapUrlService.resolveMapUrl(rawUrl);
    if (coords != null && mounted) {
      final lat = coords['lat']!;
      final lng = coords['lng']!;
      setState(() {
        _searchedLatLng = LatLng(lat, lng);
        _isSearching = false;
      });
      _mapController.move(_searchedLatLng!, 15.5);
      return;
    }

    if (mounted) {
      setState(() {
        _isSearching = false;
        _searchError = 'Could not extract coordinates from this URL. Please verify the URL or enter coordinates directly (e.g. 13.0827, 80.2707).';
      });
    }
  }

  void _compareLocations() async {
    if (_searchedLatLng == null) {
      await _searchMapUrl();
      if (_searchedLatLng == null) return;
    }

    if (_actualClinicLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Actual clinic coordinates not found in database.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final dist = Geolocator.distanceBetween(
      _actualClinicLatLng!.latitude,
      _actualClinicLatLng!.longitude,
      _searchedLatLng!.latitude,
      _searchedLatLng!.longitude,
    );

    setState(() {
      _isCompared = true;
      _distanceMeters = dist;
    });

    _fitBothMarkers();
  }

  void _fitBothMarkers() {
    if (_actualClinicLatLng == null || _searchedLatLng == null) return;

    final lat1 = _actualClinicLatLng!.latitude;
    final lng1 = _actualClinicLatLng!.longitude;
    final lat2 = _searchedLatLng!.latitude;
    final lng2 = _searchedLatLng!.longitude;

    final centerLat = (lat1 + lat2) / 2.0;
    final centerLng = (lng1 + lng2) / 2.0;

    final latDiff = (lat1 - lat2).abs();
    final lngDiff = (lng1 - lng2).abs();
    final maxDiff = math.max(latDiff, lngDiff);

    double zoom = 14.5;
    if (maxDiff > 0.1) {
      zoom = 10.5;
    } else if (maxDiff > 0.05) {
      zoom = 12.0;
    } else if (maxDiff > 0.02) {
      zoom = 13.0;
    } else if (maxDiff > 0.008) {
      zoom = 14.0;
    }

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km (${meters.toStringAsFixed(0)} m)';
    }
    return '${meters.toStringAsFixed(1)} meters';
  }

  @override
  Widget build(BuildContext context) {
    final defaultCenter = _actualClinicLatLng ?? const LatLng(13.0827, 80.2707);

    return Container(
      margin: const EdgeInsets.only(top: 45),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 42,
            height: 4.5,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 14, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFD1FAE5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified_rounded, color: _emeraldDark, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Verify Map Location',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText),
                          ),
                          const SizedBox(width: 6),
                          if (_taskId > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '#$_taskId',
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dr. $_doctorName • $_clinicName',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Main Scrollable Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Actual Clinic Info Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.local_hospital_rounded, size: 13, color: _emeraldDark),
                                  SizedBox(width: 4),
                                  Text(
                                    'ACTUAL CLINIC (Database)',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _emeraldDark),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (_salesRepName.isNotEmpty)
                              Text(
                                'Rep: $_salesRepName',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _clinicName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                        ),
                        if (_clinicAddress.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.place_outlined, size: 14, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _clinicAddress,
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD1FAE5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.gps_fixed_rounded, size: 14, color: _emeraldDark),
                              const SizedBox(width: 6),
                              Text(
                                _actualClinicLatLng != null
                                    ? 'Actual Lat: ${_actualClinicLatLng!.latitude.toStringAsFixed(6)} | Lng: ${_actualClinicLatLng!.longitude.toStringAsFixed(6)}'
                                    : 'Coordinates: Not available',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _emeraldDark),
                              ),
                            ],
                          ),
                        ),
                        if (_notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Task Note: $_notes',
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  _buildPerformanceCard(),

                  const SizedBox(height: 12),

                  // Map URL Search Input Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Maps URL / Coordinates Input:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _darkText),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlController,
                                style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E293B)),
                                decoration: InputDecoration(
                                  hintText: 'Paste Google Maps link (e.g. @13.0827,80.2707)...',
                                  hintStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                                  prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF0284C7), size: 18),
                                  suffixIcon: _urlController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 16),
                                          onPressed: () {
                                            _urlController.clear();
                                            setState(() {
                                              _searchedLatLng = null;
                                              _isCompared = false;
                                              _distanceMeters = null;
                                            });
                                          },
                                        )
                                      : null,
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF0284C7), width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isSearching ? null : _searchMapUrl,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                elevation: 0,
                              ),
                              icon: _isSearching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.search_rounded, size: 16),
                              label: const Text('Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),

                        if (_searchError.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            _searchError,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.w500),
                          ),
                        ],

                        if (_searchedLatLng != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF0284C7)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'URL Extracted: Lat: ${_searchedLatLng!.latitude.toStringAsFixed(6)} | Lng: ${_searchedLatLng!.longitude.toStringAsFixed(6)}',
                                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0369A1)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Action Buttons Row: Compare & Center actions
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _compareLocations,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _emeraldDark,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                          label: const Text(
                            'Compare Locations',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_actualClinicLatLng != null) {
                            _mapController.move(_actualClinicLatLng!, 16.0);
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _emeraldDark,
                          side: const BorderSide(color: Color(0xFFA7F3D0)),
                          backgroundColor: const Color(0xFFECFDF5),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                        label: const Text('Reset', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),

                  // Comparison Verdict Section
                  if (_isCompared && _distanceMeters != null) ...[
                    const SizedBox(height: 12),
                    _buildComparisonResultCard(),
                  ],

                  const SizedBox(height: 12),

                  // Map Container
                  Container(
                    height: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: defaultCenter,
                            initialZoom: 14.5,
                            minZoom: 3.0,
                            maxZoom: 18.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.medsafe.medsafelifescience',
                            ),

                            // Polyline between Actual Clinic and Searched Location
                            if (_isCompared && _actualClinicLatLng != null && _searchedLatLng != null)
                              PolylineLayer(
                                polylines: [
                                  // Contrast outline
                                  Polyline(
                                    points: [_actualClinicLatLng!, _searchedLatLng!],
                                    strokeWidth: 6.0,
                                    color: Colors.black.withValues(alpha: 0.4),
                                  ),
                                  // Colored dotted polyline
                                  Polyline(
                                    points: [_actualClinicLatLng!, _searchedLatLng!],
                                    strokeWidth: 3.5,
                                    color: (_distanceMeters ?? 0) <= 100
                                        ? _emerald
                                        : ((_distanceMeters ?? 0) <= 500 ? const Color(0xFFE65100) : const Color(0xFFDC2626)),
                                  ),
                                ],
                              ),

                            // Markers
                            MarkerLayer(
                              markers: [
                                // Marker 1: Actual Clinic Location (Emerald)
                                if (_actualClinicLatLng != null)
                                  Marker(
                                    point: _actualClinicLatLng!,
                                    width: 100,
                                    height: 70,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _emeraldDark,
                                            borderRadius: BorderRadius.circular(6),
                                            boxShadow: [
                                              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                                            ],
                                          ),
                                          child: const Text(
                                            'Actual Clinic',
                                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.location_on_rounded, color: _emeraldDark, size: 36),
                                      ],
                                    ),
                                  ),

                                // Marker 2: URL Searched Location (Blue/Red)
                                if (_searchedLatLng != null)
                                  Marker(
                                    point: _searchedLatLng!,
                                    width: 100,
                                    height: 70,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0284C7),
                                            borderRadius: BorderRadius.circular(6),
                                            boxShadow: [
                                              BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
                                            ],
                                          ),
                                          child: const Text(
                                            'URL Location',
                                            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(Icons.location_on_rounded, color: Color(0xFF0284C7), size: 36),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),

                        // Map Legend / Quick Controls
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _emeraldDark, shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                const Text('Actual DB', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _darkText)),
                                if (_searchedLatLng != null) ...[
                                  const SizedBox(width: 8),
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF0284C7), shape: BoxShape.circle)),
                                  const SizedBox(width: 4),
                                  const Text('URL Map', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: _darkText)),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonResultCard() {
    final dist = _distanceMeters ?? 0.0;
    final isMatch = dist <= 100.0;
    final isClose = dist <= 500.0;

    final Color bgColor = isMatch
        ? const Color(0xFFECFDF5)
        : (isClose ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2));

    final Color borderColor = isMatch
        ? const Color(0xFFA7F3D0)
        : (isClose ? const Color(0xFFFDE68A) : const Color(0xFFFECACA));

    final Color textColor = isMatch
        ? const Color(0xFF065F46)
        : (isClose ? const Color(0xFF92400E) : const Color(0xFF991B1B));

    final IconData iconData = isMatch
        ? Icons.verified_rounded
        : (isClose ? Icons.warning_amber_rounded : Icons.cancel_rounded);

    final String statusTitle = isMatch
        ? 'LOCATION VERIFIED / MATCH'
        : (isClose ? 'CLOSE PROXIMITY (Acceptable)' : 'LOCATION MISMATCH');

    final String statusDescription = isMatch
        ? 'The Google Maps URL location matches the actual clinic location accurately within ${dist.toStringAsFixed(1)}m.'
        : (isClose
            ? 'The locations are in close proximity (${_formatDistance(dist)} difference).'
            : 'The Google Maps URL is ${_formatDistance(dist)} away from the registered clinic location.');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: textColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusTitle,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor, letterSpacing: 0.2),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  'Dist: ${_formatDistance(dist)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            statusDescription,
            style: TextStyle(fontSize: 11.5, color: textColor.withValues(alpha: 0.85), height: 1.3),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Actual Clinic DB:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    Text(
                      _actualClinicLatLng != null
                          ? '${_actualClinicLatLng!.latitude.toStringAsFixed(5)}, ${_actualClinicLatLng!.longitude.toStringAsFixed(5)}'
                          : '—',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _emeraldDark),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Google Maps URL:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    Text(
                      _searchedLatLng != null
                          ? '${_searchedLatLng!.latitude.toStringAsFixed(5)}, ${_searchedLatLng!.longitude.toStringAsFixed(5)}'
                          : '—',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceCard() {
    final bool isGreen = _colorCategory == 'green' || _performanceStatus.contains('GREAT') || _performanceStatus.contains('ON TIME') || _performanceStatus.contains('ON TRACK');
    final bool isRed = _colorCategory == 'red' || _performanceStatus.contains('BAD') || _performanceStatus.contains('LATE') || _performanceStatus.contains('OVERDUE');

    Color badgeBg = const Color(0xFFF1F5F9);
    Color badgeText = const Color(0xFF475569);
    Color badgeBorder = const Color(0xFFCBD5E1);
    IconData badgeIcon = Icons.hourglass_top_rounded;

    if (isGreen) {
      badgeBg = const Color(0xFFD1FAE5);
      badgeText = const Color(0xFF065F46);
      badgeBorder = const Color(0xFFA7F3D0);
      badgeIcon = Icons.check_circle_rounded;
    } else if (isRed) {
      badgeBg = const Color(0xFFFEE2E2);
      badgeText = const Color(0xFF991B1B);
      badgeBorder = const Color(0xFFFECACA);
      badgeIcon = Icons.warning_amber_rounded;
    }

    final displayStatus = _performanceStatus.isNotEmpty
        ? _performanceStatus
        : (_taskStatus == 'completed' ? 'COMPLETED' : (_taskStatus == 'active' ? 'IN PROGRESS' : 'PENDING'));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.speed_rounded, size: 13, color: Color(0xFF1D4ED8)),
                    SizedBox(width: 4),
                    Text(
                      'PERFORMANCE & DEADLINE',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeText),
                    const SizedBox(width: 4),
                    Text(
                      displayStatus,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Details rows
          Row(
            children: [
              Expanded(
                child: _buildPerfInfoTile(
                  icon: Icons.alarm_rounded,
                  label: 'Target Deadline',
                  value: _deadline.isNotEmpty ? _deadline : 'No Deadline',
                  color: const Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildPerfInfoTile(
                  icon: Icons.stars_rounded,
                  label: 'Points Earned',
                  value: _pointsEarned > 0 ? '+$_pointsEarned pts' : (_pointsEarned < 0 ? '$_pointsEarned pts' : '0 pts'),
                  color: _pointsEarned > 0 ? const Color(0xFF059669) : (_pointsEarned < 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
          if (_startedAt.isNotEmpty || _completedAt.isNotEmpty || _lateBy.isNotEmpty || _totalDuration.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (_totalDuration.isNotEmpty)
                  Expanded(
                    child: _buildPerfInfoTile(
                      icon: Icons.timer_outlined,
                      label: 'Total Duration',
                      value: _totalDuration,
                      color: const Color(0xFF475569),
                    ),
                  ),
                if (_totalDuration.isNotEmpty && _lateBy.isNotEmpty)
                  const SizedBox(width: 8),
                if (_lateBy.isNotEmpty)
                  Expanded(
                    child: _buildPerfInfoTile(
                      icon: Icons.timelapse_rounded,
                      label: 'Late By',
                      value: _lateBy,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
              ],
            ),
          ],
          if (_destinationReachedAt.isNotEmpty || _completionResult.isNotEmpty || _overtimeReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _completionResult == 'within_target'
                    ? const Color(0xFFF0FDF4)
                    : (_completionResult == 'overtime' ? const Color(0xFFFFF7ED) : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _completionResult == 'within_target'
                      ? const Color(0xFFBBF7D0)
                      : (_completionResult == 'overtime' ? const Color(0xFFFED7AA) : const Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _completionResult == 'within_target'
                            ? Icons.check_circle_rounded
                            : (_completionResult == 'overtime' ? Icons.timelapse_rounded : Icons.location_on_rounded),
                        size: 13,
                        color: _completionResult == 'within_target'
                            ? const Color(0xFF047857)
                            : (_completionResult == 'overtime' ? const Color(0xFFC2410C) : const Color(0xFF0284C7)),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _completionResult == 'within_target'
                            ? 'DESTINATION TARGET: WITHIN 5 MIN (SUCCESS)'
                            : (_completionResult == 'overtime' ? 'DESTINATION TARGET: OVERTIME' : 'DESTINATION MONITORING'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _completionResult == 'within_target'
                              ? const Color(0xFF047857)
                              : (_completionResult == 'overtime' ? const Color(0xFFC2410C) : const Color(0xFF0284C7)),
                        ),
                      ),
                    ],
                  ),
                  if (_destinationReachedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Reached Destination: $_destinationReachedAt',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                    ),
                  ],
                  if (_finalDistanceMeters != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Final Distance: ${_finalDistanceMeters!.toStringAsFixed(1)} m (within 15m radius)',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFF475569)),
                    ),
                  ],
                  if (_overtimeReason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overtime Reason: ',
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                        ),
                        Expanded(
                          child: Text(
                            _overtimeReason,
                            style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Color(0xFF7C2D12)),
                          ),
                        ),
                      ],
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

  Widget _buildPerfInfoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class AttendanceRecord {
  final int id;
  final int userId;
  final String salesRepName;
  final String type; // 'check_in' or 'check_out'
  final double lat;
  final double lng;
  final String address;
  final String notes;
  final DateTime createdAt;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    required this.salesRepName,
    required this.type,
    required this.lat,
    required this.lng,
    required this.address,
    required this.notes,
    required this.createdAt,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id:           (j['id'] as num).toInt(),
        userId:       (j['user_id'] as num).toInt(),
        salesRepName: j['sales_rep_name'] as String,
        type:         j['type'] as String,
        lat:          (j['lat'] as num).toDouble(),
        lng:          (j['lng'] as num).toDouble(),
        address:      j['address'] as String? ?? '',
        notes:        j['notes'] as String? ?? '',
        createdAt:    DateTime.parse(j['created_at'] as String),
      );

  bool get isCheckIn => type == 'check_in';
}

class AdminAttendanceHistoryScreen extends StatefulWidget {
  final int? initialUserId;
  final String? initialRepName;

  const AdminAttendanceHistoryScreen({
    super.key,
    this.initialUserId,
    this.initialRepName,
  });

  @override
  State<AdminAttendanceHistoryScreen> createState() =>
      _AdminAttendanceHistoryScreenState();
}

class _AdminAttendanceHistoryScreenState
    extends State<AdminAttendanceHistoryScreen> {
  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _emeraldDark    = Color(0xFF047857);
  static const _darkText       = Color(0xFF1E293B);
  static const _coralRed       = Color(0xFFE53935);

  final MapController _mapController = MapController();

  List<AttendanceRecord> _allRecords = [];
  List<AttendanceRecord> _filteredRecords = [];
  bool _loading = true;
  String _error = '';

  // Filters
  int? _selectedUserId;
  String _selectedTypeFilter = 'all'; // 'all', 'check_in', 'check_out'
  DateTime? _selectedDate;

  // Reps list for filter dropdown
  Map<int, String> _repsMap = {};

  // Currently focused record for map detail callout
  AttendanceRecord? _selectedRecord;

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.initialUserId;
    _fetchHistory();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    setState(() { _loading = true; _error = ''; });

    final bases = AppConfig.allHosts;

    for (final base in bases) {
      try {
        final url = Uri.parse('$base/backend/get_attendance_history.php');
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          // Strip any PHP debug/HTML noise before the JSON
          final raw = res.body.trim();
          final jsonStart = raw.indexOf('{');
          if (jsonStart < 0) continue;
          final jsonBody = raw.substring(jsonStart);

          final data = json.decode(jsonBody) as Map<String, dynamic>;
          if (data['success'] == true) {
            final list = (data['history'] as List? ?? [])
                .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
                .toList();

            final reps = <int, String>{};
            for (final r in list) {
              reps[r.userId] = r.salesRepName;
            }

            if (mounted) {
              setState(() {
                _allRecords = list;
                _repsMap    = reps;
                _loading    = false;
                _error      = '';
              });
              _applyFilters();
            }
            return; // success — stop trying hosts
          }
        }
      } catch (e) {
        debugPrint('[AttendanceHistory] Error from $base: $e');
      }
    }

    // All hosts failed
    if (mounted) {
      setState(() {
        _loading = false;
        _error   = 'Could not connect to server. Make sure WAMP is running and you are on the same WiFi.';
      });
    }
  }


  void _applyFilters() {
    List<AttendanceRecord> list = List.from(_allRecords);

    if (_selectedUserId != null && _selectedUserId! > 0) {
      list = list.where((r) => r.userId == _selectedUserId).toList();
    }

    if (_selectedTypeFilter == 'check_in') {
      list = list.where((r) => r.isCheckIn).toList();
    } else if (_selectedTypeFilter == 'check_out') {
      list = list.where((r) => !r.isCheckIn).toList();
    }

    if (_selectedDate != null) {
      list = list.where((r) {
        return r.createdAt.year == _selectedDate!.year &&
            r.createdAt.month == _selectedDate!.month &&
            r.createdAt.day == _selectedDate!.day;
      }).toList();
    }

    setState(() {
      _filteredRecords = list;
      if (_selectedRecord != null && !list.contains(_selectedRecord)) {
        _selectedRecord = null;
      }
    });

    // Auto fit camera if records exist
    if (list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitMapToRecords(list);
      });
    }
  }

  void _fitMapToRecords(List<AttendanceRecord> records) {
    if (records.isEmpty) return;
    if (records.length == 1) {
      _mapController.move(LatLng(records.first.lat, records.first.lng), 15.0);
      return;
    }

    double minLat = records.first.lat;
    double maxLat = records.first.lat;
    double minLng = records.first.lng;
    double maxLng = records.first.lng;

    for (final r in records) {
      if (r.lat < minLat) minLat = r.lat;
      if (r.lat > maxLat) maxLat = r.lat;
      if (r.lng < minLng) minLng = r.lng;
      if (r.lng > maxLng) maxLng = r.lng;
    }

    try {
      final bounds = LatLngBounds(
        LatLng(minLat, minLng),
        LatLng(maxLat, maxLng),
      );
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(70)),
      );
    } catch (_) {
      _mapController.move(LatLng(records.first.lat, records.first.lng), 13.0);
    }
  }

  void _focusRecord(AttendanceRecord rec) {
    setState(() => _selectedRecord = rec);
    _mapController.move(LatLng(rec.lat, rec.lng), 16.0);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(2024),
      lastDate: now,
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
      setState(() => _selectedDate = picked);
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalCount    = _filteredRecords.length;
    final checkInCount  = _filteredRecords.where((r) => r.isCheckIn).length;
    final checkOutCount = _filteredRecords.where((r) => !r.isCheckIn).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // ── Map View ──
          _buildMap(),

          // ── Header & Filter Bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopHeader(context, totalCount, checkInCount, checkOutCount),
          ),

          // ── Selected Record Popup Banner ──
          if (_selectedRecord != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 180,
              left: 16,
              right: 16,
              child: _buildSelectedDetailCard(),
            ),

          // ── Bottom History List Sheet ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomHistoryPanel(),
          ),

          // ── Loading overlay ──
          if (_loading)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(color: _emeraldPrimary),
              ),
            ),

          // ── Error overlay ──
          if (_error.isNotEmpty && !_loading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 180,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error,
                        style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
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

  Widget _buildTopHeader(BuildContext context, int total, int inCount, int outCount) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 3)),
        ],
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Back, Title, Refresh
          Row(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.initialRepName != null
                          ? '${widget.initialRepName}\'s Location History'
                          : 'Check-In & Check-Out History',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _darkText),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text('Sales Person Checkin & Checkout Locations',
                        style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _fetchHistory,
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
          const SizedBox(height: 10),

          // Row 2: Metrics chips
          Row(
            children: [
              _buildMetricChip('Total Logs', '$total', Icons.history_rounded, const Color(0xFF0284C7), const Color(0xFFE0F2FE)),
              const SizedBox(width: 8),
              _buildMetricChip('Check In', '$inCount', Icons.login_rounded, _emeraldPrimary, const Color(0xFFD1FAE5)),
              const SizedBox(width: 8),
              _buildMetricChip('Check Out', '$outCount', Icons.logout_rounded, _coralRed, const Color(0xFFFFEBEE)),
            ],
          ),
          const SizedBox(height: 10),

          // Row 3: Filter controls (Sales Rep Dropdown, Type Segment, Date Picker)
          Row(
            children: [
              // Rep Dropdown
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _selectedUserId,
                      isExpanded: true,
                      hint: const Text('All Sales Reps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _emeraldDark),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Sales Reps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        if (_selectedUserId != null && !_repsMap.containsKey(_selectedUserId))
                          DropdownMenuItem<int?>(
                            value: _selectedUserId,
                            child: Text(widget.initialRepName ?? 'Sales Rep #$_selectedUserId', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ..._repsMap.entries.map((entry) {
                          return DropdownMenuItem<int?>(
                            value: entry.key,
                            child: Text(entry.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedUserId = val);
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Date Picker Button
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedDate != null ? _emeraldPrimary : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          size: 16,
                          color: _selectedDate != null ? Colors.white : _emeraldDark),
                      const SizedBox(width: 4),
                      Text(
                        _selectedDate != null
                            ? '${_selectedDate!.day}/${_selectedDate!.month}'
                            : 'Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _selectedDate != null ? Colors.white : _darkText,
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedDate = null);
                            _applyFilters();
                          },
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 4: Check-in / Check-out filter chips
          Row(
            children: [
              _buildTypeFilterChip('all', 'All Events'),
              const SizedBox(width: 6),
              _buildTypeFilterChip('check_in', 'Check In Only'),
              const SizedBox(width: 6),
              _buildTypeFilterChip('check_out', 'Check Out Only'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, IconData icon, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text('$label: ', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilterChip(String key, String label) {
    final isSel = _selectedTypeFilter == key;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedTypeFilter = key);
          _applyFilters();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSel ? _emeraldPrimary : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSel ? _emeraldPrimary : const Color(0xFFCBD5E1)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isSel ? Colors.white : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    final initialPos = _filteredRecords.isNotEmpty
        ? LatLng(_filteredRecords.first.lat, _filteredRecords.first.lng)
        : const LatLng(13.0827, 80.2707);

    // Group points by rep for polylines
    final Map<int, List<LatLng>> repPaths = {};
    for (final r in _filteredRecords) {
      repPaths.putIfAbsent(r.userId, () => []).add(LatLng(r.lat, r.lng));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialPos,
        initialZoom: 13.0,
        initialRotation: 0.0,
        maxZoom: 18.0,
        minZoom: 4.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.medsafe.medsafelifescience',
        ),

        // Route lines connecting pings
        PolylineLayer(
          polylines: repPaths.entries.map((entry) {
            return Polyline(
              points: entry.value,
              strokeWidth: 3.0,
              color: _emeraldPrimary.withValues(alpha: 0.6),
            );
          }).toList(),
        ),

        // Check-in and Check-out Markers
        MarkerLayer(
          markers: _filteredRecords.map((r) {
            final isSel = _selectedRecord?.id == r.id;
            final isCheckIn = r.isCheckIn;
            final color = isCheckIn ? _emeraldPrimary : _coralRed;

            return Marker(
              point: LatLng(r.lat, r.lng),
              width: isSel ? 54 : 44,
              height: isSel ? 54 : 44,
              child: GestureDetector(
                onTap: () => _focusRecord(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSel ? Colors.yellowAccent : Colors.white,
                      width: isSel ? 3 : 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: isSel ? 10 : 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                      color: Colors.white,
                      size: isSel ? 26 : 20,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSelectedDetailCard() {
    final r = _selectedRecord!;
    final color = r.isCheckIn ? _emeraldPrimary : _coralRed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  r.isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.salesRepName,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _darkText),
                    ),
                    Text(
                      '${r.isCheckIn ? 'CHECK IN' : 'CHECK OUT'} • ${_formatTimestamp(r.createdAt)}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _selectedRecord = null),
                child: const Icon(Icons.close_rounded, size: 20, color: Colors.grey),
              ),
            ],
          ),
          if (r.address.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    r.address,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'GPS: ${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
          if (r.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Note: ${r.notes}',
                style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomHistoryPanel() {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, -3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top drag indicator bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.history_toggle_off_rounded, color: _emeraldPrimary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Check-In & Check-Out History Log (${_filteredRecords.length})',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _darkText),
                ),
              ],
            ),
          ),
          const Divider(height: 12, color: Color(0xFFF1F5F9)),

          Expanded(
            child: _filteredRecords.isEmpty
                ? const Center(
                    child: Text(
                      'No check-in / check-out history logs found for these filters.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: _filteredRecords.length,
                    itemBuilder: (context, idx) {
                      final r = _filteredRecords[idx];
                      final isSelected = _selectedRecord?.id == r.id;
                      final isCheckIn = r.isCheckIn;
                      final color = isCheckIn ? _emeraldPrimary : _coralRed;

                      return GestureDetector(
                        onTap: () => _focusRecord(r),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? color : const Color(0xFFE2E8F0),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isCheckIn ? Icons.login_rounded : Icons.logout_rounded,
                                  color: color,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          r.salesRepName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _darkText,
                                          ),
                                        ),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            isCheckIn ? 'CHECK IN' : 'CHECK OUT',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                              color: color,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatTimestamp(r.createdAt),
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                    if (r.address.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        r.address,
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
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
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final hr = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y at $hr:$min';
  }
}

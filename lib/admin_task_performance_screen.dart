import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'app_config.dart';
import 'admin_pdf_reports_screen.dart';
import 'widgets/task_map_verification_modal.dart';

enum TaskPeriodType {
  daily,
  weekly,
  monthly,
  yearly,
  custom,
}

class AdminSalesRepTaskSummary {
  final int repId;
  final String repName;
  final String repEmail;
  final String repPhone;
  final bool isOnline;
  final List<Map<String, dynamic>> tasks;

  AdminSalesRepTaskSummary({
    required this.repId,
    required this.repName,
    required this.repEmail,
    required this.repPhone,
    required this.isOnline,
    required this.tasks,
  });

  int get totalTasks => tasks.length;

  int get completedTasks => tasks.where((t) {
        final st = (t['status'] ?? '').toString().trim().toLowerCase();
        return st == 'completed';
      }).length;

  int get pendingTasks => totalTasks - completedTasks;

  double get completionRate =>
      totalTasks > 0 ? (completedTasks / totalTasks) * 100.0 : 0.0;
}

class AdminTaskPerformanceScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? initialTasks;
  final List<dynamic>? initialReps;

  const AdminTaskPerformanceScreen({
    super.key,
    this.initialTasks,
    this.initialReps,
  });

  @override
  State<AdminTaskPerformanceScreen> createState() =>
      _AdminTaskPerformanceScreenState();
}

class _AdminTaskPerformanceScreenState
    extends State<AdminTaskPerformanceScreen> {
  static const _emerald = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _darkText = Color(0xFF1B4332);

  TaskPeriodType _periodType = TaskPeriodType.daily;
  DateTime _selectedDate = DateTime.now();
  DateTime? _customFromDate;
  DateTime? _customToDate;

  List<dynamic> _reps = [];
  List<Map<String, dynamic>> _allTasks = [];
  bool _loading = true;
  String _searchQuery = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialReps != null && widget.initialReps!.isNotEmpty) {
      _reps = widget.initialReps!;
    }
    if (widget.initialTasks != null && widget.initialTasks!.isNotEmpty) {
      _allTasks = widget.initialTasks!;
      _loading = false;
    }
    _fetchAllData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchAllData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAllData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    await Future.wait([_fetchReps(), _fetchTasks()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fetchReps() async {
    const path = '/backend/get_all_sales_reps.php';
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$path');
        final res = await http
            .get(url, headers: AppConfig.headers)
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final list = data['reps'] as List? ?? [];
            if (mounted) {
              setState(() => _reps = list);
            }
            return;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _fetchTasks() async {
    const path = '/backend/get_user_tasks.php?all=1';
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$path');
        final res = await http
            .get(url, headers: AppConfig.headers)
            .timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final list = (data['tasks'] as List? ?? []).cast<Map<String, dynamic>>();
            if (mounted) {
              setState(() => _allTasks = list);
            }
            return;
          }
        }
      } catch (_) {}
    }
  }

  DateTimeRange _getDateRangeForPeriod() {
    final now = _selectedDate;
    switch (_periodType) {
      case TaskPeriodType.daily:
        final d = DateTime(now.year, now.month, now.day);
        return DateTimeRange(start: d, end: d);

      case TaskPeriodType.weekly:
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1)); // Monday
        final end = start.add(const Duration(days: 6)); // Sunday
        return DateTimeRange(start: start, end: end);

      case TaskPeriodType.monthly:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        return DateTimeRange(start: start, end: end);

      case TaskPeriodType.yearly:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31);
        return DateTimeRange(start: start, end: end);

      case TaskPeriodType.custom:
        final start = _customFromDate ?? DateTime(now.year, now.month, 1);
        final end = _customToDate ?? now;
        return DateTimeRange(
          start: DateTime(start.year, start.month, start.day),
          end: DateTime(end.year, end.month, end.day),
        );
    }
  }

  DateTime? _extractTaskDate(Map<String, dynamic> task) {
    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    final checkoutDateTime = (task['checkout_datetime'] ?? '').toString().trim();
    final createdAt = (task['created_at'] ?? '').toString().trim();
    final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();
    final updatedAt = (task['updated_at'] ?? '').toString().trim();

    String rawDate = '';
    if (checkoutDate.isNotEmpty && checkoutDate.length >= 10) {
      rawDate = checkoutDate.substring(0, 10);
    } else if (checkoutDateTime.isNotEmpty && checkoutDateTime.length >= 10) {
      rawDate = checkoutDateTime.substring(0, 10);
    } else if (createdAt.isNotEmpty && createdAt.length >= 10) {
      rawDate = createdAt.substring(0, 10);
    } else if (checkedOutAt.isNotEmpty && checkedOutAt.length >= 10) {
      rawDate = checkedOutAt.substring(0, 10);
    } else if (updatedAt.isNotEmpty && updatedAt.length >= 10) {
      rawDate = updatedAt.substring(0, 10);
    }

    if (rawDate.isEmpty) return null;

    try {
      if (rawDate.contains('/')) {
        final parts = rawDate.split('/');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          } else {
            return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        }
      } else if (rawDate.contains('-')) {
        final parts = rawDate.split('-');
        if (parts.length == 3) {
          if (parts[0].length == 4) {
            return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
          } else {
            return DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isTaskInPeriod(Map<String, dynamic> task, DateTimeRange range) {
    final taskDt = _extractTaskDate(task);
    if (taskDt == null) return false;
    final day = DateTime(taskDt.year, taskDt.month, taskDt.day);
    final startDay = DateTime(range.start.year, range.start.month, range.start.day);
    final endDay = DateTime(range.end.year, range.end.month, range.end.day);
    return !day.isBefore(startDay) && !day.isAfter(endDay);
  }

  List<AdminSalesRepTaskSummary> _computeSummaries(DateTimeRange range) {
    final periodTasks = _allTasks.where((t) => _isTaskInPeriod(t, range)).toList();

    // Map by Rep ID and Rep Name
    final Map<String, List<Map<String, dynamic>>> repTasksMap = {};

    // Initialize all known reps
    for (final r in _reps) {
      final repId = (r['id'] as num?)?.toInt() ?? 0;
      final repName = (r['name'] ?? '').toString().trim();
      final key = '$repId|${repName.toLowerCase()}';
      repTasksMap[key] = [];
    }

    // Match tasks to reps
    for (final t in periodTasks) {
      final uid = (t['user_id'] as num?)?.toInt();
      final rname = (t['sales_rep_name'] ?? '').toString().trim().toLowerCase();

      bool matched = false;
      for (final key in repTasksMap.keys) {
        final parts = key.split('|');
        final id = int.tryParse(parts[0]) ?? 0;
        final name = parts.length > 1 ? parts[1] : '';

        if ((uid != null && uid == id) || (rname.isNotEmpty && rname == name)) {
          repTasksMap[key]!.add(t);
          matched = true;
          break;
        }
      }

      if (!matched) {
        final fallbackKey = '${uid ?? 0}|$rname';
        repTasksMap.putIfAbsent(fallbackKey, () => []).add(t);
      }
    }

    final List<AdminSalesRepTaskSummary> list = [];

    for (final entry in repTasksMap.entries) {
      final parts = entry.key.split('|');
      final repId = int.tryParse(parts[0]) ?? 0;
      final repKeyName = parts.length > 1 ? parts[1] : '';

      dynamic repData;
      for (final r in _reps) {
        final rId = (r['id'] as num?)?.toInt() ?? 0;
        final rName = (r['name'] ?? '').toString().trim().toLowerCase();
        if ((repId > 0 && rId == repId) || (repKeyName.isNotEmpty && rName == repKeyName)) {
          repData = r;
          break;
        }
      }

      final name = repData != null
          ? (repData['name'] ?? 'Unknown Rep')
          : (repKeyName.isNotEmpty ? repKeyName.toUpperCase() : 'Rep #$repId');
      final email = repData != null ? (repData['email'] ?? '') : '';
      final phone = repData != null ? (repData['phone'] ?? '') : '';
      final isOnline = repData != null ? (repData['is_online'] == true) : false;

      // Filter by search query if any
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!name.toString().toLowerCase().contains(q) &&
            !email.toString().toLowerCase().contains(q) &&
            !phone.toString().toLowerCase().contains(q)) {
          continue;
        }
      }

      list.add(AdminSalesRepTaskSummary(
        repId: repId,
        repName: name.toString(),
        repEmail: email.toString(),
        repPhone: phone.toString(),
        isOnline: isOnline,
        tasks: entry.value,
      ));
    }

    // Sort by total tasks descending, then name
    list.sort((a, b) {
      final cmp = b.totalTasks.compareTo(a.totalTasks);
      if (cmp != 0) return cmp;
      return a.repName.compareTo(b.repName);
    });

    return list;
  }

  String _getPeriodDescription(DateTimeRange range) {
    switch (_periodType) {
      case TaskPeriodType.daily:
        return DateFormat('EEEE, dd MMMM yyyy').format(range.start);
      case TaskPeriodType.weekly:
        return '${DateFormat('dd/MM/yyyy').format(range.start)} – ${DateFormat('dd/MM/yyyy').format(range.end)}';
      case TaskPeriodType.monthly:
        return DateFormat('MMMM yyyy').format(range.start);
      case TaskPeriodType.yearly:
        return 'Year ${DateFormat('yyyy').format(range.start)}';
      case TaskPeriodType.custom:
        return '${DateFormat('dd/MM/yyyy').format(range.start)} – ${DateFormat('dd/MM/yyyy').format(range.end)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _getDateRangeForPeriod();
    final summaries = _computeSummaries(range);

    final overallTotal = summaries.fold<int>(0, (sum, s) => sum + s.totalTasks);
    final overallCompleted =
        summaries.fold<int>(0, (sum, s) => sum + s.completedTasks);
    final overallPending = overallTotal - overallCompleted;
    final overallRate =
        overallTotal > 0 ? (overallCompleted / overallTotal) * 100.0 : 0.0;

    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _fetchAllData,
        color: _emerald,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
          children: [
            // Period Filter Tabs
            _buildPeriodFilterTabs(),
            const SizedBox(height: 10),

            // Period Navigation / Custom Date Selectors
            _buildPeriodDateControls(range),
            const SizedBox(height: 12),

            // Overview Metric Summary Cards
            _buildOverallMetricsBar(
              total: overallTotal,
              completed: overallCompleted,
              pending: overallPending,
              rate: overallRate,
            ),
            const SizedBox(height: 14),

            // Section Header & Search
            Row(
              children: [
                const Icon(Icons.people_alt_rounded, size: 18, color: _emeraldDark),
                const SizedBox(width: 8),
                const Text(
                  'Sales Rep Performance',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _darkText,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdminPdfReportsScreen(
                        initialReps: _reps,
                        initialTasks: _allTasks,
                        initialReportType: AdminReportType.performance,
                      ),
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 13, color: Color(0xFF7E22CE)),
                        SizedBox(width: 4),
                        Text('PDF Reports', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF7E22CE))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    '${summaries.length} Reps',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _emeraldDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: const InputDecoration(
                  icon: Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                  hintText: 'Search Sales Rep by name, email, or phone…',
                  hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Sales Rep Summary Cards List
            if (_loading && summaries.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: _emerald),
                ),
              )
            else if (summaries.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.assignment_turned_in_outlined,
                      size: 40,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No Reps Found',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No tasks were recorded for ${_getPeriodDescription(range)}.',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...summaries.map((s) => _buildSalesRepPerformanceCard(s, range)),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodFilterTabs() {
    final items = [
      {'type': TaskPeriodType.daily, 'label': 'Daily', 'icon': Icons.today_rounded},
      {'type': TaskPeriodType.weekly, 'label': 'Weekly', 'icon': Icons.view_week_rounded},
      {'type': TaskPeriodType.monthly, 'label': 'Monthly', 'icon': Icons.calendar_month_rounded},
      {'type': TaskPeriodType.yearly, 'label': 'Yearly', 'icon': Icons.date_range_rounded},
      {'type': TaskPeriodType.custom, 'label': 'Custom', 'icon': Icons.tune_rounded},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: items.map((item) {
          final type = item['type'] as TaskPeriodType;
          final isSelected = _periodType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _periodType = type);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item['icon'] as IconData,
                      size: 14,
                      color: isSelected ? Colors.white : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item['label'] as String,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPeriodDateControls(DateTimeRange range) {
    if (_periodType == TaskPeriodType.custom) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _customFromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => _customFromDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 13, color: _emeraldDark),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _customFromDate != null
                              ? DateFormat('dd/MM/yyyy').format(_customFromDate!)
                              : 'From Date',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _customToDate ?? _customFromDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => _customToDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded, size: 13, color: _emeraldDark),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          _customToDate != null
                              ? DateFormat('dd/MM/yyyy').format(_customToDate!)
                              : 'To Date',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_customFromDate != null || _customToDate != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _customFromDate = null;
                    _customToDate = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFFDC2626)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Daily / Weekly / Monthly / Yearly navigation bar
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20, color: _emeraldDark),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                switch (_periodType) {
                  case TaskPeriodType.daily:
                    _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    break;
                  case TaskPeriodType.weekly:
                    _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                    break;
                  case TaskPeriodType.monthly:
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
                    break;
                  case TaskPeriodType.yearly:
                    _selectedDate = DateTime(_selectedDate.year - 1, 1, 1);
                    break;
                  case TaskPeriodType.custom:
                    break;
                }
              });
            },
          ),
          const Spacer(),
          const Icon(Icons.date_range_rounded, size: 14, color: _emeraldDark),
          const SizedBox(width: 6),
          Text(
            _getPeriodDescription(range),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _darkText,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20, color: _emeraldDark),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                switch (_periodType) {
                  case TaskPeriodType.daily:
                    _selectedDate = _selectedDate.add(const Duration(days: 1));
                    break;
                  case TaskPeriodType.weekly:
                    _selectedDate = _selectedDate.add(const Duration(days: 7));
                    break;
                  case TaskPeriodType.monthly:
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
                    break;
                  case TaskPeriodType.yearly:
                    _selectedDate = DateTime(_selectedDate.year + 1, 1, 1);
                    break;
                  case TaskPeriodType.custom:
                    break;
                }
              });
            },
          ),
          if (_selectedDate.year != DateTime.now().year ||
              _selectedDate.month != DateTime.now().month ||
              _selectedDate.day != DateTime.now().day)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: GestureDetector(
                onTap: () => setState(() => _selectedDate = DateTime.now()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _emerald,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Today',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverallMetricsBar({
    required int total,
    required int completed,
    required int pending,
    required double rate,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  'Total Tasks',
                  '$total',
                  Icons.assignment_rounded,
                  const Color(0xFF0284C7),
                  const Color(0xFFE0F2FE),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricItem(
                  'Completed',
                  '$completed',
                  Icons.check_circle_rounded,
                  const Color(0xFF00A86B),
                  const Color(0xFFE8F5E9),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricItem(
                  'Pending',
                  '$pending',
                  Icons.pending_actions_rounded,
                  const Color(0xFFE65100),
                  const Color(0xFFFFF3E0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricItem(
                  'Success Rate',
                  '${rate.toStringAsFixed(0)}%',
                  Icons.pie_chart_rounded,
                  const Color(0xFF7C3AED),
                  const Color(0xFFF3E8FF),
                ),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate / 100.0,
                minHeight: 6,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation<Color>(_emerald),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricItem(
      String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSalesRepPerformanceCard(
      AdminSalesRepTaskSummary summary, DateTimeRange range) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: summary.totalTasks > 0 ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
          width: summary.totalTasks > 0 ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar, Name, Status, View Tasks Button
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: summary.isOnline ? _emerald : const Color(0xFFCBD5E1),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    summary.repName.isNotEmpty
                        ? summary.repName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: _emerald,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
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
                            summary.repName,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: _darkText,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: summary.isOnline ? _emerald : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    if (summary.repEmail.isNotEmpty)
                      Text(
                        summary.repEmail,
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showSalesRepDetailedTasksModal(summary, range),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _emerald,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.assignment_rounded, size: 14),
                label: Text(
                  'View Tasks (${summary.totalTasks})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // Row 2: Metrics Strip: Total | Completed | Pending | Completion Rate
          Row(
            children: [
              Expanded(
                child: _buildRepMiniMetric(
                  'Total',
                  '${summary.totalTasks}',
                  const Color(0xFF0F172A),
                  const Color(0xFFF8FAFC),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildRepMiniMetric(
                  'Completed',
                  '${summary.completedTasks}',
                  const Color(0xFF00A86B),
                  const Color(0xFFECFDF5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildRepMiniMetric(
                  'Pending',
                  '${summary.pendingTasks}',
                  const Color(0xFFE65100),
                  const Color(0xFFFFF3E0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildRepMiniMetric(
                  'Completion %',
                  '${summary.completionRate.toStringAsFixed(0)}%',
                  const Color(0xFF7C3AED),
                  const Color(0xFFF3E8FF),
                ),
              ),
            ],
          ),

          // Mini progress bar
          if (summary.totalTasks > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: summary.completionRate / 100.0,
                minHeight: 4,
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: AlwaysStoppedAnimation<Color>(
                  summary.completionRate >= 80
                      ? _emerald
                      : (summary.completionRate >= 50
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFEF4444)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRepMiniMetric(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  void _showSalesRepDetailedTasksModal(
      AdminSalesRepTaskSummary summary, DateTimeRange range) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String filterStatus = 'all';

        return StatefulBuilder(
          builder: (context, setModalState) {
            final tasks = summary.tasks;
            final completed = tasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').toList();
            final pending = tasks.where((t) => (t['status'] ?? '').toString().toLowerCase() != 'completed').toList();

            List<Map<String, dynamic>> displayedTasks = tasks;
            if (filterStatus == 'completed') {
              displayedTasks = completed;
            } else if (filterStatus == 'pending') {
              displayedTasks = pending;
            }

            return Container(
              margin: const EdgeInsets.only(top: 50),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Modal Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header: Sales Rep Name + Close
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
                          child: const Icon(Icons.assignment_ind_rounded, color: _emeraldDark, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sales Rep: ${summary.repName}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _darkText,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Period: ${_getPeriodDescription(range)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _emeraldDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
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

                  // Summary Strip: Total | Completed | Pending | Completion Rate
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _buildRepMiniMetric(
                                'Total',
                                '${summary.totalTasks}',
                                const Color(0xFF0F172A),
                                const Color(0xFFF8FAFC),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildRepMiniMetric(
                                'Completed',
                                '${summary.completedTasks}',
                                const Color(0xFF00A86B),
                                const Color(0xFFECFDF5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildRepMiniMetric(
                                'Pending',
                                '${summary.pendingTasks}',
                                const Color(0xFFE65100),
                                const Color(0xFFFFF3E0),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildRepMiniMetric(
                                'Completion %',
                                '${summary.completionRate.toStringAsFixed(0)}%',
                                const Color(0xFF7C3AED),
                                const Color(0xFFF3E8FF),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Filter Pills: All | Completed | Pending
                        Row(
                          children: [
                            _buildModalFilterChip(
                              label: 'All (${tasks.length})',
                              isSelected: filterStatus == 'all',
                              onTap: () => setModalState(() => filterStatus = 'all'),
                            ),
                            const SizedBox(width: 6),
                            _buildModalFilterChip(
                              label: 'Completed (${completed.length})',
                              isSelected: filterStatus == 'completed',
                              color: const Color(0xFF00A86B),
                              onTap: () => setModalState(() => filterStatus = 'completed'),
                            ),
                            const SizedBox(width: 6),
                            _buildModalFilterChip(
                              label: 'Pending (${pending.length})',
                              isSelected: filterStatus == 'pending',
                              color: const Color(0xFFE65100),
                              onTap: () => setModalState(() => filterStatus = 'pending'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Task List
                  Expanded(
                    child: displayedTasks.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.assignment_late_outlined, size: 44, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 10),
                                  Text(
                                    filterStatus == 'all'
                                        ? 'No tasks assigned to ${summary.repName} in this period.'
                                        : 'No $filterStatus tasks found.',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF64748B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(14),
                            itemCount: displayedTasks.length,
                            itemBuilder: (context, i) {
                              return _buildIndividualTaskCard(
                                task: displayedTasks[i],
                                repName: summary.repName,
                              );
                            },
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

  Widget _buildModalFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color color = _emerald,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFCBD5E1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildIndividualTaskCard({
    required Map<String, dynamic> task,
    required String repName,
  }) {
    final taskId = task['id'] ?? '';
    final doctor = task['doctor_name'] ?? 'N/A';
    final clinic = task['clinic_name'] ?? 'N/A';
    final clinicAddress = task['clinic_address'] ?? '';
    final sourceAddress = task['source_address'] ?? '';
    final status = (task['status'] ?? 'pending').toString().toLowerCase().trim();
    final isCompleted = status == 'completed';

    final deadline = (task['deadline_date_time'] ?? task['deadline'] ?? '').toString().trim();
    final perfStatus = (task['performance_status'] ?? '').toString().trim();
    final colorCategory = (task['color_category'] ?? '').toString().toLowerCase().trim();
    final lateBy = (task['late_by'] ?? '').toString().trim();
    final pointsEarned = (task['points_earned'] as num?)?.toInt() ?? 0;
    final totalDuration = (task['total_duration'] ?? '').toString().trim();

    final bool isGreen = colorCategory == 'green' || perfStatus.contains('GREAT') || perfStatus.contains('ON TIME') || perfStatus.contains('ON TRACK');
    final bool isRed = colorCategory == 'red' || perfStatus.contains('BAD') || perfStatus.contains('LATE') || perfStatus.contains('OVERDUE');

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

    final displayPerf = perfStatus.isNotEmpty
        ? perfStatus
        : (isCompleted ? 'ON TIME' : 'PENDING');

    // Date
    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    final createdAt = (task['created_at'] ?? '').toString().trim();
    final checkoutDateTime = (task['checkout_datetime'] ?? '').toString().trim();
    final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();

    String taskDateDisplay = checkoutDate.isNotEmpty
        ? checkoutDate
        : (checkoutDateTime.isNotEmpty && checkoutDateTime.length >= 10
            ? checkoutDateTime.substring(0, 10)
            : (createdAt.length >= 10 ? createdAt.substring(0, 10) : '—'));

    // Checkout Time & Date
    final checkoutTime = (task['checkout_time'] ?? '').toString().trim();
    String checkoutDateTimeDisplay = '—';
    if (isCompleted) {
      if (checkoutDateTime.isNotEmpty) {
        checkoutDateTimeDisplay = checkoutDateTime;
      } else if (checkedOutAt.isNotEmpty) {
        checkoutDateTimeDisplay = checkedOutAt;
      } else if (checkoutDate.isNotEmpty && checkoutTime.isNotEmpty) {
        checkoutDateTimeDisplay = '$checkoutDate $checkoutTime';
      } else if (checkoutDate.isNotEmpty) {
        checkoutDateTimeDisplay = checkoutDate;
      } else if (checkoutTime.isNotEmpty) {
        checkoutDateTimeDisplay = checkoutTime;
      }
    }

    // Checkout Mode
    final rawCheckoutType = (task['checkout_type'] ?? task['checkout_mode'] ?? '').toString().trim().toUpperCase();
    final checkoutMode = isCompleted
        ? (rawCheckoutType.isNotEmpty ? rawCheckoutType : 'ONLINE')
        : '—';

    // Notes
    final notes = (task['notes'] ?? task['task_notes'] ?? '').toString().trim();
    final noteDisplay = notes.isNotEmpty ? notes : '—';

    // Checkout Location
    final lat = task['checkout_latitude'] ?? task['checkout_lat'] ?? task['lat'];
    final lng = task['checkout_longitude'] ?? task['checkout_lng'] ?? task['lng'];
    final locAddress = (task['checkout_address'] ?? task['checkout_location_name'] ?? '').toString().trim();

    String locationDisplay = '—';
    if (isCompleted) {
      if (lat != null && lng != null) {
        final latD = (lat as num).toDouble();
        final lngD = (lng as num).toDouble();
        locationDisplay = '${latD.toStringAsFixed(5)}, ${lngD.toStringAsFixed(5)}';
        if (locAddress.isNotEmpty) {
          locationDisplay += ' ($locAddress)';
        }
      } else if (locAddress.isNotEmpty) {
        locationDisplay = locAddress;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFFD8A8),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: ID, Date, Status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '#$taskId',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
              const SizedBox(width: 4),
              Text(
                'Task Date: $taskDateDisplay',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
              const Spacer(),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFFD8A8),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCompleted ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      size: 12,
                      color: isCompleted ? const Color(0xFF00A86B) : const Color(0xFFE65100),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isCompleted ? 'COMPLETED' : 'PENDING',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isCompleted ? const Color(0xFF00A86B) : const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Performance Evaluation Badge & Points
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeBorder),
            ),
            child: Row(
              children: [
                Icon(badgeIcon, size: 14, color: badgeText),
                const SizedBox(width: 6),
                Text(
                  displayPerf,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: badgeText,
                  ),
                ),
                const Spacer(),
                if (lateBy.isNotEmpty) ...[
                  Text(
                    'Late: $lateBy',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    pointsEarned > 0 ? '+$pointsEarned pts' : (pointsEarned < 0 ? '$pointsEarned pts' : '0 pts'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: pointsEarned > 0 ? const Color(0xFF059669) : (pointsEarned < 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Deadline & Duration row
          if (deadline.isNotEmpty || totalDuration.isNotEmpty) ...[
            Row(
              children: [
                if (deadline.isNotEmpty)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFD1FAE5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_rounded, size: 12, color: Color(0xFF047857)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Due: $deadline',
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (deadline.isNotEmpty && totalDuration.isNotEmpty)
                  const SizedBox(width: 6),
                if (totalDuration.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(
                          'Duration: $totalDuration',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Doctor & Clinic
          Row(
            children: [
              const Icon(Icons.local_hospital_rounded, size: 16, color: _emerald),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Dr. $doctor • $clinic',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Source & Destination Card
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.my_location_rounded, size: 13, color: Color(0xFF0284C7)),
                    const SizedBox(width: 6),
                    const Text('Source: ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                    Expanded(
                      child: Text(
                        sourceAddress.isNotEmpty ? sourceAddress : 'Sales Rep Start Location',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 13, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    const Text('Destination: ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
                    Expanded(
                      child: Text(
                        clinicAddress.isNotEmpty ? clinicAddress : clinic,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Task Note
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD1FAE5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes_rounded, size: 13, color: Color(0xFF047857)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Note: $noteDisplay',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: notes.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      color: notes.isNotEmpty ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Checkout Mode & Checkout Date/Time & Location
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Checkout Mode: ',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                    ),
                    if (!isCompleted)
                      const Text('—', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)))
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: checkoutMode.contains('OFFLINE')
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          checkoutMode,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: checkoutMode.contains('OFFLINE')
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF0284C7),
                          ),
                        ),
                      ),
                    const Spacer(),
                    const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFF64748B)),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        'Checkout: $checkoutDateTimeDisplay',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                          color: isCompleted ? const Color(0xFF334155) : const Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (isCompleted && locationDisplay != '—') ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.pin_drop_rounded, size: 11, color: Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      const Text('Checkout Location: ',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                      Expanded(
                        child: Text(
                          locationDisplay,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF334155)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (isCompleted && ((task['completion_result'] ?? '').toString().isNotEmpty || (task['overtime_reason'] ?? '').toString().isNotEmpty)) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: task['completion_result'] == 'within_target'
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: task['completion_result'] == 'within_target'
                            ? const Color(0xFFA7F3D0)
                            : const Color(0xFFFED7AA),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              task['completion_result'] == 'within_target'
                                  ? Icons.check_circle_rounded
                                  : Icons.timer_outlined,
                              size: 13,
                              color: task['completion_result'] == 'within_target'
                                  ? const Color(0xFF047857)
                                  : const Color(0xFFC2410C),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              task['completion_result'] == 'within_target'
                                  ? 'TARGET: WITHIN 5 MIN'
                                  : 'TARGET: OVERTIME',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: task['completion_result'] == 'within_target'
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFC2410C),
                              ),
                            ),
                          ],
                        ),
                        if ((task['overtime_reason'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reason: ',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9A3412),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  task['overtime_reason'].toString(),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: Color(0xFF7C2D12),
                                  ),
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
          ),
          const SizedBox(height: 8),

          // Verify Map Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => TaskMapVerificationModal.show(context, task),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF047857),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              icon: const Icon(Icons.verified_outlined, size: 15),
              label: const Text(
                'Verify Map',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

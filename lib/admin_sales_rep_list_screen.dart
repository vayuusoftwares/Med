import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'admin_live_tracking_screen.dart';
import 'admin_attendance_history_screen.dart';
import 'admin_task_performance_screen.dart';
import 'admin_pdf_reports_screen.dart';
import 'app_config.dart';
import 'services/auth_service.dart';
import 'widgets/task_map_verification_modal.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class _SalesRep {
  final int id;
  final String name;
  final String email;
  final String phone;
  final bool isActive;
  final String createdAt;
  final double? lastLat;
  final double? lastLng;
  final double? lastAccuracy;
  final String? lastPingAt;
  final bool isOnline;
  final int performanceScore;
  final int greenCount;
  final int redCount;
  final int overdueCount;
  final double onTimePct;

  const _SalesRep({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.isActive,
    required this.createdAt,
    this.lastLat,
    this.lastLng,
    this.lastAccuracy,
    this.lastPingAt,
    required this.isOnline,
    this.performanceScore = 0,
    this.greenCount = 0,
    this.redCount = 0,
    this.overdueCount = 0,
    this.onTimePct = 0.0,
  });

  factory _SalesRep.fromJson(Map<String, dynamic> j) => _SalesRep(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        email: j['email'] as String,
        phone: j['phone'] as String,
        isActive: j['is_active'] == true,
        createdAt: j['created_at'] as String,
        lastLat: j['last_lat'] != null ? (j['last_lat'] as num).toDouble() : null,
        lastLng: j['last_lng'] != null ? (j['last_lng'] as num).toDouble() : null,
        lastAccuracy: j['last_accuracy'] != null ? (j['last_accuracy'] as num).toDouble() : null,
        lastPingAt: j['last_ping_at'] as String?,
        isOnline: j['is_online'] == true,
        performanceScore: (j['performance_score'] as num?)?.toInt() ?? 0,
        greenCount: (j['green_count'] as num?)?.toInt() ?? 0,
        redCount: (j['red_count'] as num?)?.toInt() ?? 0,
        overdueCount: (j['overdue_count'] as num?)?.toInt() ?? 0,
        onTimePct: (j['on_time_pct'] as num?)?.toDouble() ?? 0.0,
      );
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class AdminSalesRepListScreen extends StatefulWidget {
  const AdminSalesRepListScreen({super.key});

  @override
  State<AdminSalesRepListScreen> createState() => _AdminSalesRepListScreenState();
}

class _AdminSalesRepListScreenState extends State<AdminSalesRepListScreen> {
  static const _emerald     = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _darkText    = Color(0xFF1B4332);

  List<_SalesRep> _reps = [];
  List<Map<String, dynamic>> _allTasks = [];
  String _selectedRepFilter = 'All Sales Reps';
  bool _loading = true;
  String _error = '';
  Timer? _refreshTimer;

  // Date Range Filter
  DateTime? _mainFromDate;
  DateTime? _mainToDate;
  DateTime? _appliedFromDate;
  DateTime? _appliedToDate;
  bool _loadingTasks = false;

  List<_SalesRep> get _filteredReps {
    if (_selectedRepFilter == 'All Sales Reps') {
      return _reps;
    }
    final filtered = _reps.where((r) => r.name.toLowerCase() == _selectedRepFilter.toLowerCase()).toList();
    return filtered.isNotEmpty ? filtered : _reps;
  }

  @override
  void initState() {
    super.initState();
    _fetchReps();
    _fetchTasks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _fetchReps();
      _fetchTasks();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTasks({DateTime? fromDate, DateTime? toDate}) async {
    final useFrom = fromDate ?? _appliedFromDate;
    final useTo = toDate ?? _appliedToDate;

    String query = '?all=1';
    if (useFrom != null) {
      query += '&from_date=${DateFormat('yyyy-MM-dd').format(useFrom)}';
    }
    if (useTo != null) {
      query += '&to_date=${DateFormat('yyyy-MM-dd').format(useTo)}';
    }

    if (mounted) setState(() => _loadingTasks = true);

    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base/backend/get_user_tasks.php$query');
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = AppConfig.safeJsonDecode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            AppConfig.setWorkingHost(base);
            final rawList = data['tasks'] as List? ?? [];
            final list = rawList.cast<Map<String, dynamic>>();
            if (mounted) {
              setState(() {
                _allTasks = list;
                _loadingTasks = false;
              });
            }
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loadingTasks = false);
  }

  Future<void> _fetchReps() async {
    final relativePath = '/backend/get_all_sales_reps.php';
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$relativePath');
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = AppConfig.safeJsonDecode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            AppConfig.setWorkingHost(base);
            final list = (data['reps'] as List? ?? [])
                .map((e) => _SalesRep.fromJson(e as Map<String, dynamic>))
                .toList();
            if (mounted) {
              setState(() {
                _reps = list;
                _loading = false;
                _error = '';
              });
            }
            return; // success — stop trying hosts
          }
        }
      } catch (e) {
        debugPrint('[SalesRepList] Error from $base: $e');
      }
    }

    if (mounted && _reps.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Could not reach server. Retrying…';
      });
    }
  }

  // ─── Step 3: Admin Registration of New Sales Rep/MR ───────────────────────
  void _showRegisterSalesRepDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool obscurePassword = true;
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildField({
              required TextEditingController controller,
              required String hint,
              required IconData icon,
              TextInputType keyboardType = TextInputType.text,
              bool obscure = false,
              Widget? suffix,
              String? Function(String?)? validator,
            }) {
              return TextFormField(
                controller: controller,
                keyboardType: keyboardType,
                obscureText: obscure,
                validator: validator,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  prefixIcon: Icon(icon, size: 20, color: _emeraldDark),
                  suffixIcon: suffix,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _emerald, width: 1.8),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEF4444)),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
                  ),
                  errorStyle: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              );
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Icon(Icons.person_add_alt_1_rounded, color: _emeraldDark, size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Register Sales Rep',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Add a new Representative to the field team',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF94A3B8)),
                              onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Form
                        Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 1. Sales Rep Name
                              buildField(
                                controller: nameCtrl,
                                hint: 'Sales Rep Full Name',
                                icon: Icons.person_outline_rounded,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter Sales Rep Name' : null,
                              ),
                              const SizedBox(height: 12),
                              // 2. Email
                              buildField(
                                controller: emailCtrl,
                                hint: 'Email Address',
                                icon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Please enter email';
                                  if (!v.contains('@') || !v.contains('.')) return 'Please enter a valid email';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              // 3. Password
                              buildField(
                                controller: passwordCtrl,
                                hint: 'Password (min. 6 chars)',
                                icon: Icons.lock_outline_rounded,
                                obscure: obscurePassword,
                                suffix: IconButton(
                                  icon: Icon(
                                    obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                    size: 20,
                                    color: const Color(0xFF94A3B8),
                                  ),
                                  onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Please enter password';
                                  if (v.trim().length < 6) return 'Password must be at least 6 characters';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              // 4. Mobile Number
                              buildField(
                                controller: phoneCtrl,
                                hint: 'Mobile Number',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter mobile number' : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        if (!formKey.currentState!.validate()) return;
                                        setDialogState(() => isSubmitting = true);

                                        final messenger = ScaffoldMessenger.of(context);
                                        final dialogMessenger = ScaffoldMessenger.of(dialogCtx);
                                        final nav = Navigator.of(dialogCtx);
                                        final authService = AuthService();
                                        final res = await authService.wampRegister(
                                          name: nameCtrl.text.trim(),
                                          email: emailCtrl.text.trim(),
                                          phone: phoneCtrl.text.trim(),
                                          password: passwordCtrl.text,
                                          role: 'sales_rep',
                                        );

                                        setDialogState(() => isSubmitting = false);

                                        if (res.success) {
                                          if (mounted) {
                                            nav.pop();
                                            _fetchReps();
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text('Sales Representative "${nameCtrl.text.trim()}" registered successfully!'),
                                                backgroundColor: _emerald,
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            );
                                          }
                                        } else {
                                          if (mounted) {
                                            dialogMessenger.showSnackBar(
                                              SnackBar(
                                                content: Text(res.message),
                                                backgroundColor: const Color(0xFFDC2626),
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(0, 46),
                                  backgroundColor: _emerald,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: isSubmitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text(
                                        'Register',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRegisterSalesRepDialog(context),
        backgroundColor: _emerald,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_rounded),
        label: const Text('Register Sales Rep', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          _buildTopBar(context),
          _buildDateRangeFilterBar(context),
          if (_loading && _reps.isEmpty)
            const Expanded(
              child: Center(child: CircularProgressIndicator(color: _emerald)),
            )
          else if (_error.isNotEmpty && _reps.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(_error, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchReps,
                      style: ElevatedButton.styleFrom(backgroundColor: _emerald),
                      child: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await Future.wait([_fetchReps(), _fetchTasks()]);
                },
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: _filteredReps.length,
                  itemBuilder: (context, i) => _buildRepCard(_filteredReps[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _datePickerTheme(Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: _emerald,
          onPrimary: Colors.white,
          onSurface: _darkText,
        ),
      ),
      child: child!,
    );
  }

  Widget _buildDatePickerButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: hasDate ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasDate ? _emerald : const Color(0xFFCBD5E1),
            width: hasDate ? 1.3 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: hasDate ? _emeraldDark : const Color(0xFF64748B),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                hasDate ? DateFormat('dd/MM/yyyy').format(date) : label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: hasDate ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasDate && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Icon(Icons.close_rounded, size: 13, color: Color(0xFF64748B)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyFilterButton() {
    return ElevatedButton(
      onPressed: () {
        if (_mainFromDate != null && _mainToDate != null && _mainFromDate!.isAfter(_mainToDate!)) {
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

        if (_mainFromDate == null && _mainToDate == null) {
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
          _appliedFromDate = _mainFromDate;
          _appliedToDate = _mainToDate;
        });
        _fetchTasks(fromDate: _mainFromDate, toDate: _mainToDate);
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: _emerald,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: _loadingTasks
          ? const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, size: 14),
                SizedBox(width: 4),
                Text('Apply / Search', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
    );
  }

  Widget _buildDateRangeFilterBar(BuildContext context) {
    final isFiltered = _appliedFromDate != null || _appliedToDate != null;
    final hasSelection = _mainFromDate != null || _mainToDate != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFiltered ? _emerald.withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
          width: isFiltered ? 1.5 : 1.0,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.date_range_rounded, size: 14, color: _emeraldDark),
              ),
              const SizedBox(width: 6),
              const Text(
                'Filter by Date Range',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _darkText,
                ),
              ),
              if (isFiltered) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Text(
                    '${_allTasks.length} task${_allTasks.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _emeraldDark),
                  ),
                ),
              ],
              const Spacer(),
              if (isFiltered || hasSelection)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _mainFromDate = null;
                      _mainToDate = null;
                      _appliedFromDate = null;
                      _appliedToDate = null;
                    });
                    _fetchTasks();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_rounded, size: 11, color: Color(0xFFDC2626)),
                        SizedBox(width: 2),
                        Text(
                          'Reset Filter',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildDatePickerButton(
                  label: 'From Date',
                  date: _mainFromDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _mainFromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (context, child) => _datePickerTheme(child),
                    );
                    if (picked != null) {
                      setState(() => _mainFromDate = picked);
                    }
                  },
                  onClear: _mainFromDate != null ? () => setState(() => _mainFromDate = null) : null,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildDatePickerButton(
                  label: 'To Date',
                  date: _mainToDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _mainToDate ?? _mainFromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (context, child) => _datePickerTheme(child),
                    );
                    if (picked != null) {
                      setState(() => _mainToDate = picked);
                    }
                  },
                  onClear: _mainToDate != null ? () => setState(() => _mainToDate = null) : null,
                ),
              ),
              const SizedBox(width: 6),
              _buildApplyFilterButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final canPop = Navigator.canPop(context);

    final dropdownWidget = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(12),
          elevation: 4,
          value: (_selectedRepFilter == 'All Sales Reps' || _reps.any((r) => r.name == _selectedRepFilter))
              ? _selectedRepFilter
              : 'All Sales Reps',
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _emeraldDark, size: 20),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
          onChanged: (String? newValue) {
            setState(() {
              _selectedRepFilter = newValue ?? 'All Sales Reps';
            });
          },
          items: [
            DropdownMenuItem<String>(
              value: 'All Sales Reps',
              child: Row(
                children: [
                  const Icon(Icons.people_alt_rounded, size: 16, color: _emeraldDark),
                  const SizedBox(width: 8),
                  Text(
                    'All Sales Representatives (${_reps.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                  ),
                ],
              ),
            ),
            ..._reps.map((rep) => DropdownMenuItem<String>(
                  value: rep.name,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rep.isOnline ? _emerald : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        rep.name,
                        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rep.isOnline ? '(Online)' : '(Offline)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: rep.isOnline ? _emeraldDark : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );

    final performanceChip = GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminTaskPerformanceScreen(
            initialTasks: _allTasks,
            initialReps: _reps.map((r) => {
              'id': r.id,
              'name': r.name,
              'email': r.email,
              'phone': r.phone,
              'is_online': r.isOnline,
            }).toList(),
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F2FE),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBAE6FD)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 14, color: Color(0xFF0284C7)),
            SizedBox(width: 5),
            Text('Performance', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF0284C7))),
          ],
        ),
      ),
    );

    final pdfReportsChip = GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminPdfReportsScreen(
            initialReps: _reps.map((r) => {
              'id': r.id,
              'name': r.name,
              'email': r.email,
              'phone': r.phone,
              'is_online': r.isOnline,
            }).toList(),
            initialTasks: _allTasks,
          ),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF3E8FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE9D5FF)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_rounded, size: 14, color: Color(0xFF7E22CE)),
            SizedBox(width: 5),
            Text('PDF Reports', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7E22CE))),
          ],
        ),
      ),
    );

    final historyMapChip = GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const AdminAttendanceHistoryScreen(),
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_rounded, size: 14, color: _emeraldDark),
            SizedBox(width: 5),
            Text('History Map', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _emeraldDark)),
          ],
        ),
      ),
    );

    final refreshButton = GestureDetector(
      onTap: () {
        setState(() => _loading = true);
        _fetchReps();
      },
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: const Icon(Icons.refresh_rounded, size: 17, color: _emeraldDark),
      ),
    );

    final registerRepButton = GestureDetector(
      onTap: () => _showRegisterSalesRepDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _emerald,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_add_rounded, size: 15, color: Colors.white),
            SizedBox(width: 5),
            Text('Register Rep', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Header + Count badge + Quick actions
          Row(
            children: [
              if (canPop) ...[
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: _emeraldDark),
                  ),
                ),
              ],
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: _emerald, shape: BoxShape.circle),
                child: const Icon(Icons.people_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sales Representatives',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _darkText)),
                    Text(
                      _selectedRepFilter == 'All Sales Reps'
                          ? '${_reps.length} total active'
                          : 'Filtered: $_selectedRepFilter',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              registerRepButton,
              const SizedBox(width: 6),
              refreshButton,
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Spacious Dropdown Selector
          dropdownWidget,
          const SizedBox(height: 8),

          // Row 3: Horizontal Scrollable Action Chips (Smooth, no text clipping)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                performanceChip,
                const SizedBox(width: 8),
                pdfReportsChip,
                const SizedBox(width: 8),
                historyMapChip,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepCard(_SalesRep rep) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2F0E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: Name + Active status + Tracking button ──
          Row(
            children: [
              // Avatar
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _emerald.withValues(alpha: 0.4), width: 2),
                ),
                child: Center(
                  child: Text(
                    rep.name.isNotEmpty ? rep.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: _emerald, fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(rep.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _darkText)),
                        ),
                        // About/Info button
                        GestureDetector(
                          onTap: () => _showRepDetails(rep),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD1FAE5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.info_outline_rounded,
                                size: 16, color: _emeraldDark),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: rep.isOnline ? _emerald : const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          rep.isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: rep.isOnline ? _emerald : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Tracking button
              if (rep.lastLat != null && rep.lastLng != null)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AdminLiveTrackingScreen(
                        initialRepId: rep.id,
                        initialRepName: rep.name,
                      ),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _emerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: const Text('Track',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('No GPS',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFE2F0E8)),
          const SizedBox(height: 12),
          // ── Bio details (horizontal row) ──
          Row(
            children: [
              Expanded(
                child: _buildBioItem(Icons.email_outlined, 'Email', rep.email),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBioItem(Icons.phone_outlined, 'Phone',
                    rep.phone.isNotEmpty ? rep.phone : 'N/A'),
              ),
            ],
          ),
          if (rep.lastPingAt != null) ...[
            const SizedBox(height: 10),
            _buildBioItem(
              Icons.access_time_rounded,
              'Last Seen',
              _formatLastSeen(rep.lastPingAt!),
            ),
          ],
          const SizedBox(height: 12),
          // ── Task Statistics & Actions ──
          () {
            final repTasks = _allTasks.where((t) {
              final uid = (t['user_id'] as num?)?.toInt();
              final rname = (t['sales_rep_name'] ?? '').toString().trim().toLowerCase();
              return (uid != null && uid == rep.id) || (rname.isNotEmpty && rname == rep.name.trim().toLowerCase());
            }).toList();
            final totalCount = repTasks.length;
            final pendingCount = repTasks.where((t) => (t['status'] ?? 'pending').toString().toLowerCase() != 'completed').length;
            final completedCount = repTasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').length;

            return Column(
              children: [
                // Summary Metrics Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _buildMiniCountBadge('Total Tasks', '$totalCount', const Color(0xFF0284C7), const Color(0xFFE0F2FE))),
                      const SizedBox(width: 6),
                      Expanded(child: _buildMiniCountBadge('Pending', '$pendingCount', const Color(0xFFE65100), const Color(0xFFFFF3E0))),
                      const SizedBox(width: 6),
                      Expanded(child: _buildMiniCountBadge('Completed', '$completedCount', const Color(0xFF00A86B), const Color(0xFFD1FAE5))),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Performance & Points Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD1FAE5)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniCountBadge(
                          'Score / 100',
                          '${rep.performanceScore}',
                          const Color(0xFF047857),
                          const Color(0xFFDCFCE7),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _buildMiniCountBadge(
                          'Green (On Time)',
                          '${rep.greenCount}',
                          const Color(0xFF059669),
                          const Color(0xFFD1FAE5),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _buildMiniCountBadge(
                          'Red / Late',
                          '${rep.redCount + rep.overdueCount}',
                          const Color(0xFFDC2626),
                          const Color(0xFFFEE2E2),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: _buildMiniCountBadge(
                          'On-Time %',
                          '${rep.onTimePct.toStringAsFixed(0)}%',
                          const Color(0xFF7C3AED),
                          const Color(0xFFF3E8FF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        onPressed: () => _showSalesRepTasksModal(context, rep, repTasks),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _emerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.assignment_rounded, size: 14),
                        label: Text(
                          'Tasks ($totalCount)',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminAttendanceHistoryScreen(
                              initialUserId: rep.id,
                              initialRepName: rep.name,
                            ),
                          ));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _emeraldDark,
                          side: const BorderSide(color: Color(0xFFA7F3D0), width: 1.2),
                          backgroundColor: const Color(0xFFECFDF5),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.history_rounded, size: 14),
                        label: const Text(
                          'History',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      flex: 4,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AdminPdfReportsScreen(
                              initialRepId: rep.id,
                              initialRepName: rep.name,
                              initialTasks: _allTasks,
                            ),
                          ));
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7E22CE),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 1,
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
                        label: const Text(
                          'Report',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }(),
        ],
      ),
    );
  }

  Widget _buildMiniCountBadge(String label, String count, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(count, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 1),
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center, maxLines: 1),
        ],
      ),
    );
  }

  void _showSalesRepTasksModal(BuildContext context, _SalesRep rep, List<Map<String, dynamic>> tasks) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        DateTime? modalFromDate = _appliedFromDate;
        DateTime? modalToDate = _appliedToDate;
        return StatefulBuilder(
          builder: (context, setModalState) {
            bool matchesDateRange(Map<String, dynamic> t) {
              if (modalFromDate == null && modalToDate == null) return true;

              final checkoutDate = (t['checkout_date'] ?? '').toString().trim();
              final createdAt = (t['created_at'] ?? '').toString().trim();
              final updatedAt = (t['updated_at'] ?? '').toString().trim();
              final checkedOutAt = (t['checked_out_at'] ?? '').toString().trim();

              String rawDate = '';
              if (checkoutDate.isNotEmpty && checkoutDate.length >= 10) {
                rawDate = checkoutDate.substring(0, 10);
              } else if (createdAt.isNotEmpty && createdAt.length >= 10) {
                rawDate = createdAt.substring(0, 10);
              } else if (checkedOutAt.isNotEmpty && checkedOutAt.length >= 10) {
                rawDate = checkedOutAt.substring(0, 10);
              } else if (updatedAt.isNotEmpty && updatedAt.length >= 10) {
                rawDate = updatedAt.substring(0, 10);
              }

              if (rawDate.isEmpty) return false;

              DateTime? taskDt;
              try {
                if (rawDate.contains('/')) {
                  final parts = rawDate.split('/');
                  if (parts.length == 3) {
                    if (parts[0].length == 4) {
                      taskDt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                    } else {
                      taskDt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                    }
                  }
                } else if (rawDate.contains('-')) {
                  final parts = rawDate.split('-');
                  if (parts.length == 3) {
                    if (parts[0].length == 4) {
                      taskDt = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                    } else {
                      taskDt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                    }
                  }
                }
              } catch (_) {}

              if (taskDt == null) {
                final fromStr = modalFromDate != null ? DateFormat('yyyy-MM-dd').format(modalFromDate!) : null;
                final toStr = modalToDate != null ? DateFormat('yyyy-MM-dd').format(modalToDate!) : null;
                if (fromStr != null && toStr != null) {
                  return rawDate.compareTo(fromStr) >= 0 && rawDate.compareTo(toStr) <= 0;
                } else if (fromStr != null) {
                  return rawDate.compareTo(fromStr) >= 0;
                } else if (toStr != null) {
                  return rawDate.compareTo(toStr) <= 0;
                }
                return true;
              }

              final taskDay = DateTime(taskDt.year, taskDt.month, taskDt.day);
              if (modalFromDate != null && modalToDate != null) {
                final fromDay = DateTime(modalFromDate!.year, modalFromDate!.month, modalFromDate!.day);
                final toDay = DateTime(modalToDate!.year, modalToDate!.month, modalToDate!.day);
                return !taskDay.isBefore(fromDay) && !taskDay.isAfter(toDay);
              } else if (modalFromDate != null) {
                final fromDay = DateTime(modalFromDate!.year, modalFromDate!.month, modalFromDate!.day);
                return !taskDay.isBefore(fromDay);
              } else if (modalToDate != null) {
                final toDay = DateTime(modalToDate!.year, modalToDate!.month, modalToDate!.day);
                return !taskDay.isAfter(toDay);
              }
              return true;
            }

            final filteredTasks = tasks.where(matchesDateRange).toList();
            final pendingTasks = filteredTasks.where((t) => (t['status'] ?? 'pending').toString().toLowerCase() != 'completed').toList();
            final completedTasks = filteredTasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').toList();

            return Container(
              margin: const EdgeInsets.only(top: 60),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header with Sales Rep info and close button
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 16, 14),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(color: Color(0xFFD1FAE5), shape: BoxShape.circle),
                          child: const Icon(Icons.assignment_rounded, color: _emeraldDark, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${rep.name} — Tasks',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Rep ID #${rep.id} • ${rep.email}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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

                  // Filter & Metrics Bar
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Filter by Date Range:',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _darkText),
                            ),
                            const Spacer(),
                            if (modalFromDate != null || modalToDate != null)
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    modalFromDate = null;
                                    modalToDate = null;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF2F2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFFECACA)),
                                  ),
                                  child: const Text(
                                    'Clear',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: modalFromDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                    builder: (context, child) => _datePickerTheme(child),
                                  );
                                  if (picked != null) {
                                    setModalState(() => modalFromDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: modalFromDate != null ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: modalFromDate != null ? _emerald : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 12, color: modalFromDate != null ? _emeraldDark : const Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          modalFromDate != null ? 'From: ${DateFormat('dd/MM/yyyy').format(modalFromDate!)}' : 'From Date',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: modalFromDate != null ? _emeraldDark : const Color(0xFF64748B),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (modalFromDate != null)
                                        GestureDetector(
                                          onTap: () => setModalState(() => modalFromDate = null),
                                          child: const Icon(Icons.close_rounded, size: 13, color: _emeraldDark),
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
                                    initialDate: modalToDate ?? modalFromDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                    builder: (context, child) => _datePickerTheme(child),
                                  );
                                  if (picked != null) {
                                    setModalState(() => modalToDate = picked);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: modalToDate != null ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: modalToDate != null ? _emerald : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.event_available_rounded, size: 12, color: modalToDate != null ? _emeraldDark : const Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          modalToDate != null ? 'To: ${DateFormat('dd/MM/yyyy').format(modalToDate!)}' : 'To Date',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: modalToDate != null ? _emeraldDark : const Color(0xFF64748B),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (modalToDate != null)
                                        GestureDetector(
                                          onTap: () => setModalState(() => modalToDate = null),
                                          child: const Icon(Icons.close_rounded, size: 13, color: _emeraldDark),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Dynamic Metrics Pills
                        Row(
                          children: [
                            Expanded(child: _buildMiniCountBadge('Total Tasks', '${filteredTasks.length}', const Color(0xFF0284C7), const Color(0xFFE0F2FE))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMiniCountBadge('Pending', '${pendingTasks.length}', const Color(0xFFE65100), const Color(0xFFFFF3E0))),
                            const SizedBox(width: 8),
                            Expanded(child: _buildMiniCountBadge('Completed', '${completedTasks.length}', const Color(0xFF00A86B), const Color(0xFFE8F5E9))),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Tasks List Content
                  Expanded(
                    child: filteredTasks.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.assignment_outlined, size: 48, color: Color(0xFF94A3B8)),
                                  const SizedBox(height: 12),
                                  Text(
                                    modalFromDate != null && modalToDate != null
                                        ? 'No tasks found from ${DateFormat('dd/MM/yyyy').format(modalFromDate!)} to ${DateFormat('dd/MM/yyyy').format(modalToDate!)}'
                                        : (modalFromDate != null
                                            ? 'No tasks found from ${DateFormat('dd/MM/yyyy').format(modalFromDate!)} onwards'
                                            : (modalToDate != null
                                                ? 'No tasks found up to ${DateFormat('dd/MM/yyyy').format(modalToDate!)}'
                                                : 'No tasks found for this Sales Representative.')),
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredTasks.length,
                            itemBuilder: (context, i) {
                              final task = filteredTasks[i];
                              final taskId = task['id'] ?? '';
                              final doctor = task['doctor_name'] ?? 'N/A';
                              final clinic = task['clinic_name'] ?? 'N/A';
                              final area = (task['area'] ?? '').toString().trim();
                              final clinicAddress = task['clinic_address'] ?? '';
                              final sourceAddress = task['source_address'] ?? '';
                              final status = (task['status'] ?? 'pending').toString().toLowerCase();
                              final isCompleted = status == 'completed';
                              final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
                              final createdAt = (task['created_at'] ?? '').toString().trim();
                              final taskDate = checkoutDate.isNotEmpty
                                  ? checkoutDate
                                  : (createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt);
                              final checkoutTime = (task['checkout_time'] ?? '').toString().trim();
                              final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();
                              final compTime = isCompleted
                                  ? (checkoutTime.isNotEmpty
                                      ? checkoutTime
                                      : (checkedOutAt.length >= 11 ? checkedOutAt.substring(11) : '—'))
                                  : '—';

                              final checkoutType = (task['checkout_type'] ?? 'ONLINE').toString().toUpperCase().trim();
                              final isOffline = checkoutType.contains('OFFLINE');
                              final notes = (task['notes'] ?? '').toString().trim();
                              final noteDisplay = notes.isNotEmpty ? notes : '—';
                              final repName = (task['sales_rep_name'] ?? '').toString().trim().isNotEmpty
                                  ? task['sales_rep_name'].toString().trim()
                                  : rep.name;

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
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
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
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (taskDate.isNotEmpty)
                                          Row(
                                            children: [
                                              const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                                              const SizedBox(width: 4),
                                              Text(
                                                taskDate,
                                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                                              ),
                                            ],
                                          ),
                                        const Spacer(),
                                        // Status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isCompleted ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: isCompleted ? const Color(0xFFA7F3D0) : const Color(0xFFFFD8A8)),
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

                                    // Row: Sales Rep & Note
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
                                    const SizedBox(height: 10),

                                    // Row 2: Doctor & Clinic
                                    if (area.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                        margin: const EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEFF6FF),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(color: const Color(0xFFBFDBFE)),
                                        ),
                                        child: Text(
                                          'AREA: ${area.toUpperCase()}',
                                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                                        ),
                                      ),
                                    ],
                                    Row(
                                      children: [
                                        const Icon(Icons.local_hospital_rounded, size: 16, color: _emerald),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Dr. $doctor • $clinic',
                                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _darkText),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),

                                    // Source & Destination
                                    Container(
                                      padding: const EdgeInsets.all(10),
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
                                              const Text('Source: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
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
                                              const Text('Destination: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
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
                                    const SizedBox(height: 10),

                                    // Row 3: Checkout Mode & Completion Time
                                    Row(
                                      children: [
                                        // Checkout Mode
                                        const Text(
                                          'Checkout Mode: ',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                        ),
                                        if (!isCompleted)
                                          const Text(
                                            '—',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8)),
                                          )
                                        else if (isOffline)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEE2E2),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFFCA5A5)),
                                            ),
                                            child: const Text(
                                              'OFFLINE',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFFDC2626),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0F2FE),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFBAE6FD)),
                                            ),
                                            child: const Text(
                                              'ONLINE',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0284C7),
                                              ),
                                            ),
                                          ),

                                        const Spacer(),

                                        // Completion Time
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF64748B)),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Completed: $compTime',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isCompleted ? FontWeight.w600 : FontWeight.normal,
                                                color: isCompleted ? const Color(0xFF334155) : const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (isCompleted && ((task['completion_result'] ?? '').toString().isNotEmpty || (task['overtime_reason'] ?? '').toString().isNotEmpty)) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: task['completion_result'] == 'within_target'
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFFFF7ED),
                                          borderRadius: BorderRadius.circular(8),
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
                                                  size: 14,
                                                  color: task['completion_result'] == 'within_target'
                                                      ? const Color(0xFF047857)
                                                      : const Color(0xFFC2410C),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  task['completion_result'] == 'within_target'
                                                      ? 'DESTINATION TARGET: WITHIN 5 MIN'
                                                      : 'DESTINATION TARGET: OVERTIME',
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: task['completion_result'] == 'within_target'
                                                        ? const Color(0xFF047857)
                                                        : const Color(0xFFC2410C),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if ((task['overtime_reason'] ?? '').toString().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Overtime Reason: ',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFF9A3412),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Text(
                                                      task['overtime_reason'].toString(),
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
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
                                    const SizedBox(height: 10),
                                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => TaskMapVerificationModal.show(context, task),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF047857),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
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

  Widget _buildBioItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _emerald),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 10, color: Color(0xFF52796F))),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _darkText),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  String _formatLastSeen(String dt) {
    try {
      final then = DateTime.parse(dt);
      final now = DateTime.now();
      final diff = then.isUtc ? now.toUtc().difference(then) : now.difference(then.toLocal());
      if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return dt;
    }
  }

  // ── About / Details bottom sheet ──────────────────────────────────────────

  void _showRepDetails(_SalesRep rep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RepDetailSheet(rep: rep, onTrack: () {
        Navigator.pop(context);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminLiveTrackingScreen(
            initialRepId: rep.id,
            initialRepName: rep.name,
          ),
        ));
      }),
    );
  }
}

// ─── Rep Detail Bottom Sheet ──────────────────────────────────────────────────

class _RepDetailSheet extends StatelessWidget {
  final _SalesRep rep;
  final VoidCallback onTrack;

  const _RepDetailSheet({required this.rep, required this.onTrack});

  static const _emerald  = Color(0xFF00A86B);
  static const _darkText = Color(0xFF1B4332);

  String _formatLastSeen(String? dt) {
    if (dt == null || dt.isEmpty) return 'Never';
    try {
      final then = DateTime.parse(dt);
      final now = DateTime.now();
      final diff = then.isUtc ? now.toUtc().difference(then) : now.difference(then.toLocal());
      if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24)  return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return dt;
    }
  }

  String _formatDate(String dt) {
    try {
      final d = DateTime.parse(dt);
      return '${d.day.toString().padLeft(2, '0')}/'
             '${d.month.toString().padLeft(2, '0')}/'
             '${d.year}';
    } catch (_) {
      return dt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header row ──
                  Row(
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          color: _emerald.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                          border: Border.all(color: _emerald.withValues(alpha: 0.4), width: 2.5),
                        ),
                        child: Center(
                          child: Text(
                            rep.name.isNotEmpty ? rep.name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: _emerald, fontWeight: FontWeight.w800, fontSize: 26),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rep.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w800, color: _darkText)),
                            const SizedBox(height: 4),
                            Row(children: [
                              Container(
                                width: 9, height: 9,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: rep.isOnline ? _emerald : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                rep.isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600,
                                  color: rep.isOnline ? _emerald : const Color(0xFF64748B),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFE2F0E8)),
                  const SizedBox(height: 16),

                  // ── Section: Contact ──
                  _sectionTitle('Contact Information'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _infoCard(Icons.email_outlined, 'Email', rep.email)),
                    const SizedBox(width: 10),
                    Expanded(child: _infoCard(Icons.phone_outlined, 'Phone',
                        rep.phone.isNotEmpty ? rep.phone : 'Not provided')),
                  ]),
                  const SizedBox(height: 16),

                  // ── Section: Account ──
                  _sectionTitle('Account Details'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _infoCard(Icons.badge_outlined, 'Rep ID', '#${rep.id}')),
                    const SizedBox(width: 10),
                    Expanded(child: _infoCard(Icons.calendar_today_outlined, 'Joined',
                        _formatDate(rep.createdAt))),
                  ]),
                  const SizedBox(height: 16),

                  // ── Section: Location ──
                  _sectionTitle('Last Known Location'),
                  const SizedBox(height: 12),
                  if (rep.lastLat != null) ...[
                    Row(children: [
                      Expanded(child: _infoCard(Icons.south_rounded, 'Latitude',
                          rep.lastLat!.toStringAsFixed(6))),
                      const SizedBox(width: 10),
                      Expanded(child: _infoCard(Icons.east_rounded, 'Longitude',
                          rep.lastLng!.toStringAsFixed(6))),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _infoCard(Icons.access_time_rounded, 'Last Ping',
                          _formatLastSeen(rep.lastPingAt))),
                      const SizedBox(width: 10),
                      Expanded(child: _infoCard(Icons.gps_fixed_rounded, 'Accuracy',
                          rep.lastAccuracy != null
                              ? '±${rep.lastAccuracy!.toStringAsFixed(0)} m'
                              : 'N/A')),
                    ]),
                    const SizedBox(height: 20),
                    // Track button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onTrack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _emerald,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                          shadowColor: _emerald.withValues(alpha: 0.4),
                        ),
                        icon: const Icon(Icons.my_location_rounded, size: 20),
                        label: const Text('Open Live Tracking',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Row(children: [
                        Icon(Icons.location_off_rounded, color: Colors.grey, size: 20),
                        SizedBox(width: 10),
                        Text('No location data yet.\nApp not opened or GPS not shared.',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Row(children: [
      Container(width: 3, height: 16,
          decoration: BoxDecoration(color: _emerald, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: _darkText, letterSpacing: 0.2)),
    ]);
  }

  Widget _infoCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1FAE5)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: _emerald),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: Color(0xFF52796F))),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: _darkText),
              overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );
  }
}

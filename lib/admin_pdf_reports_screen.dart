import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'app_config.dart';

enum AdminReportType {
  pending,
  completed,
  overall,
  performance,
}

class AdminPdfReportsScreen extends StatefulWidget {
  final int? initialRepId;
  final String? initialRepName;
  final bool isEmbedded;
  final List<dynamic>? initialReps;
  final List<Map<String, dynamic>>? initialTasks;
  final AdminReportType? initialReportType;
  final String? initialPerformanceFilter;

  const AdminPdfReportsScreen({
    super.key,
    this.initialRepId,
    this.initialRepName,
    this.isEmbedded = false,
    this.initialReps,
    this.initialTasks,
    this.initialReportType,
    this.initialPerformanceFilter,
  });

  @override
  State<AdminPdfReportsScreen> createState() => _AdminPdfReportsScreenState();
}

class _AdminPdfReportsScreenState extends State<AdminPdfReportsScreen> {
  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _emeraldDark = Color(0xFF047857);
  static const _emeraldLight = Color(0xFFECFDF5);
  static const _darkText = Color(0xFF0F172A);
  static const _subtext = Color(0xFF64748B);
  static const _bgLight = Color(0xFFF8FAFC);
  static const _cardBorder = Color(0xFFE2E8F0);

  List<dynamic> _reps = [];
  List<Map<String, dynamic>> _allTasks = [];
  bool _loading = true;
  bool _generatingPdf = false;
  String _errorMessage = '';

  // Selection state
  String? _selectedRepName; // null means "All Medical Reps" or specific rep name
  int? _selectedRepId;
  AdminReportType _selectedReportType = AdminReportType.overall;
  String _performanceFilter = 'overall'; // 'overall', 'green', 'red'

  // Date filters (optional)
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialReportType != null) {
      _selectedReportType = widget.initialReportType!;
    }
    if (widget.initialPerformanceFilter != null && widget.initialPerformanceFilter!.isNotEmpty) {
      _performanceFilter = widget.initialPerformanceFilter!.toLowerCase();
    }
    if (widget.initialReps != null && widget.initialReps!.isNotEmpty) {
      _reps = widget.initialReps!;
    }
    if (widget.initialTasks != null && widget.initialTasks!.isNotEmpty) {
      _allTasks = widget.initialTasks!;
      _loading = false;
    }
    if (widget.initialRepName != null && widget.initialRepName!.isNotEmpty) {
      _selectedRepName = widget.initialRepName;
      _selectedRepId = widget.initialRepId;
    }
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (_allTasks.isEmpty || _reps.isEmpty) {
      setState(() => _loading = true);
    }
    await Future.wait([_fetchReps(), _fetchTasks()]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchReps() async {
    const path = '/backend/get_all_sales_reps.php';
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$path');
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final list = data['reps'] as List? ?? [];
            if (mounted) {
              setState(() {
                _reps = list;
                if (_selectedRepName != null && _selectedRepId == null) {
                  final found = list.firstWhere(
                    (r) => (r['name'] ?? '').toString().toLowerCase() == _selectedRepName!.toLowerCase(),
                    orElse: () => null,
                  );
                  if (found != null) {
                    _selectedRepId = (found['id'] as num?)?.toInt();
                  }
                }
              });
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
        final res = await http.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          if (data['success'] == true) {
            final rawList = data['tasks'] as List? ?? [];
            final list = rawList.cast<Map<String, dynamic>>();
            if (mounted) {
              setState(() {
                _allTasks = list;
                _errorMessage = '';
              });
            }
            return;
          }
        }
      } catch (_) {}
    }
    if (mounted && _allTasks.isEmpty) {
      setState(() => _errorMessage = 'Could not load tasks from database.');
    }
  }

  // ─── Data Filtering Helper ──────────────────────────────────────────────────

  bool _taskMatchesDate(Map<String, dynamic> task, DateTime? from, DateTime? to) {
    if (from == null && to == null) return true;

    final checkoutDate = (task['checkout_date'] ?? '').toString().trim();
    final createdAt = (task['created_at'] ?? '').toString().trim();
    final updatedAt = (task['updated_at'] ?? '').toString().trim();
    final checkedOutAt = (task['checked_out_at'] ?? '').toString().trim();

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
      final fromStr = from != null ? DateFormat('yyyy-MM-dd').format(from) : null;
      final toStr = to != null ? DateFormat('yyyy-MM-dd').format(to) : null;
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
    if (from != null && to != null) {
      final fromDay = DateTime(from.year, from.month, from.day);
      final toDay = DateTime(to.year, to.month, to.day);
      return !taskDay.isBefore(fromDay) && !taskDay.isAfter(toDay);
    } else if (from != null) {
      final fromDay = DateTime(from.year, from.month, from.day);
      return !taskDay.isBefore(fromDay);
    } else if (to != null) {
      final toDay = DateTime(to.year, to.month, to.day);
      return !taskDay.isAfter(toDay);
    }
    return true;
  }

  /// Get tasks filtered by the selected Medical Rep & Date Range
  List<Map<String, dynamic>> _getRepTasks() {
    List<Map<String, dynamic>> list = _allTasks;

    if (_selectedRepName != null && _selectedRepName != 'All Medical Reps') {
      list = list.where((t) {
        final repName = (t['sales_rep_name'] ?? '').toString().trim().toLowerCase();
        final repId = (t['user_id'] as num?)?.toInt();
        if (_selectedRepId != null && repId != null && repId == _selectedRepId) {
          return true;
        }
        return repName == _selectedRepName!.toLowerCase();
      }).toList();
    }

    if (_fromDate != null || _toDate != null) {
      list = list.where((t) => _taskMatchesDate(t, _fromDate, _toDate)).toList();
    }

    return list;
  }

  /// Get final tasks based on Report Type (Pending, Completed, Overall, or Performance)
  List<Map<String, dynamic>> _getFinalReportTasks() {
    final repTasks = _getRepTasks();
    switch (_selectedReportType) {
      case AdminReportType.pending:
        return repTasks.where((t) => (t['status'] ?? 'pending').toString().toLowerCase() != 'completed').toList();
      case AdminReportType.completed:
        return repTasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').toList();
      case AdminReportType.overall:
        return repTasks;
      case AdminReportType.performance:
        final filter = _performanceFilter.toLowerCase();
        if (filter == 'green') {
          return repTasks.where((t) {
            final cat = (t['color_category'] ?? '').toString().toLowerCase();
            final status = (t['performance_status'] ?? '').toString().toUpperCase();
            return cat == 'green' || status.contains('GREAT') || status.contains('ON TIME') || status.contains('ON TRACK');
          }).toList();
        } else if (filter == 'red') {
          return repTasks.where((t) {
            final cat = (t['color_category'] ?? '').toString().toLowerCase();
            final status = (t['performance_status'] ?? '').toString().toUpperCase();
            return cat == 'red' || status.contains('BAD') || status.contains('LATE') || status.contains('OVERDUE');
          }).toList();
        }
        return repTasks;
    }
  }

  Map<String, dynamic>? _getSelectedRepData() {
    if (_selectedRepName == null || _selectedRepName == 'All Medical Reps') {
      return null;
    }
    for (final r in _reps) {
      if ((r['name'] ?? '').toString().toLowerCase() == _selectedRepName!.toLowerCase()) {
        return r is Map<String, dynamic> ? r : Map<String, dynamic>.from(r as Map);
      }
    }
    return null;
  }

  String _sanitizeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  // ─── PDF Generation Logic ──────────────────────────────────────────────────

  Future<void> _handleGeneratePdf() async {
    // 1. Validation: Medical Rep Selected
    if (_selectedRepName == null || _selectedRepName!.trim().isEmpty) {
      _showWarningSnackBar('Please select a Medical Rep.');
      return;
    }

    // 2. Validation: Date Range Validity
    if (_fromDate != null && _toDate != null && _fromDate!.isAfter(_toDate!)) {
      _showWarningSnackBar('From Date cannot be after To Date.');
      return;
    }

    setState(() => _generatingPdf = true);

    try {
      // Re-fetch latest tasks if needed
      await _fetchTasks();

      final reportTasks = _getFinalReportTasks();

      // 3. Validation: Check if records exist
      if (reportTasks.isEmpty) {
        setState(() => _generatingPdf = false);
        _showNoRecordsDialog();
        return;
      }

      final repData = _getSelectedRepData();
      final targetRepName = _selectedRepName == 'All Medical Reps' ? 'All Medical Reps' : _selectedRepName!;
      final sanitizedRep = _sanitizeFileName(targetRepName);

      String reportTypeName;
      String fileTypeSuffix;
      switch (_selectedReportType) {
        case AdminReportType.pending:
          reportTypeName = 'Pending Work Report';
          fileTypeSuffix = 'Pending_Report';
          break;
        case AdminReportType.completed:
          reportTypeName = 'Completed Work Report';
          fileTypeSuffix = 'Completed_Report';
          break;
        case AdminReportType.overall:
          reportTypeName = 'Overall Report';
          fileTypeSuffix = 'Overall_Report';
          break;
        case AdminReportType.performance:
          final filterTitle = _performanceFilter == 'green' ? 'Green (On Time)' : (_performanceFilter == 'red' ? 'Red (Late & Overdue)' : 'Overall');
          reportTypeName = 'Sales Rep Performance Report ($filterTitle)';
          final filterSuffix = _performanceFilter[0].toUpperCase() + _performanceFilter.substring(1);
          fileTypeSuffix = 'Performance_$filterSuffix';
          break;
      }

      final fileName = '${sanitizedRep}_$fileTypeSuffix.pdf';

      // Build Document
      final pdf = pw.Document(
        title: '$targetRepName - $reportTypeName',
        author: 'MedSafe Life Science Admin Portal',
      );

      final totalAllRepTasks = _getRepTasks();
      final totalAssigned = totalAllRepTasks.length;
      final totalCompleted = totalAllRepTasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').length;
      final totalPending = totalAssigned - totalCompleted;
      final completionRate = totalAssigned > 0 ? (totalCompleted / totalAssigned * 100.0) : 0.0;

      // Performance stats for KPI
      int perfGreen = 0;
      int perfRed = 0;
      int perfOverdue = 0;
      int perfPoints = 0;
      for (final t in totalAllRepTasks) {
        final cat = (t['color_category'] ?? '').toString().toLowerCase();
        final status = (t['performance_status'] ?? '').toString().toUpperCase();
        final pts = (t['points_earned'] as num?)?.toInt() ?? 0;
        perfPoints += pts;
        if (cat == 'green' || status.contains('GREAT') || status.contains('ON TIME') || status.contains('ON TRACK')) {
          perfGreen++;
        } else if (cat == 'red' || status.contains('BAD') || status.contains('LATE')) {
          perfRed++;
        } else if (status.contains('OVERDUE')) {
          perfOverdue++;
        }
      }
      final evalCount = perfGreen + perfRed + perfOverdue;
      final perfScore = evalCount > 0 ? ((perfGreen / evalCount) * 100).round() : 0;

      final nowFormatted = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());
      String dateFilterStr = 'All Available Records';
      if (_fromDate != null && _toDate != null) {
        dateFilterStr = '${DateFormat('dd/MM/yyyy').format(_fromDate!)} to ${DateFormat('dd/MM/yyyy').format(_toDate!)}';
      } else if (_fromDate != null) {
        dateFilterStr = 'From ${DateFormat('dd/MM/yyyy').format(_fromDate!)}';
      } else if (_toDate != null) {
        dateFilterStr = 'Up to ${DateFormat('dd/MM/yyyy').format(_toDate!)}';
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          header: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 10),
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: PdfColors.teal800, width: 1.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'MedSafe Life Science',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.teal900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Pharmaceuticals & Field Operations Management System',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.teal50,
                          borderRadius: pw.BorderRadius.circular(4),
                          border: pw.Border.all(color: PdfColors.teal200, width: 0.8),
                        ),
                        child: pw.Text(
                          reportTypeName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.teal900,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Generated: $nowFormatted',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          footer: (pw.Context context) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(top: 8),
              padding: const pw.EdgeInsets.only(top: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.8),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Official MedSafe Life Science Field Performance Document • Single Source of Truth',
                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount}',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700),
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              // ── Medical Rep Info & Metadata Card ──
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Text('Medical Rep: ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
                            pw.Text(targetRepName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.teal900)),
                          ],
                        ),
                        pw.SizedBox(height: 2),
                        if (repData != null) ...[
                          pw.Text(
                            'Email: ${repData['email'] ?? 'N/A'}  •  Phone: ${repData['phone'] ?? 'N/A'}',
                            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                          ),
                        ] else ...[
                          pw.Text('Scope: All Field Representatives', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        ],
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date Filter: $dateFilterStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                        pw.SizedBox(height: 2),
                        pw.Text('Records in Report: ${reportTasks.length}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.teal800)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),

              // ── Summary KPI Cards ──
              if (_selectedReportType == AdminReportType.performance) ...[
                pw.Row(
                  children: [
                    _buildPdfKpiCard('Total Tasks', '$totalAssigned', PdfColors.blue50, PdfColors.blue900, PdfColors.blue200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Green (On Time)', '$perfGreen', PdfColors.green50, PdfColors.green900, PdfColors.green200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Red (Late)', '$perfRed', PdfColors.red50, PdfColors.red900, PdfColors.red200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Overdue', '$perfOverdue', PdfColors.red50, PdfColors.red900, PdfColors.red200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Points Earned', perfPoints >= 0 ? '+$perfPoints pts' : '$perfPoints pts', PdfColors.purple50, PdfColors.purple900, PdfColors.purple200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Performance Score', '$perfScore / 100', PdfColors.teal50, PdfColors.teal900, PdfColors.teal200),
                  ],
                ),
                pw.SizedBox(height: 10),
              ] else if (_selectedReportType == AdminReportType.overall || totalAssigned > 0) ...[
                pw.Row(
                  children: [
                    _buildPdfKpiCard('Total Assigned', '$totalAssigned', PdfColors.blue50, PdfColors.blue900, PdfColors.blue200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Total Completed', '$totalCompleted', PdfColors.green50, PdfColors.green900, PdfColors.green200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Total Pending', '$totalPending', PdfColors.orange50, PdfColors.orange900, PdfColors.orange200),
                    pw.SizedBox(width: 6),
                    _buildPdfKpiCard('Completion Rate', '${completionRate.toStringAsFixed(1)}%', PdfColors.teal50, PdfColors.teal900, PdfColors.teal200),
                  ],
                ),
                pw.SizedBox(height: 10),
              ],

              // ── Report Table ──
              _buildPdfTable(reportTasks),
            ];
          },
        ),
      );

      setState(() => _generatingPdf = false);

      // Trigger automatic printing/download dialog
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: fileName,
      );
    } catch (e, stack) {
      debugPrint('[PDF Report] Error generating PDF: $e\n$stack');
      setState(() => _generatingPdf = false);
      _showErrorDialog('Failed to generate PDF: $e');
    }
  }

  pw.Widget _buildPdfKpiCard(String label, String value, PdfColor bg, PdfColor text, PdfColor border) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(5),
          border: pw.Border.all(color: border, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: text)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: text, fontWeight: pw.FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfTable(List<Map<String, dynamic>> tasks) {
    if (_selectedReportType == AdminReportType.performance) {
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.teal900),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellStyle: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey900),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
        columnWidths: {
          0: const pw.FixedColumnWidth(18), // S.No
          1: const pw.FlexColumnWidth(2.0), // Doctor / Clinic
          2: const pw.FlexColumnWidth(1.1), // Category
          3: const pw.FlexColumnWidth(1.2), // Sales Rep
          4: const pw.FlexColumnWidth(1.1), // Assigned
          5: const pw.FlexColumnWidth(1.3), // Deadline
          6: const pw.FlexColumnWidth(1.3), // Completed
          7: const pw.FlexColumnWidth(1.0), // Duration
          8: const pw.FlexColumnWidth(1.4), // Performance
          9: const pw.FlexColumnWidth(1.0), // Late By
          10: const pw.FlexColumnWidth(0.8), // Points
        },
        headers: ['#', 'Doctor / Clinic', 'Category', 'Sales Rep', 'Assigned', 'Deadline', 'Completed', 'Duration', 'Performance', 'Late By', 'Points'],
        data: List.generate(tasks.length, (i) {
          final t = tasks[i];
          final doc = (t['doctor_name'] ?? 'N/A').toString();
          final clinic = (t['clinic_name'] ?? 'N/A').toString();
          final category = (t['task_category'] ?? '—').toString();
          final rep = (t['sales_rep_name'] ?? '—').toString();
          final createdAt = (t['created_at'] ?? '').toString();
          final assignedDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

          final deadline = (t['deadline_date_time'] ?? t['deadline'] ?? '—').toString();
          final completedAt = (t['completed_at'] ?? t['checkout_datetime'] ?? t['checked_out_at'] ?? (t['status'] == 'completed' ? 'Completed' : '—')).toString();
          final duration = (t['total_duration'] ?? '—').toString();
          final perfStatus = (t['performance_status'] ?? (t['status'] == 'completed' ? 'ON TIME' : 'PENDING')).toString();
          final lateBy = (t['late_by'] ?? '—').toString();
          final pts = (t['points_earned'] as num?)?.toInt() ?? 0;
          final ptsStr = pts > 0 ? '+$pts' : (pts < 0 ? '$pts' : '0');

          return [
            '${i + 1}',
            'Dr. $doc\n$clinic',
            category.isNotEmpty ? category : '—',
            rep,
            assignedDate.isNotEmpty ? assignedDate : '—',
            deadline.isNotEmpty ? deadline : '—',
            completedAt.isNotEmpty ? completedAt : '—',
            duration.isNotEmpty ? duration : '—',
            perfStatus,
            lateBy.isNotEmpty ? lateBy : '—',
            ptsStr,
          ];
        }),
      );
    } else if (_selectedReportType == AdminReportType.pending) {
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange800),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        columnWidths: {
          0: const pw.FixedColumnWidth(22), // S.No
          1: const pw.FlexColumnWidth(2.2), // Doctor & Clinic
          2: const pw.FlexColumnWidth(2.2), // Address & Details
          3: const pw.FlexColumnWidth(1.2), // Category
          4: const pw.FlexColumnWidth(1.0), // Basis
          5: const pw.FlexColumnWidth(1.3), // Assigned Date
          6: const pw.FlexColumnWidth(1.0), // Status
        },
        headers: ['#', 'Doctor / Clinic', 'Clinic Address / Notes', 'Category', 'Basis', 'Assigned Date', 'Status'],
        data: List.generate(tasks.length, (i) {
          final t = tasks[i];
          final doc = (t['doctor_name'] ?? 'N/A').toString();
          final clinic = (t['clinic_name'] ?? 'N/A').toString();
          final addr = (t['clinic_address'] ?? '').toString();
          final notes = (t['notes'] ?? '').toString();
          final category = (t['task_category'] ?? '—').toString();
          final basis = (t['task_basis'] ?? 'Daily').toString();
          final createdAt = (t['created_at'] ?? '').toString();
          final assignedDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
          final status = (t['status'] ?? 'pending').toString().toUpperCase();

          final addressNote = addr.isNotEmpty && notes.isNotEmpty
              ? '$addr\nNote: $notes'
              : (addr.isNotEmpty ? addr : (notes.isNotEmpty ? 'Note: $notes' : '—'));

          return [
            '${i + 1}',
            'Dr. $doc\n$clinic',
            addressNote,
            category.isNotEmpty ? category : '—',
            basis,
            assignedDate.isNotEmpty ? assignedDate : '—',
            status,
          ];
        }),
      );
    } else if (_selectedReportType == AdminReportType.completed) {
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.teal800),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        columnWidths: {
          0: const pw.FixedColumnWidth(22), // S.No
          1: const pw.FlexColumnWidth(2.0), // Doctor & Clinic
          2: const pw.FlexColumnWidth(1.2), // Category
          3: const pw.FlexColumnWidth(1.0), // Basis
          4: const pw.FlexColumnWidth(1.2), // Assigned Date
          5: const pw.FlexColumnWidth(1.4), // Completed At
          6: const pw.FlexColumnWidth(1.0), // Mode
          7: const pw.FlexColumnWidth(1.0), // Status
        },
        headers: ['#', 'Doctor / Clinic', 'Category', 'Basis', 'Assigned Date', 'Completed Date', 'Checkout Mode', 'Status'],
        data: List.generate(tasks.length, (i) {
          final t = tasks[i];
          final doc = (t['doctor_name'] ?? 'N/A').toString();
          final clinic = (t['clinic_name'] ?? 'N/A').toString();
          final category = (t['task_category'] ?? '—').toString();
          final basis = (t['task_basis'] ?? 'Daily').toString();
          final createdAt = (t['created_at'] ?? '').toString();
          final assignedDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

          final checkoutDate = (t['checkout_date'] ?? '').toString();
          final checkoutTime = (t['checkout_time'] ?? '').toString();
          final checkedOutAt = (t['checked_out_at'] ?? '').toString();
          String compStr = '';
          if (checkoutDate.isNotEmpty && checkoutTime.isNotEmpty) {
            compStr = '$checkoutDate\n$checkoutTime';
          } else if (checkedOutAt.isNotEmpty) {
            compStr = checkedOutAt;
          } else if (checkoutDate.isNotEmpty) {
            compStr = checkoutDate;
          } else {
            compStr = 'Completed';
          }

          final mode = (t['checkout_type'] ?? 'ONLINE').toString().toUpperCase();
          final status = (t['status'] ?? 'completed').toString().toUpperCase();

          return [
            '${i + 1}',
            'Dr. $doc\n$clinic',
            category.isNotEmpty ? category : '—',
            basis,
            assignedDate.isNotEmpty ? assignedDate : '—',
            compStr,
            mode.isNotEmpty ? mode : 'ONLINE',
            status,
          ];
        }),
      );
    } else {
      // Overall Report Table
      return pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellStyle: const pw.TextStyle(fontSize: 8, color: PdfColors.grey900),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        columnWidths: {
          0: const pw.FixedColumnWidth(22), // S.No
          1: const pw.FlexColumnWidth(2.0), // Doctor / Clinic
          2: const pw.FlexColumnWidth(1.2), // Category
          3: const pw.FlexColumnWidth(1.0), // Basis
          4: const pw.FlexColumnWidth(1.2), // Assigned Date
          5: const pw.FlexColumnWidth(1.4), // Completed Date
          6: const pw.FlexColumnWidth(1.1), // Status
        },
        headers: ['#', 'Doctor / Clinic', 'Category', 'Basis', 'Assigned Date', 'Completed Date', 'Status'],
        data: List.generate(tasks.length, (i) {
          final t = tasks[i];
          final doc = (t['doctor_name'] ?? 'N/A').toString();
          final clinic = (t['clinic_name'] ?? 'N/A').toString();
          final category = (t['task_category'] ?? '—').toString();
          final basis = (t['task_basis'] ?? 'Daily').toString();
          final createdAt = (t['created_at'] ?? '').toString();
          final assignedDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

          final isDone = (t['status'] ?? '').toString().toLowerCase() == 'completed';
          final checkoutDate = (t['checkout_date'] ?? '').toString();
          final checkoutTime = (t['checkout_time'] ?? '').toString();
          String compStr = '—';
          if (isDone) {
            if (checkoutDate.isNotEmpty && checkoutTime.isNotEmpty) {
              compStr = '$checkoutDate\n$checkoutTime';
            } else if (checkoutDate.isNotEmpty) {
              compStr = checkoutDate;
            } else {
              compStr = 'Completed';
            }
          }

          final status = (t['status'] ?? 'pending').toString().toUpperCase();

          return [
            '${i + 1}',
            'Dr. $doc\n$clinic',
            category.isNotEmpty ? category : '—',
            basis,
            assignedDate.isNotEmpty ? assignedDate : '—',
            compStr,
            status,
          ];
        }),
      );
    }
  }

  // ─── Step 3: Report Type Selection Widget ──────────────────────────────────

  Widget _buildReportTypeSelectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fact_check_rounded, color: Color(0xFF1D4ED8), size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '2. Select Report Type',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                  ),
                  Text(
                    'Choose the reporting criteria & records',
                    style: TextStyle(fontSize: 11, color: _subtext),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4 Report Options: Pending, Completed, Overall, Performance
          _buildReportTypeOption(
            type: AdminReportType.pending,
            title: '1. Pending Work Report',
            subtitle: 'Only currently pending & ongoing assigned tasks',
            icon: Icons.pending_actions_rounded,
            color: const Color(0xFFD97706),
            bgColor: const Color(0xFFFFFBEB),
          ),
          const SizedBox(height: 8),
          _buildReportTypeOption(
            type: AdminReportType.completed,
            title: '2. Completed Work Report',
            subtitle: 'Only completed work with dates & verification mode',
            icon: Icons.task_alt_rounded,
            color: const Color(0xFF00A86B),
            bgColor: const Color(0xFFF0FDF4),
          ),
          const SizedBox(height: 8),
          _buildReportTypeOption(
            type: AdminReportType.overall,
            title: '3. Overall Report',
            subtitle: 'Complete work summary, completion metrics & all task records',
            icon: Icons.analytics_rounded,
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
          ),
          const SizedBox(height: 8),
          _buildReportTypeOption(
            type: AdminReportType.performance,
            title: '4. Performance Report',
            subtitle: 'Target deadlines, on-time evaluations, delay analysis & point scores',
            icon: Icons.speed_rounded,
            color: const Color(0xFF047857),
            bgColor: const Color(0xFFECFDF5),
          ),

          if (_selectedReportType == AdminReportType.performance) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter Performance Status:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPerfFilterChip('Overall', 'overall', Icons.list_alt_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildPerfFilterChip('Green (On Time)', 'green', Icons.check_circle_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildPerfFilterChip('Red (Late/Overdue)', 'red', Icons.warning_amber_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPerfFilterChip(String label, String value, IconData icon) {
    final isSelected = _performanceFilter == value;
    Color activeColor = const Color(0xFF047857);
    if (value == 'green') activeColor = const Color(0xFF059669);
    if (value == 'red') activeColor = const Color(0xFFDC2626);

    return GestureDetector(
      onTap: () => setState(() => _performanceFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? activeColor : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: isSelected ? Colors.white : activeColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Alerts & Dialogs ──────────────────────────────────────────────────────

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
        backgroundColor: const Color(0xFFD97706),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showNoRecordsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFFE65100), size: 24),
            SizedBox(width: 10),
            Text('No Records Found', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _darkText)),
          ],
        ),
        content: const Text(
          'No records found for the selected Medical Rep and report type.\n\nPlease select another report type or adjust the date filter.',
          style: TextStyle(fontSize: 13.5, color: _subtext, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _emeraldPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 10),
            Text('Report Generation Error', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _darkText)),
          ],
        ),
        content: Text(
          error,
          style: const TextStyle(fontSize: 13, color: _subtext, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─── UI Widgets ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bodyContent = _loading && _reps.isEmpty && _allTasks.isEmpty
        ? const Center(child: CircularProgressIndicator(color: _emeraldPrimary))
        : RefreshIndicator(
            onRefresh: _fetchData,
            color: _emeraldPrimary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_off_rounded, color: Color(0xFFDC2626), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage,
                              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: _fetchData,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Step 1 & 2: Medical Rep Selection Card
                  _buildRepSelectionCard(),
                  const SizedBox(height: 16),

                  // Step 3: Report Type Selection Card
                  _buildReportTypeSelectionCard(),
                  const SizedBox(height: 16),

                  // Step 4: Optional Date Range Filter
                  _buildDateFilterCard(),
                  const SizedBox(height: 16),

                  // Step 5: Data Summary & Record Preview
                  _buildPreviewSummaryCard(),
                  const SizedBox(height: 24),

                  // Step 6: Generate PDF Report Button
                  _buildGenerateButton(),
                ],
              ),
            ),
          );

    if (widget.isEmbedded) {
      return Material(
        color: _bgLight,
        child: bodyContent,
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: _darkText),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _emeraldLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.picture_as_pdf_rounded, color: _emeraldDark, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medical Rep PDF Reports',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
                Text(
                  'Generate verified official reports',
                  style: TextStyle(fontSize: 11, color: _subtext),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _emeraldDark),
            tooltip: 'Refresh Database Records',
            onPressed: _fetchData,
          ),
        ],
      ),
      body: SafeArea(child: bodyContent),
    );
  }

  // ─── Step 2: Medical Rep Selection Widget ──────────────────────────────────

  // ─── Step 2: Medical Rep Selection Widget ──────────────────────────────────

  void _openRepSelectorSheet() {
    final searchController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final filteredReps = _reps.where((r) {
              if (query.isEmpty) return true;
              final name = (r['name'] ?? '').toString().toLowerCase();
              final email = (r['email'] ?? '').toString().toLowerCase();
              final phone = (r['phone'] ?? '').toString().toLowerCase();
              return name.contains(query) || email.contains(query) || phone.contains(query);
            }).toList();

            final isAllSelected = _selectedRepName == null || _selectedRepName == 'All Medical Reps';

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _emeraldLight,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.people_alt_rounded, color: _emeraldDark, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Medical Rep',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _darkText,
                                ),
                              ),
                              Text(
                                'Choose a representative to generate report',
                                style: TextStyle(fontSize: 11, color: _subtext),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: _subtext),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Search Bar if multiple reps
                  if (_reps.length > 3)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        style: const TextStyle(fontSize: 13, color: _darkText),
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, or phone...',
                          hintStyle: const TextStyle(fontSize: 12, color: _subtext),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _subtext),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16, color: _subtext),
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: _bgLight,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _emeraldPrimary, width: 1.5),
                          ),
                        ),
                      ),
                    ),

                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

                  // List of Reps
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        // Option: All Medical Reps
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedRepName = 'All Medical Reps';
                              _selectedRepId = null;
                            });
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: isAllSelected ? const Color(0xFFECFDF5) : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isAllSelected ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                                width: isAllSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isAllSelected ? _emeraldPrimary : const Color(0xFFE2E8F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.groups_rounded,
                                    color: isAllSelected ? Colors.white : const Color(0xFF64748B),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'All Medical Reps',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _darkText,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Consolidated report for all team members',
                                        style: TextStyle(fontSize: 11, color: _subtext),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isAllSelected)
                                  const Icon(Icons.check_circle_rounded, color: _emeraldDark, size: 22)
                                else
                                  const Icon(Icons.radio_button_unchecked_rounded, color: Color(0xFFCBD5E1), size: 20),
                              ],
                            ),
                          ),
                        ),

                        // Section divider
                        if (filteredReps.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
                            child: Text(
                              'INDIVIDUAL REPRESENTATIVES (${filteredReps.length})',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),

                        // List of individual reps
                        ...filteredReps.map((r) {
                          final name = (r['name'] ?? 'Unknown').toString();
                          final email = (r['email'] ?? '').toString();
                          final phone = (r['phone'] ?? '').toString();
                          final id = (r['id'] as num?)?.toInt();
                          final isSelected = !isAllSelected &&
                              ((id != null && _selectedRepId != null && id == _selectedRepId) ||
                                  (name.toLowerCase() == (_selectedRepName ?? '').toLowerCase()));

                          final initials = name.trim().isNotEmpty
                              ? name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
                              : 'MR';

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedRepName = name;
                                _selectedRepId = id;
                              });
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF93C5FD) : const Color(0xFFF1F5F9),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      initials,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: _darkText,
                                          ),
                                        ),
                                        if (email.isNotEmpty || phone.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              email.isNotEmpty ? email : phone,
                                              style: const TextStyle(fontSize: 11, color: _subtext),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 22)
                                  else
                                    const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
                                ],
                              ),
                            ),
                          );
                        }),

                        if (filteredReps.isEmpty && query.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No Medical Reps found for "$query"',
                                style: const TextStyle(fontSize: 12, color: _subtext),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRepSelectionCard() {
    // List of rep options
    final repOptions = <String>['All Medical Reps'];
    for (final r in _reps) {
      final name = (r['name'] ?? '').toString().trim();
      if (name.isNotEmpty && !repOptions.contains(name)) {
        repOptions.add(name);
      }
    }

    // Default selection fallback
    if (_selectedRepName == null && repOptions.isNotEmpty) {
      _selectedRepName = repOptions.length > 1 ? repOptions[1] : repOptions[0];
    }

    final selectedRepData = _getSelectedRepData();
    final isAll = _selectedRepName == null || _selectedRepName == 'All Medical Reps';
    final currentName = _selectedRepName ?? 'Select Medical Rep';

    final initials = currentName.trim().isNotEmpty && !isAll
        ? currentName.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase()
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                decoration: const BoxDecoration(
                  color: _emeraldLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_rounded, color: _emeraldDark, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '1. Select Medical Representative',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                  ),
                  Text(
                    'Choose a Medical Rep to generate the report',
                    style: TextStyle(fontSize: 11, color: _subtext),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Modern Interactive Selector Tile
          InkWell(
            onTap: _openRepSelectorSheet,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _bgLight,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
              ),
              child: Row(
                children: [
                  // Rep Avatar
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: isAll
                          ? const LinearGradient(
                              colors: [_emeraldPrimary, _emeraldDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isAll ? _emeraldPrimary : const Color(0xFF3B82F6)).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: isAll
                        ? const Icon(Icons.groups_rounded, color: Colors.white, size: 20)
                        : Text(
                            initials.isNotEmpty ? initials : 'MR',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Rep details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isAll
                              ? 'Consolidated report for all team members'
                              : (selectedRepData != null && (selectedRepData['email'] ?? '').toString().isNotEmpty
                                  ? selectedRepData['email'].toString()
                                  : 'Tap to change representative'),
                          style: const TextStyle(fontSize: 11, color: _subtext),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Change button pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _emeraldLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Change',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _emeraldDark,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, color: _emeraldDark, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Rep Details Mini Pill
          if (selectedRepData != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD1FAE5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.contact_mail_outlined, size: 14, color: _emeraldDark),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Email: ${selectedRepData['email'] ?? '—'}  |  Phone: ${selectedRepData['phone'] ?? '—'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF1B4332), fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportTypeOption({
    required AdminReportType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    final isSelected = _selectedReportType == type;

    return GestureDetector(
      onTap: () => setState(() => _selectedReportType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : _bgLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFCBD5E1),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0)),
              ),
              child: Icon(icon, color: isSelected ? color : _subtext, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? color : _darkText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? color.withValues(alpha: 0.85) : _subtext,
                    ),
                  ),
                ],
              ),
            ),
            Radio<AdminReportType>(
              value: type,
              groupValue: _selectedReportType,
              activeColor: color,
              onChanged: (AdminReportType? val) {
                if (val != null) setState(() => _selectedReportType = val);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Step 4: Optional Date Range Filter Widget ─────────────────────────────

  Widget _buildDateFilterCard() {
    final isFiltered = _fromDate != null || _toDate != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isFiltered ? _emeraldPrimary.withValues(alpha: 0.5) : _cardBorder,
          width: isFiltered ? 1.4 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.date_range_rounded, color: Color(0xFFEA580C), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3. Date Range Filter (Optional)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                    ),
                    Text(
                      'Leave empty to include all available records',
                      style: TextStyle(fontSize: 11, color: _subtext),
                    ),
                  ],
                ),
              ),
              if (isFiltered)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                    });
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
                        Text('Clear Filter', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Date Pickers
          Row(
            children: [
              Expanded(
                child: _buildDatePicker(
                  label: 'From Date',
                  date: _fromDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (ctx, child) => Theme(
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
                    if (picked != null) setState(() => _fromDate = picked);
                  },
                  onClear: _fromDate != null ? () => setState(() => _fromDate = null) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDatePicker(
                  label: 'To Date',
                  date: _toDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _toDate ?? _fromDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (ctx, child) => Theme(
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
                    if (picked != null) setState(() => _toDate = picked);
                  },
                  onClear: _toDate != null ? () => setState(() => _toDate = null) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Presets Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip('All Time', null, null),
                const SizedBox(width: 6),
                _buildPresetChip('Today', DateTime.now(), DateTime.now()),
                const SizedBox(width: 6),
                _buildPresetChip('Last 7 Days', DateTime.now().subtract(const Duration(days: 6)), DateTime.now()),
                const SizedBox(width: 6),
                _buildPresetChip('This Month', DateTime(DateTime.now().year, DateTime.now().month, 1), DateTime.now()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasDate = date != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: hasDate ? _emeraldLight : _bgLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasDate ? _emeraldPrimary : const Color(0xFFCBD5E1),
            width: hasDate ? 1.3 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded, size: 15, color: hasDate ? _emeraldDark : _subtext),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                hasDate ? DateFormat('dd/MM/yyyy').format(date) : label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasDate ? FontWeight.bold : FontWeight.w500,
                  color: hasDate ? _darkText : _subtext,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasDate && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded, size: 14, color: _subtext),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, DateTime? from, DateTime? to) {
    final isSelected = (_fromDate == null && _toDate == null && from == null && to == null) ||
        (_fromDate != null && from != null && _toDate != null && to != null &&
         _fromDate!.year == from.year && _fromDate!.month == from.month && _fromDate!.day == from.day &&
         _toDate!.year == to.year && _toDate!.month == to.month && _toDate!.day == to.day);

    return GestureDetector(
      onTap: () {
        setState(() {
          _fromDate = from;
          _toDate = to;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? _emeraldPrimary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? _emeraldDark : const Color(0xFFE2E8F0)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : _subtext,
          ),
        ),
      ),
    );
  }

  // ─── Step 5: Summary & Live Preview Widget ─────────────────────────────────

  Widget _buildPreviewSummaryCard() {
    final repTasks = _getRepTasks();
    final totalAssigned = repTasks.length;
    final totalCompleted = repTasks.where((t) => (t['status'] ?? '').toString().toLowerCase() == 'completed').length;
    final totalPending = totalAssigned - totalCompleted;
    final completionRate = totalAssigned > 0 ? (totalCompleted / totalAssigned * 100.0) : 0.0;
    final finalTasks = _getFinalReportTasks();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFF3E8FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.preview_rounded, color: Color(0xFF7E22CE), size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '4. Live Database Records Preview',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _darkText),
                  ),
                  Text(
                    'Exact counts & records retrieved for PDF',
                    style: TextStyle(fontSize: 11, color: _subtext),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4 Metric Badges
          Row(
            children: [
              Expanded(child: _buildMetricTile('Total Assigned', '$totalAssigned', const Color(0xFF0284C7), const Color(0xFFE0F2FE))),
              const SizedBox(width: 6),
              Expanded(child: _buildMetricTile('Pending', '$totalPending', const Color(0xFFD97706), const Color(0xFFFEF3C7))),
              const SizedBox(width: 6),
              Expanded(child: _buildMetricTile('Completed', '$totalCompleted', const Color(0xFF00A86B), const Color(0xFFD1FAE5))),
              const SizedBox(width: 6),
              Expanded(child: _buildMetricTile('Rate', '${completionRate.toStringAsFixed(0)}%', const Color(0xFF7C3AED), const Color(0xFFEDE9FE))),
            ],
          ),
          const SizedBox(height: 12),

          // Output Status Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: finalTasks.isNotEmpty ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: finalTasks.isNotEmpty ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  finalTasks.isNotEmpty ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 15,
                  color: finalTasks.isNotEmpty ? _emeraldDark : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    finalTasks.isNotEmpty
                        ? 'Ready to generate PDF with ${finalTasks.length} record${finalTasks.length == 1 ? '' : 's'}.'
                        : 'No records match the selected criteria.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: finalTasks.isNotEmpty ? _emeraldDark : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center, maxLines: 1),
        ],
      ),
    );
  }

  // ─── Step 6: Generate PDF Report Button Widget ─────────────────────────────

  Widget _buildGenerateButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_emeraldPrimary, _emeraldDark],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: _emeraldPrimary.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _generatingPdf ? null : _handleGeneratePdf,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: _generatingPdf
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : const Icon(Icons.picture_as_pdf_rounded, size: 22, color: Colors.white),
        label: Text(
          _generatingPdf ? 'Generating PDF Report...' : 'Generate PDF Report',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

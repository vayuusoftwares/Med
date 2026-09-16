import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../app_config.dart';
import '../models/performance_model.dart';

class PerformanceService {
  final http.Client _client;

  PerformanceService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch centralized performance data directly from backend (Single Source of Truth)
  Future<Map<String, dynamic>> fetchPerformanceData({
    int? userId,
    String? salesRepName,
    String? filter = 'overall',
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final queryParams = <String, String>{};
    if (userId != null && userId > 0) {
      queryParams['user_id'] = userId.toString();
    }
    if (salesRepName != null && salesRepName.isNotEmpty && salesRepName.toLowerCase() != 'all sales reps' && salesRepName.toLowerCase() != 'all') {
      queryParams['sales_rep_name'] = salesRepName;
    }
    if (filter != null && filter.isNotEmpty) {
      queryParams['filter'] = filter;
    }
    if (fromDate != null) {
      queryParams['from_date'] = DateFormat('yyyy-MM-dd').format(fromDate);
    }
    if (toDate != null) {
      queryParams['to_date'] = DateFormat('yyyy-MM-dd').format(toDate);
    }

    final queryString = queryParams.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final relativePath = '/backend/get_sales_rep_performance.php${queryString.isNotEmpty ? '?$queryString' : ''}';

    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$relativePath');
        final response = await _client.get(url, headers: AppConfig.headers).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = AppConfig.safeJsonDecode(response.body);
          if (data['success'] == true) {
            AppConfig.setWorkingHost(base);
            final summary = data['summary'] != null
                ? SalesRepPerformanceSummary.fromJson(data['summary'] as Map<String, dynamic>)
                : SalesRepPerformanceSummary.empty();

            final rawReps = (data['reps'] as List? ?? []);
            final reps = rawReps.map((r) => SalesRepRepSummary.fromJson(r as Map<String, dynamic>)).toList();

            final rawTasks = (data['tasks'] as List? ?? []);
            final tasks = rawTasks.map((t) => TaskPerformance.fromJson(t as Map<String, dynamic>)).toList();

            return {
              'success': true,
              'summary': summary,
              'reps': reps,
              'tasks': tasks,
              'count': data['count'] ?? tasks.length,
            };
          }
        }
      } catch (e) {
        debugPrint('[PerformanceService] Error fetching from $base: $e');
      }
    }

    return {
      'success': false,
      'summary': SalesRepPerformanceSummary.empty(),
      'reps': <SalesRepRepSummary>[],
      'tasks': <TaskPerformance>[],
      'count': 0,
    };
  }
}

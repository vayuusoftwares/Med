import 'package:flutter/material.dart';

class TaskPerformance {
  final int taskId;
  final int salesRepId;
  final String salesRepName;
  final String doctorName;
  final String clinicName;
  final String clinicAddress;
  final String taskCategory;
  final String taskBasis;
  final String notes;
  final String status;
  final String taskStatus;
  final String assignedDateTime;
  final String startDateTime;
  final String deadlineDateTime;
  final String endDateTime;
  final String totalDuration;
  final String performanceStatus;
  final String colorCategory;
  final String lateBy;
  final int pointsEarned;
  final String checkoutType;
  final String createdAt;

  const TaskPerformance({
    required this.taskId,
    required this.salesRepId,
    required this.salesRepName,
    required this.doctorName,
    required this.clinicName,
    required this.clinicAddress,
    required this.taskCategory,
    required this.taskBasis,
    required this.notes,
    required this.status,
    required this.taskStatus,
    required this.assignedDateTime,
    required this.startDateTime,
    required this.deadlineDateTime,
    required this.endDateTime,
    required this.totalDuration,
    required this.performanceStatus,
    required this.colorCategory,
    required this.lateBy,
    required this.pointsEarned,
    required this.checkoutType,
    required this.createdAt,
  });

  bool get isCompleted => taskStatus.toLowerCase() == 'completed' || status.toLowerCase() == 'completed';
  bool get isGreen => colorCategory.toUpperCase() == 'GREEN' || performanceStatus == 'GREAT / ON TIME';
  bool get isRed => colorCategory.toUpperCase() == 'RED' || isLate || isOverdue;
  bool get isLate => performanceStatus == 'BAD / LATE' || performanceStatus.contains('LATE');
  bool get isOverdue => performanceStatus == 'OVERDUE';
  bool get isOnTrack => performanceStatus == 'ON TRACK';
  bool get isPending => performanceStatus.contains('PENDING');

  Color get statusBadgeColor {
    if (isOverdue) return const Color(0xFFDC2626); // Red
    if (isLate) return const Color(0xFFE11D48); // Rose Red
    if (performanceStatus == 'GREAT / ON TIME') return const Color(0xFF00A86B); // Green
    if (isOnTrack) return const Color(0xFF0284C7); // Blue
    return const Color(0xFF64748B); // Slate
  }

  Color get statusBadgeBgColor {
    if (isOverdue) return const Color(0xFFFEF2F2);
    if (isLate) return const Color(0xFFFFF1F2);
    if (performanceStatus == 'GREAT / ON TIME') return const Color(0xFFECFDF5);
    if (isOnTrack) return const Color(0xFFF0F9FF);
    return const Color(0xFFF8FAFC);
  }

  factory TaskPerformance.fromJson(Map<String, dynamic> j) {
    return TaskPerformance(
      taskId: (j['task_id'] ?? j['id'] as num?)?.toInt() ?? 0,
      salesRepId: (j['sales_rep_id'] ?? j['user_id'] as num?)?.toInt() ?? 0,
      salesRepName: (j['sales_rep_name'] ?? '').toString(),
      doctorName: (j['doctor_name'] ?? '').toString(),
      clinicName: (j['clinic_name'] ?? '').toString(),
      clinicAddress: (j['clinic_address'] ?? '').toString(),
      taskCategory: (j['task_category'] ?? '').toString(),
      taskBasis: (j['task_basis'] ?? 'Daily').toString(),
      notes: (j['notes'] ?? '').toString(),
      status: (j['status'] ?? 'pending').toString(),
      taskStatus: (j['task_status'] ?? j['status'] ?? 'pending').toString(),
      assignedDateTime: (j['assigned_date_time'] ?? j['assigned_at'] ?? '').toString(),
      startDateTime: (j['start_date_time'] ?? j['started_at'] ?? '').toString(),
      deadlineDateTime: (j['deadline_date_time'] ?? j['deadline'] ?? '').toString(),
      endDateTime: (j['end_date_time'] ?? j['checked_out_at'] ?? j['checkout_date'] ?? '').toString(),
      totalDuration: (j['total_duration'] ?? '—').toString(),
      performanceStatus: (j['performance_status'] ?? 'PENDING / ON TRACK').toString(),
      colorCategory: (j['color_category'] ?? 'GREEN').toString(),
      lateBy: (j['late_by'] ?? '').toString(),
      pointsEarned: (j['points_earned'] as num?)?.toInt() ?? 0,
      checkoutType: (j['checkout_type'] ?? '').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
    );
  }
}

class SalesRepPerformanceSummary {
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int greenTasks;
  final int redTasks;
  final int overdueTasks;
  final int onTrackTasks;
  final double onTimePercentage;
  final int performanceScore;
  final String scoreDisplay;
  final bool hasData;

  const SalesRepPerformanceSummary({
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.greenTasks,
    required this.redTasks,
    required this.overdueTasks,
    required this.onTrackTasks,
    required this.onTimePercentage,
    required this.performanceScore,
    required this.scoreDisplay,
    required this.hasData,
  });

  factory SalesRepPerformanceSummary.fromJson(Map<String, dynamic> j) {
    return SalesRepPerformanceSummary(
      totalTasks: (j['total_tasks'] as num?)?.toInt() ?? 0,
      completedTasks: (j['completed_tasks'] as num?)?.toInt() ?? 0,
      pendingTasks: (j['pending_tasks'] as num?)?.toInt() ?? 0,
      greenTasks: (j['green_tasks'] as num?)?.toInt() ?? 0,
      redTasks: (j['red_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (j['overdue_tasks'] as num?)?.toInt() ?? 0,
      onTrackTasks: (j['on_track_tasks'] as num?)?.toInt() ?? 0,
      onTimePercentage: (j['on_time_percentage'] as num?)?.toDouble() ?? 0.0,
      performanceScore: (j['performance_score'] as num?)?.toInt() ?? 0,
      scoreDisplay: (j['score_display'] ?? '0 / 100').toString(),
      hasData: j['has_data'] == true,
    );
  }

  factory SalesRepPerformanceSummary.empty() {
    return const SalesRepPerformanceSummary(
      totalTasks: 0,
      completedTasks: 0,
      pendingTasks: 0,
      greenTasks: 0,
      redTasks: 0,
      overdueTasks: 0,
      onTrackTasks: 0,
      onTimePercentage: 0.0,
      performanceScore: 0,
      scoreDisplay: 'No Performance Data',
      hasData: false,
    );
  }
}

class SalesRepRepSummary {
  final int id;
  final String name;
  final String email;
  final String phone;
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;
  final int greenTasks;
  final int redTasks;
  final int overdueTasks;
  final int onTrackTasks;
  final double onTimePercentage;
  final int performanceScore;
  final String scoreDisplay;
  final bool hasData;

  const SalesRepRepSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
    required this.greenTasks,
    required this.redTasks,
    required this.overdueTasks,
    required this.onTrackTasks,
    required this.onTimePercentage,
    required this.performanceScore,
    required this.scoreDisplay,
    required this.hasData,
  });

  factory SalesRepRepSummary.fromJson(Map<String, dynamic> j) {
    return SalesRepRepSummary(
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      totalTasks: (j['total_tasks'] as num?)?.toInt() ?? 0,
      completedTasks: (j['completed_tasks'] as num?)?.toInt() ?? 0,
      pendingTasks: (j['pending_tasks'] as num?)?.toInt() ?? 0,
      greenTasks: (j['green_tasks'] as num?)?.toInt() ?? 0,
      redTasks: (j['red_tasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (j['overdue_tasks'] as num?)?.toInt() ?? 0,
      onTrackTasks: (j['on_track_tasks'] as num?)?.toInt() ?? 0,
      onTimePercentage: (j['on_time_percentage'] as num?)?.toDouble() ?? 0.0,
      performanceScore: (j['performance_score'] as num?)?.toInt() ?? 0,
      scoreDisplay: (j['score_display'] ?? '0 / 100').toString(),
      hasData: j['has_data'] == true,
    );
  }
}

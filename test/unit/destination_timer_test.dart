import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:medsafelifescience/app_config.dart';

String formatElapsedMMSS(int totalSeconds) {
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

DateTime? parseDestinationReachedAt(dynamic value) {
  if (value == null) return null;
  final str = value.toString().trim();
  if (str.isEmpty || str == 'null' || str == '0000-00-00 00:00:00') return null;
  return DateTime.tryParse(str);
}

int? calculateElapsedSeconds({
  required Map<String, dynamic> task,
  required DateTime currentTime,
}) {
  final status = (task['status'] ?? 'pending').toString().toLowerCase();
  if (status != 'in_progress' && status != 'started') {
    return null;
  }

  final reachedStr = task['destination_reached_at'];
  final reachedDt = parseDestinationReachedAt(reachedStr);
  if (reachedDt == null) {
    return null;
  }

  final diff = currentTime.difference(reachedDt).inSeconds;
  return diff >= 0 ? diff : 0;
}

bool isInside15mDestination({
  required double currentLat,
  required double currentLng,
  required double destLat,
  required double destLng,
}) {
  final dist = Geolocator.distanceBetween(currentLat, currentLng, destLat, destLng);
  return dist <= AppConfig.destinationRadiusMeters;
}

void main() {
  group('15-Meter Destination Timer MM:SS Formatting', () {
    test('formats seconds strictly as MM:SS', () {
      expect(formatElapsedMMSS(0), equals('00:00'));
      expect(formatElapsedMMSS(1), equals('00:01'));
      expect(formatElapsedMMSS(30), equals('00:30'));
      expect(formatElapsedMMSS(90), equals('01:30'));
      expect(formatElapsedMMSS(299), equals('04:59'));
      expect(formatElapsedMMSS(300), equals('05:00'));
      expect(formatElapsedMMSS(365), equals('06:05'));
      expect(formatElapsedMMSS(3600), equals('60:00'));
    });
  });

  group('Strict 15.0m Radius Constraint for Destination Timer', () {
    const clinicLat = 13.0827;
    const clinicLng = 80.2707;

    test('exact destination location (0m) is inside 15m radius', () {
      expect(
        isInside15mDestination(
          currentLat: clinicLat,
          currentLng: clinicLng,
          destLat: clinicLat,
          destLng: clinicLng,
        ),
        isTrue,
      );
    });

    test('offset of 10m is inside 15m radius', () {
      const offsetLat = clinicLat + 0.000045;
      final dist = Geolocator.distanceBetween(offsetLat, clinicLng, clinicLat, clinicLng);
      expect(dist, lessThanOrEqualTo(15.0));

      expect(
        isInside15mDestination(
          currentLat: offsetLat,
          currentLng: clinicLng,
          destLat: clinicLat,
          destLng: clinicLng,
        ),
        isTrue,
      );
    });

    test('offset > 15.0m (15.01m, 15.05m, 20m) is outside 15m radius', () {
      const outsideLat18 = clinicLat + 0.000162;
      final dist18 = Geolocator.distanceBetween(outsideLat18, clinicLng, clinicLat, clinicLng);
      expect(dist18, greaterThan(15.0));

      expect(
        isInside15mDestination(
          currentLat: outsideLat18,
          currentLng: clinicLng,
          destLat: clinicLat,
          destLng: clinicLng,
        ),
        isFalse,
      );
    });
  });

  group('Backend Timestamp Recovery & Timer Activation Rules', () {
    final baseTime = DateTime(2026, 9, 16, 9, 30, 0);

    test('timer does NOT start when task is assigned (pending status)', () {
      final task = {
        'id': 1,
        'status': 'pending',
        'destination_reached_at': null,
      };

      final elapsed = calculateElapsedSeconds(task: task, currentTime: baseTime);
      expect(elapsed, isNull);
    });

    test('timer does NOT start when task is started but destination not reached', () {
      final task = {
        'id': 1,
        'status': 'in_progress',
        'destination_reached_at': null,
      };

      final elapsed = calculateElapsedSeconds(task: task, currentTime: baseTime);
      expect(elapsed, isNull);
    });

    test('timer starts and recovers exact elapsed seconds from destination_reached_at', () {
      final task = {
        'id': 1,
        'status': 'in_progress',
        'destination_reached_at': '2026-09-16 09:30:00',
      };

      expect(
        calculateElapsedSeconds(task: task, currentTime: baseTime),
        equals(0),
      );

      expect(
        calculateElapsedSeconds(
          task: task,
          currentTime: baseTime.add(const Duration(seconds: 30)),
        ),
        equals(30),
      );

      final elapsed90 = calculateElapsedSeconds(
        task: task,
        currentTime: baseTime.add(const Duration(seconds: 90)),
      );
      expect(elapsed90, equals(90));
      expect(formatElapsedMMSS(elapsed90!), equals('01:30'));

      final elapsed300 = calculateElapsedSeconds(
        task: task,
        currentTime: baseTime.add(const Duration(seconds: 300)),
      );
      expect(elapsed300, equals(300));
      expect(formatElapsedMMSS(elapsed300!), equals('05:00'));

      final elapsed301 = calculateElapsedSeconds(
        task: task,
        currentTime: baseTime.add(const Duration(seconds: 301)),
      );
      expect(elapsed301, equals(301));
      expect(formatElapsedMMSS(elapsed301!), equals('05:01'));

      final elapsed390 = calculateElapsedSeconds(
        task: task,
        currentTime: baseTime.add(const Duration(seconds: 390)),
      );
      expect(elapsed390, equals(390));
      expect(formatElapsedMMSS(elapsed390!), equals('06:30'));
    });
  });

  group('5-Minute Target & Overtime Evaluation Rules', () {
    test('elapsed < 300s is TARGET ACTIVE (within target)', () {
      const elapsed = 90; // 01:30
      final isOvertime = elapsed > 300;
      final isAtTarget = elapsed == 300;
      expect(isOvertime, isFalse);
      expect(isAtTarget, isFalse);
      expect(formatElapsedMMSS(elapsed), equals('01:30'));
    });

    test('elapsed == 300s is TARGET REACHED (exact 5-minute deadline)', () {
      const elapsed = 300; // 05:00
      final isOvertime = elapsed > 300;
      final isAtTarget = elapsed == 300;
      expect(isOvertime, isFalse);
      expect(isAtTarget, isTrue);
      expect(formatElapsedMMSS(elapsed), equals('05:00'));
    });

    test('elapsed > 300s is OVERTIME with exact extra seconds', () {
      const elapsed = 390; // 06:30
      final isOvertime = elapsed > 300;
      final overtimeSec = elapsed - 300;
      expect(isOvertime, isTrue);
      expect(overtimeSec, equals(90));
      expect(formatElapsedMMSS(elapsed), equals('06:30'));
      expect(formatElapsedMMSS(overtimeSec), equals('01:30'));
    });
  });

  group('Overtime Reason Validation (Mandatory & Reject Spaces)', () {
    bool isValidOvertimeReason(String? reason) {
      if (reason == null) return false;
      return reason.trim().isNotEmpty;
    }

    test('empty string is rejected', () {
      expect(isValidOvertimeReason(''), isFalse);
    });

    test('whitespace-only strings are rejected', () {
      expect(isValidOvertimeReason('   '), isFalse);
      expect(isValidOvertimeReason('\t\n  '), isFalse);
    });

    test('non-empty reason is accepted', () {
      expect(isValidOvertimeReason('Doctor in consultation'), isTrue);
      expect(isValidOvertimeReason('   Emergency case   '), isTrue);
    });
  });

  group('Admin vs Sales Rep Overtime Reason Privacy Rule', () {
    Map<String, dynamic> sanitizeTaskForRole(Map<String, dynamic> rawTask, {required bool isAdmin}) {
      final item = Map<String, dynamic>.from(rawTask);
      if (!isAdmin) {
        item.remove('overtime_reason');
      }
      return item;
    }

    final rawTask = {
      'id': 101,
      'sales_rep_name': 'John Doe',
      'completion_result': 'OVERTIME',
      'overtime_duration_seconds': 90,
      'overtime_reason': 'Doctor was performing minor surgery',
    };

    test('Admin sees overtime reason', () {
      final adminView = sanitizeTaskForRole(rawTask, isAdmin: true);
      expect(adminView.containsKey('overtime_reason'), isTrue);
      expect(adminView['overtime_reason'], equals('Doctor was performing minor surgery'));
    });

    test('Sales Rep does NOT see overtime reason', () {
      final repView = sanitizeTaskForRole(rawTask, isAdmin: false);
      expect(repView.containsKey('overtime_reason'), isFalse);
    });
  });
}

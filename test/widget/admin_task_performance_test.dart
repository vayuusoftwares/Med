import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:medsafelifescience/admin_task_performance_screen.dart';

void main() {
  final sampleReps = [
    {
      'id': 101,
      'name': 'Kumar',
      'email': 'kumar@example.com',
      'phone': '9876543210',
      'is_online': true,
    },
    {
      'id': 102,
      'name': 'Raj',
      'email': 'raj@example.com',
      'phone': '9876543211',
      'is_online': false,
    },
  ];

  final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

  final sampleTasks = [
    {
      'id': 'TASK-1',
      'user_id': 101,
      'sales_rep_name': 'Kumar',
      'doctor_name': 'ABC Doctor',
      'clinic_name': 'ABC Clinic',
      'clinic_address': 'ABC Clinic Address, Chennai',
      'source_address': 'Chennai Central',
      'status': 'completed',
      'notes': 'Follow-up required',
      'checkout_type': 'ONLINE',
      'checkout_date': todayStr,
      'checkout_time': '10:30:00',
      'checkout_datetime': '$todayStr 10:30:00',
      'checkout_latitude': 13.0827,
      'checkout_longitude': 80.2707,
      'checkout_address': 'Chennai, Tamil Nadu',
    },
    {
      'id': 'TASK-2',
      'user_id': 101,
      'sales_rep_name': 'Kumar',
      'doctor_name': 'XYZ Doctor',
      'clinic_name': 'XYZ Hospital',
      'clinic_address': 'XYZ Hospital, Chennai',
      'source_address': 'Chennai Central',
      'status': 'pending',
      'notes': '',
      'checkout_type': '',
      'checkout_date': todayStr,
    },
    {
      'id': 'TASK-3',
      'user_id': 102,
      'sales_rep_name': 'Raj',
      'doctor_name': 'Dr. Raman',
      'clinic_name': 'City Care',
      'clinic_address': 'City Care Clinic',
      'source_address': 'T Nagar',
      'status': 'completed',
      'notes': 'Order placed',
      'checkout_type': 'OFFLINE',
      'checkout_date': todayStr,
      'checkout_time': '11:00:00',
      'checkout_datetime': '$todayStr 11:00:00',
    },
  ];

  testWidgets('renders AdminTaskPerformanceScreen with Period Filters and Rep Summaries', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminTaskPerformanceScreen(
            initialReps: sampleReps,
            initialTasks: sampleTasks,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify Period filter tabs exist
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);

    // Verify Metric Summary
    expect(find.text('Total Tasks'), findsOneWidget);
    expect(find.text('Completed'), findsWidgets);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Success Rate'), findsOneWidget);

    // Verify Sales Rep summaries
    expect(find.text('Kumar'), findsOneWidget);
    expect(find.text('Raj'), findsOneWidget);

    // Verify View Tasks buttons
    expect(find.text('View Tasks (2)'), findsOneWidget);
    expect(find.text('View Tasks (1)'), findsOneWidget);
  });

  testWidgets('switching between period tabs (Weekly, Monthly, Yearly, Custom) updates filter', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminTaskPerformanceScreen(
            initialReps: sampleReps,
            initialTasks: sampleTasks,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tap Weekly
    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    expect(find.text('Kumar'), findsOneWidget);

    // Tap Monthly
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('Kumar'), findsOneWidget);

    // Tap Yearly
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    expect(find.text('Kumar'), findsOneWidget);

    // Tap Custom
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
  });

  testWidgets('clicking View Tasks opens detailed task list modal for that Sales Rep', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminTaskPerformanceScreen(
            initialReps: sampleReps,
            initialTasks: sampleTasks,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tap View Tasks (2) for Kumar
    final viewTasksBtn = find.text('View Tasks (2)');
    expect(viewTasksBtn, findsOneWidget);
    await tester.tap(viewTasksBtn);
    await tester.pumpAndSettle();

    // Verify modal header
    expect(find.text('Sales Rep: Kumar'), findsOneWidget);
    expect(find.text('#TASK-1'), findsOneWidget);

    // Verify Task 1 details
    expect(find.text('Dr. ABC Doctor • ABC Clinic'), findsOneWidget);
    expect(find.text('Note: Follow-up required'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);

    // Scroll modal ListView to Task 2 and verify details
    await tester.drag(find.byType(ListView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('#TASK-2'), findsOneWidget);
    expect(find.text('Dr. XYZ Doctor • XYZ Hospital'), findsOneWidget);
    expect(find.text('PENDING'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/admin_pdf_reports_screen.dart';

void main() {
  final sampleReps = [
    {
      'id': 101,
      'name': 'Rahul Sharma',
      'email': 'rahul@medsafe.com',
      'phone': '9876543210',
      'is_online': true,
    },
    {
      'id': 102,
      'name': 'Priya Patel',
      'email': 'priya@medsafe.com',
      'phone': '9123456780',
      'is_online': false,
    },
  ];

  final sampleTasks = [
    {
      'id': 1,
      'user_id': 101,
      'sales_rep_name': 'Rahul Sharma',
      'task_basis': 'Daily',
      'doctor_name': 'Dr. Alok Verma',
      'clinic_name': 'City Care Clinic',
      'clinic_address': 'MG Road, Bengaluru',
      'task_category': 'General',
      'notes': 'Follow up on sample delivery',
      'status': 'pending',
      'created_at': '2026-09-08 10:30:00',
    },
    {
      'id': 2,
      'user_id': 101,
      'sales_rep_name': 'Rahul Sharma',
      'task_basis': 'Weekly',
      'doctor_name': 'Dr. Sunita Rao',
      'clinic_name': 'Apex Hospital',
      'clinic_address': 'Indiranagar, Bengaluru',
      'task_category': 'Orthopedic',
      'notes': 'Delivered catalog',
      'status': 'completed',
      'checkout_type': 'ONLINE',
      'checkout_date': '2026-09-09',
      'checkout_time': '14:20:00',
      'created_at': '2026-09-09 09:00:00',
    },
    {
      'id': 3,
      'user_id': 102,
      'sales_rep_name': 'Priya Patel',
      'task_basis': 'Daily',
      'doctor_name': 'Dr. Rajesh Kumar',
      'clinic_name': 'Lifeline Clinic',
      'clinic_address': 'Koramangala, Bengaluru',
      'task_category': 'Neurology',
      'notes': 'First visit',
      'status': 'pending',
      'created_at': '2026-09-10 11:00:00',
    },
  ];

  Widget buildTestWidget({
    int? initialRepId,
    String? initialRepName,
    bool isEmbedded = false,
  }) {
    return MaterialApp(
      home: AdminPdfReportsScreen(
        initialRepId: initialRepId,
        initialRepName: initialRepName,
        isEmbedded: isEmbedded,
        initialReps: sampleReps,
        initialTasks: sampleTasks,
      ),
    );
  }

  group('AdminPdfReportsScreen Tests', () {
    testWidgets('renders all section headers, options, and view report button', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Verify Screen Title
      expect(find.text('Medical Rep PDF Reports'), findsOneWidget);

      // Verify Step 1: Rep selection header
      expect(find.text('1. Select Medical Representative'), findsOneWidget);

      // Verify Step 2: Report Type options
      expect(find.text('2. Select Report Type'), findsOneWidget);
      expect(find.text('1. Pending Work Report'), findsOneWidget);
      expect(find.text('2. Completed Work Report'), findsOneWidget);
      expect(find.text('3. Overall Report'), findsOneWidget);

      // Verify Step 3: Date Range Filter
      expect(find.text('3. Date Range Filter (Optional)'), findsOneWidget);
      expect(find.text('From Date'), findsOneWidget);
      expect(find.text('To Date'), findsOneWidget);
      expect(find.text('All Time'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);

      // Verify Step 4: Preview summary card
      expect(find.text('4. Live Database Records Preview'), findsOneWidget);
      expect(find.text('Total Assigned'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);

      // Verify View Report Button
      expect(find.text('View Report'), findsOneWidget);
    });

    testWidgets('pre-selects specific Medical Rep when passed via props', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialRepId: 101,
        initialRepName: 'Rahul Sharma',
      ));
      await tester.pumpAndSettle();

      // Verify pre-selected rep name appears
      expect(find.text('Rahul Sharma'), findsWidgets);
      // Rahul has 2 tasks (1 pending, 1 completed)
      expect(find.text('2'), findsWidgets); // Total Assigned 2
    });

    testWidgets('switching report types updates live preview status', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialRepId: 101,
        initialRepName: 'Rahul Sharma',
      ));
      await tester.pumpAndSettle();

      // Tap Pending Work Report
      await tester.tap(find.text('1. Pending Work Report'));
      await tester.pumpAndSettle();

      // Tap Completed Work Report
      await tester.tap(find.text('2. Completed Work Report'));
      await tester.pumpAndSettle();

      // Tap Overall Report
      await tester.tap(find.text('3. Overall Report'));
      await tester.pumpAndSettle();
    });

    testWidgets('opening rep selector sheet allows switching medical reps', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialRepId: 101,
        initialRepName: 'Rahul Sharma',
      ));
      await tester.pumpAndSettle();

      // Tap the selector tile / Change button
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      // Verify sheet is displayed
      expect(find.text('Select Medical Rep'), findsOneWidget);
      expect(find.text('Priya Patel'), findsOneWidget);

      // Select Priya Patel
      await tester.tap(find.text('Priya Patel'));
      await tester.pumpAndSettle();

      // Verify sheet closed and Priya is selected
      expect(find.text('Priya Patel'), findsWidgets);
      // Priya has 1 task in sample data
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('tapping View Report opens Report Viewer in view mode with Download Report buttons', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(
        initialRepId: 101,
        initialRepName: 'Rahul Sharma',
      ));
      await tester.pumpAndSettle();

      // Scroll View Report into view and tap it
      await tester.ensureVisible(find.text('View Report'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Report'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify we are in View Mode inside AdminReportViewerScreen
      expect(find.text('Report View Mode: Review the document below, then tap Download Report.'), findsOneWidget);
      expect(find.text('Download Report'), findsWidgets);
    });

    testWidgets('embedded mode renders seamlessly without duplicate scaffold', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(isEmbedded: true));
      await tester.pumpAndSettle();

      // When embedded, Scaffold AppBar title is not rendered
      expect(find.text('1. Select Medical Representative'), findsOneWidget);
      expect(find.text('View Report'), findsOneWidget);
    });
  });
}

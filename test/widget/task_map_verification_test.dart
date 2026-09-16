import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/widgets/task_map_verification_modal.dart';

final Map<String, dynamic> _mockTask = {
  'id': 42,
  'user_id': 1,
  'sales_rep_name': 'Kumar',
  'doctor_name': 'Sharma',
  'clinic_name': 'City Care Centre',
  'clinic_address': 'Anna Salai, Chennai',
  'clinic_lat': 13.0674,
  'clinic_lng': 80.2376,
  'notes': 'Follow-up requested',
  'status': 'pending',
};

Widget _wrapModal(Map<String, dynamic> task) => MaterialApp(
      home: Scaffold(
        body: TaskMapVerificationModal(task: task),
      ),
    );

void main() {
  testWidgets('renders TaskMapVerificationModal with clinic info and buttons', (tester) async {
    await tester.pumpWidget(_wrapModal(_mockTask));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Verify Map Location'), findsOneWidget);
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('City Care Centre'), findsOneWidget);
    expect(find.text('Anna Salai, Chennai'), findsOneWidget);
    expect(find.text('Rep: Kumar'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Compare Locations'), findsOneWidget);
  });

  testWidgets('searches Google Maps URL and calculates comparison distance', (tester) async {
    await tester.pumpWidget(_wrapModal(_mockTask));
    await tester.pump(const Duration(milliseconds: 300));

    // Enter a matching Google Maps URL (same coordinates)
    final urlField = find.byType(TextField);
    expect(urlField, findsOneWidget);

    await tester.enterText(urlField, 'https://maps.google.com/?q=13.0674,80.2376');
    await tester.pump();

    // Click Search
    final searchBtn = find.text('Search');
    await tester.tap(searchBtn);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('URL Extracted:'), findsOneWidget);

    // Click Compare Locations
    final compareBtn = find.text('Compare Locations');
    await tester.ensureVisible(compareBtn);
    await tester.pumpAndSettle();
    await tester.tap(compareBtn);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('LOCATION VERIFIED / MATCH'), findsOneWidget);
  });
}

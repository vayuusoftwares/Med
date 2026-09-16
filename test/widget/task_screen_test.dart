import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/task_screen.dart';
import 'package:medsafelifescience/models/user_model.dart';

final _testUser = User(
  id: 1,
  name: 'Abikrishna',
  email: 'abi@medsafe.com',
  phone: '9876543210',
  role: 'sales_rep',
  roleLabel: 'Sales Representative',
  isActive: true,
  createdAt: '2024-01-01',
);

Widget _wrapTaskScreen() => MaterialApp(
      home: TaskScreen(salesRep: _testUser),
    );

void main() {
  testWidgets('renders TaskScreen header and sections', (tester) async {
    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Assign Task'), findsOneWidget);
    expect(find.text('Task Basis'), findsOneWidget);
    expect(find.text('Medical Representative'), findsOneWidget);
  });

  testWidgets('renders SHOW ALL button and opens management modal', (tester) async {
    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final showAllBtn = find.text('SHOW ALL');
    expect(showAllBtn, findsWidgets);

    await tester.tap(showAllBtn.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Show All Doctors & Clinics'), findsOneWidget);
    expect(find.text('Select and delete incorrect or obsolete records'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Select items to delete'), findsOneWidget);
  });
}

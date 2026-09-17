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

Widget _wrapTaskScreen({Map<String, dynamic>? existingTask}) => MaterialApp(
      home: TaskScreen(salesRep: _testUser, existingTask: existingTask),
    );

void main() {
  testWidgets('renders TaskScreen header and sections', (tester) async {
    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Assign Task'), findsOneWidget);
    expect(find.text('Task Basis'), findsOneWidget);
    expect(find.text('Medical Representative'), findsOneWidget);
  });

  testWidgets('renders SHOW ALL button and opens management modal for Doctors and Clinics', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final showAllBtn = find.text('SHOW ALL');
    expect(showAllBtn, findsWidgets);

    // Tap the SHOW ALL in Task Assignment
    await tester.tap(showAllBtn.last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Show All Doctors & Clinics'), findsOneWidget);
    expect(find.text('Select and delete incorrect or obsolete records'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Select items to delete'), findsOneWidget);
  });

  testWidgets('renders Doctor and Clinic autocomplete fields and accepts typing', (tester) async {
    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final doctorField = find.widgetWithText(TextField, 'Select or Type Doctor...');
    expect(doctorField, findsWidgets);

    await tester.enterText(doctorField.first, 'Dr. Kumar');
    await tester.pump(const Duration(milliseconds: 200));

    final clinicField = find.widgetWithText(TextField, 'Select or Type Clinic / Hospital...');
    expect(clinicField, findsWidgets);

    await tester.enterText(clinicField.first, 'ABC Clinic');
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('opens doctor and clinic search pickers when browse icon is clicked', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final browseDoctorBtn = find.byTooltip('Browse Doctors');
    expect(browseDoctorBtn, findsWidgets);

    // Tap browse doctors button
    await tester.tap(browseDoctorBtn.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Select or Search Doctor'), findsOneWidget);
  });

  testWidgets('pre-populates existingTask with matching Doctor and Clinic info', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final taskData = {
      'id': 101,
      'task_basis': 'Daily',
      'doctor_name': 'Dr. Kumar',
      'clinic_name': 'ABC Clinic',
      'clinic_lat': 12.9716,
      'clinic_lng': 77.5946,
      'clinic_address': 'MG Road, Bangalore',
      'task_category': 'Samples',
      'notes': 'Visit doctor regarding new product',
      'deadline_date_time': '2026-09-20 18:00:00',
    };

    await tester.pumpWidget(_wrapTaskScreen(existingTask: taskData));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Dr. Kumar'), findsWidgets);
    expect(find.text('ABC Clinic'), findsWidgets);
    expect(find.text('MG Road, Bangalore'), findsWidgets);
    expect(find.text('Samples'), findsOneWidget);
  });

  testWidgets('renders Area / Division dropdown and supports opening area selector', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Area / Division Filter'), findsOneWidget);
    expect(find.text('All Areas (Show All Records)'), findsOneWidget);

    // Tap on the Area selector
    await tester.tap(find.text('All Areas (Show All Records)'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Select Area / Division'), findsOneWidget);
    expect(find.text('Area: Chennai'), findsOneWidget);
    expect(find.text('Area: Villupuram'), findsOneWidget);
  });

  testWidgets('renders Area field in Add Doctor dialog', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final addButtons = find.byTooltip('Add new doctor');
    expect(addButtons, findsWidgets);

    await tester.tap(addButtons.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add New Doctor'), findsOneWidget);
    expect(find.text('Area / Division (e.g. Chennai)'), findsOneWidget);
  });

  testWidgets('renders Area field in Add Clinic dialog', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final addClinicButtons = find.byTooltip('Add new clinic');
    expect(addClinicButtons, findsWidgets);

    await tester.tap(addClinicButtons.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add New Clinic'), findsOneWidget);
    expect(find.text('Area / Division (e.g. Chennai)'), findsOneWidget);
  });

  testWidgets('renders Area SHOW ALL button and opens Area Management Modal', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final showAllBtns = find.text('SHOW ALL');
    expect(showAllBtns, findsWidgets);

    // Tap first SHOW ALL (the one next to Area / Division Filter)
    await tester.tap(showAllBtns.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Show All Areas / Divisions'), findsOneWidget);
    expect(find.text('Select and delete obsolete or unused areas'), findsOneWidget);
    expect(find.text('Select All'), findsOneWidget);
    expect(find.text('Select areas to delete'), findsOneWidget);
    expect(find.text('Chennai'), findsOneWidget);
    expect(find.text('Villupuram'), findsOneWidget);
  });

  testWidgets('renders Add Area button and opens Add Area dialog', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(_wrapTaskScreen());
    await tester.pump(const Duration(milliseconds: 600));

    final addAreaBtn = find.byTooltip('Add new area / division');
    expect(addAreaBtn, findsOneWidget);

    await tester.tap(addAreaBtn);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Add New Area'), findsOneWidget);
    expect(find.text('Area / Division Name * (e.g. Coimbatore)'), findsOneWidget);
  });
}

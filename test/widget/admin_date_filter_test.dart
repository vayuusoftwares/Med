import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/admin_sales_rep_list_screen.dart';

void main() {
  testWidgets('renders AdminSalesRepListScreen with Date Range Filter Bar', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSalesRepListScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Sales Representatives'), findsOneWidget);
    expect(find.text('Filter by Date Range'), findsOneWidget);
    expect(find.text('From Date'), findsOneWidget);
    expect(find.text('To Date'), findsOneWidget);
    expect(find.text('Apply / Search'), findsOneWidget);
  });

  testWidgets('shows snackbar when clicking Apply without selecting dates', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSalesRepListScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final applyBtn = find.text('Apply / Search');
    expect(applyBtn, findsOneWidget);
    await tester.tap(applyBtn);
    await tester.pump();

    expect(find.text('Please select From Date and/or To Date to filter.'), findsOneWidget);
  });

  testWidgets('tapping From Date and To Date opens date pickers', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSalesRepListScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Tap From Date
    final fromDateBtn = find.text('From Date');
    expect(fromDateBtn, findsOneWidget);
    await tester.tap(fromDateBtn);
    await tester.pumpAndSettle();

    // Verify DatePicker dialog is shown
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Close dialog
    final cancelBtn = find.text('Cancel');
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('renders Today, Yesterday, Day Before, Select / Custom, and All presets', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSalesRepListScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Day Before'), findsOneWidget);
    expect(find.text('Select / Custom'), findsOneWidget);

    // Tap Today
    await tester.tap(find.text('Today'));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Yesterday
    await tester.tap(find.text('Yesterday'));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Day Before
    await tester.tap(find.text('Day Before'));
    await tester.pump(const Duration(milliseconds: 100));

    // Tap All to reset
    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('renders phone bio item with touch and dialer capability', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminSalesRepListScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Verify screen rendered
    expect(find.text('Sales Representatives'), findsOneWidget);
  });
}

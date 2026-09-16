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
}

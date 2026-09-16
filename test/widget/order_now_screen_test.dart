import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/order_now_screen.dart';
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

Widget _wrapOrderNow() => MaterialApp(
      home: OrderNowScreen(salesRep: _testUser),
    );

void main() {
  testWidgets('renders OrderNowScreen title and form fields', (tester) async {
    await tester.pumpWidget(_wrapOrderNow());
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Doctor Product Order'), findsOneWidget);
    expect(find.text('Doctor Information'), findsOneWidget);
  });

  testWidgets('renders action buttons', (tester) async {
    await tester.pumpWidget(_wrapOrderNow());
    await tester.pump(const Duration(milliseconds: 600));

    final downloadBtn = find.text('Download PDF');
    await tester.ensureVisible(downloadBtn);
    await tester.pump();

    expect(downloadBtn, findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });
}

// App-level smoke test — verifies MedSafeApp launches and shows the SplashScreen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medsafelifescience/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('MedSafeApp launches and shows SplashScreen', (tester) async {
    await tester.pumpWidget(const MedSafeApp());
    // First frame: SplashScreen should be visible with MEDSAFE brand text
    expect(find.text('MEDSAFE'), findsOneWidget);
    expect(find.text('Life Science Force'), findsOneWidget);
  });

  testWidgets('MedSafeApp has no debug banner', (tester) async {
    await tester.pumpWidget(const MedSafeApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.debugShowCheckedModeBanner, isFalse);
  });

  testWidgets('MedSafeApp title is MedSafe Life Science', (tester) async {
    await tester.pumpWidget(const MedSafeApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'MedSafe Life Science');
  });

  testWidgets('MedSafeApp uses Material3', (tester) async {
    await tester.pumpWidget(const MedSafeApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.useMaterial3, isTrue);
  });
}

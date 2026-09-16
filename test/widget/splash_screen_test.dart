import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medsafelifescience/splash_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget _wrapSplash() => const MaterialApp(home: SplashScreen());

  testWidgets('shows MEDSAFE brand text', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.text('MEDSAFE'), findsOneWidget);
  });

  testWidgets('shows Life Science Force subtitle', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.text('Life Science Force'), findsOneWidget);
  });

  testWidgets('shows medical services icon (logo badge)', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.byIcon(Icons.medical_services_rounded), findsOneWidget);
  });

  testWidgets('shows animated bus icon', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.byIcon(Icons.directions_bus_rounded), findsOneWidget);
  });

  testWidgets('shows Loading Field Force Modules text', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.text('Loading Field Force Modules...'), findsOneWidget);
  });

  testWidgets('shows a percentage counter initially at 0%', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    // Only pump one frame so the timer has not fired yet
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('progress counter increments after timer ticks', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    // Advance 31ms → first tick fires (interval = 30ms)
    await tester.pump(const Duration(milliseconds: 31));
    expect(find.text('0%'), findsNothing);
    expect(find.textContaining('%'), findsOneWidget);
  });

  testWidgets('has white background scaffold', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.white);
  });

  testWidgets('animation bus is inside a Stack', (tester) async {
    await tester.pumpWidget(_wrapSplash());
    expect(find.byType(Stack), findsWidgets);
  });

  testWidgets('navigates away after 3 seconds when no stored token', (tester) async {
    // No token/user in prefs -> should navigate to LoginScreen
    await tester.pumpWidget(_wrapSplash());
    // Fast-forward past the 3-second splash (100 ticks x 30ms + nav animation)
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    // After navigation the SplashScreen widget should be gone
    expect(find.text('MEDSAFE'), findsNothing);
  });
}

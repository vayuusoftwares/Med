import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medsafelifescience/login_screen.dart';

// ── Video player stub ─────────────────────────────────────────────────────────
void _setupVideoPlayerStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.io/videoPlayer'),
    (call) async => call.method == 'create' ? {'textureId': 1} : null,
  );
}

Widget _wrap() => const MaterialApp(home: LoginScreen());

// Pump widget + wait for entrance animation
Future<void> _pumpLogin(WidgetTester tester) async {
  await tester.pumpWidget(_wrap());
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  setUpAll(_setupVideoPlayerStub);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Static content ─────────────────────────────────────────────────────────

  testWidgets('shows MedSafe Life Science title', (tester) async {
    await _pumpLogin(tester);
    // Title has fontSize 23 / weight 800 — footer brand has fontSize 12.
    // Both contain 'MedSafe Life Science', so use findsWidgets (>=1).
    expect(find.textContaining('MedSafe Life Science'), findsWidgets);
  });

  testWidgets('shows AI-Powered subtitle text', (tester) async {
    await _pumpLogin(tester);
    expect(find.textContaining('AI-Powered'), findsWidgets);
  });

  testWidgets('shows Sales Rep dropdown field in Sales Check In', (tester) async {
    await _pumpLogin(tester);
    expect(find.text('Select Sales Rep'), findsWidgets);
  });

  testWidgets('shows Password field', (tester) async {
    await _pumpLogin(tester);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
  });

  // ── Submit button ──────────────────────────────────────────────────────────

  testWidgets('submit button says Check In as Sales Rep', (tester) async {
    await _pumpLogin(tester);
    expect(find.text('Check In as Sales Rep'), findsOneWidget);
  });

  // ── Form validation ────────────────────────────────────────────────────────

  testWidgets('unselected sales rep shows validation error on submit', (tester) async {
    await _pumpLogin(tester);
    await tester.tap(find.text('Check In as Sales Rep'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Please select a Sales Rep'), findsOneWidget);
  });

  // ── Password visibility ────────────────────────────────────────────────────

  testWidgets('password is initially obscured (eye-off icon)', (tester) async {
    await _pumpLogin(tester);
    expect(find.byIcon(Icons.visibility_off_rounded), findsWidgets);
  });

  testWidgets('tapping eye icon reveals password', (tester) async {
    await _pumpLogin(tester);
    await tester.tap(find.byIcon(Icons.visibility_off_rounded).first);
    await tester.pump();
    expect(find.byIcon(Icons.visibility_rounded), findsWidgets);
  });

  // ── Role toggle ────────────────────────────────────────────────────────────

  testWidgets('role toggle shows Sales Check In label', (tester) async {
    await _pumpLogin(tester);
    expect(find.text('Sales Check In'), findsOneWidget);
  });

  testWidgets('role toggle shows Admin Check In label', (tester) async {
    await _pumpLogin(tester);
    expect(find.text('Admin Check In'), findsOneWidget);
  });

  testWidgets('switching to Admin Check In shows Admin Email / ID field', (tester) async {
    await _pumpLogin(tester);
    await tester.tap(find.text('Admin Check In'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Admin Email / ID'), findsOneWidget);
    expect(find.text('Check In as Admin'), findsOneWidget);
  });
}

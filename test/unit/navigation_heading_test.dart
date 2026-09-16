import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

/// Computes the forward navigation bearing from [source] to [destination] in degrees (0..360).
double calculateNavigationBearing(LatLng source, LatLng destination) {
  if (source.latitude == destination.latitude && source.longitude == destination.longitude) {
    return 0.0;
  }
  final dLng = (destination.longitude - source.longitude) * (math.pi / 180.0);
  final lat1 = source.latitude * (math.pi / 180.0);
  final lat2 = destination.latitude * (math.pi / 180.0);
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  final brng = (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
  return brng;
}

/// Normalizes any accumulated map rotation or device angle into 0°..359° range.
int normalizeAngle(double angle) {
  return ((angle.round() % 360 + 360) % 360);
}

void main() {
  group('Navigation Cursor & Heading Angle Calculations', () {
    test('bearing due North returns ~0° (or 360°)', () {
      final source = LatLng(10.0, 78.0);
      final destNorth = LatLng(11.0, 78.0);
      final bearing = calculateNavigationBearing(source, destNorth);
      expect(bearing, closeTo(0.0, 0.5));
    });

    test('bearing due East returns ~90°', () {
      final source = LatLng(10.0, 78.0);
      final destEast = LatLng(10.0, 79.0);
      final bearing = calculateNavigationBearing(source, destEast);
      expect(bearing, closeTo(90.0, 0.5));
    });

    test('bearing due South returns ~180°', () {
      final source = LatLng(10.0, 78.0);
      final destSouth = LatLng(9.0, 78.0);
      final bearing = calculateNavigationBearing(source, destSouth);
      expect(bearing, closeTo(180.0, 0.5));
    });

    test('bearing due West returns ~270°', () {
      final source = LatLng(10.0, 78.0);
      final destWest = LatLng(10.0, 77.0);
      final bearing = calculateNavigationBearing(source, destWest);
      expect(bearing, closeTo(270.0, 0.5));
    });

    test('cursor heading updates dynamically as user moves along route', () {
      // Step 1: User at Start moving towards Waypoint A
      LatLng userPos = LatLng(10.0000, 78.0000);
      LatLng waypointA = LatLng(10.0050, 78.0000); // North
      double heading1 = calculateNavigationBearing(userPos, waypointA);
      expect(heading1, closeTo(0.0, 0.1));

      // Step 2: User turns East towards Waypoint B
      userPos = waypointA;
      LatLng waypointB = LatLng(10.0050, 78.0050); // East
      double heading2 = calculateNavigationBearing(userPos, waypointB);
      expect(heading2, closeTo(90.0, 0.1));

      // Step 3: User turns South-East towards Destination C
      userPos = waypointB;
      LatLng destC = LatLng(10.0000, 78.0100);
      double heading3 = calculateNavigationBearing(userPos, destC);
      expect(heading3, closeTo(135.0, 1.0));
    });

    test('angle normalization keeps compass within 0°..359° for multi-turn gestures', () {
      expect(normalizeAngle(0.0), equals(0));
      expect(normalizeAngle(359.0), equals(359));
      expect(normalizeAngle(360.0), equals(0));
      expect(normalizeAngle(740.0), equals(20)); // Test user screenshot scenario: 740° -> 20°
      expect(normalizeAngle(-45.0), equals(315));
      expect(normalizeAngle(-360.0), equals(0));
    });
  });
}

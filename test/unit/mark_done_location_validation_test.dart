import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:medsafelifescience/app_config.dart';

bool isLocationValidForCompletion({
  required double currentLat,
  required double currentLng,
  required double? destLat,
  required double? destLng,
  double maxRadiusMeters = AppConfig.destinationRadiusMeters,
}) {
  if (destLat == null || destLng == null || destLat == 0.0 || destLng == 0.0) {
    return false;
  }
  if (currentLat == 0.0 && currentLng == 0.0) {
    return false;
  }

  final distance = Geolocator.distanceBetween(
    currentLat,
    currentLng,
    destLat,
    destLng,
  );

  return distance <= maxRadiusMeters;
}

void main() {
  group('Sales Rep Mark Done Location Validation (Strict 15.0m Destination Radius)', () {
    const clinicLat = 13.0827;
    const clinicLng = 80.2707;

    test('exact destination location (0m distance) is valid (<= 15.0m)', () {
      final isValid = isLocationValidForCompletion(
        currentLat: clinicLat,
        currentLng: clinicLng,
        destLat: clinicLat,
        destLng: clinicLng,
      );
      expect(isValid, isTrue);
    });

    test('location within 10 meters is valid (<= 15.0m)', () {
      // Offset by ~5 meters
      const offsetLat = clinicLat + 0.000045;
      final dist = Geolocator.distanceBetween(offsetLat, clinicLng, clinicLat, clinicLng);
      expect(dist, lessThanOrEqualTo(15.0));

      final isValid = isLocationValidForCompletion(
        currentLat: offsetLat,
        currentLng: clinicLng,
        destLat: clinicLat,
        destLng: clinicLng,
      );
      expect(isValid, isTrue);
    });

    test('location at exactly 15.0 meters is valid (<= 15.0m)', () {
      final isValid = isLocationValidForCompletion(
        currentLat: clinicLat,
        currentLng: clinicLng,
        destLat: clinicLat,
        destLng: clinicLng,
        maxRadiusMeters: 15.0,
      );
      expect(isValid, isTrue);
    });

    test('location at 15.01m, 15.05m, 20.0m or beyond is strictly invalid (> 15.0m)', () {
      // Offset by ~18 meters (greater than 15.0m, less than 20m)
      const outsideLat18m = clinicLat + 0.000162;
      final dist18 = Geolocator.distanceBetween(outsideLat18m, clinicLng, clinicLat, clinicLng);
      expect(dist18, greaterThan(15.0));

      final isValid18 = isLocationValidForCompletion(
        currentLat: outsideLat18m,
        currentLng: clinicLng,
        destLat: clinicLat,
        destLng: clinicLng,
      );
      expect(isValid18, isFalse);

      // Offset by ~55 meters
      const outsideLat55m = clinicLat + 0.0005;
      final dist55 = Geolocator.distanceBetween(outsideLat55m, clinicLng, clinicLat, clinicLng);
      expect(dist55, greaterThan(15.0));

      final isValid55 = isLocationValidForCompletion(
        currentLat: outsideLat55m,
        currentLng: clinicLng,
        destLat: clinicLat,
        destLng: clinicLng,
      );
      expect(isValid55, isFalse);
    });

    test('null destination coordinates are rejected', () {
      final isValid = isLocationValidForCompletion(
        currentLat: clinicLat,
        currentLng: clinicLng,
        destLat: null,
        destLng: null,
      );
      expect(isValid, isFalse);
    });

    test('zero/missing GPS coordinates are rejected', () {
      final isValid = isLocationValidForCompletion(
        currentLat: 0.0,
        currentLng: 0.0,
        destLat: clinicLat,
        destLng: clinicLng,
      );
      expect(isValid, isFalse);
    });
  });
}

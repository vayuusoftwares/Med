import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/services/map_url_service.dart';

void main() {
  group('MapUrlService.extractCoordinatesFromText', () {
    test('extracts coordinates from standard @lat,lng format', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/@13.082680,80.270718,17z',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.082680, 0.0001));
      expect(res['lng'], closeTo(80.270718, 0.0001));
    });

    test('extracts coordinates from place URL with !3d and !4d', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/Apollo+Hospital/@13.060422,80.251234,17z/data=!3m1!4b1!4m6!3m5!1s0x3a52661000000001:0x1!8m2!3d13.060422!4d80.251234',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.060422, 0.0001));
      expect(res['lng'], closeTo(80.251234, 0.0001));
    });

    test('extracts coordinates from !3d and !4d only without @ in URL', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/City+Clinic/data=!4m2!3m1!1s0x0:0x0!3d12.971598!4d77.594562',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(12.971598, 0.0001));
      expect(res['lng'], closeTo(77.594562, 0.0001));
    });

    test('extracts coordinates from ?q=lat,lng query param', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.google.com/?q=13.0827,80.2707',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.0827, 0.0001));
      expect(res['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts coordinates from ?q=loc:lat,lng format', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.google.com/?q=loc:13.0827,80.2707',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.0827, 0.0001));
      expect(res['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts coordinates from ?query=lat+lng format', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/search/?api=1&query=13.0827,80.2707',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.0827, 0.0001));
      expect(res['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts coordinates from geo: URI scheme', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'geo:13.0827,80.2707?z=15',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.0827, 0.0001));
      expect(res['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts coordinates from staticmap URL', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.google.com/maps/api/staticmap?center=13.0827%2C80.2707&zoom=15&size=400x400',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(13.0827, 0.0001));
      expect(res['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts coordinates from plain coordinate text', () {
      final res1 = MapUrlService.extractCoordinatesFromText('13.0827, 80.2707');
      expect(res1, isNotNull);
      expect(res1!['lat'], closeTo(13.0827, 0.0001));
      expect(res1['lng'], closeTo(80.2707, 0.0001));

      final res2 = MapUrlService.extractCoordinatesFromText('(13.0827, 80.2707)');
      expect(res2, isNotNull);
      expect(res2!['lat'], closeTo(13.0827, 0.0001));
      expect(res2['lng'], closeTo(80.2707, 0.0001));
    });

    test('extracts negative coordinates (South/West)', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.google.com/?q=-33.8688,-151.2093',
      );
      expect(res, isNotNull);
      expect(res!['lat'], closeTo(-33.8688, 0.0001));
      expect(res['lng'], closeTo(-151.2093, 0.0001));
    });

    test('returns null for empty or invalid text', () {
      expect(MapUrlService.extractCoordinatesFromText(''), isNull);
      expect(MapUrlService.extractCoordinatesFromText('hello world'), isNull);
      expect(MapUrlService.extractCoordinatesFromText('https://google.com'), isNull);
    });

    test('rejects out of range latitude/longitude', () {
      expect(MapUrlService.extractCoordinatesFromText('95.0, 80.0'), isNull); // Lat > 90
      expect(MapUrlService.extractCoordinatesFromText('13.0, 195.0'), isNull); // Lng > 180
      expect(MapUrlService.extractCoordinatesFromText('0.0, 0.0'), isNull);
    });
  });
}

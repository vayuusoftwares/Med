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

    test('prioritizes exact !3d/!4d pin coordinates OVER viewport @lat,lng center', () {
      // Viewport center is 13.085500, 80.276000 but the exact pinned place is 11.016500, 79.852100
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/MedSafe+Clinic/@13.085500,80.276000,17z/data=!4m6!3m5!1s0x3a52661000000001:0x1!8m2!3d11.016500!4d79.852100',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.016500));
      expect(res['lng'], equals(79.852100));
    });

    test('prioritizes exact !4d/!3d reversed pin coordinates OVER viewport @lat,lng center', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/Apollo/@13.0855,80.2760,17z/data=!4d79.345678!3d11.234567',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.234567));
      expect(res['lng'], equals(79.345678));
    });

    test('extracts coordinates from destination= query param (Directions URL)', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/dir/?api=1&destination=11.234567,79.345678',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.234567));
      expect(res['lng'], equals(79.345678));
    });

    test('extracts coordinates from daddr= query param', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.google.com/maps?saddr=13.0827,80.2707&daddr=11.234567,79.345678',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.234567));
      expect(res['lng'], equals(79.345678));
    });

    test('preserves full coordinate precision without rounding', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/Clinic/@13.0855,80.2760,17z/data=!3d11.01654321!4d79.85219876',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.01654321));
      expect(res['lng'], equals(79.85219876));
    });

    test('extracts marker coordinates from staticmap URL with markers param', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.googleapis.com/maps/api/staticmap?center=13.0855,80.2760&zoom=14&size=400x400&markers=color:red%7C11.0165,79.8521',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.0165));
      expect(res['lng'], equals(79.8521));
    });

    test('extracts coordinates from HTML meta itemprop latitude/longitude tags', () {
      final html = '''
        <html>
          <head>
            <meta itemprop="latitude" content="11.016500" />
            <meta itemprop="longitude" content="79.852100" />
          </head>
        </html>
      ''';
      final res = MapUrlService.extractCoordinatesFromText(html);
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.016500));
      expect(res['lng'], equals(79.852100));
    });

    test('extracts coordinates from Degrees Minutes Seconds (DMS) format', () {
      final res1 = MapUrlService.extractCoordinatesFromText('13°04\'57.7"N 80°16\'14.5"E');
      expect(res1, isNotNull);
      expect(res1!['lat'], closeTo(13.082694, 0.0001));
      expect(res1['lng'], closeTo(80.270694, 0.0001));

      final res2 = MapUrlService.extractCoordinatesFromText('13°04.962\'N, 80°16.242\'E');
      expect(res2, isNotNull);
      expect(res2!['lat'], closeTo(13.0827, 0.0001));
      expect(res2['lng'], closeTo(80.2707, 0.0001));

      final res3 = MapUrlService.extractCoordinatesFromText('33°52\'07.7"S 151°12\'33.5"W');
      expect(res3, isNotNull);
      expect(res3!['lat'], closeTo(-33.8688, 0.0001));
      expect(res3['lng'], closeTo(-151.2093, 0.0001));
    });

    test('extracts marker coordinates from staticmap URL with multiple style tags in markers param', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://maps.googleapis.com/maps/api/staticmap?center=13.0855,80.2760&zoom=14&size=400x400&markers=color:red%7Csize:mid%7Cscale:2%7C11.0165%2C79.8521',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.0165));
      expect(res['lng'], equals(79.8521));
    });

    test('extracts route destination coordinates with !1d and !2d', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/dir/Current+Location/Apollo/@13.0855,80.2760,17z/data=!4m2!4m1!3e0!1m5!1m1!1s0x0:0x0!2m2!1d79.8521!2d11.0165',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.0165));
      expect(res['lng'], equals(79.8521));
    });

    test('extracts coordinates directly from /maps/place/<lat>,<lng> URL path', () {
      final res = MapUrlService.extractCoordinatesFromText(
        'https://www.google.com/maps/place/11.0165,79.8521/@13.0855,80.2760,17z',
      );
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.0165));
      expect(res['lng'], equals(79.8521));
    });

    test('extracts coordinates from JSON-LD structure in HTML', () {
      final html = '''
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@type": "MedicalClinic",
          "name": "Apollo Clinic",
          "geo": {
            "@type": "GeoCoordinates",
            "latitude": 11.0165,
            "longitude": 79.8521
          }
        }
        </script>
      ''';
      final res = MapUrlService.extractCoordinatesFromText(html);
      expect(res, isNotNull);
      expect(res!['lat'], equals(11.0165));
      expect(res['lng'], equals(79.8521));
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

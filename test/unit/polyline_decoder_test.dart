import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// The polyline decoder in HomeScreen is private, so we replicate the exact
// algorithm here to unit-test it in isolation.
List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0;
  final int len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
}

void main() {
  group('Polyline decoder', () {
    test('empty string returns empty list', () {
      expect(decodePolyline(''), isEmpty);
    });

    test('decodes known single-point polyline correctly', () {
      // Encoded polyline for (13.0827, 80.2707) - Chennai
      // Manually computed: lat=1308270 → encodes as specific chars
      // We use a known Google-encoded sample and verify approximate coords.
      // '_p~iF~ps|U' = (38.5, -120.2) — well-known test vector
      final points = decodePolyline('_p~iF~ps|U');
      expect(points, hasLength(1));
      expect(points[0].latitude, closeTo(38.5, 0.001));
      expect(points[0].longitude, closeTo(-120.2, 0.001));
    });

    test('decodes 3-point path correctly', () {
      // '_p~iF~ps|U_ulLnnqC_mqNvxq`@' = (38.5,-120.2), (40.7,-120.95), (43.252,-126.453)
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      expect(points, hasLength(3));
      expect(points[0].latitude, closeTo(38.5, 0.001));
      expect(points[0].longitude, closeTo(-120.2, 0.001));
      expect(points[1].latitude, closeTo(40.7, 0.001));
      expect(points[1].longitude, closeTo(-120.95, 0.001));
      expect(points[2].latitude, closeTo(43.252, 0.001));
      expect(points[2].longitude, closeTo(-126.453, 0.001));
    });

    test('decoder returns LatLng objects', () {
      final points = decodePolyline('_p~iF~ps|U');
      expect(points.first, isA<LatLng>());
    });

    test('all decoded latitudes are in valid range [-90, 90]', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      for (final p in points) {
        expect(p.latitude, inInclusiveRange(-90.0, 90.0));
      }
    });

    test('all decoded longitudes are in valid range [-180, 180]', () {
      final points = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
      for (final p in points) {
        expect(p.longitude, inInclusiveRange(-180.0, 180.0));
      }
    });
  });
}

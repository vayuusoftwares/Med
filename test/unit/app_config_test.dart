import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/app_config.dart';

void main() {
  group('AppConfig', () {
    test('baseUrl matches ngrokUrl when useNgrok=true, http://localhost otherwise', () {
      if (AppConfig.useNgrok) {
        expect(AppConfig.baseUrl, AppConfig.ngrokUrl);
      } else {
        expect(AppConfig.baseUrl, 'http://localhost');
      }
    });

    test('ngrokUrl starts with https://', () {
      expect(AppConfig.ngrokUrl, startsWith('https://'));
    });

    test('localIp starts with http://', () {
      expect(AppConfig.localIp, startsWith('http://'));
    });

    test('headers always contain Content-Type: application/json', () {
      expect(AppConfig.headers['Content-Type'], 'application/json');
    });

    test('headers always contain Accept: application/json', () {
      expect(AppConfig.headers['Accept'], 'application/json');
    });

    test('ngrok-skip-browser-warning header present when useNgrok=true', () {
      if (AppConfig.useNgrok) {
        expect(AppConfig.headers.containsKey('ngrok-skip-browser-warning'), isTrue);
        expect(AppConfig.headers['ngrok-skip-browser-warning'], 'true');
      } else {
        expect(AppConfig.headers.containsKey('ngrok-skip-browser-warning'), isFalse);
      }
    });

    test('allHosts is non-empty', () {
      expect(AppConfig.allHosts, isNotEmpty);
    });

    test('allHosts contains ngrokUrl when useNgrok=true', () {
      if (AppConfig.useNgrok) {
        expect(AppConfig.allHosts, contains(AppConfig.ngrokUrl));
        expect(AppConfig.allHosts.length, greaterThan(1));
      }
    });

    test('allHosts contains multiple fallbacks when useNgrok=false', () {
      if (!AppConfig.useNgrok) {
        expect(AppConfig.allHosts.length, greaterThan(1));
        expect(AppConfig.allHosts.first, 'http://localhost');
      }
    });
  });
}

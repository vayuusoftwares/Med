import 'package:flutter_test/flutter_test.dart';
import 'package:medsafelifescience/models/user_model.dart';

void main() {
  const Map<String, dynamic> salesRepJson = {
    'id': 1,
    'name': 'Abikrishna',
    'email': 'abi@medsafe.com',
    'phone': '9876543210',
    'role': 'sales_rep',
    'role_label': 'Sales Representative',
    'is_active': true,
    'created_at': '2024-08-01T00:00:00.000Z',
  };

  const Map<String, dynamic> adminJson = {
    'id': 99,
    'name': 'Admin User',
    'email': 'admin@medsafe.com',
    'phone': '1234567890',
    'role': 'admin',
    'role_label': 'Administrator',
    'is_active': true,
    'created_at': '2024-01-01T00:00:00.000Z',
  };

  group('User.fromJson', () {
    test('parses id', () => expect(User.fromJson(salesRepJson).id, 1));
    test('parses name', () => expect(User.fromJson(salesRepJson).name, 'Abikrishna'));
    test('parses email', () => expect(User.fromJson(salesRepJson).email, 'abi@medsafe.com'));
    test('parses phone', () => expect(User.fromJson(salesRepJson).phone, '9876543210'));
    test('parses role', () => expect(User.fromJson(salesRepJson).role, 'sales_rep'));
    test('parses role_label', () => expect(User.fromJson(salesRepJson).roleLabel, 'Sales Representative'));
    test('parses created_at', () => expect(User.fromJson(salesRepJson).createdAt, '2024-08-01T00:00:00.000Z'));

    test('is_active = bool true', () => expect(User.fromJson({...salesRepJson, 'is_active': true}).isActive, isTrue));
    test('is_active = bool false', () => expect(User.fromJson({...salesRepJson, 'is_active': false}).isActive, isFalse));
    test('is_active = int 1 is truthy', () => expect(User.fromJson({...salesRepJson, 'is_active': 1}).isActive, isTrue));
    test('is_active = int 0 is false', () => expect(User.fromJson({...salesRepJson, 'is_active': 0}).isActive, isFalse));
  });

  group('User.isAdmin', () {
    test('false for sales_rep', () => expect(User.fromJson(salesRepJson).isAdmin, isFalse));
    test('true for admin', () => expect(User.fromJson(adminJson).isAdmin, isTrue));
  });

  group('User.toJson round-trip', () {
    test('preserves all fields', () {
      final json = User.fromJson(salesRepJson).toJson();
      expect(json['id'], salesRepJson['id']);
      expect(json['name'], salesRepJson['name']);
      expect(json['email'], salesRepJson['email']);
      expect(json['phone'], salesRepJson['phone']);
      expect(json['role'], salesRepJson['role']);
      expect(json['role_label'], salesRepJson['role_label']);
      expect(json['is_active'], salesRepJson['is_active']);
      expect(json['created_at'], salesRepJson['created_at']);
    });

    test('admin survives fromJson -> toJson -> fromJson', () {
      final rebuilt = User.fromJson(User.fromJson(adminJson).toJson());
      expect(rebuilt.isAdmin, isTrue);
      expect(rebuilt.id, 99);
      expect(rebuilt.name, 'Admin User');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medsafelifescience/services/storage_service.dart';
import 'package:medsafelifescience/models/user_model.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Helpers ────────────────────────────────────────────────────────────────
  User _makeUser({String role = 'sales_rep'}) => User(
        id: 42,
        name: 'Test User',
        email: 'test@medsafe.com',
        phone: '9999999999',
        role: role,
        roleLabel: role == 'admin' ? 'Administrator' : 'Sales Representative',
        isActive: true,
        createdAt: '2024-01-01',
      );

  // ── Token ──────────────────────────────────────────────────────────────────
  group('StorageService Token', () {
    test('saveToken then getToken returns same value', () async {
      final svc = StorageService();
      await svc.saveToken('tok_abc123');
      expect(await svc.getToken(), 'tok_abc123');
    });

    test('getToken returns null when nothing saved', () async {
      expect(await StorageService().getToken(), isNull);
    });

    test('deleteToken makes getToken return null', () async {
      final svc = StorageService();
      await svc.saveToken('tok_to_delete');
      await svc.deleteToken();
      expect(await svc.getToken(), isNull);
    });

    test('saveToken overwrites previous token', () async {
      final svc = StorageService();
      await svc.saveToken('first');
      await svc.saveToken('second');
      expect(await svc.getToken(), 'second');
    });
  });

  // ── User ───────────────────────────────────────────────────────────────────
  group('StorageService User', () {
    test('saveUser then getUser returns equivalent user', () async {
      final svc = StorageService();
      final user = _makeUser();
      await svc.saveUser(user);
      final got = await svc.getUser();
      expect(got, isNotNull);
      expect(got!.id, user.id);
      expect(got.name, user.name);
      expect(got.email, user.email);
      expect(got.phone, user.phone);
      expect(got.role, user.role);
      expect(got.roleLabel, user.roleLabel);
      expect(got.isActive, user.isActive);
      expect(got.createdAt, user.createdAt);
    });

    test('getUser returns null when nothing saved', () async {
      expect(await StorageService().getUser(), isNull);
    });

    test('deleteUser makes getUser return null', () async {
      final svc = StorageService();
      await svc.saveUser(_makeUser());
      await svc.deleteUser();
      expect(await svc.getUser(), isNull);
    });

    test('admin user round-trips with isAdmin=true', () async {
      final svc = StorageService();
      await svc.saveUser(_makeUser(role: 'admin'));
      final got = await svc.getUser();
      expect(got!.isAdmin, isTrue);
    });

    test('corrupted JSON returns null gracefully', () async {
      SharedPreferences.setMockInitialValues({'auth_user': 'NOT_VALID_JSON!!'});
      expect(await StorageService().getUser(), isNull);
    });
  });

  // ── clearAll ───────────────────────────────────────────────────────────────
  group('StorageService.clearAll', () {
    test('clears both token and user', () async {
      final svc = StorageService();
      await svc.saveToken('tok');
      await svc.saveUser(_makeUser());
      await svc.clearAll();
      expect(await svc.getToken(), isNull);
      expect(await svc.getUser(), isNull);
    });

    test('clearAll on empty storage is safe', () async {
      await expectLater(StorageService().clearAll(), completes);
    });
  });
}

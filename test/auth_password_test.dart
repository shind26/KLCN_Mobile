import 'package:flutter_test/flutter_test.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';

void main() {
  group('AuthService Password Hashing & Verification Tests', () {
    test('Xác thực mật khẩu plain-text (tài khoản cũ)', () {
      expect(AuthService.verifyPassword('123456', '123456'), isTrue);
      expect(AuthService.verifyPassword('wrong', '123456'), isFalse);
    });

    test(r'Xác thực mật khẩu mã hóa BCrypt ($2b$11$ từ web chủ trọ)', () {
      final hash = AuthService.hashPassword('MatKhau@123');
      expect(hash.startsWith(r'$2a$') || hash.startsWith(r'$2b$'), isTrue);

      // Thử verify hash vừa tạo
      expect(AuthService.verifyPassword('MatKhau@123', hash), isTrue);
      expect(AuthService.verifyPassword('SaiMatKhau', hash), isFalse);

      // Thử đổi tiền tố sang $2b$ (như hệ thống của chủ trọ trong ảnh DB)
      final hash2b = hash.replaceFirst(r'$2a$', r'$2b$');
      expect(AuthService.verifyPassword('MatKhau@123', hash2b), isTrue);
      expect(AuthService.verifyPassword('SaiMatKhau', hash2b), isFalse);
    });

    test('Xử lý an toàn với chuỗi rỗng', () {
      expect(AuthService.verifyPassword('', ''), isFalse);
      expect(AuthService.verifyPassword('123456', ''), isFalse);
    });
  });
}

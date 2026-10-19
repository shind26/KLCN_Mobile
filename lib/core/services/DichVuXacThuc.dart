import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static const String _keyCurrentUser = 'auth_current_user_json';
  static const String _keySavedUsername = 'saved_login_username';
  static const String _keyRememberMe = 'saved_remember_me';

  static final ValueNotifier<UserModel?> currentUserNotifier =
      ValueNotifier<UserModel?>(null);

  /// Kiểm tra mật khẩu (hỗ trợ cả chuẩn BCrypt $2a$, $2b$, $2y$ lẫn mật khẩu thường)
  static bool verifyPassword(String plainPassword, String storedHashOrPassword) {
    if (storedHashOrPassword.isEmpty) return false;

    // Nếu mật khẩu trong DB được mã hóa bằng BCrypt ($2a$, $2b$, $2y$)
    if (storedHashOrPassword.startsWith(r'$2a$') ||
        storedHashOrPassword.startsWith(r'$2b$') ||
        storedHashOrPassword.startsWith(r'$2y$')) {
      try {
        if (BCrypt.checkpw(plainPassword, storedHashOrPassword)) {
          return true;
        }
      } catch (e) {
        debugPrint('BCrypt checkpw error: $e');
      }

      // Chuẩn hóa tiền tố $2b$ / $2y$ sang $2a$ nếu thư viện yêu cầu format chuẩn
      try {
        final normalized = storedHashOrPassword.replaceFirst(
          RegExp(r'^\$2[by]\$'),
          r'$2a$',
        );
        if (BCrypt.checkpw(plainPassword, normalized)) {
          return true;
        }
      } catch (_) {}

      return false;
    }

    // Trường hợp tài khoản cũ lưu mật khẩu thường dạng plain-text
    return plainPassword == storedHashOrPassword;
  }

  /// Mã hóa mật khẩu thành chuỗi BCrypt (cost factor = 11 tương thích chuẩn hệ thống chủ trọ)
  static String hashPassword(String plainPassword) {
    try {
      final salt = BCrypt.gensalt(logRounds: 11);
      return BCrypt.hashpw(plainPassword, salt);
    } catch (e) {
      debugPrint('Lỗi BCrypt hashPassword: $e');
      return BCrypt.hashpw(plainPassword, BCrypt.gensalt());
    }
  }

  /// Khởi tạo AuthService, đọc session lưu trước đó (chỉ phục hồi khi có chọn Ghi nhớ đăng nhập)
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
      if (!rememberMe) {
        // Nếu không tick 'Ghi nhớ đăng nhập', xóa session cũ để người dùng vào với tư cách Khách vãng lai
        await prefs.remove(_keyCurrentUser);
        currentUserNotifier.value = null;
        debugPrint('>>> [AuthService.init] rememberMe = false -> Chế độ Khách vãng lai (Chưa đăng nhập)');
        return;
      }
      final userJsonStr = prefs.getString(_keyCurrentUser);
      debugPrint(
        '>>> [AuthService.init] Đang đọc session từ SharedPreferences: $userJsonStr',
      );
      if (userJsonStr != null && userJsonStr.isNotEmpty) {
        final Map<String, dynamic> userMap = jsonDecode(userJsonStr);
        currentUserNotifier.value = UserModel.fromJson(userMap);
        debugPrint(
          '>>> [AuthService.init] Phục hồi phiên đăng nhập thành công: ${currentUserNotifier.value?.tenDangNhap} (Vai trò: ${currentUserNotifier.value?.vaiTro})',
        );
      } else {
        currentUserNotifier.value = null;
      }
    } catch (e) {
      debugPrint('Lỗi khởi tạo AuthService: $e');
      currentUserNotifier.value = null;
    }
  }

  /// Kiểm tra xem người dùng đã đăng nhập chưa
  static bool get isLoggedIn => currentUserNotifier.value != null;

  /// Lấy thông tin user hiện tại
  static UserModel? get currentUser => currentUserNotifier.value;

  /// Đăng nhập bằng tên đăng nhập / số điện thoại và mật khẩu
  static Future<({bool success, String? error, UserModel? user})> login({
    required String username,
    required String password,
    required bool rememberMe,
  }) async {
    try {
      final res = await Supabase.instance.client
          .from('tai_khoan')
          .select()
          .eq('ten_dang_nhap', username.trim())
          .maybeSingle();

      if (res == null) {
        return (
          success: false,
          error: 'Tài khoản hoặc mật khẩu không chính xác!',
          user: null,
        );
      }

      // Xác thực mật khẩu với BCrypt / Plain text
      final dbPassword = res['mat_khau']?.toString() ?? '';
      if (!verifyPassword(password, dbPassword)) {
        return (
          success: false,
          error: 'Tài khoản hoặc mật khẩu không chính xác!',
          user: null,
        );
      }

      final user = UserModel.fromJson(Map<String, dynamic>.from(res));
      if (!user.isActive) {
        return (
          success: false,
          error: 'Tài khoản đang bị tạm khóa. Vui lòng liên hệ BQL!',
          user: null,
        );
      }

      // Lưu phiên đăng nhập nếu được chọn ghi nhớ
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        await prefs.setString(_keyCurrentUser, jsonEncode(user.toJson()));
        await prefs.setString(_keySavedUsername, username.trim());
        await prefs.setBool(_keyRememberMe, true);
      } else {
        await prefs.remove(_keyCurrentUser);
        await prefs.remove(_keySavedUsername);
        await prefs.setBool(_keyRememberMe, false);
      }

      // Cập nhật State toàn cục trong RAM cho phiên hiện tại
      currentUserNotifier.value = user;

      return (success: true, error: null, user: user);
    } catch (e) {
      debugPrint('Lỗi AuthService.login: $e');
      return (
        success: false,
        error: 'Lỗi kết nối cơ sở dữ liệu. Vui lòng thử lại!',
        user: null,
      );
    }
  }

  /// Đăng nhập bằng mã OTP (Zalo OTP hoặc SMS OTP)
  static Future<({bool success, String? error, UserModel? user})>
  loginWithPhoneOtp({required String phone, required String otpType}) async {
    try {
      final cleanPhone = phone.trim();
      final res = await Supabase.instance.client
          .from('tai_khoan')
          .select()
          .eq('ten_dang_nhap', cleanPhone)
          .maybeSingle();

      UserModel user;
      if (res != null) {
        user = UserModel.fromJson(Map<String, dynamic>.from(res));
        if (!user.isActive) {
          return (
            success: false,
            error: 'Tài khoản đang bị tạm khóa. Vui lòng liên hệ BQL!',
            user: null,
          );
        }
      } else {
        // Tạo tài khoản mới cho số điện thoại nếu chưa có
        final newAccountCode =
            'TK_${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        final newUserData = {
          'ma_tai_khoan': newAccountCode,
          'ten_dang_nhap': cleanPhone,
          'mat_khau': 'otp_verified',
          'vai_tro': 'KhachThue',
          'co_so_van_hanh': 'Kiêu Giang House',
          'trang_thai': 'HoatDong',
          'ngay_tao': DateTime.now().toIso8601String(),
        };

        try {
          await Supabase.instance.client.from('tai_khoan').insert(newUserData);
          user = UserModel.fromJson(newUserData);
        } catch (e) {
          debugPrint(
            'Tạo tài khoản Supabase thất bại, sử dụng phiên local: $e',
          );
          user = UserModel(
            maTaiKhoan: newAccountCode,
            tenDangNhap: cleanPhone,
            matKhau: 'otp_verified',
            vaiTro: 'KhachThue',
            coSoVanHanh: 'Kiêu Giang House',
            trangThai: 'HoatDong',
          );
        }
      }

      // Lưu phiên đăng nhập
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCurrentUser, jsonEncode(user.toJson()));
      await prefs.setString(_keySavedUsername, cleanPhone);

      // Cập nhật State toàn cục
      currentUserNotifier.value = user;

      return (success: true, error: null, user: user);
    } catch (e) {
      debugPrint('Lỗi loginWithPhoneOtp: $e');
      return (
        success: false,
        error: 'Lỗi xác thực OTP. Vui lòng thử lại!',
        user: null,
      );
    }
  }

  /// Đăng xuất tài khoản
  static Future<void> logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyCurrentUser);
      await prefs.remove(_keySavedUsername);
      await prefs.setBool(_keyRememberMe, false);
      currentUserNotifier.value = null;
      debugPrint('>>> [AuthService.logout] Đã đăng xuất và xóa toàn bộ session lưu');
    } catch (e) {
      debugPrint('Lỗi khi đăng xuất: $e');
      currentUserNotifier.value = null;
    }
  }

  /// Lấy tên đăng nhập đã lưu
  static Future<String?> getSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedUsername);
  }

  /// Lấy trạng thái ghi nhớ
  static Future<bool> getRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyRememberMe) ?? false;
  }

  /// Cập nhật user hiện tại và lưu vào SharedPreferences
  static Future<void> updateCurrentUser(UserModel updatedUser) async {
    try {
      currentUserNotifier.value = updatedUser;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCurrentUser, jsonEncode(updatedUser.toJson()));
    } catch (e) {
      debugPrint('Lỗi updateCurrentUser: $e');
    }
  }
}

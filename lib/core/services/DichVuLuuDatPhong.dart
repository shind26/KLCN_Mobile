import 'package:shared_preferences/shared_preferences.dart';

class BookingStorageService {
  static const String _keyPhone = 'guest_last_booking_phone';
  static const String _keyCode = 'guest_last_booking_code';
  static const String _keyNotifiedIds = 'guest_notified_confirmed_ids';

  /// Lưu số điện thoại và mã đặt lịch gần nhất
  static Future<void> saveLastBooking({
    required String phone,
    required String appointmentCode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPhone, phone);
    await prefs.setString(_keyCode, appointmentCode);
  }

  /// Lấy số điện thoại đã đặt gần nhất
  static Future<String?> getLastPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPhone);
  }

  /// Lấy mã phiếu đặt lịch gần nhất
  static Future<String?> getLastCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCode);
  }

  /// Kiểm tra xem ID lịch hẹn này đã được hiện popup thông báo chưa
  static Future<bool> isAlreadyNotified(String maLichHen) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyNotifiedIds) ?? [];
    return list.contains(maLichHen);
  }

  /// Đánh dấu ID lịch hẹn đã được hiện thông báo
  static Future<void> markAsNotified(String maLichHen) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyNotifiedIds) ?? [];
    if (!list.contains(maLichHen)) {
      list.add(maLichHen);
      await prefs.setStringList(_keyNotifiedIds, list);
    }
  }
}

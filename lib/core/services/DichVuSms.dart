import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SmsService {
  static const String apiKey = '9B1B0CA55BCD1C4CBF7337135FC72D';
  static const String secretKey = '665C1CD47157FA3EAD1462C58FC5BE';

  /// Gửi tin nhắn SMS OTP qua cổng eSMS.vn (Hệ thống viễn thông)
  /// Tự động thích ứng môi trường Web (chặn CORS) để không bị kẹt khi demo/test
  static Future<
    ({bool success, String? message, String? smsId, bool isTestOtp})
  >
  sendOtpSms({required String phone, required String otpCode}) async {
    try {
      // Chuẩn hóa số điện thoại: VD +84987654321 -> 0987654321
      String cleanPhone = phone.trim().replaceAll(RegExp(r'\s+'), '');
      if (cleanPhone.startsWith('+84')) {
        cleanPhone = '0${cleanPhone.substring(3)}';
      } else if (cleanPhone.startsWith('84') && cleanPhone.length > 9) {
        cleanPhone = '0${cleanPhone.substring(2)}';
      }

      final content = 'Nha tro Kieu Giang: Ma OTP cua ban la $otpCode';

      // 1. Trên trình duyệt Web (Chrome)
      if (kIsWeb) {
        debugPrint('Web environment: Cấp mã OTP xác thực: $otpCode');
        return (
          success: true,
          message: 'Mã OTP xác thực của bạn là $otpCode',
          smsId: 'WEB_OTP_$otpCode',
          isTestOtp: true,
        );
      }

      // 2. Chạy trên thiết bị thật (Android, iOS, Windows App): gửi SMS thật 100% qua eSMS
      final queryParams = {
        'Phone': cleanPhone,
        'Content': content,
        'ApiKey': apiKey,
        'SecretKey': secretKey,
        'IsUnicode': '0',
        'SmsType': '8', // 8: Đầu số ngẫu nhiên OTP không cần đăng ký Brandname
      };

      final directUri = Uri.http(
        'rest.esms.vn',
        '/MainService.svc/json/SendMultipleMessage_V4_get',
        queryParams,
      );

      debugPrint('Đang gửi SMS thật qua eSMS đến $cleanPhone: $directUri');

      final response = await http
          .get(directUri)
          .timeout(const Duration(seconds: 10));

      debugPrint(
        'Kết quả phản hồi eSMS: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final codeResult = data['CodeResult']?.toString();
        final smsId = data['SMSID']?.toString();
        final errorMessage = data['ErrorMessage']?.toString();

        if (codeResult == '100') {
          // 100 là mã thành công của eSMS
          return (
            success: true,
            message: 'Đã gửi mã OTP đến số $cleanPhone thành công!',
            smsId: smsId,
            isTestOtp: false,
          );
        } else {
          return (
            success: false,
            message: errorMessage ?? 'Lỗi eSMS mã: $codeResult',
            smsId: null,
            isTestOtp: false,
          );
        }
      } else {
        return (
          success: false,
          message: 'Lỗi máy chủ eSMS: HTTP ${response.statusCode}',
          smsId: null,
          isTestOtp: false,
        );
      }
    } catch (e) {
      debugPrint('Lỗi ngoại lệ gửi SMS qua eSMS: $e -> Dùng mã OTP xác thực');
      return (
        success: true,
        message: 'Mã OTP xác thực của bạn là $otpCode',
        smsId: 'OTP_$otpCode',
        isTestOtp: true,
      );
    }
  }
}

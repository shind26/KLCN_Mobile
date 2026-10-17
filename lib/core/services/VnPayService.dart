import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

class VnPayService {
  // Thông tin cấu hình chính thức từ email VNPAY Sandbox cấp
  static const String tmnCode = '6MIU5WOT';
  static const String hashSecret = 'AWQAUWDJMKCZVDNGYYGWURCAFDZTVWYN';
  static const String vnpUrl =
      'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';
  static const String returnUrl =
      'https://sandbox.vnpayment.vn/apis/vnpay-demo/';

  static String generatePaymentUrl({
    required String orderId,
    required double amount,
    required String orderInfo,
  }) {
    final now = DateTime.now();
    final expire = now.add(const Duration(minutes: 15));
    final formatter = DateFormat('yyyyMMddHHmmss');
    final createDate = formatter.format(now);
    final expireDate = formatter.format(expire);

    final cleanOrderId = orderId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final cleanOrderInfo = orderInfo.replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '');

    final Map<String, String> params = {
      'vnp_Version': '2.1.0',
      'vnp_Command': 'pay',
      'vnp_TmnCode': tmnCode,
      'vnp_Amount': '${(amount * 100).toInt()}',
      'vnp_CreateDate': createDate,
      'vnp_CurrCode': 'VND',
      'vnp_IpAddr': '127.0.0.1',
      'vnp_Locale': 'vn',
      'vnp_OrderInfo': cleanOrderInfo,
      'vnp_OrderType': 'other',
      'vnp_ReturnUrl': returnUrl,
      'vnp_ExpireDate': expireDate,
      'vnp_TxnRef': cleanOrderId,
    };

    // 1. Sắp xếp tham số theo alphabet
    final sortedKeys = params.keys.toList()..sort();

    // 2. Tạo chuỗi hashData và queryData chuẩn RFC 3986
    final List<String> hashParts = [];
    final List<String> queryParts = [];

    for (final key in sortedKeys) {
      final value = params[key]!;
      if (value.isNotEmpty) {
        final encodedKey = Uri.encodeQueryComponent(key);
        final encodedValue = Uri.encodeQueryComponent(value);
        hashParts.add('$encodedKey=$encodedValue');
        queryParts.add('$encodedKey=$encodedValue');
      }
    }

    final hashData = hashParts.join('&');
    final queryString = queryParts.join('&');

    // 3. Ký bảo mật HMAC SHA512
    final keyBytes = utf8.encode(hashSecret);
    final dataBytes = utf8.encode(hashData);
    final hmac = Hmac(sha512, keyBytes);
    final digest = hmac.convert(dataBytes);
    final secureHash = digest.toString();

    return '$vnpUrl?$queryString&vnp_SecureHash=$secureHash';
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';

void main() {
  group('DepositService Validation Tests', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    test('Không cho phép đặt ngày ở quá khứ', () {
      final pastDate = today.subtract(const Duration(days: 1));
      final res = DepositService.validateExpectedDate(pastDate);
      expect(res.isValid, isFalse);
      expect(res.error, contains('quá khứ'));
    });

    test('Cho phép chọn từ hôm nay đến 5 ngày tới', () {
      for (int i = 0; i <= 5; i++) {
        final validDate = today.add(Duration(days: i));
        final res = DepositService.validateExpectedDate(validDate);
        expect(res.isValid, isTrue, reason: 'Ngày $i từ hôm nay phải hợp lệ');
        expect(res.error, isNull);
      }
    });

    test('Không cho phép chọn ngày vượt quá 5 ngày', () {
      final futureDate = today.add(const Duration(days: 6));
      final res = DepositService.validateExpectedDate(futureDate);
      expect(res.isValid, isFalse);
      expect(res.error, contains('5 ngày'));
    });

    test('Giá trị tiền thế chân và thời hạn chuẩn', () {
      expect(DepositService.depositAmount, 100000.0);
      expect(DepositService.maxHoldDays, 5);
      expect(DepositService.paymentTimeoutMinutes, 15);
    });
  });
}

class VietQrHelper {
  static const String bankCode = '970422'; // MB Bank
  static const String accountNumber = '0865109632';
  static const String accountHolder = 'TRINH MY DUYEN';

  /// Tính toán mã kiểm tra CRC-16/CCITT-FALSE chuẩn EMVCo Quốc Tế
  static String calculateCrc16(String data) {
    int crc = 0xFFFF;
    for (int i = 0; i < data.length; i++) {
      crc ^= (data.codeUnitAt(i) << 8);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// Tạo chuỗi VietQR chuẩn EMVCo Napas247 cho QrImageView với mã CRC-16 hợp lệ để quét được
  static String generateVietQrString({
    required double amount,
    required String memo,
    required String bankBin,
    required String accountNo,
  }) {
    final amt = amount.toInt();
    final accLen = accountNo.length.toString().padLeft(2, '0');
    final amtStr = amt.toString();
    final amtLen = amtStr.length.toString().padLeft(2, '0');
    final memoLen = memo.length.toString().padLeft(2, '0');
    final total62Len = (memo.length + 4).toString().padLeft(2, '0');

    final payloadWithoutCrc =
        '00020101021238570010A00000072701270006${bankBin}01$accLen${accountNo}0208QRIBFTTA530370454$amtLen${amtStr}5802VN62${total62Len}08$memoLen${memo}6304';
    final crc = calculateCrc16(payloadWithoutCrc);
    return '$payloadWithoutCrc$crc';
  }

  /// Tạo link ảnh VietQR để tải hoặc lưu vào máy
  static String buildVietQrImageUrl({
    required double amount,
    required String memo,
    required String bankBin,
    required String accountNo,
    required String accountName,
  }) {
    final amt = amount.toInt();
    final addInfo = Uri.encodeComponent(memo.trim());
    final accName = Uri.encodeComponent(accountName.trim());
    return 'https://img.vietqr.io/image/MB-$accountNo-compact2.png?amount=$amt&addInfo=$addInfo&accountName=$accName';
  }

  /// Link ảnh VietQR động chung
  static String generateQrUrl({required num amount, required String noiDung}) {
    return buildVietQrImageUrl(
      amount: amount.toDouble(),
      memo: noiDung,
      bankBin: bankCode,
      accountNo: accountNumber,
      accountName: accountHolder,
    );
  }
}

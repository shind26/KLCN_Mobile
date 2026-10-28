import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

class KetQuaQuetDongHo {
  final double? chiSo;
  final String rawText;
  final bool thanhCong;
  final String? thongDiep;

  KetQuaQuetDongHo({
    this.chiSo,
    this.rawText = '',
    required this.thanhCong,
    this.thongDiep,
  });
}

class DichVuQuetDongHo {
  /// Danh sách các thông số kỹ thuật phổ biến trên mặt đồng hồ cơ cần loại trừ
  static final Set<num> _thongSoKyThuatBoQua = {
    // Điện áp & Tần số
    50, 60, 110, 220, 230, 380, 400,
    // Dòng điện định mức (Ampe)
    5, 10, 20, 40, 80, 100,
    // Hằng số xung công tơ (rev/kWh, imp/kWh)
    450, 900, 1000, 1200, 1600, 2000, 2400, 3200,
    // Năm sản xuất & Tiêu chuẩn
    2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020,
    2021, 2022, 2023, 2024, 2025, 2026, 2027, 2028, 2029, 2030,
  };

  /// Quét ảnh đồng hồ điện hoặc nước từ Uint8List — dùng Google ML Kit (on-device, offline)
  static Future<KetQuaQuetDongHo> quetChiSoDongHoBytes(
    Uint8List bytes, {
    required bool isDien,
    double chiSoCu = 0.0,
  }) async {
    File? tempFile;
    try {
      debugPrint(
        '[METER_OCR] Đang nhận diện ảnh đồng hồ ${isDien ? 'Điện' : 'Nước'} (Số cũ: $chiSoCu)...',
      );

      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/meter_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(bytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final textRecognizer = TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      RecognizedText recognizedText;
      try {
        recognizedText = await textRecognizer.processImage(inputImage);
      } finally {
        textRecognizer.close();
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }

      final parsedText = recognizedText.text;
      debugPrint('[METER_OCR] Văn bản OCR đọc được:\n$parsedText');

      if (parsedText.trim().isEmpty) {
        return KetQuaQuetDongHo(
          chiSo: null,
          thanhCong: false,
          thongDiep:
              'Không nhận diện được nội dung trên ảnh. Vui lòng chụp gần và đủ sáng hơn.',
        );
      }

      // ── TRÍCH XUẤT CHỈ SỐ THÔNG MINH ĐA TẦNG ──
      final double? chiSo = _trichXuatChiSoThongMinh(
        parsedText,
        isDien: isDien,
        chiSoCu: chiSoCu,
      );

      if (chiSo != null && chiSo > 0) {
        debugPrint(
          '[METER_OCR] => Đã tìm thấy chỉ số tối ưu: $chiSo ${isDien ? "kWh" : "m³"}',
        );

        // Kiểm tra xem số có biểu hiện bánh xe số đang quay lơ lửng không
        final isDangQuayDoChung =
            (chiSo % 1 != 0) || (chiSoCu > 0 && chiSo < chiSoCu);
        final msg = isDangQuayDoChung
            ? 'AI quét: $chiSo ${isDien ? 'kWh' : 'm³'} (Nếu số đang quay lơ lửng giữa chừng, bạn có thể chạm để chỉnh)'
            : 'AI quét thành công: $chiSo ${isDien ? 'kWh' : 'm³'}';

        return KetQuaQuetDongHo(
          chiSo: chiSo,
          rawText: parsedText,
          thanhCong: true,
          thongDiep: msg,
        );
      } else {
        debugPrint('[METER_OCR] => Không tìm thấy dãy số hợp lệ!');
        return KetQuaQuetDongHo(
          chiSo: null,
          rawText: parsedText,
          thanhCong: false,
          thongDiep: isDien
              ? 'Chưa đọc rõ hộp số công tơ điện. Vui lòng chụp thẳng góc dãy số trên mặt đồng hồ.'
              : 'Chưa đọc rõ hộp số đồng hồ nước. Vui lòng chụp thẳng góc dãy số trên mặt đồng hồ.',
        );
      }
    } catch (e) {
      debugPrint('[METER_OCR] Lỗi nhận diện: $e');
    }

    return KetQuaQuetDongHo(
      chiSo: null,
      thanhCong: false,
      thongDiep: isDien
          ? 'Không đọc được chỉ số điện. Vui lòng chụp gần và rõ nét hơn.'
          : 'Không đọc được chỉ số nước. Vui lòng chụp gần và rõ nét hơn.',
    );
  }

  /// Thuật toán trích xuất đa tầng:
  /// 1. Ưu tiên số đứng cùng dòng / sát đơn vị kWh / m³
  /// 2. Tìm dãy số hộp số cơ khí (Odometer: 3-6 chữ số, ví dụ 00392, 05167)
  /// 3. Ghép số bị tách rời bởi khoảng trắng hoặc xuống dòng do bánh xe số đỏ
  /// 4. Sửa lỗi ký tự do bánh xe quay lơ lửng giữa 2 số
  /// 5. Phân tích đối chiếu với chỉ số cũ để tự động phát hiện số đỏ thập phân
  static double? _trichXuatChiSoThongMinh(
    String text, {
    required bool isDien,
    required double chiSoCu,
  }) {
    if (text.trim().isEmpty) return null;
    final normalized = text.replaceAll('\r', '');
    final lines = normalized
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ── TẦNG 1: TÌM SỐ ĐỨNG NGAY TRƯỚC ĐƠN VỊ KWH HOẶC M3 ──
    final unitRegex = isDien
        ? RegExp(
            r'([0-9][0-9 \t.,]{0,10}[0-9]|[0-9])[ \t]*(?:kwh|kw\.h|kw/h)\b',
            caseSensitive: false,
          )
        : RegExp(
            r'([0-9][0-9 \t.,]{0,10}[0-9]|[0-9])[ \t]*(?:m3|m³|m\^3|m\s*3|m\s*³|m\b)(?![ \t]*/[ \t]*h)',
            caseSensitive: false,
          );

    for (final m in unitRegex.allMatches(normalized)) {
      final fullMatch = m.group(0)?.toLowerCase() ?? '';
      if (fullMatch.contains('rev') ||
          fullMatch.contains('imp') ||
          fullMatch.contains('/kwh') ||
          fullMatch.contains('/h')) {
        continue;
      }
      final rawNum = m.group(1);
      if (rawNum != null) {
        final val = _chuanHoaSo(rawNum);
        if (val != null && !_thongSoKyThuatBoQua.contains(val) && val > 0) {
          final adjusted = _dieuChinhTheoChiSoCu(
            val,
            isDien: isDien,
            chiSoCu: chiSoCu,
          );
          return adjusted;
        }
      }
    }

    // ── TẦNG 2: TÌM DÃY SỐ HỘP SỐ CÔNG TƠ (ODOMETER PATTERN) ──
    final candidates = <double>[];

    // Regex 1: Dãy số 3-6 chữ số (có thể có tiền tố H, No, № hoặc số 0 ở đầu)
    final odometerRegex = RegExp(
      r'(?:[HhNn№oO#]?\s*)([0-9]{3,6}(?:[.,][0-9])?)\b',
    );
    for (final line in lines) {
      final lower = line.toLowerCase();
      // Bỏ qua dòng chỉ chứa thông số kỹ thuật
      if (lower.contains('rev/kwh') ||
          lower.contains('imp/kwh') ||
          lower.contains('50hz') ||
          lower.contains('220v')) {
        continue;
      }
      for (final m in odometerRegex.allMatches(line)) {
        final val = _chuanHoaSo(m.group(1)!);
        if (val != null && !_thongSoKyThuatBoQua.contains(val) && val > 0) {
          candidates.add(val);
        }
      }
    }

    // Regex 2: Ghép số bị tách rời do ô số đỏ cách biệt (ví dụ: "0039 2" thành 00392)
    final splitNumRegex = RegExp(r'\b([0-9]{3,5})\s+([0-9])\b');
    for (final line in lines) {
      for (final m in splitNumRegex.allMatches(line)) {
        final combined = '${m.group(1)}${m.group(2)}';
        final val = _chuanHoaSo(combined);
        if (val != null && !_thongSoKyThuatBoQua.contains(val) && val > 0) {
          candidates.add(val);
        }
      }
    }

    // Regex 3: Ghép số bị ngắt qua 2 dòng (Dòng 1: "H 0039", Dòng 2: "2" hoặc "2 m³")
    for (int i = 0; i < lines.length - 1; i++) {
      final m1 = RegExp(r'([0-9]{3,5})$').firstMatch(lines[i]);
      final m2 = RegExp(r'^([0-9])\b').firstMatch(lines[i + 1]);
      if (m1 != null && m2 != null) {
        final combined = '${m1.group(1)}${m2.group(1)}';
        final val = _chuanHoaSo(combined);
        if (val != null && !_thongSoKyThuatBoQua.contains(val) && val > 0) {
          candidates.add(val);
        }
      }
    }

    // Regex 4: Sửa lỗi bánh xe quay lơ lửng bị ML Kit đọc thành ký tự chữ ở cuối (ví dụ "0039z" -> "00392")
    final rotateFixRegex = RegExp(r'\b([0-9]{3,5})([a-zA-Z])\b');
    for (final line in lines) {
      for (final m in rotateFixRegex.allMatches(line)) {
        final base = m.group(1)!;
        final letter = m.group(2)!.toLowerCase();
        final fixedChar = _suaKyTuQuayLoLung(letter);
        if (fixedChar != null) {
          final val = _chuanHoaSo('$base$fixedChar');
          if (val != null && !_thongSoKyThuatBoQua.contains(val) && val > 0) {
            candidates.add(val);
          }
        }
      }
    }

    if (candidates.isEmpty) return null;

    // ── TẦNG 3: CHẤM ĐIỂM VÀ LỰA CHỌN ỨNG VIÊN TỐI ƯU DỰA TRÊN SỐ CŨ ──
    double? bestVal;
    double bestScore = -999999;

    for (final cand in candidates) {
      final adjusted = _dieuChinhTheoChiSoCu(
        cand,
        isDien: isDien,
        chiSoCu: chiSoCu,
      );
      double score = 0;

      if (chiSoCu > 0) {
        if (adjusted >= chiSoCu) {
          final diff = adjusted - chiSoCu;
          final maxHopLy = isDien ? 800.0 : 60.0;
          if (diff <= maxHopLy) {
            // Mức tiêu thụ tháng rất hợp lý -> điểm cực cao
            score = 1000 - diff;
          } else {
            // Tăng quá cao so với số cũ
            score = 500 - (diff / 10);
          }
        } else {
          // Nhỏ hơn số cũ
          score = -100 - (chiSoCu - adjusted);
        }
      } else {
        // Chưa có số cũ: Ưu tiên dãy số có giá trị lớn hơn các hằng số nhỏ
        score = adjusted;
      }

      if (score > bestScore) {
        bestScore = score;
        bestVal = adjusted;
      }
    }

    return bestVal;
  }

  /// Tự động phát hiện và xử lý số đỏ thập phân của công tơ cơ khí:
  /// Ví dụ công tơ điện hiển thị 0516 (đen) + 7 (đỏ) -> OCR đọc 5167.
  /// Nếu số cũ là 210, 5167 là vô lý (tăng 4957 kWh), nhưng 516.7 thì tăng 306.7 kWh (rất hợp lý)!
  static double _dieuChinhTheoChiSoCu(
    double val, {
    required bool isDien,
    required double chiSoCu,
  }) {
    if (chiSoCu <= 0) return val;

    if (isDien) {
      // Nếu số đọc được lớn hơn số cũ gấp nhiều lần (> 4 lần) và > 1000:
      // Khả năng cao có 1 chữ số đỏ thập phân ở hàng cuối cùng
      if (val > chiSoCu * 4 && val > 1000) {
        final valDiv10 = double.parse((val / 10).toStringAsFixed(1));
        if (valDiv10 >= chiSoCu && (valDiv10 - chiSoCu) < 800) {
          return valDiv10;
        }
      }
    } else {
      // Đối với nước: tương tự nếu OCR đọc cả số đỏ
      if (val > chiSoCu * 5 && val > 1000) {
        final valDiv10 = double.parse((val / 10).toStringAsFixed(1));
        if (valDiv10 >= chiSoCu && (valDiv10 - chiSoCu) < 100) {
          return valDiv10;
        }
      }
    }

    return val;
  }

  /// Chuyển đổi các ký tự nhận diện nhầm khi bánh xe số cơ khí quay lơ lửng giữa 2 vạch
  static String? _suaKyTuQuayLoLung(String letter) {
    switch (letter) {
      case 'o':
      case 'd':
        return '0';
      case 'i':
      case 'l':
        return '1';
      case 'z':
        return '2';
      case 'e':
        return '3';
      case 'a':
        return '4';
      case 's':
        return '5';
      case 'b':
        return '8';
      case 'g':
      case 'q':
        return '9';
      default:
        return null;
    }
  }

  /// Chuẩn hóa số: loại khoảng trắng, đổi dấu phẩy thành dấu chấm
  static double? _chuanHoaSo(String raw) {
    String clean = raw.replaceAll(RegExp(r'[ \t]+'), '');
    clean = clean.replaceAll(',', '.');
    final dotCount = '.'.allMatches(clean).length;
    if (dotCount > 1) {
      final parts = clean.split('.');
      clean = '${parts.sublist(0, parts.length - 1).join('')}.${parts.last}';
    }
    return double.tryParse(clean);
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class KetQuaQuetCccd {
  final String hoTen;
  final String soCccd;
  final String? ngaySinh;
  final String? gioiTinh;
  final String? queQuan;
  final String? diaChiThuongTru;
  final String? ngayCap;
  final String? noiCap;
  final String rawText;

  KetQuaQuetCccd({
    required this.hoTen,
    required this.soCccd,
    this.ngaySinh,
    this.gioiTinh,
    this.queQuan,
    this.diaChiThuongTru,
    this.ngayCap,
    this.noiCap,
    this.rawText = '',
  });

  bool get hopLe => hoTen.isNotEmpty || soCccd.isNotEmpty;
}

class DichVuQuetCccd {
  static const String _ocrApiKey = 'helloworld'; // Hoặc K88796868888957
  static const String _ocrApiUrl = 'https://api.ocr.space/parse/image';

  /// Quét ảnh CCCD từ Uint8List bytes (hoạt động tốt trên cả Web và Mobile)
  static Future<KetQuaQuetCccd?> quetAnhCccdBytes(Uint8List bytes) async {
    try {
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';

      debugPrint('[OCR] Bắt đầu gửi ảnh lên OCR engine...');

      final response = await http
          .post(
            Uri.parse(_ocrApiUrl),
            headers: {'apikey': _ocrApiKey},
            body: {
              'base64Image': base64Image,
              'language': 'vnm',
              'isOverlayRequired': 'false',
              'detectOrientation': 'true',
              'scale': 'true',
              'OCREngine': '2',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['OCRExitCode'] == 1 &&
            data['ParsedResults'] != null &&
            (data['ParsedResults'] as List).isNotEmpty) {
          final parsedText =
              data['ParsedResults'][0]['ParsedText'] as String? ?? '';
          debugPrint('[OCR] Raw text nhận diện:\n$parsedText');
          return _phanTichThongTinCccd(parsedText);
        }
      }
    } catch (e) {
      debugPrint('[OCR] Lỗi khi quét OCR: $e');
    }

    return null;
  }

  /// Quét ảnh CCCD từ File
  static Future<KetQuaQuetCccd?> quetAnhCccd(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      return quetAnhCccdBytes(bytes);
    } catch (e) {
      debugPrint('[OCR] Lỗi đọc file: $e');
      return null;
    }
  }

  /// Bóc tách các trường: Số CCCD (12 số), Họ và tên, Giới tính, Thường trú, Ngày sinh...
  static KetQuaQuetCccd _phanTichThongTinCccd(String text) {
    String hoTen = '';
    String soCccd = '';
    String? ngaySinh;
    String? gioiTinh;
    String? queQuan;
    String? diaChiThuongTru;
    String? ngayCap;
    String? noiCap;

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1. Tìm số CCCD: 12 chữ số liên tiếp (bắt đầu bằng 0)
    final cccdRegex = RegExp(r'\b0\d{11}\b');
    final cccdFallbackRegex = RegExp(r'\b\d{12}\b');

    for (final line in lines) {
      final match =
          cccdRegex.firstMatch(line) ?? cccdFallbackRegex.firstMatch(line);
      if (match != null) {
        soCccd = match.group(0)!;
        break;
      }
    }

    // 2. Tìm ngày sinh: dạng dd/mm/yyyy
    final dobRegex = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('sinh') ||
          lower.contains('birth') ||
          lower.contains('ngày')) {
        final match = dobRegex.firstMatch(line);
        if (match != null) {
          ngaySinh = match.group(1);
          break;
        }
      }
    }
    // Fallback ngày sinh nếu chưa có
    if (ngaySinh == null) {
      for (final line in lines) {
        final match = dobRegex.firstMatch(line);
        if (match != null) {
          ngaySinh = match.group(1);
          break;
        }
      }
    }

    // 3. Giới tính
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('giới tính') || lower.contains('sex')) {
        if (lower.contains('nữ') ||
            lower.contains('nu') ||
            lower.contains('female')) {
          gioiTinh = 'Nữ';
          break;
        } else if (lower.contains('nam') || lower.contains('male')) {
          gioiTinh = 'Nam';
          break;
        }
      }
    }

    // 4. Tìm Họ và tên:
    final nameKeyRegex = RegExp(
      r'(họ\s*và\s*tên|full\s*name|họ\s*tên|họ\s*và\s*chữ\s*đệm)',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (nameKeyRegex.hasMatch(line)) {
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1 && colonIdx < line.length - 1) {
          final potentialName = line.substring(colonIdx + 1).trim();
          if (_laTenNguoiHopLe(potentialName)) {
            hoTen = _chuanHoaTen(potentialName);
            break;
          }
        }

        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (_laTenNguoiHopLe(nextLine)) {
            hoTen = _chuanHoaTen(nextLine);
            break;
          }
        }
      }
    }

    // Fallback tìm tên bằng chữ in hoa toàn bộ tiếng Việt
    if (hoTen.isEmpty) {
      final uppercaseVietnameseRegex = RegExp(
        r'^[A-ZÀÁẢÃẠÂẦẤẨẪẬĂẰẮẲẴẶÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ\s]{5,}$',
      );

      for (final line in lines) {
        final upper = line.toUpperCase();
        if (upper.contains('CỘNG HÒA') ||
            upper.contains('ĐỘC LẬP') ||
            upper.contains('CĂN CƯỚC') ||
            upper.contains('CỤC CẢNH SÁT') ||
            upper.contains('VIỆT NAM')) {
          continue;
        }

        if (uppercaseVietnameseRegex.hasMatch(line) &&
            line.split(' ').length >= 2) {
          hoTen = _chuanHoaTen(line);
          break;
        }
      }
    }

    // 5. Nơi thường trú (Place of residence)
    final resRegex = RegExp(
      r'(nơi\s*thường\s*trú|place\s*of\s*residence|thường\s*trú)',
      caseSensitive: false,
    );
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (resRegex.hasMatch(line)) {
        String address = '';
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1 && colonIdx < line.length - 1) {
          address = line.substring(colonIdx + 1).trim();
        }
        // Kiểm tra các dòng kế tiếp nếu địa chỉ dài nhiều dòng
        int nextIdx = i + 1;
        while (nextIdx < lines.length) {
          final nextL = lines[nextIdx].trim();
          if (nextL.toLowerCase().contains('ngày') ||
              nextL.toLowerCase().contains('có giá trị') ||
              nextL.toLowerCase().contains('date of expiry')) {
            break;
          }
          if (address.isEmpty) {
            address = nextL;
          } else {
            address += ', $nextL';
          }
          nextIdx++;
          if (nextIdx > i + 2) break; // Lấy tối đa 2 dòng tiếp theo
        }
        if (address.isNotEmpty) {
          diaChiThuongTru = address;
          break;
        }
      }
    }

    // 6. Quê quán (Place of origin)
    final originRegex = RegExp(
      r'(quê\s*quán|place\s*of\s*origin)',
      caseSensitive: false,
    );
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (originRegex.hasMatch(line)) {
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1 && colonIdx < line.length - 1) {
          queQuan = line.substring(colonIdx + 1).trim();
          break;
        } else if (i + 1 < lines.length) {
          queQuan = lines[i + 1].trim();
          break;
        }
      }
    }

    // 7. Nơi cấp / Cục CS QLHC về TTXH
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.contains('CỤC CẢNH SÁT') || upper.contains('QLHC VỀ TTXH')) {
        noiCap = 'Cục Cảnh sát QLHC về TTXH';
        break;
      }
    }

    return KetQuaQuetCccd(
      hoTen: hoTen,
      soCccd: soCccd,
      ngaySinh: ngaySinh,
      gioiTinh: gioiTinh,
      queQuan: queQuan,
      diaChiThuongTru: diaChiThuongTru,
      ngayCap: ngayCap,
      noiCap: noiCap ?? 'Cục Cảnh sát QLHC về TTXH',
      rawText: text,
    );
  }

  static bool _laTenNguoiHopLe(String str) {
    if (str.length < 4) return false;
    final words = str.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return false;
    final upper = str.toUpperCase();
    if (upper.contains('CỘNG HÒA') ||
        upper.contains('CĂN CƯỚC') ||
        upper.contains('NGÀY') ||
        upper.contains('GIỚI TÍNH')) {
      return false;
    }
    return true;
  }

  static String _chuanHoaTen(String raw) {
    final words = raw.trim().split(RegExp(r'\s+'));
    return words
        .map((w) {
          if (w.isEmpty) return '';
          final lower = w.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
  }
}

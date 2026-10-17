import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class KetQuaQuetCccd {
  final String hoTen;
  final String soCccd;
  final String? ngaySinh;
  final String? gioiTinh;
  final String? diaChi;
  final String? queQuan;
  final String rawText;
  final String nguon;

  KetQuaQuetCccd({
    required this.hoTen,
    required this.soCccd,
    this.ngaySinh,
    this.gioiTinh,
    this.diaChi,
    this.queQuan,
    this.rawText = '',
    this.nguon = 'AI OCR',
  });

  bool get hopLe => hoTen.isNotEmpty || soCccd.isNotEmpty;
}

class DichVuQuetCccd {
  static const String _ocrApiKey = 'helloworld'; // API key dự phòng
  static const String _ocrApiUrl = 'https://api.ocr.space/parse/image';

  /// Quét ảnh CCCD từ File (tự động thử Google ML Kit offline trước, sau đó fallback sang OCR API)
  static Future<KetQuaQuetCccd?> quetAnhCccd(File imageFile) async {
    try {
      // 1. Thử Google ML Kit (Offline, siêu tốc trên máy)
      try {
        final inputImage = InputImage.fromFilePath(imageFile.path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final recognizedText = await textRecognizer.processImage(inputImage);
          final text = recognizedText.text;
          debugPrint('[CCCD_OCR] ML Kit raw text:\n$text');
          if (text.trim().isNotEmpty) {
            final ketQua = _phanTichThongTinCccd(text, nguon: 'Google ML Kit');
            if (ketQua.hopLe) {
              return ketQua;
            }
          }
        } finally {
          await textRecognizer.close();
        }
      } catch (mlError) {
        debugPrint('[CCCD_OCR] ML Kit không khả dụng trên thiết bị này: $mlError');
      }

      // 2. Fallback sang OCR API online qua bytes
      final bytes = await imageFile.readAsBytes();
      return await quetAnhCccdBytes(bytes);
    } catch (e) {
      debugPrint('[CCCD_OCR] Lỗi quetAnhCccd: $e');
      return null;
    }
  }

  /// Quét ảnh CCCD từ Uint8List bytes
  static Future<KetQuaQuetCccd?> quetAnhCccdBytes(Uint8List bytes) async {
    File? tempFile;
    try {
      // 1. Thử lưu file tạm và quét qua ML Kit
      try {
        final tempDir = await getTemporaryDirectory();
        tempFile = File('${tempDir.path}/cccd_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(bytes);

        final inputImage = InputImage.fromFilePath(tempFile.path);
        final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
        try {
          final recognizedText = await textRecognizer.processImage(inputImage);
          final text = recognizedText.text;
          if (text.trim().isNotEmpty) {
            final ketQua = _phanTichThongTinCccd(text, nguon: 'Google ML Kit');
            if (ketQua.hopLe) {
              return ketQua;
            }
          }
        } finally {
          await textRecognizer.close();
        }
      } catch (e) {
        debugPrint('[CCCD_OCR] ML Kit temp file check: $e');
      } finally {
        if (tempFile != null && await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }

      // 2. Dự phòng OCR.space API
      final base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      debugPrint('[CCCD_OCR] Gửi ảnh lên OCR.space API fallback...');

      final response = await http.post(
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
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['OCRExitCode'] == 1 &&
            data['ParsedResults'] != null &&
            (data['ParsedResults'] as List).isNotEmpty) {
          final parsedText = data['ParsedResults'][0]['ParsedText'] as String? ?? '';
          debugPrint('[CCCD_OCR] OCR.space parsed text:\n$parsedText');
          return _phanTichThongTinCccd(parsedText, nguon: 'OCR Online');
        }
      }
    } catch (e) {
      debugPrint('[CCCD_OCR] Lỗi khi quét OCR: $e');
    }

    return null;
  }

  /// Bóc tách các trường: Số CCCD (12 số), Họ và tên, Ngày sinh, Giới tính, Quê quán, Địa chỉ
  static KetQuaQuetCccd _phanTichThongTinCccd(String text, {String nguon = 'AI OCR'}) {
    // 0. Kiểm tra xem có phải định dạng mã QR của CCCD gắn chip không
    // Cấu trúc QR: Số CCCD|Số CMND cũ|Họ và tên|Ngày sinh (ddMMyyyy)|Giới tính|Địa chỉ thường trú|Ngày cấp
    final qrPattern = RegExp(r'(\d{12})\|([^|]*)\|([^|]+)\|(\d{8})\|([^|]+)\|([^|\n]+)');
    final qrMatch = qrPattern.firstMatch(text);
    if (qrMatch != null) {
      final cccd = qrMatch.group(1) ?? '';
      final hoTen = _chuanHoaTen(qrMatch.group(3) ?? '');
      final rawDob = qrMatch.group(4) ?? '';
      String? dob;
      if (rawDob.length == 8) {
        dob = '${rawDob.substring(0, 2)}/${rawDob.substring(2, 4)}/${rawDob.substring(4, 8)}';
      }
      final gioiTinh = qrMatch.group(5)?.trim();
      final diaChi = qrMatch.group(6)?.trim();

      return KetQuaQuetCccd(
        hoTen: hoTen,
        soCccd: cccd,
        ngaySinh: dob,
        gioiTinh: gioiTinh,
        diaChi: diaChi,
        rawText: text,
        nguon: 'QR CCCD',
      );
    }

    String hoTen = '';
    String soCccd = '';
    String? ngaySinh;
    String? gioiTinh;
    String? queQuan;
    String? diaChi;

    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1. Tìm số CCCD: 12 chữ số liên tiếp (bắt đầu bằng 0) hoặc 9 số CMND cũ
    final cccdRegex = RegExp(r'\b0\d{11}\b');
    final cccdSpacingRegex = RegExp(r'\b0\d{2}\s\d{3}\s\d{6}\b');
    final cccdFallbackRegex = RegExp(r'\b\d{12}\b');

    for (final line in lines) {
      final match = cccdRegex.firstMatch(line) ??
          cccdFallbackRegex.firstMatch(line);
      if (match != null) {
        soCccd = match.group(0)!;
        break;
      }
      final matchSpace = cccdSpacingRegex.firstMatch(line);
      if (matchSpace != null) {
        soCccd = matchSpace.group(0)!.replaceAll(' ', '');
        break;
      }
    }

    // Nếu dòng có chữ "Số" hoặc "No", trích xuất số sau nó
    if (soCccd.isEmpty) {
      for (final line in lines) {
        if (RegExp(r'(số|no\.?|số\s*căn\s*cước)', caseSensitive: false).hasMatch(line)) {
          final digits = line.replaceAll(RegExp(r'\D'), '');
          if (digits.length == 12 || digits.length == 9) {
            soCccd = digits;
            break;
          }
        }
      }
    }

    // 2. Tìm ngày sinh: dạng dd/mm/yyyy
    final dobRegex = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');
    for (final line in lines) {
      if (RegExp(r'(ngày\s*sinh|date\s*of\s*birth|sinh\s*ngày)', caseSensitive: false).hasMatch(line)) {
        final match = dobRegex.firstMatch(line);
        if (match != null) {
          ngaySinh = match.group(1);
          break;
        }
      }
    }
    if (ngaySinh == null) {
      for (final line in lines) {
        final match = dobRegex.firstMatch(line);
        if (match != null) {
          ngaySinh = match.group(1);
          break;
        }
      }
    }

    // 3. Tìm Giới tính: Nam / Nữ / Male / Female
    for (final line in lines) {
      if (RegExp(r'(giới\s*tính|sex)', caseSensitive: false).hasMatch(line)) {
        if (RegExp(r'\b(nam|male)\b', caseSensitive: false).hasMatch(line)) {
          gioiTinh = 'Nam';
          break;
        } else if (RegExp(r'\b(nữ|nu|female)\b', caseSensitive: false).hasMatch(line)) {
          gioiTinh = 'Nữ';
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
        // Tên cùng dòng sau dấu :
        final colonIdx = line.indexOf(':');
        if (colonIdx != -1 && colonIdx < line.length - 1) {
          final potentialName = line.substring(colonIdx + 1).trim();
          if (_laTenNguoiHopLe(potentialName)) {
            hoTen = _chuanHoaTen(potentialName);
            break;
          }
        }

        // Tên ở dòng tiếp theo
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (_laTenNguoiHopLe(nextLine)) {
            hoTen = _chuanHoaTen(nextLine);
            break;
          }
        }
      }
    }

    // Nếu chưa tìm thấy họ tên, quét dòng IN HOA toàn bộ tiếng Việt
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
            upper.contains('VIỆT NAM') ||
            upper.contains('XÃ HỘI') ||
            upper.contains('CHỦ NGHĨA')) {
          continue;
        }

        if (uppercaseVietnameseRegex.hasMatch(line) && line.split(' ').length >= 2) {
          hoTen = _chuanHoaTen(line);
          break;
        }
      }
    }

    // 5. Tìm Địa chỉ / Quê quán / Nơi thường trú
    final addressKeyRegex = RegExp(
      r'(nơi\s*thường\s*trú|thường\s*trú|place\s*of\s*residence|quê\s*quán|place\s*of\s*origin)',
      caseSensitive: false,
    );

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (addressKeyRegex.hasMatch(line)) {
        final colonIdx = line.indexOf(':');
        String addrPart = '';
        if (colonIdx != -1 && colonIdx < line.length - 1) {
          addrPart = line.substring(colonIdx + 1).trim();
        }
        // Ghép dòng tiếp theo nếu có
        if (i + 1 < lines.length) {
          final nextLine = lines[i + 1].trim();
          if (!nextLine.contains(':') && nextLine.length > 3) {
            addrPart = addrPart.isEmpty ? nextLine : '$addrPart, $nextLine';
          }
        }
        if (addrPart.isNotEmpty) {
          diaChi = addrPart;
          break;
        }
      }
    }

    return KetQuaQuetCccd(
      hoTen: hoTen,
      soCccd: soCccd,
      ngaySinh: ngaySinh,
      gioiTinh: gioiTinh,
      diaChi: diaChi,
      queQuan: queQuan,
      rawText: text,
      nguon: nguon,
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
        upper.contains('GIỚI TÍNH') ||
        upper.contains('VIỆT NAM') ||
        upper.contains('QUỐC TỊCH')) {
      return false;
    }
    return true;
  }

  static String _chuanHoaTen(String raw) {
    final words = raw.trim().split(RegExp(r'\s+'));
    return words.map((w) {
      if (w.isEmpty) return '';
      final lower = w.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThongBaoType { thanhCong, canhBao, thatBai, thongTin }

class ThongBaoHelper {
  // Bộ nhớ đệm lưu các thông báo / sự kiện người dùng đã bấm 'Đã hiểu'
  static final Set<String> _daXemTags = {};
  static bool _daKhoiTao = false;

  /// Khởi tạo và nạp danh sách tag đã bấm xác nhận từ SharedPreferences
  static Future<void> init() async {
    if (_daKhoiTao) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('kieugiang_daxem_thongbao_keys') ?? [];
      _daXemTags.addAll(list);
      _daKhoiTao = true;
    } catch (e) {
      debugPrint('[THONG_BAO] Lỗi nạp tag đã xem: $e');
    }
  }

  /// Kiểm tra xem một sự kiện/thông báo đã được bấm 'Đã hiểu' chưa
  static bool daXem(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    return _daXemTags.contains(tag);
  }

  /// Đánh dấu một sự kiện đã được xem và lưu vĩnh viễn vào SharedPreferences
  static Future<void> danhDauDaXem(String? tag) async {
    if (tag == null || tag.isEmpty) return;
    _daXemTags.add(tag);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _daXemTags.toList();
      if (list.length > 300) {
        list.removeRange(0, list.length - 300);
      }
      await prefs.setStringList('kieugiang_daxem_thongbao_keys', list);
    } catch (_) {}
  }

  /// Hiển thị thông báo dạng Modal Dialog nổi bật ngay giữa màn hình
  /// - Nếu truyền [tag], hệ thống sẽ đảm bảo chỉ hiện duy nhất 1 LẦN cho đến khi người dùng bấm xác nhận
  ///   và KHÔNG BAO GIỜ hiện lại lần 2 hay lần 3 khi quay lại màn hình.
  static Future<void> hienThongBao(
    BuildContext context, {
    required String tieuDe,
    required String noiDung,
    ThongBaoType type = ThongBaoType.thongTin,
    String nutText = 'Đã hiểu',
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
    String? tag,
    bool force = false,
  }) async {
    if (!context.mounted) return;

    if (tag != null && tag.isNotEmpty && !force) {
      if (!_daKhoiTao) {
        await init();
      }
      if (_daXemTags.contains(tag)) {
        debugPrint('[THONG_BAO] Bỏ qua vì người dùng đã bấm Đã hiểu trước đó cho tag=$tag');
        return;
      }
      // Ghi nhận ngay vào RAM để chặn hiện dialog đúp nếu có nhiều timer/stream cùng kích hoạt
      _daXemTags.add(tag);
    }

    Color primaryColor;
    Color bgColor;
    Color borderColor;
    IconData icon;

    switch (type) {
      case ThongBaoType.thanhCong:
        primaryColor = const Color(0xFF16A34A);
        bgColor = const Color(0xFFDCFCE7);
        borderColor = const Color(0xFF86EFAC);
        icon = Icons.check_circle_rounded;
        break;
      case ThongBaoType.canhBao:
        primaryColor = const Color(0xFFD97706);
        bgColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFFCD34D);
        icon = Icons.warning_amber_rounded;
        break;
      case ThongBaoType.thatBai:
        primaryColor = const Color(0xFFDC2626);
        bgColor = const Color(0xFFFEE2E2);
        borderColor = const Color(0xFFFCA5A5);
        icon = Icons.error_outline_rounded;
        break;
      case ThongBaoType.thongTin:
        primaryColor = const Color(0xFF09638E);
        bgColor = const Color(0xFFE0F2FE);
        borderColor = const Color(0xFFBAE6FD);
        icon = Icons.info_outline_rounded;
        break;
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon ở giữa với vòng tròn màu
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: borderColor, width: 2.5),
                    ),
                    child: Icon(icon, color: primaryColor, size: 36),
                  ),
                  const SizedBox(height: 16),

                  // Tiêu đề
                  Text(
                    tieuDe,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Nội dung
                  Text(
                    noiDung,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF475569),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Nút bấm xác nhận (Đã hiểu)
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: () {
                        if (tag != null && tag.isNotEmpty) {
                          danhDauDaXem(tag);
                        }
                        Navigator.of(ctx).pop();
                        if (onConfirm != null) onConfirm();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        nutText,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Khi đóng dialog (dù bấm nút hay bấm ra ngoài), lưu tag vĩnh viễn
    if (tag != null && tag.isNotEmpty) {
      await danhDauDaXem(tag);
    }
  }
}


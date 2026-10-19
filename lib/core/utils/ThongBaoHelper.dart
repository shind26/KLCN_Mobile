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

    Color gradientStart;
    Color gradientEnd;
    Color tagBg;
    Color tagColor;
    String tagLabel;
    IconData iconData;

    switch (type) {
      case ThongBaoType.thanhCong:
        gradientStart = const Color(0xFF10B981);
        gradientEnd = const Color(0xFF059669);
        tagBg = const Color(0xFFECFDF5);
        tagColor = const Color(0xFF047857);
        tagLabel = 'THÀNH CÔNG';
        iconData = Icons.check_circle_rounded;
        break;
      case ThongBaoType.canhBao:
        gradientStart = const Color(0xFFF59E0B);
        gradientEnd = const Color(0xFFD97706);
        tagBg = const Color(0xFFFFFBEB);
        tagColor = const Color(0xFFB45309);
        tagLabel = 'LƯU Ý QUAN TRỌNG';
        iconData = Icons.info_rounded;
        break;
      case ThongBaoType.thatBai:
        gradientStart = const Color(0xFFF43F5E);
        gradientEnd = const Color(0xFFE11D48);
        tagBg = const Color(0xFFFFF1F2);
        tagColor = const Color(0xFFBE123C);
        tagLabel = 'THÔNG BÁO HỆ THỐNG';
        iconData = Icons.priority_high_rounded;
        break;
      case ThongBaoType.thongTin:
        gradientStart = const Color(0xFF0284C7);
        gradientEnd = const Color(0xFF09638E);
        tagBg = const Color(0xFFF0F9FF);
        tagColor = const Color(0xFF0369A1);
        tagLabel = 'THÔNG BÁO';
        iconData = Icons.notifications_active_rounded;
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
              constraints: const BoxConstraints(maxWidth: 390),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: gradientStart.withValues(alpha: 0.14),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(color: const Color(0xFFF1F5F9), width: 1.2),
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Icon đôi với vòng sáng dịu hiện đại
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: gradientStart.withValues(alpha: 0.12),
                        ),
                      ),
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [gradientStart, gradientEnd],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: gradientStart.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(iconData, color: Colors.white, size: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Tag phân loại thông báo
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: tagBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: gradientStart.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      tagLabel,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: tagColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

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
                  const SizedBox(height: 12),

                  // Khung nội dung trang nhã
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      noiDung,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF334155),
                        height: 1.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Nút bấm xác nhận hiện đại với hiệu ứng gradient
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [gradientStart, gradientEnd],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: gradientStart.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            if (tag != null && tag.isNotEmpty) {
                              danhDauDaXem(tag);
                            }
                            Navigator.of(ctx).pop();
                            if (onConfirm != null) onConfirm();
                          },
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  nutText,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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

  /// Hiển thị thông báo nhanh (Toast HUD) nổi bật ngay chính GIỮA MÀN HÌNH
  /// Tự động biến mất sau [duration] (mặc định 2.2 giây) hoặc khi người dùng chạm vào
  static Future<void> hienToast(
    BuildContext context, {
    required String noiDung,
    String? tieuDe,
    ThongBaoType type = ThongBaoType.thanhCong,
    Duration duration = const Duration(milliseconds: 2200),
  }) async {
    if (!context.mounted) return;

    Color bgGradient1;
    Color bgGradient2;
    IconData icon;
    String defaultTitle;

    switch (type) {
      case ThongBaoType.thanhCong:
        bgGradient1 = const Color(0xFF10B981);
        bgGradient2 = const Color(0xFF059669);
        icon = Icons.check_circle_rounded;
        defaultTitle = 'Thành công';
        break;
      case ThongBaoType.thatBai:
        bgGradient1 = const Color(0xFFF43F5E);
        bgGradient2 = const Color(0xFFE11D48);
        icon = Icons.cancel_rounded;
        defaultTitle = 'Thất bại';
        break;
      case ThongBaoType.canhBao:
        bgGradient1 = const Color(0xFFF59E0B);
        bgGradient2 = const Color(0xFFD97706);
        icon = Icons.warning_amber_rounded;
        defaultTitle = 'Lưu ý';
        break;
      case ThongBaoType.thongTin:
        bgGradient1 = const Color(0xFF0EA5E9);
        bgGradient2 = const Color(0xFF0284C7);
        icon = Icons.info_outline_rounded;
        defaultTitle = 'Thông báo';
        break;
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ToastDismiss',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (toastCtx, _, __) {
        // Tự động tắt sau khoảng thời gian duration
        Future.delayed(duration, () {
          if (toastCtx.mounted && Navigator.canPop(toastCtx)) {
            Navigator.pop(toastCtx);
          }
        });

        return Center(
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: () {
                if (toastCtx.mounted && Navigator.canPop(toastCtx)) {
                  Navigator.pop(toastCtx);
                }
              },
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: bgGradient1.withValues(alpha: 0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [bgGradient1, bgGradient2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: bgGradient1.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tieuDe ?? defaultTitle,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        noiDung,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF475569),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}


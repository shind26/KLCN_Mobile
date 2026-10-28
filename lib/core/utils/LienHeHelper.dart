import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

class LienHeHelper {
  /// Số điện thoại Hotline & Zalo chính của Nhà Trọ Kiều Giang
  static const String defaultHotline = '0328004663';
  static const String defaultHotlineDisplay = '0328.004.663';

  /// Mở ứng dụng Zalo thật để nhắn tin với chủ trọ / ban quản lý
  /// Sử dụng đường dẫn chính thức https://zalo.me/so_dien_thoai
  static Future<void> moZaloChat(BuildContext context, {String? phone}) async {
    final targetPhone = (phone ?? defaultHotline).replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final zaloUri = Uri.parse('https://zalo.me/$targetPhone');

    try {
      final launched = await launchUrl(
        zaloUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Thông báo Zalo',
          noiDung:
              'Không thể mở ứng dụng Zalo. Bạn có thể liên hệ trực tiếp qua số: $targetPhone',
          type: ThongBaoType.canhBao,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Lỗi Zalo',
          noiDung: 'Không thể kết nối Zalo: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  /// Thực hiện cuộc gọi điện thoại trực tiếp đến Hotline
  static Future<void> goiDien(BuildContext context, {String? phone}) async {
    final targetPhone = (phone ?? defaultHotline).replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final telUri = Uri.parse('tel:$targetPhone');

    try {
      final launched = await launchUrl(
        telUri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Không thể gọi điện',
          noiDung: 'Không thể mở trình quay số điện thoại cho số: $targetPhone',
          type: ThongBaoType.canhBao,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Lỗi cuộc gọi',
          noiDung: 'Lỗi thực hiện cuộc gọi: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  /// Hiển thị bảng chọn tiện ích: Gọi Hotline hoặc Nhắn tin Zalo
  static void hienThiLuaChonLienHe(
    BuildContext context, {
    String? phone,
    String title = 'Liên hệ Ban Quản Lý Kiều Giang',
  }) {
    final display = phone ?? defaultHotlineDisplay;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hotline / Zalo: $display',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBF5FA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: Color(0xFF09638E),
                    ),
                  ),
                  title: const Text(
                    'Nhắn tin qua Zalo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Mở ứng dụng Zalo thật để trò chuyện trực tiếp',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    moZaloChat(context, phone: phone);
                  },
                ),
                const Divider(height: 12),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.phone_in_talk_rounded,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  title: const Text(
                    'Gọi điện thoại Hotline',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Gọi tới số $display (Hỗ trợ 24/7)',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    goiDien(context, phone: phone);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

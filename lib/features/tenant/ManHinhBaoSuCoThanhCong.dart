import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhBaoSuCoThanhCong extends StatelessWidget {
  final String maPhieu;
  final String tenPhong;
  final String toaNha;
  final String danhMuc;
  final String moTa;
  final List<dynamic> danhSachAnh;

  const ManHinhBaoSuCoThanhCong({
    super.key,
    required this.maPhieu,
    this.tenPhong = 'Phòng 302',
    this.toaNha = 'Kiêu Giang 2',
    required this.danhMuc,
    required this.moTa,
    required this.danhSachAnh,
  });

  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            children: [
              // Header Card có mã phiếu (Đã chống tràn)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    // Bọc Expanded ở đây để cột bên trái tự co giãn theo màn hình
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Báo sự cố',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(
                                Icons.meeting_room_outlined,
                                size: 14,
                                color: _primary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '$tenPhong • $toaNha',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        maPhieu,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Banner Gửi yêu cầu thành công
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE0F2FE), Color(0xFFF0F9FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFF38BDF8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Gửi Yêu Cầu Sửa Chữa Thành\nCông!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0C4A6E),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.circle, size: 8, color: Color(0xFF0284C7)),
                          SizedBox(width: 6),
                          Text(
                            'Đang chờ BQL xếp thợ kỹ thuật',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0369A1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Thẻ tóm tắt thông tin sự cố
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE0F2FE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.build_rounded,
                            size: 18,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sự cố $danhMuc',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                moTa,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Phản hồi: ~2-4h',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (danhSachAnh.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Ảnh hiện trường đính kèm (${danhSachAnh.length}) - Nhấn để phóng to',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: danhSachAnh.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, idx) {
                            return InkWell(
                              onTap: () => _showFullImageDialog(
                                context,
                                danhSachAnh[idx],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 130,
                                  height: 90,
                                  color: const Color(0xFFE2E8F0),
                                  child: _buildImageWidget(danhSachAnh[idx]),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Thẻ Trực kỹ thuật 24/7
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFBAE6FD),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: _primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Trực kỹ thuật 24/7',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Tổng đài hỗ trợ kỹ thuật',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0284C7),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 14),
                      label: const Text(
                        'Gọi ngay',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _primary,
                        elevation: 0,
                        side: const BorderSide(color: Color(0xFFBAE6FD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Nút 1: Xem Danh Sách Sự Cố
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const TenantHomeScreen(initialTabIndex: 3),
                      ),
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.build_rounded, size: 18),
                  label: const Text(
                    'Xem Danh Sách Sự Cố',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Nút 2: Xóa báo cáo này nếu lỡ gửi nhầm
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _xacNhanXoaPhieu(context),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 18,
                  ),
                  label: const Text(
                    'Xóa Báo Cáo Này (Nếu Gửi Nhầm)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    backgroundColor: const Color(0xFFFFF1F2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  Future<void> _xacNhanXoaPhieu(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
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
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFDC2626),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Xóa Báo Cáo Sự Cố?',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bạn có chắc chắn muốn xóa phiếu báo sự cố $maPhieu này không? Bạn có thể gửi lại phiếu mới với đúng hình ảnh.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text(
                          'Giữ lại',
                          style: TextStyle(color: Color(0xFF475569)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text(
                          'Xác nhận xóa',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await Supabase.instance.client
            .from('su_co_bao_tri')
            .delete()
            .eq('ma_su_co', maPhieu);

        if (context.mounted) {
          await ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Đã Xóa Thành Công',
            noiDung: 'Phiếu sự cố $maPhieu đã được gỡ bỏ khỏi hệ thống.',
            type: ThongBaoType.thanhCong,
            nutText: 'Về Quản Lý Sự Cố',
          );
          if (context.mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => const TenantHomeScreen(initialTabIndex: 3),
              ),
              (route) => false,
            );
          }
        }
      } catch (err) {
        if (context.mounted) {
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Không Thể Xóa',
            noiDung: 'Lỗi khi xóa sự cố: $err',
            type: ThongBaoType.thatBai,
          );
        }
      }
    }
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'Kiêu Giang',
        style: TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.bold,
          color: _primary,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: Color(0xFF475569),
          ),
          onPressed: () {},
        ),
        const CircleAvatar(
          radius: 14,
          backgroundColor: Color(0xFFE2E8F0),
          child: Icon(Icons.person, size: 16, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 14),
      ],
    );
  }

  Widget _buildImageWidget(dynamic img) {
    if (img is String) {
      if (img.startsWith('data:image')) {
        try {
          final b64 = img.contains(',') ? img.split(',').last : img;
          return Image.memory(base64Decode(b64), fit: BoxFit.cover);
        } catch (_) {
          return const Icon(Icons.broken_image_rounded, color: Colors.grey);
        }
      } else if (img.startsWith('http')) {
        return Image.network(
          img,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_rounded, color: Colors.grey),
        );
      }
    } else if (img is Uint8List) {
      return Image.memory(img, fit: BoxFit.cover);
    } else if (!kIsWeb && img is File) {
      return Image.file(img, fit: BoxFit.cover);
    }
    return const Icon(Icons.image_rounded, color: Colors.grey);
  }

  void _showFullImageDialog(BuildContext context, dynamic img) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(child: _buildImageWidget(img)),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 16,
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 3, // Tab Sự cố
      onTap: (i) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => TenantHomeScreen(initialTabIndex: i),
          ),
          (route) => false,
        );
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: _primary,
      unselectedItemColor: const Color(0xFF94A3B8),
      selectedFontSize: 11,
      unselectedFontSize: 11,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: 'Trang chủ',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.key_rounded), label: 'Phòng'),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Hóa đơn',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.build_rounded),
          label: 'Sự cố',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Cá nhân',
        ),
      ],
    );
  }
}

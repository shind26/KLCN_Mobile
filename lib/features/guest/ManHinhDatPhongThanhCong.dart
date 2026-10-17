import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhTrangChuKhach.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhLichSuDatPhong.dart';

class BookingSuccessScreen extends StatelessWidget {
  final String appointmentCode;
  final RoomModel room;
  final String customerName;
  final String customerPhone;
  final String appointmentDate;
  final String timeSlot;
  final int guestCount;
  final String note;

  const BookingSuccessScreen({
    super.key,
    required this.appointmentCode,
    required this.room,
    required this.customerName,
    required this.customerPhone,
    required this.appointmentDate,
    required this.timeSlot,
    required this.guestCount,
    this.note = '',
  });

  String _formatCurrency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.') + 'đ';
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: appointmentCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép mã lịch hẹn vào bộ nhớ tạm!'),
        backgroundColor: Color(0xFF09638E),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        title: const Text(
          'Xác Nhận Đặt Lịch',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  children: [
                    // ====== SUCCESS HEADER ICON ======
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.25),
                            blurRadius: 18,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        size: 48,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text(
                      'Đặt Lịch Xem Phòng Thành Công!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // MÃ PHIẾU HẸN (COPYABLE)
                    GestureDetector(
                      onTap: () => _copyToClipboard(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF5FA),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Mã phiếu hẹn: ',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF09638E),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '#$appointmentCode',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF09638E),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: Color(0xFF09638E),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ====== TICKET / RECEIPT CARD ======
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header Room Info
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    room.hinhAnh,
                                    width: 68,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 68,
                                      height: 60,
                                      color: const Color(0xFFCBD5E1),
                                      child: const Icon(Icons.meeting_room_rounded, color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        room.tenHienThi,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Tầng ${room.tang} • ${room.toaNha}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_formatCurrency(room.giaThue)} /tháng',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF09638E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const Divider(height: 1, color: Color(0xFFE2E8F0)),

                          // Appointment Details
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildDetailRow(
                                  icon: Icons.calendar_month_rounded,
                                  iconColor: const Color(0xFF09638E),
                                  label: 'Ngày hẹn xem',
                                  value: appointmentDate,
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  icon: Icons.access_time_rounded,
                                  iconColor: const Color(0xFFD97706),
                                  label: 'Khung giờ',
                                  value: timeSlot,
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  icon: Icons.person_rounded,
                                  iconColor: const Color(0xFF16A34A),
                                  label: 'Khách hẹn',
                                  value: customerName,
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  icon: Icons.phone_rounded,
                                  iconColor: const Color(0xFF7C3AED),
                                  label: 'Số điện thoại',
                                  value: customerPhone,
                                ),
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  icon: Icons.group_rounded,
                                  iconColor: const Color(0xFF0284C7),
                                  label: 'Dự kiến ở',
                                  value: '$guestCount người',
                                ),
                                if (note.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildDetailRow(
                                    icon: Icons.notes_rounded,
                                    iconColor: const Color(0xFF64748B),
                                    label: 'Ghi chú',
                                    value: note,
                                  ),
                                ],
                                const SizedBox(height: 12),
                                _buildDetailRow(
                                  icon: Icons.verified_user_rounded,
                                  iconColor: const Color(0xFF16A34A),
                                  label: 'Tiền thế chân',
                                  value: '100.000 đ (Đã thanh toán)',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ====== NEXT STEPS TIMELINE ======
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF09638E)),
                              SizedBox(width: 8),
                              Text(
                                'Quy trình tiếp theo',
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _buildStepItem(
                            step: '1',
                            title: 'Xác nhận lịch hẹn',
                            desc: 'Ban Quản Lý sẽ gọi điện thoại hoặc gửi tin nhắn Zalo xác nhận trong 15-30 phút.',
                          ),
                          const SizedBox(height: 12),
                          _buildStepItem(
                            step: '2',
                            title: 'Đón tiếp tại nhà trọ',
                            desc: 'Đến đúng giờ hẹn, bảo vệ và quản lý sẽ trực tiếp đón và dẫn bạn xem phòng.',
                          ),
                          const SizedBox(height: 12),
                          _buildStepItem(
                            step: '3',
                            title: 'Ưu tiên giữ phòng',
                            desc: 'Nếu ưng ý, bạn được ưu tiên giữ phòng miễn phí trong 24h trước khi mở cho khách khác.',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ====== BOTTOM ACTION BUTTONS ======
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const GuestHomeScreen()),
                          (route) => false,
                        );
                      },
                      icon: const Icon(Icons.home_rounded, size: 18, color: Colors.white),
                      label: const Text(
                        'Về Trang Chủ Khám Phá',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookingHistoryScreen(initialPhone: customerPhone),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded, size: 18, color: Color(0xFF09638E)),
                      label: const Text(
                        'Xem Danh Sách Lịch Hẹn Của Tôi',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF09638E),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: const BorderSide(color: Color(0xFF09638E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.phone_in_talk_rounded, size: 14, color: Color(0xFF64748B)),
                      SizedBox(width: 6),
                      Text(
                        'Hotline hỗ trợ 24/7: ',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      Text(
                        '0987.654.321',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF09638E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem({
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(
            color: Color(0xFFEBF5FA),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF09638E),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

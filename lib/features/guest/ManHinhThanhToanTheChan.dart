import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/services/VnPayService.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/core/utils/VietQrHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhGiuCho.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhDatPhongThanhCong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhTrangChuKhach.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhVnPayWebView.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ManHinhThanhToanTheChan extends StatefulWidget {
  final GiuChoModel giuCho;
  final RoomModel room;
  final String customerName;
  final String customerPhone;
  final String? appointmentCode;
  final String? appointmentDate;
  final String? timeSlot;
  final int? guestCount;
  final String? note;

  const ManHinhThanhToanTheChan({
    super.key,
    required this.giuCho,
    required this.room,
    required this.customerName,
    required this.customerPhone,
    this.appointmentCode,
    this.appointmentDate,
    this.timeSlot,
    this.guestCount,
    this.note,
  });

  @override
  State<ManHinhThanhToanTheChan> createState() => _ManHinhThanhToanTheChanState();
}

class _ManHinhThanhToanTheChanState extends State<ManHinhThanhToanTheChan>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF09638E);
  static const _bankCode = VietQrHelper.bankCode;
  static const _accountNo = VietQrHelper.accountNumber;
  static const _accountName = VietQrHelper.accountHolder;

  int _countdownSec = 15 * 60; // 15 phút đếm ngược
  Timer? _countdownTimer;
  StreamSubscription? _streamSub;
  bool _isCompleted = false;
  bool _isProcessing = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation cho hiệu ứng đèn đếm ngược
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initCountdown();
    _initRealtimeListener();
  }

  void _initCountdown() {
    // Tính số giây còn lại từ expiresAt nếu có
    if (widget.giuCho.expiresAt != null) {
      final diff = widget.giuCho.expiresAt!.difference(DateTime.now()).inSeconds;
      if (diff > 0) {
        _countdownSec = diff;
      }
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted || _isCompleted) {
        timer.cancel();
        return;
      }

      if (_countdownSec > 0) {
        setState(() => _countdownSec--);
      } else {
        timer.cancel();
        await _handleTimeout();
      }
    });
  }

  void _initRealtimeListener() {
    try {
      _streamSub = DepositService.streamGiuCho(widget.giuCho.maGiuCho).listen((rows) {
        if (!mounted || _isCompleted || rows.isEmpty) return;
        final st = rows.first['trang_thai']?.toString() ?? '';
        if (st == 'DangGiu' || st == 'DaDatCoc') {
          _onPaymentSuccess();
        }
      });
    } catch (_) {}
  }

  /// Khi hết 15 phút: hủy cọc, trả phòng về trạng thái Trống
  Future<void> _handleTimeout() async {
    if (_isCompleted || !mounted) return;
    setState(() => _isProcessing = true);

    await DepositService.xuLyHetHanGiuCho(
      maGiuCho: widget.giuCho.maGiuCho,
      maPhong: widget.room.maPhong,
    );

    if (!mounted) return;
    setState(() => _isProcessing = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.timer_off_rounded, color: Color(0xFFDC2626), size: 26),
            SizedBox(width: 8),
            Text('Hết Hạn Giữ Chỗ', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Đã hết thời gian 15 phút thanh toán cọc thế chân. Phiếu cọc đã chuyển thành HetHan và phòng ${widget.room.tenHienThi} đã lập tức trở về trạng thái Trống để khách khác có thể đặt.',
          style: const TextStyle(fontSize: 14, height: 1.45),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Đã hiểu', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Xác nhận thanh toán thành công (dòng tiền ảo / SePay / VNPAY)
  Future<void> _handleConfirmPayment() async {
    if (_isProcessing || _isCompleted || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await DepositService.xacNhanThanhToanTheChan(
        maGiuCho: widget.giuCho.maGiuCho,
        maPhong: widget.room.maPhong,
      );

      if (widget.appointmentCode != null && widget.appointmentCode!.isNotEmpty) {
        try {
          await Supabase.instance.client
              .from('dat_lich_xem_phong')
              .update({'trang_thai': 'Đã xác nhận'})
              .eq('ma_lich_hen', widget.appointmentCode!);
        } catch (eApp) {
          debugPrint('Lỗi cập nhật dat_lich_xem_phong: $eApp');
        }
      }

      _onPaymentSuccess();
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xác nhận: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _onPaymentSuccess() {
    if (_isCompleted || !mounted) return;
    _isCompleted = true;
    _countdownTimer?.cancel();
    _streamSub?.cancel();

    // Phát chuông thanh toán thành công
    PaymentSoundHelper.playSuccess();

    // Gửi thông báo hệ thống
    try {
      SystemNotificationService.show(
        title: '🎉 Đặt cọc giữ chỗ phòng thành công!',
        body:
            'Đã nhận thế chân 100.000đ cho phòng ${widget.room.tenHienThi}. Hạn giữ phòng trong 5 ngày.',
        tag: 'deposit_${widget.giuCho.maGiuCho}',
      );
    } catch (_) {}

    _showSuccessDialog();
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 46,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Đặt Cọc Giữ Chỗ Thành Công!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hệ thống đã ghi nhận số tiền thế chân 100.000đ của bạn cho phòng ${widget.room.tenHienThi}. Phòng đã chuyển sang trạng thái Đã cọc!',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildReceiptRow('Mã giữ chỗ:', widget.giuCho.maGiuCho),
                  const SizedBox(height: 6),
                  _buildReceiptRow('Phòng:', widget.room.tenHienThi),
                  const SizedBox(height: 6),
                  _buildReceiptRow('Tiền thế chân:', '100.000 đ'),
                  const SizedBox(height: 6),
                  _buildReceiptRow(
                    'Thời hạn giữ chỗ:',
                    widget.giuCho.ngayHetHan != null
                        ? DateFormat('dd/MM/yyyy').format(widget.giuCho.ngayHetHan!)
                        : '5 ngày tới',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BookingSuccessScreen(
                        appointmentCode: widget.appointmentCode ?? widget.giuCho.maGiuCho,
                        room: widget.room,
                        customerName: widget.customerName,
                        customerPhone: widget.customerPhone,
                        appointmentDate: widget.appointmentDate ??
                            (widget.giuCho.ngayDuKienO != null
                                ? DateFormat('dd/MM/yyyy').format(widget.giuCho.ngayDuKienO!)
                                : 'Hôm nay'),
                        timeSlot: widget.timeSlot ?? 'Khung giờ linh hoạt',
                        guestCount: widget.guestCount ?? widget.giuCho.soNguoiO,
                        note: widget.note ?? (widget.giuCho.ghiChu ?? ''),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_outline_rounded, size: 20, color: Colors.white),
                label: const Text(
                  'Xem Xác Nhận Đặt Lịch',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const GuestHomeScreen()),
                  (route) => false,
                );
              },
              child: const Text('Về Trang Chủ Khách', style: TextStyle(color: Color(0xFF64748B))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  String get _memo => 'THECHAN ${widget.giuCho.maGiuCho}';

  String get _countdownText {
    final m = _countdownSec ~/ 60;
    final s = _countdownSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label!'),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _streamSub?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = DepositService.depositAmount;
    final qrData = VietQrHelper.generateVietQrString(
      amount: amount,
      memo: _memo,
      bankBin: _bankCode,
      accountNo: _accountNo,
    );
    final qrImageUrl = VietQrHelper.buildVietQrImageUrl(
      amount: amount,
      memo: _memo,
      bankBin: _bankCode,
      accountNo: _accountNo,
      accountName: _accountName,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF1F6FA),
      appBar: AppBar(
        title: const Text(
          'Thanh Toán Tiền Thế Chân',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: _primary,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            // ====== BANNER ĐẾM NGƯỢC 15 PHÚT ======
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  FadeTransition(
                    opacity: _pulseAnimation,
                    child: const Icon(
                      Icons.alarm_rounded,
                      color: Color(0xFFB45309),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thời gian giữ phòng còn lại:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        Text(
                          'Quá 15 phút không thanh toán, phòng sẽ tự động mở lại cho khách khác',
                          style: TextStyle(fontSize: 10.5, color: Colors.amber.shade900),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB45309),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _countdownText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ====== THẺ THÔNG TIN PHÒNG VÀ TIỀN THẾ CHÂN ======
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.meeting_room_rounded, color: _primary, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.room.tenHienThi,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${widget.room.toaNha} • Tầng ${widget.room.tang}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Đang giữ chỗ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  _buildDetailRow('Người đặt:', widget.customerName),
                  _buildDetailRow('Số điện thoại:', widget.customerPhone),
                  _buildDetailRow('Số người ở:', '${widget.giuCho.soNguoiO} người'),
                  _buildDetailRow(
                    'Ngày dự kiến ở:',
                    widget.giuCho.ngayDuKienO != null
                        ? DateFormat('dd/MM/yyyy').format(widget.giuCho.ngayDuKienO!)
                        : 'Chưa xác định',
                  ),
                  _buildDetailRow('Thời hạn giữ chỗ:', 'Tối đa 5 ngày'),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tiền thế chân cọc:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '100.000 đ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ====== KHUNG QUÉT MÃ VIETQR NAPAS 24/7 CHUYỂN KHOẢN CHỦ NHÀ ======
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.qr_code_2_rounded, color: _primary, size: 20),
                      SizedBox(width: 6),
                      Text(
                        'Quét mã Napas 24/7 chuyển khoản',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Chuyển khoản trực tiếp tới tài khoản chính chủ',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 14),

                  // Mã QR Vector
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 190.0,
                      errorStateBuilder: (c, e) => Image.network(
                        qrImageUrl,
                        width: 190,
                        height: 190,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Bảng thông tin tài khoản
                  _buildBankInfoRow('Ngân hàng:', 'MB Bank (Quân Đội)', copyText: 'MB Bank'),
                  _buildBankInfoRow('Chủ tài khoản:', _accountName, copyText: _accountName),
                  _buildBankInfoRow('Số tài khoản:', _accountNo, copyText: _accountNo),
                  _buildBankInfoRow('Số tiền:', '100.000 đ', copyText: '100000'),
                  _buildBankInfoRow('Nội dung CK:', _memo, copyText: _memo, isHighlight: true),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ====== CÁC NÚT HÀNH ĐỘNG / DÒNG TIỀN ẢO ======
            // 1. Nút Xác nhận đã chuyển khoản (Dòng tiền ảo như bên hóa đơn)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: _isProcessing ? null : _handleConfirmPayment,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_rounded, color: Colors.white),
                label: Text(
                  _isProcessing
                      ? 'Đang xác nhận dòng tiền...'
                      : 'Đã Chuyển Khoản Xong (Xác Nhận)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 2. Nút Mở Cổng VNPAY Sandbox (Tùy chọn)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: Color(0xFF005BAA)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final vnpUrl = VnPayService.generatePaymentUrl(
                    orderId: widget.giuCho.maGiuCho,
                    amount: 100000,
                    orderInfo: 'The chan giu cho phong ${widget.room.maPhong}',
                  );
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VnPayWebViewScreen(
                        paymentUrl: vnpUrl,
                        maHoaDon: widget.giuCho.maGiuCho,
                        onSuccess: () => _handleConfirmPayment(),
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payment_rounded, color: Color(0xFF005BAA)),
                label: const Text(
                  'Thanh toán qua Cổng VNPAY Sandbox',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF005BAA),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 3. Nút Hủy giữ chỗ
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hủy Đặt Cọc?'),
                    content: const Text(
                      'Bạn có chắc chắn muốn hủy giữ chỗ phòng này không? Phòng sẽ được hoàn lại trạng thái Trống ngay lập tức.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hủy giữ chỗ', style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await DepositService.xuLyHetHanGiuCho(
                    maGiuCho: widget.giuCho.maGiuCho,
                    maPhong: widget.room.maPhong,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Hủy giữ chỗ này', style: TextStyle(color: Color(0xFF64748B))),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B))),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankInfoRow(
    String label,
    String value, {
    required String copyText,
    bool isHighlight = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isHighlight ? const Color(0xFF1E40AF) : const Color(0xFF64748B),
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isHighlight ? const Color(0xFF1E3A8A) : const Color(0xFF0F172A),
              ),
            ),
          ),
          InkWell(
            onTap: () => _copy(copyText, label.replaceAll(':', '')),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy_rounded,
                size: 16,
                color: isHighlight ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

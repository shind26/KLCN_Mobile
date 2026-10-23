import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuHoaDon.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';

/// Màn hình Thanh Toán Thành Công Chuẩn Fintech Hiện Đại (MB Bank & SePay)
/// Tự động hiển thị khi hệ thống nhận diện giao dịch thành công.
/// Kèm hiệu ứng Confetti pháo hoa, sóng xung kích Ripple, âm thanh chuông ngân và Biên lai điện tử cao cấp.
class PaymentCompletedScreen extends StatefulWidget {
  final HoaDonModel hoaDon;
  final String tenPhong;
  final String bankName;
  final String transactionTime;
  final Uint8List? imageBytes;
  final String? imageFileName;
  final String? imageFileSizeStr;
  final String? note;
  final num? amountPaid;
  final String? tenDot;
  final String? transactionRef;

  const PaymentCompletedScreen({
    super.key,
    required this.hoaDon,
    required this.tenPhong,
    required this.bankName,
    required this.transactionTime,
    this.imageBytes,
    this.imageFileName,
    this.imageFileSizeStr,
    this.note,
    this.amountPaid,
    this.tenDot,
    this.transactionRef,
  });

  @override
  State<PaymentCompletedScreen> createState() => _PaymentCompletedScreenState();
}

class _PaymentCompletedScreenState extends State<PaymentCompletedScreen>
    with TickerProviderStateMixin {
  // ─── Theme Colors ───
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _accentGreen = Color(0xFF10B981);
  static const _darkGreen = Color(0xFF047857);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  // ─── Animation Controllers ───
  late AnimationController _badgeController;
  late AnimationController _confettiController;
  late AnimationController _rippleController;

  late Animation<double> _badgeScale;
  late Animation<double> _rippleAnimation;

  late final String _transactionRef = widget.transactionRef ?? 'FT26278507322143';

  num get _displayAmount {
    if (widget.amountPaid != null && widget.amountPaid! > 0) {
      return widget.amountPaid!;
    }
    if (widget.hoaDon.tongTien > 0) {
      return widget.hoaDon.tongTien;
    }
    final sum =
        widget.hoaDon.tienPhong +
        widget.hoaDon.tienDienNuoc +
        widget.hoaDon.tienDichVuKhac +
        widget.hoaDon.noCu;
    return sum > 0 ? sum : 0;
  }

  @override
  void initState() {
    super.initState();
    _initAnimations();
    // 🔔 Phát âm thanh chuông ngân thanh toán thành công (Fintech Chime)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PaymentSoundHelper.playSuccess();
      _ensurePhieuThuRecorded();
    });
  }

  /// Tự động kiểm tra và lưu dự phòng vào bảng phieu_thu nếu chưa có bản ghi
  Future<void> _ensurePhieuThuRecorded() async {
    try {
      final db = Supabase.instance.client;
      final maHD = widget.hoaDon.maHoaDon.trim();
      if (maHD.isEmpty) return;

      final existing = await db
          .from('phieu_thu')
          .select('ma_phieu_thu')
          .eq('ma_hoa_don', maHD)
          .limit(1);

      if (existing.isEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final maPT = 'PT${(timestamp % 100000000).toString().padLeft(8, '0')}';
        final num soTien = widget.amountPaid ?? _displayAmount;
        final String hinhThuc = widget.bankName.isNotEmpty
            ? widget.bankName
            : 'Chuyển khoản MB Bank';

        await db.from('phieu_thu').insert({
          'ma_phieu_thu': maPT,
          'ma_hoa_don': maHD,
          'ma_tra_cuu': _transactionRef,
          'so_tien_thu': soTien,
          'hinh_thuc': hinhThuc,
          'ngay_thu': DateTime.now().toIso8601String(),
          'trang_thai': 'Đã thanh toán',
        });
        debugPrint('[PHIEU_THU] Đã ghi nhận phiếu thu bổ sung: $maPT cho $maHD');
      }
    } catch (e) {
      debugPrint('[PHIEU_THU] Lỗi đồng bộ phiếu thu: $e');
    }
  }

  void _initAnimations() {
    // 1. Elastic Pop Badge Animation
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _badgeScale = CurvedAnimation(
      parent: _badgeController,
      curve: Curves.elasticOut,
    );

    // 2. Confetti Particle Animation
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();

    // 3. Ripple Waves Animation
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _badgeController.dispose();
    _confettiController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  void _copyRef() {
    Clipboard.setData(ClipboardData(text: _transactionRef));
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Đã sao chép',
      noiDung: 'Đã sao chép mã giao dịch: $_transactionRef vào bộ nhớ tạm!',
      type: ThongBaoType.thongTin,
      duration: const Duration(milliseconds: 1500),
    );
  }

  void _shareReceipt() {
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Biên lai điện tử',
      noiDung: 'Biên lai điện tử đã sẵn sàng để lưu hoặc in.',
      type: ThongBaoType.thongTin,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Background Gradient trang nhã
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFE6F4EA), Color(0xFFF0FDF4), _bg],
                ),
              ),
            ),
          ),

          // Hiệu ứng pháo hoa Confetti rơi từ trên xuống
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _ConfettiPainter(
                    progress: _confettiController.value,
                  ),
                );
              },
            ),
          ),

          // Nội dung chính cuộn mượt
          SafeArea(
            child: Column(
              children: [
                _buildTopHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                    child: Column(
                      children: [
                        _buildHeroSuccessSection(),
                        const SizedBox(height: 20),
                        _buildReceiptTicketCard(),
                        const SizedBox(height: 20),
                        _buildSecurityBanner(),
                        const SizedBox(height: 24),
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── TOP HEADER ───
  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TenantHomeScreen(initialTabIndex: 2),
                  ),
                  (route) => false,
                );
              }
            },
            icon: const Icon(Icons.close_rounded, color: _textDark, size: 24),
            tooltip: 'Đóng',
          ),
          const Expanded(
            child: Text(
              'Xác Nhận Thanh Toán',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
          ),
          IconButton(
            onPressed: _shareReceipt,
            icon: const Icon(Icons.share_outlined, color: _primary, size: 22),
            tooltip: 'Chia sẻ biên lai',
          ),
        ],
      ),
    );
  }

  // ─── HERO SUCCESS (Icon tích xanh + Số tiền + Badge tự động gạch nợ) ───
  Widget _buildHeroSuccessSection() {
    return Column(
      children: [
        // Ripple & Elastic Icon
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ripple 1
              AnimatedBuilder(
                animation: _rippleAnimation,
                builder: (context, child) {
                  return Container(
                    width: 70 + (_rippleAnimation.value * 45),
                    height: 70 + (_rippleAnimation.value * 45),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accentGreen.withValues(
                        alpha: (1.0 - _rippleAnimation.value) * 0.25,
                      ),
                    ),
                  );
                },
              ),
              // Ripple 2
              AnimatedBuilder(
                animation: _rippleAnimation,
                builder: (context, child) {
                  final v2 = (_rippleAnimation.value + 0.5) % 1.0;
                  return Container(
                    width: 70 + (v2 * 35),
                    height: 70 + (v2 * 35),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accentGreen.withValues(alpha: (1.0 - v2) * 0.2),
                    ),
                  );
                },
              ),
              // Main Badge
              ScaleTransition(
                scale: _badgeScale,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [_accentGreen, _darkGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _accentGreen.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tiêu đề
        const Text(
          'Thanh Toán Thành Công!',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: _textDark,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),

        // Subtitle
        const Text(
          'Hệ thống MB Bank & SePay đã tự động ghi nhận thanh toán.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
        ),
        const SizedBox(height: 14),

        // Số tiền khổng lồ nổi bật
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FormatUtils.currency(_displayAmount.toDouble()),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: _primaryDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'VNĐ',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Pill status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: Color(0xFF15803D)),
              SizedBox(width: 5),
              Text(
                'ĐÃ GẠCH NỢ TỰ ĐỘNG 24/7',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF15803D),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── BIÊN LAI ĐIỆN TỬ (TICKET RECEIPT CARD) ───
  Widget _buildReceiptTicketCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header vé
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: _primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BIÊN LAI ĐIỆN TỬ',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Nhà Trọ Kiêu Giang',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
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
                  child: Text(
                    widget.hoaDon.maHoaDon,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Đường đứt nét vé (Perforation Line)
          Row(
            children: [
              Container(
                width: 12,
                height: 24,
                decoration: const BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final count = (constraints.constrainWidth() / 10).floor();
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(
                        count,
                        (_) => const SizedBox(
                          width: 5,
                          height: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: 12,
                height: 24,
                decoration: const BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          // Chi tiết các trường
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              children: [
                _buildReceiptRow(
                  'Căn hộ / Phòng',
                  '${widget.tenPhong} • Tòa Kiêu Giang 2',
                ),
                _buildDivider(),
                _buildReceiptRow(
                  'Kỳ hóa đơn',
                  'Tháng ${widget.hoaDon.thangNam}',
                ),
                if (widget.tenDot != null && widget.tenDot!.isNotEmpty) ...[
                  _buildDivider(),
                  _buildReceiptRow(
                    'Đợt thanh toán',
                    widget.tenDot!,
                    trailingColor: const Color(0xFF09638E),
                  ),
                ],
                _buildDivider(),
                _buildReceiptRow('Ngân hàng', 'MB Bank (Quân Đội)'),
                _buildDivider(),
                _buildReceiptRow('Chủ tài khoản', 'TRINH MY DUYEN'),
                _buildDivider(),
                _buildReceiptRow('Số tài khoản', '0865109632'),
                _buildDivider(),
                _buildReceiptRow('Thời gian', widget.transactionTime),
                _buildDivider(),
                _buildReceiptRow(
                  'Mã giao dịch',
                  _transactionRef,
                  isCopyable: true,
                ),
                _buildDivider(),
                _buildReceiptRow(
                  'Phương thức',
                  'Chuyển khoản VietQR 24/7',
                  trailingColor: const Color(0xFF16A34A),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(
    String label,
    String value, {
    bool isCopyable = false,
    Color? trailingColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: trailingColor ?? _textDark,
                      fontFamily: isCopyable ? 'monospace' : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCopyable) ...[
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _copyRef,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: _primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 8, thickness: 0.6, color: Color(0xFFF1F5F9));
  }

  // ─── SECURITY BANNER ───
  Widget _buildSecurityBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Giao dịch được bảo mật & xác thực',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Hóa đơn điện tử có giá trị đối soát pháp lý lưu trữ trên hệ thống.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF166534),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── ACTION BUTTONS (VỀ TRANG CHỦ & XEM LỊCH SỬ) ───
  Widget _buildActionButtons() {
    return Column(
      children: [
        // Nút Về trang chủ (Chính)
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const TenantHomeScreen()),
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              shadowColor: _primary.withValues(alpha: 0.3),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  'Về Trang Chủ',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Nút Xem lịch sử hóa đơn
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceHistoryScreen(
                    roomName: widget.tenPhong,
                    maHopDong: widget.hoaDon.maHopDong,
                  ),
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryDark,
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded, size: 19),
                SizedBox(width: 8),
                Text(
                  'Xem Lịch Sử Hóa Đơn',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── HIỆU ỨNG PHÁO HOA CONFETTI (CUSTOM PAINTER) ───
class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_Particle> _particles;

  _ConfettiPainter({required this.progress})
    : _particles = List.generate(45, (i) => _Particle(i));

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;

    for (final p in _particles) {
      final y = p.startY + (size.height * 0.85 * progress * p.speed);
      final x = p.startX + (math.sin(progress * math.pi * 4 + p.wobble) * 25);
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x * size.width, y);
      canvas.rotate(progress * math.pi * 2 * p.spin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}

class _Particle {
  final double startX;
  final double startY;
  final double speed;
  final double wobble;
  final double spin;
  final double size;
  final Color color;

  _Particle(int seed)
    : startX = (math.Random(seed).nextDouble()),
      startY = -20 - (math.Random(seed * 2).nextDouble() * 50),
      speed = 0.7 + (math.Random(seed * 3).nextDouble() * 0.8),
      wobble = math.Random(seed * 4).nextDouble() * math.pi,
      spin = (math.Random(seed * 5).nextDouble() - 0.5) * 4,
      size = 7 + (math.Random(seed * 6).nextDouble() * 7),
      color = [
        const Color(0xFF10B981), // Emerald
        const Color(0xFF09638E), // Brand Blue
        const Color(0xFFF59E0B), // Gold
        const Color(0xFFEC4899), // Pink
        const Color(0xFF8B5CF6), // Purple
        const Color(0xFF06B6D4), // Cyan
      ][seed % 6];
}

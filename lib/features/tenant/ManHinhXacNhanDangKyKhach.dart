import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuLuuTru.dart';

class ManHinhXacNhanDangKyKhach extends StatefulWidget {
  final String hoTen;
  final String cccd;
  final String sdt;
  final String thoiGian;
  final int soDem;
  final String moiQuanHe;
  final String tenPhong;
  final String toaNha;

  const ManHinhXacNhanDangKyKhach({
    super.key,
    required this.hoTen,
    required this.cccd,
    required this.sdt,
    required this.thoiGian,
    required this.soDem,
    required this.moiQuanHe,
    this.tenPhong = 'Phòng 302',
    this.toaNha = 'Tòa Kiêu Giang 2',
  });

  @override
  State<ManHinhXacNhanDangKyKhach> createState() => _ManHinhXacNhanDangKyKhachState();
}

class _ManHinhXacNhanDangKyKhachState extends State<ManHinhXacNhanDangKyKhach>
    with TickerProviderStateMixin {
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  late AnimationController _badgeController;
  late AnimationController _confettiController;
  late AnimationController _rippleController;

  late Animation<double> _badgeScale;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
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
      duration: const Duration(milliseconds: 3200),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  // Vòng tròn Checkmark nảy bật và sóng Ripple
                  Center(
                    child: SizedBox(
                      width: 110,
                      height: 110,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _rippleAnimation,
                            builder: (context, child) {
                              return Container(
                                width: 72 + (38 * _rippleAnimation.value),
                                height: 72 + (38 * _rippleAnimation.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF0284C7).withValues(
                                      alpha: (1.0 - _rippleAnimation.value) * 0.45,
                                    ),
                                    width: 2.5,
                                  ),
                                ),
                              );
                            },
                          ),
                          ScaleTransition(
                            scale: _badgeScale,
                            child: Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Badge Chờ BQL
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 14,
                          color: Color(0xFF0369A1),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Chờ BQL duyệt & khai báo tạm trú',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Đăng Ký Thành Công!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Thông tin đã được chuyển đến Ban Quản Lý để tiến hành thủ tục khai báo tạm trú với cơ quan chức năng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                  ),
                  const SizedBox(height: 20),

                  // Phiếu Thông Tin Chi Tiết
                  _buildTicketCard(),
                  const SizedBox(height: 24),

                  // Nút: Về Trang Chủ
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.home_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Về Trang Chủ',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nút: Xem Danh Sách Khách Lưu Trú
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManHinhLichSuLuuTru(
                              tenPhong: widget.tenPhong,
                              toaNha: widget.toaNha,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.group_outlined,
                        size: 18,
                        color: _primary,
                      ),
                      label: const Text(
                        'Xem Danh Sách Khách Lưu Trú',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFBAE6FD)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Hiệu ứng Pháo hoa Confetti bùng nổ chúc mừng
            IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiController,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size.infinite,
                    painter: _ConfettiPainter(progress: _confettiController.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: _primary,
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: Column(
        children: [
          const Text(
            'Xác Nhận Đăng Ký',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            ' • ',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.help_outline_rounded,
            color: Color(0xFF0284C7),
          ),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildTicketCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: _primary, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Phiếu #TT-302-1510',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
              const Spacer(),
              const Text(
                '15/10/2026 • 16:30',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const Divider(height: 22, color: Color(0xFFF1F5F9)),
          _buildRowInfo('Khách:', ' ()', isBold: true),
          const SizedBox(height: 10),
          _buildRowInfo('CCCD:', widget.cccd),
          const SizedBox(height: 10),
          _buildRowInfo('SĐT:', widget.sdt, isPhone: true),
          const SizedBox(height: 10),
          _buildRowThoiGian(),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Ảnh CCCD:',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF0284C7),
                size: 14,
              ),
              const SizedBox(width: 4),
              const Text(
                'Đã đính kèm 2 mặt',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0284C7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRowInfo(
    String label,
    String value, {
    bool isBold = false,
    bool isPhone = false,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isPhone ? const Color(0xFF0369A1) : _textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildRowThoiGian() {
    return Row(
      children: [
        const Text(
          'Thời gian:',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const Spacer(),
        Text(
          widget.thoiGian,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            ' đêm',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0284C7),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: 1,
      onTap: (i) {
        if (i == 0) Navigator.of(context).popUntil((route) => route.isFirst);
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
          icon: Icon(Icons.build_outlined),
          label: 'Yêu cầu',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Cá nhân',
        ),
      ],
    );
  }
}

/// Particle Confetti Painter
class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final List<_ConfettiParticle> _particles = List.generate(
    45,
    (i) => _ConfettiParticle(seed: i),
  );

  _ConfettiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    for (final p in _particles) {
      final t = (progress * 1.2).clamp(0.0, 1.0);
      final currentY = p.startY + (size.height * 0.7 * t) + (0.5 * 380 * t * t);
      final currentX = size.width * 0.5 + (p.vx * t * size.width * 0.45);
      final opacity = (1.0 - t).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.rotation + (t * 8));

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size * 0.5, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ConfettiParticle {
  final double startY;
  final double vx;
  final double size;
  final double rotation;
  final bool isCircle;
  final Color color;

  _ConfettiParticle({required int seed})
      : startY = 80 + (seed % 10) * 8.0,
        vx = (math.sin(seed * 1.7) * 2.2) - 0.2,
        size = 6.0 + (seed % 5) * 2.0,
        rotation = seed * 0.8,
        isCircle = seed % 3 == 0,
        color = _colors[seed % _colors.length];

  static const List<Color> _colors = [
    Color(0xFF0284C7),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF06B6D4),
    Color(0xFFEF4444),
  ];
}

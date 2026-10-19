import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget Thanh Load Vòng Tròn Hoạt Hình Con Mèo Siêu Đáng Yêu (Cute Cat Circular Spinner)
/// Chú mèo hoạt hình mũm mĩm chạy vòng tròn 360 độ liên tục, đuổi theo chú cá vàng,
/// để lại vệt sáng gradient và dấu chân mèo lấp lánh cực kỳ dễ thương và bắt mắt!
class LoadingMeoMeo extends StatefulWidget {
  final String message;
  final String? subMessage;
  final double size;
  final bool compact;

  const LoadingMeoMeo({
    super.key,
    this.message = 'Đang tải dữ liệu...',
    this.subMessage = 'Đợi mèo con một xíu nha~ 🐾',
    this.size = 140.0,
    this.compact = false,
  });

  /// Hiển thị thanh load chú mèo dưới dạng hộp thoại Modal Dialog ở giữa màn hình
  static Future<void> showAsDialog(
    BuildContext context, {
    String message = 'Đang xử lý...',
    String subMessage = 'Đợi mèo con một xíu nha~ 🐾',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          child: LoadingMeoMeo(
            message: message,
            subMessage: subMessage,
            size: 130,
          ),
        ),
      ),
    );
  }

  /// Tắt dialog loading
  static void hide(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  State<LoadingMeoMeo> createState() => _LoadingMeoMeoState();
}

class _LoadingMeoMeoState extends State<LoadingMeoMeo>
    with TickerProviderStateMixin {
  late AnimationController _rotateController;
  late AnimationController _blinkController;
  late AnimationController _breatheController;
  late AnimationController _dotsController;

  late Animation<double> _breatheAnim;
  late Animation<double> _blinkAnim;

  @override
  void initState() {
    super.initState();

    // 1. Vòng quay mèo chạy 360 độ mượt mà (1.8 giây / vòng)
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // 2. Nhịp thở phập phồng nhẹ nhàng
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _breatheAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _breatheController, curve: Curves.easeInOutSine),
    );

    // 3. Chớp mắt định kỳ (cứ 2.8 giây chớp 1 lần)
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    _blinkAnim = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 88),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.05).chain(CurveTween(curve: Curves.easeIn)),
        weight: 6,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.05, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 6,
      ),
    ]).animate(_blinkController);

    // 4. Ba dấu chấm nảy
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _blinkController.dispose();
    _breatheController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: _buildCatRunningSpinner(widget.size),
            ),
            if (widget.message.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildBouncingText(fontSize: 13),
            ],
          ],
        ),
      );
    }

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF09638E).withValues(alpha: 0.08),
              blurRadius: 32,
              offset: const Offset(0, 8),
              spreadRadius: 2,
            ),
          ],
          border: Border.all(
            color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Khung chứa mèo chạy vòng tròn siêu cute
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: _buildCatRunningSpinner(widget.size),
            ),
            const SizedBox(height: 18),

            // Tiêu đề với 3 dấu chấm nảy
            _buildBouncingText(fontSize: 14.5),

            // Phụ đề dễ thương
            if (widget.subMessage != null && widget.subMessage!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.subMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCatRunningSpinner(double spinnerSize) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _rotateController,
        _breatheController,
        _blinkController,
      ]),
      builder: (context, _) {
        final spinAngle = _rotateController.value * 2 * math.pi;

        return CustomPaint(
          size: Size(spinnerSize, spinnerSize),
          painter: _CatRunningInCirclePainter(
            spinAngle: spinAngle,
            breatheScale: _breatheAnim.value,
            eyeOpenFactor: _blinkAnim.value,
          ),
        );
      },
    );
  }

  Widget _buildBouncingText({required double fontSize}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          widget.message.replaceAll(RegExp(r'\.+$'), ''),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 2),
        AnimatedBuilder(
          animation: _dotsController,
          builder: (context, _) {
            final val = _dotsController.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final delay = i * 0.25;
                final norm = (val - delay) % 1.0;
                final offset = -math.sin(norm * math.pi) * 4.5;
                final y = (norm >= 0 && norm <= 0.5) ? offset : 0.0;
                return Transform.translate(
                  offset: Offset(0, y),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF09638E),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

/// CustomPainter vẽ MÈO HOẠT HÌNH CHẠY VÒNG TRÒN 360 ĐỘ SIÊU ĐẸP & MƯỢT MÀ
class _CatRunningInCirclePainter extends CustomPainter {
  final double spinAngle;
  final double breatheScale;
  final double eyeOpenFactor;

  _CatRunningInCirclePainter({
    required this.spinAngle,
    required this.breatheScale,
    required this.eyeOpenFactor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 140.0;
    // Bán kính đường đua tròn
    final trackRadius = (size.width / 2) - (20.0 * scale);

    // Bảng màu rực rỡ, cao cấp
    const gingerMain = Color(0xFFF59E0B); // Lông vàng cam ấm áp
    const gingerLight = Color(0xFFFBBF24);
    const gingerDark = Color(0xFFD97706);
    const creamWhite = Color(0xFFFFFBEB);
    const blushPink = Color(0xFFFB7185);
    const innerEarPink = Color(0xFFFDA4AF);
    const eyeDark = Color(0xFF0F172A);
    const fishGold = Color(0xFFF97316);

    // ==========================================
    // 1. RÃNH TRÒN NỀN (Soft Track)
    // ==========================================
    final trackPaint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), trackRadius, trackPaint);

    // ==========================================
    // 2. VỆT SÁNG QUAY TRÒN THEO ĐUÔI MÈO (Sweep Trail)
    // ==========================================
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(spinAngle);

    final trailShader = SweepGradient(
      colors: const [
        Color(0x0009638E), // Đuôi mờ dần
        Color(0x250284C7),
        Color(0x750EA5E9),
        Color(0xFF0284C7), // Đậm dần về phía mèo
      ],
      stops: const [0.0, 0.45, 0.8, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: trackRadius));

    final trailPaint = Paint()
      ..shader = trailShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0 * scale
      ..strokeCap = StrokeCap.round;

    // Cung vệt sáng kéo dài 190 độ (~1.05 pi)
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: trackRadius),
      -1.05 * math.pi,
      1.05 * math.pi,
      false,
      trailPaint,
    );
    canvas.restore();

    // ==========================================
    // 3. DẤU CHÂN MÈO BƯỚC THEO VÒNG TRÒN (Fading Paw Prints)
    // ==========================================
    void drawPawPrint(double angleOffset, double opacity) {
      final pAngle = spinAngle - angleOffset;
      final px = cx + trackRadius * math.cos(pAngle);
      final py = cy + trackRadius * math.sin(pAngle);

      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(pAngle + (math.pi / 2));

      final pPaint = Paint()..color = const Color(0xFF0284C7).withValues(alpha: opacity);

      // Đệm bàn chân lớn
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 4.5 * scale, height: 3.5 * scale),
        pPaint,
      );
      // 3 ngón chân nhỏ xinh
      canvas.drawCircle(Offset(-2.0 * scale, -2.6 * scale), 0.9 * scale, pPaint);
      canvas.drawCircle(Offset(0.0 * scale, -3.2 * scale), 1.0 * scale, pPaint);
      canvas.drawCircle(Offset(2.0 * scale, -2.6 * scale), 0.9 * scale, pPaint);

      canvas.restore();
    }

    drawPawPrint(0.40, 0.70);
    drawPawPrint(0.80, 0.45);
    drawPawPrint(1.20, 0.25);

    // ==========================================
    // 4. TÂM VÒNG TRÒN: CHÚ MÈO MỈM CƯỜI HOẶC BÀN CHÂN PHẬP PHỒNG
    // ==========================================
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(breatheScale, breatheScale);

    // Vầng hào quang trung tâm
    final centerGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF09638E).withValues(alpha: 0.10),
          const Color(0xFF09638E).withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: trackRadius * 0.7));
    canvas.drawCircle(Offset.zero, trackRadius * 0.7, centerGlow);

    // Khuôn mặt mèo tròn xinh xắn ở tâm
    final centerFacePaint = Paint()..color = creamWhite;
    canvas.drawCircle(Offset.zero, 18.0 * scale, centerFacePaint);
    canvas.drawCircle(
      Offset.zero,
      18.0 * scale,
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale,
    );

    // Đôi tai nhỏ mèo ở tâm
    final centerEarL = Path()
      ..moveTo(-12 * scale, -12 * scale)
      ..lineTo(-8 * scale, -22 * scale)
      ..lineTo(-3 * scale, -14 * scale)
      ..close();
    canvas.drawPath(centerEarL, Paint()..color = gingerLight);
    final centerEarR = Path()
      ..moveTo(3 * scale, -14 * scale)
      ..lineTo(8 * scale, -22 * scale)
      ..lineTo(12 * scale, -12 * scale)
      ..close();
    canvas.drawPath(centerEarR, Paint()..color = gingerLight);

    // Mắt mèo tâm liếc nhìn theo chú mèo đang chạy bên ngoài!
    final gazeX = math.cos(spinAngle) * 2.5 * scale;
    final gazeY = math.sin(spinAngle) * 2.0 * scale;

    void drawCenterEye(double ex, double ey) {
      if (eyeOpenFactor > 0.25) {
        canvas.drawCircle(Offset(ex, ey), 3.2 * scale, Paint()..color = eyeDark);
        // Con ngươi liếc
        canvas.drawCircle(Offset(ex + gazeX * 0.4, ey + gazeY * 0.4), 1.5 * scale, Paint()..color = const Color(0xFF38BDF8));
        // Đốm sáng
        canvas.drawCircle(Offset(ex - 0.9 * scale, ey - 0.9 * scale), 1.0 * scale, Paint()..color = Colors.white);
      } else {
        // Híp mí cười ^_^
        final smile = Path()
          ..moveTo(ex - 2.5 * scale, ey)
          ..quadraticBezierTo(ex, ey - 2.2 * scale, ex + 2.5 * scale, ey);
        canvas.drawPath(
          smile,
          Paint()
            ..color = eyeDark
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * scale
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    drawCenterEye(-6.5 * scale, -2 * scale);
    drawCenterEye(6.5 * scale, -2 * scale);

    // Má hồng tâm
    canvas.drawCircle(Offset(-9.5 * scale, 3.5 * scale), 2.8 * scale, Paint()..color = blushPink.withValues(alpha: 0.5));
    canvas.drawCircle(Offset(9.5 * scale, 3.5 * scale), 2.8 * scale, Paint()..color = blushPink.withValues(alpha: 0.5));

    // Mũi & miệng chữ W
    final centerMouth = Path()
      ..moveTo(-3 * scale, 4 * scale)
      ..quadraticBezierTo(-1.5 * scale, 6 * scale, 0, 4 * scale)
      ..quadraticBezierTo(1.5 * scale, 6 * scale, 3 * scale, 4 * scale);
    canvas.drawPath(
      centerMouth,
      Paint()
        ..color = eyeDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1 * scale
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore(); // Kết thúc vẽ tâm

    // ==========================================
    // 5. CHÚ CÁ VÀNG BƠI TRƯỚC (Golden Fish being chased)
    // ==========================================
    final fishAngle = spinAngle + 0.62; // Đi trước mèo ~35 độ
    final fishX = cx + trackRadius * math.cos(fishAngle);
    final fishY = cy + trackRadius * math.sin(fishAngle);

    canvas.save();
    canvas.translate(fishX, fishY);
    canvas.rotate(fishAngle + (math.pi / 2));

    final fishPaint = Paint()..color = fishGold;
    // Thân cá
    final fishBody = Path()
      ..moveTo(0, -6 * scale)
      ..quadraticBezierTo(5 * scale, 0, 0, 6 * scale)
      ..quadraticBezierTo(-5 * scale, 0, 0, -6 * scale);
    canvas.drawPath(fishBody, fishPaint);

    // Đuôi cá vẫy vẫy sinh động
    final tailFlap = math.sin(spinAngle * 10) * 2.5 * scale;
    final fishTail = Path()
      ..moveTo(0, 5 * scale)
      ..lineTo(-3.5 * scale + tailFlap, 11 * scale)
      ..lineTo(3.5 * scale + tailFlap, 11 * scale)
      ..close();
    canvas.drawPath(fishTail, fishPaint);

    // Mắt cá
    canvas.drawCircle(Offset(1.5 * scale, -2.5 * scale), 1.0 * scale, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(1.8 * scale, -2.5 * scale), 0.5 * scale, Paint()..color = eyeDark);

    // Bong bóng lấp lánh sau cá
    final bubblePaint = Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.6);
    canvas.drawCircle(Offset(-2 * scale, 14 * scale), 1.0 * scale, bubblePaint);
    canvas.drawCircle(Offset(1 * scale, 18 * scale), 1.4 * scale, bubblePaint);

    canvas.restore();

    // ==========================================
    // 6. CHÚ MÈO HOẠT HÌNH CHẠY VÒNG TRÒN 360 ĐỘ!
    // ==========================================
    final catX = cx + trackRadius * math.cos(spinAngle);
    final catY = cy + trackRadius * math.sin(spinAngle);

    canvas.save();
    canvas.translate(catX, catY);
    // Xoay theo tiếp tuyến vòng tròn: trục +X hướng tới trước (hướng chạy)
    // trục -X hướng về sau (đuôi), trục -Y hướng vào tâm, trục +Y hướng ra ngoài
    canvas.rotate(spinAngle + (math.pi / 2));

    // Nhịp chạy của 4 chân (chân trước & chân sau so le)
    final runCycle = spinAngle * 6.5;
    final legSwingFront = math.sin(runCycle) * 3.5 * scale;
    final legSwingBack = math.cos(runCycle) * 3.5 * scale;

    // 6.1. ĐUÔI MÈO NGOE NGẨY UỐN LƯỢN PHÍA SAU
    final tailWag = math.sin(spinAngle * 4.5) * 5.0 * scale;
    final tailPath = Path()
      ..moveTo(-13 * scale, 0)
      ..quadraticBezierTo(-20 * scale, tailWag * 0.6, -24 * scale, tailWag);
    canvas.drawPath(
      tailPath,
      Paint()
        ..color = gingerMain
        ..strokeWidth = 3.6 * scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    // Chóp đuôi lông trắng
    canvas.drawCircle(
      Offset(-24 * scale, tailWag),
      2.0 * scale,
      Paint()..color = creamWhite,
    );

    // 6.2. HAI CHÂN SAU ĐANG ĐẠP NỀN CHẠY
    void drawPaw(double px, double py) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(px, py), width: 5.5 * scale, height: 4.2 * scale),
        Paint()..color = creamWhite,
      );
      canvas.drawCircle(
        Offset(px, py),
        1.2 * scale,
        Paint()..color = innerEarPink.withValues(alpha: 0.8),
      );
    }

    drawPaw(-11 * scale - legSwingBack, -6.5 * scale); // Chân sau trái (phía trong)
    drawPaw(-11 * scale + legSwingBack, 6.5 * scale); // Chân sau phải (phía ngoài)

    // 6.3. THÂN MÈO BẦU BĨNH MŨM MĨM
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(-2 * scale, 0), width: 24 * scale, height: 17 * scale),
      Radius.circular(8.5 * scale),
    );
    canvas.drawRRect(bodyRect, Paint()..color = gingerMain);

    // Bụng mèo màu kem sữa ngọt ngào
    final bellyRect = Rect.fromCenter(
      center: Offset(-1 * scale, 1 * scale),
      width: 14 * scale,
      height: 11 * scale,
    );
    canvas.drawOval(bellyRect, Paint()..color = creamWhite);

    // Vằn lưng cam đậm
    final stripePaint = Paint()
      ..color = gingerDark.withValues(alpha: 0.7)
      ..strokeWidth = 1.4 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-6 * scale, -6 * scale), Offset(-4 * scale, -2 * scale), stripePaint);
    canvas.drawLine(Offset(-2 * scale, -6.5 * scale), Offset(0, -2.5 * scale), stripePaint);

    // 6.4. HAI CHÂN TRƯỚC VƯƠN VỀ PHÍA TRƯỚC ĐUỔI THEO CÁ
    drawPaw(8 * scale + legSwingFront, -6.5 * scale); // Chân trước trái
    drawPaw(8 * scale - legSwingFront, 6.5 * scale); // Chân trước phải

    // 6.5. ĐẦU CHÚ MÈO TRÒN TRĨNH HƯỚNG VỀ PHÍA TRƯỚC
    final headCenter = Offset(10 * scale, 0);
    canvas.drawCircle(headCenter, 10.5 * scale, Paint()..color = gingerMain);

    // Đốm sáng trên trán
    canvas.drawOval(
      Rect.fromCenter(center: Offset(8 * scale, 0), width: 6 * scale, height: 4 * scale),
      Paint()..color = gingerLight,
    );

    // 6.6. ĐÔI TAI MÈO VỂNH LÊN ĐÁNG YÊU
    // Tai trái (phía trong)
    final earL = Path()
      ..moveTo(8 * scale, -7 * scale)
      ..lineTo(10 * scale, -15 * scale)
      ..lineTo(14 * scale, -7 * scale)
      ..close();
    canvas.drawPath(earL, Paint()..color = gingerDark);
    final innerEarL = Path()
      ..moveTo(9.2 * scale, -7.5 * scale)
      ..lineTo(10.5 * scale, -13.0 * scale)
      ..lineTo(13.0 * scale, -7.5 * scale)
      ..close();
    canvas.drawPath(innerEarL, Paint()..color = innerEarPink);

    // Tai phải (phía ngoài)
    final earR = Path()
      ..moveTo(8 * scale, 7 * scale)
      ..lineTo(10 * scale, 15 * scale)
      ..lineTo(14 * scale, 7 * scale)
      ..close();
    canvas.drawPath(earR, Paint()..color = gingerDark);
    final innerEarR = Path()
      ..moveTo(9.2 * scale, 7.5 * scale)
      ..lineTo(10.5 * scale, 13.0 * scale)
      ..lineTo(13.0 * scale, 7.5 * scale)
      ..close();
    canvas.drawPath(innerEarR, Paint()..color = innerEarPink);

    // 6.7. MẮT MÈO TO TRÒN LONG LANH (ANIMATED)
    void drawRunningCatEye(double ey) {
      final ex = 14.5 * scale;
      if (eyeOpenFactor > 0.25) {
        // Mắt đen tròn to
        canvas.drawCircle(Offset(ex, ey), 2.6 * scale, Paint()..color = eyeDark);
        // Điểm phản chiếu ánh sáng lấp lánh
        canvas.drawCircle(Offset(ex + 0.8 * scale, ey - 0.7 * scale), 1.0 * scale, Paint()..color = Colors.white);
      } else {
        // Híp mắt cười hạnh phúc
        final smile = Path()
          ..moveTo(ex - 1.5 * scale, ey - 1.5 * scale)
          ..quadraticBezierTo(ex + 1.2 * scale, ey, ex - 1.5 * scale, ey + 1.5 * scale);
        canvas.drawPath(
          smile,
          Paint()
            ..color = eyeDark
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3 * scale
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    drawRunningCatEye(-3.8 * scale);
    drawRunningCatEye(3.8 * scale);

    // 6.8. MÁ HỒNG CHÚ MÈO
    canvas.drawCircle(Offset(12.5 * scale, -6.0 * scale), 2.2 * scale, Paint()..color = blushPink.withValues(alpha: 0.55));
    canvas.drawCircle(Offset(12.5 * scale, 6.0 * scale), 2.2 * scale, Paint()..color = blushPink.withValues(alpha: 0.55));

    // 6.9. MŨI & MIỆNG CHỮ W
    canvas.drawCircle(Offset(18.0 * scale, 0), 1.0 * scale, Paint()..color = const Color(0xFFF43F5E));
    final catMouth = Path()
      ..moveTo(17.2 * scale, -2.0 * scale)
      ..quadraticBezierTo(18.5 * scale, -1.0 * scale, 17.5 * scale, 0)
      ..quadraticBezierTo(18.5 * scale, 1.0 * scale, 17.2 * scale, 2.0 * scale);
    canvas.drawPath(
      catMouth,
      Paint()
        ..color = eyeDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale
        ..strokeCap = StrokeCap.round,
    );

    // 6.10. RIA MÉP TRẮNG DỄ THƯƠNG
    final whiskerPaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 0.9 * scale
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(16 * scale, -5 * scale), Offset(20 * scale, -8 * scale), whiskerPaint);
    canvas.drawLine(Offset(16 * scale, 5 * scale), Offset(20 * scale, 8 * scale), whiskerPaint);

    canvas.restore(); // Kết thúc vẽ chú mèo
  }

  @override
  bool shouldRepaint(covariant _CatRunningInCirclePainter oldDelegate) {
    return oldDelegate.spinAngle != spinAngle ||
        oldDelegate.breatheScale != breatheScale ||
        oldDelegate.eyeOpenFactor != eyeOpenFactor;
  }
}

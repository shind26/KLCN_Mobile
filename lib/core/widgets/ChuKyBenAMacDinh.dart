import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Widget hiển thị chữ ký số & dấu mộc điện tử của Bên A (Trịnh Mỹ Duyên)
/// Vẽ bằng CustomPainter vector sắc nét trên mọi màn hình, không bị lỗi thiếu asset khi chưa restart server
class ChuKyBenAMacDinhWidget extends StatelessWidget {
  final double height;
  final double? width;

  const ChuKyBenAMacDinhWidget({super.key, this.height = 110, this.width});

  /// Xuất ảnh chữ ký Bên A thành bytes PNG độ phân giải cao cho PDF
  static Future<Uint8List> toPngBytes({
    int width = 800,
    int height = 320,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    // Vẽ nền trắng
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      bgPaint,
    );

    // Vẽ chữ ký và mộc đỏ lên canvas
    final painter = _ChuKyBenAPainter();
    painter.paintCanvas(canvas, Size(width.toDouble(), height.toDouble()));

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width ?? constraints.maxWidth;
        return SizedBox(
          height: height,
          width: w,
          child: CustomPaint(
            size: Size(w, height),
            painter: _ChuKyBenAPainter(),
          ),
        );
      },
    );
  }
}

class _ChuKyBenAPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    paintCanvas(canvas, size);
  }

  void paintCanvas(Canvas canvas, Size size) {
    // Tỉ lệ scale dựa trên canvas chuẩn 800 x 320
    final double scale = size.height / 320.0;
    final double offsetX = math.max(0.0, (size.width - 800 * scale) / 2);

    canvas.save();
    canvas.translate(offsetX, 0);
    canvas.scale(scale, scale);

    // ── 1. VẼ NÉT CHỮ KÝ TAY (Mực xanh bút máy) ──
    final inkPaint = Paint()
      ..color = const Color(0xFF133E87)
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Chữ "M" hoa cách điệu
    final pathM = Path();
    pathM.moveTo(85, 145);
    pathM.cubicTo(70, 75, 95, 45, 120, 50);
    pathM.cubicTo(135, 55, 145, 110, 155, 140);
    pathM.cubicTo(165, 95, 185, 60, 205, 65);
    pathM.cubicTo(225, 70, 235, 115, 240, 140);
    canvas.drawPath(pathM, inkPaint);

    // Chữ "y" uốn lượn
    final pathY = Path();
    pathY.moveTo(245, 105);
    pathY.cubicTo(255, 105, 265, 130, 275, 135);
    pathY.cubicTo(285, 138, 295, 115, 305, 105);
    pathY.moveTo(300, 105);
    pathY.cubicTo(295, 135, 280, 185, 260, 195);
    pathY.cubicTo(245, 202, 235, 195, 240, 180);
    pathY.cubicTo(245, 165, 270, 155, 310, 145);
    canvas.drawPath(pathY, inkPaint);

    // Chữ "Duyen" mềm mại
    final pathDuyen = Path();
    // Chữ D hoa
    pathDuyen.moveTo(335, 140);
    pathDuyen.cubicTo(325, 80, 345, 55, 375, 58);
    pathDuyen.cubicTo(405, 62, 415, 105, 405, 138);
    pathDuyen.cubicTo(395, 150, 360, 150, 350, 140);
    // Chữ u, y, e, n nối nét
    pathDuyen.cubicTo(415, 135, 425, 115, 440, 115);
    pathDuyen.cubicTo(450, 115, 455, 138, 470, 136);
    pathDuyen.cubicTo(480, 134, 490, 112, 505, 112);
    pathDuyen.cubicTo(515, 112, 515, 138, 530, 135);
    pathDuyen.cubicTo(540, 132, 550, 120, 560, 120);
    pathDuyen.cubicTo(570, 120, 575, 138, 590, 135);
    canvas.drawPath(pathDuyen, inkPaint);

    // Nét gạch đuôi chữ ký uốn lượn sang trọng (Flourish swoosh)
    final pathSwoosh = Path();
    pathSwoosh.moveTo(100, 160);
    pathSwoosh.cubicTo(220, 215, 450, 185, 530, 115);
    pathSwoosh.cubicTo(555, 95, 510, 135, 420, 175);
    pathSwoosh.cubicTo(460, 195, 580, 190, 620, 160);
    canvas.drawPath(pathSwoosh, inkPaint);

    // Nét phụ gạch chân
    final pathSub = Path();
    pathSub.moveTo(80, 175);
    pathSub.cubicTo(160, 190, 280, 200, 380, 190);
    canvas.drawPath(
      pathSub,
      Paint()
        ..color = const Color(0xFF133E87)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── 2. HỌ TÊN IN HOA "TRỊNH MỸ DUYÊN" ──
    final textPainterName = TextPainter(
      text: const TextSpan(
        text: 'TRỊNH MỸ DUYÊN',
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainterName.layout();
    textPainterName.paint(canvas, const Offset(140, 222));

    // ── 3. DẤU MỘC CHỨNG THỰC ĐIỆN TỬ MÀU ĐỎ (STAMP) ──
    const double cx = 570;
    const double cy = 150;
    const double rOut = 92;
    const double rIn = 86;
    const stampColor = Color(0xFFDC2626);

    // 2 vòng tròn đồng tâm
    final stampPaintOut = Paint()
      ..color = stampColor
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(cx, cy), rOut, stampPaintOut);

    final stampPaintIn = Paint()
      ..color = stampColor
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(const Offset(cx, cy), rIn, stampPaintIn);

    // 3 ngôi sao ở giữa
    _drawStar(canvas, cx - 26, cy - 25, 7, 3, stampColor);
    _drawStar(canvas, cx, cy - 27, 9, 4, stampColor);
    _drawStar(canvas, cx + 26, cy - 25, 7, 3, stampColor);

    // Text trong con dấu
    _drawCenteredText(
      canvas,
      'NHÀ TRỌ KIÊU GIANG',
      const Offset(cx, cy - 54),
      13.5,
      FontWeight.bold,
      stampColor,
    );
    _drawCenteredText(
      canvas,
      'CHỨNG THỰC',
      const Offset(cx, cy - 3),
      16.0,
      FontWeight.w900,
      stampColor,
    );
    _drawCenteredText(
      canvas,
      'KÝ SỐ ĐIỆN TỬ',
      const Offset(cx, cy + 22),
      16.0,
      FontWeight.w900,
      stampColor,
    );
    _drawCenteredText(
      canvas,
      'BAN QUẢN LÝ',
      const Offset(cx, cy + 52),
      13.0,
      FontWeight.bold,
      stampColor,
    );

    canvas.restore();
  }

  void _drawStar(
    Canvas canvas,
    double cx,
    double cy,
    double rOut,
    double rIn,
    Color color,
  ) {
    final path = Path();
    for (int i = 0; i < 10; i++) {
      final double angle = -math.pi / 2 + i * math.pi / 5;
      final double r = i.isEven ? rOut : rIn;
      final double x = cx + r * math.cos(angle);
      final double y = cy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    double fontSize,
    FontWeight fontWeight,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          letterSpacing: 0.5,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

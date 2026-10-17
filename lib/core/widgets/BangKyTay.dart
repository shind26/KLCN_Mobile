import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Controller quản lý các nét vẽ chữ ký tay
class ChuKyController extends ChangeNotifier {
  final List<List<Offset>> _cacNet = [];
  Size _kichThuocVe = Size.zero;

  List<List<Offset>> get cacNet => List.unmodifiable(_cacNet);
  bool get isEmpty => _cacNet.isEmpty;
  bool get isNotEmpty => _cacNet.isNotEmpty;
  bool get isFilled => _cacNet.isNotEmpty;

  /// Bắt đầu một nét vẽ mới
  void batDauNet(Offset diem) {
    _cacNet.add([diem]);
    notifyListeners();
  }

  /// Thêm điểm vào nét vẽ hiện tại
  void themDiem(Offset diem) {
    if (_cacNet.isNotEmpty) {
      _cacNet.last.add(diem);
      notifyListeners();
    }
  }

  /// Xóa toàn bộ chữ ký
  void clear() {
    _cacNet.clear();
    notifyListeners();
  }

  /// Cập nhật kích thước thực tế của vùng vẽ
  void setRenderSize(Size s) {
    _kichThuocVe = s;
  }

  /// Xuất chữ ký thành mảng byte PNG với nền trắng độ phân giải cao
  Future<Uint8List?> toPngBytes({int width = 800, int height = 320}) async {
    if (isEmpty) return null;

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

    // Tỉ lệ co giãn tọa độ theo khung hình xuất
    double scaleX = 1.0;
    double scaleY = 1.0;
    if (_kichThuocVe.width > 0 && _kichThuocVe.height > 0) {
      scaleX = width / _kichThuocVe.width;
      scaleY = height / _kichThuocVe.height;
    }

    final double avgScale = (scaleX + scaleY) / 2;
    final netPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.2 * avgScale
      ..style = PaintingStyle.stroke;

    for (final net in _cacNet) {
      if (net.isEmpty) continue;
      if (net.length == 1) {
        canvas.drawCircle(
          Offset(net[0].dx * scaleX, net[0].dy * scaleY),
          netPaint.strokeWidth / 2,
          Paint()
            ..color = netPaint.color
            ..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        path.moveTo(net[0].dx * scaleX, net[0].dy * scaleY);
        for (int i = 1; i < net.length; i++) {
          path.lineTo(net[i].dx * scaleX, net[i].dy * scaleY);
        }
        canvas.drawPath(path, netPaint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

/// Widget hiển thị ô ký tay bằng ngón tay
class BangKyTay extends StatelessWidget {
  final ChuKyController controller;
  final Color mauNet;
  final double doDayNet;

  const BangKyTay({
    super.key,
    required this.controller,
    this.mauNet = const Color(0xFF0F172A),
    this.doDayNet = 2.8,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        controller.setRenderSize(
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        return ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                controller.batDauNet(details.localPosition);
              },
              onPanUpdate: (details) {
                controller.themDiem(details.localPosition);
              },
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: _ChuKyPainter(
                  cacNet: controller.cacNet,
                  mauNet: mauNet,
                  doDayNet: doDayNet,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChuKyPainter extends CustomPainter {
  final List<List<Offset>> cacNet;
  final Color mauNet;
  final double doDayNet;

  _ChuKyPainter({
    required this.cacNet,
    required this.mauNet,
    required this.doDayNet,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = mauNet
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = doDayNet
      ..style = PaintingStyle.stroke;

    for (final net in cacNet) {
      if (net.isEmpty) continue;
      if (net.length == 1) {
        canvas.drawCircle(
          net[0],
          doDayNet / 2,
          Paint()
            ..color = mauNet
            ..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        path.moveTo(net[0].dx, net[0].dy);
        for (int i = 1; i < net.length; i++) {
          path.lineTo(net[i].dx, net[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChuKyPainter oldDelegate) => true;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, Clipboard, ClipboardData;
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/services/VnPayService.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/core/utils/VietQrHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhVnPayWebView.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// ─── Chế độ thanh toán ────────────────────────────────────────────────────────
enum PaymentMode { payAll, payInstallment }

/// Màn hình Thanh Toán QR - Hỗ trợ thanh toán toàn bộ hoặc chia 2 đợt.
/// Mã QR VietQR tự động điền số tiền đã chọn. Không cần tải biên lai.
class PaymentScreen extends StatefulWidget {
  final HoaDonModel hoaDon;
  final String tenPhong;

  /// Callback khi thanh toán thành công để màn hình cha tự cập nhật
  final void Function(num amountPaid)? onPaymentSuccess;

  const PaymentScreen({
    super.key,
    required this.hoaDon,
    required this.tenPhong,
    this.onPaymentSuccess,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ─── Thông tin thụ hưởng MB Bank theo ảnh thực tế ───
  static const _bankCode = '970422'; // MB Bank Napas BIN
  static const _bankFullName = 'MB Bank (Ngân hàng Quân Đội)';
  static const _bankBranch = 'Chi nhánh TP. Hồ Chí Minh';
  static const _accountNo = '0865109632';
  static const _accountName = 'TRINH MY DUYEN';
  static const _bqlLabel = 'NHÀ TRỌ KIÊU GIANG - BQL TÒA 2';

  // ─── SePay API Token tích hợp MB Bank tự động ───
  static const _sepayApiToken =
      'FNWKJB1MTCSNMOHYXDEURWAAQQ4WXGE4MZFJP83RTU6IZFVXWQCYQCZ9S71KIEAR';

  // ─── Theme Colors ───
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _mbBlue = Color(0xFF003DA5);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  // ─── Animations (Chỉ giữ pulse nhẹ cho chấm đèn đếm ngược) ───
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ─── States ────────────────────────────────────────────────────────────────
  int _countdownSec = 15 * 60;
  Timer? _countdownTimer;
  bool _isFeesExpanded = false;

  /// Chế độ thanh toán
  PaymentMode _paymentMode = PaymentMode.payAll;

  /// Đợt đang thanh toán (1 hoặc 2), chỉ dùng khi _paymentMode == payInstallment
  int _installmentStep = 1;

  /// Trạng thái đang xử lý xác nhận
  bool _isConfirming = false;

  /// Cờ đánh dấu đã hoàn tất thanh toán để tránh gọi lặp
  bool _isPaymentCompleted = false;

  /// Đóng màn hình thanh toán, ưu tiên pop về màn hình trước đó, nếu không thì về tab Hóa đơn (initialTabIndex: 2)
  void _dongManHinh() {
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
  }

  /// Timers & subscriptions cho hệ thống tự động gạch nợ 24/7
  Timer? _autoDetectionTimer;
  Timer? _pollTimer;
  StreamSubscription? _realtimeSub;

  // ─── Ràng buộc chia 2 đợt & Phí phạt trễ hạn ────────────────────────────────────
  int get _soNgayQuaHan =>
      widget.hoaDon.soNgayConLai < 0 ? -widget.hoaDon.soNgayConLai : 0;

  num get _phiPhatTreHan => 0;

  num get _tongGiaTriHoaDon {
    final base =
        widget.hoaDon.tienPhong +
        widget.hoaDon.tienDienNuoc +
        widget.hoaDon.tienDichVuKhac +
        widget.hoaDon.noCu;
    if (base > 0) return base;
    return widget.hoaDon.tongTien > 0 ? widget.hoaDon.tongTien : 0;
  }

  num get _dotMotMin => (_tongGiaTriHoaDon * 0.5).ceilToDouble();
  num get _dotHai => _tongGiaTriHoaDon - _dotMotMin;

  DateTime get _hanChotDot2Date {
    DateTime base = DateTime.now();
    if (widget.hoaDon.hanDongTien.isNotEmpty) {
      try {
        base = DateTime.parse(widget.hoaDon.hanDongTien);
      } catch (_) {}
    } else if (widget.hoaDon.ngayLap.isNotEmpty) {
      try {
        base = DateTime.parse(widget.hoaDon.ngayLap);
      } catch (_) {}
    }
    // Ngày 15 giữa tháng của kỳ hóa đơn
    DateTime mid = DateTime(base.year, base.month, 15);
    // Nếu ngày hạn đợt 1 gốc rơi vào sau ngày 15, dời sang ngày 15 tháng kế tiếp
    if (base.day > 15) {
      mid = DateTime(base.year, base.month + 1, 15);
    }
    return mid;
  }

  String get _hanChotDot2Formatted {
    final d = _hanChotDot2Date;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  bool get _isPayingRemainingDebt =>
      widget.hoaDon.trangThai == 'Thanh toán một phần' ||
      _initialStatus == 'Thanh toán một phần';

  num get _soTienCanThanhToan {
    if (_isPayingRemainingDebt) {
      if (widget.hoaDon.tongTien > 0 &&
          widget.hoaDon.tongTien < _tongGiaTriHoaDon) {
        return widget.hoaDon.tongTien;
      }
      return _dotHai;
    }
    if (_paymentMode == PaymentMode.payAll) {
      return _tongGiaTriHoaDon;
    }
    return _installmentStep == 1 ? _dotMotMin : _dotHai;
  }

  num get _tongTien =>
      _isPayingRemainingDebt ? _soTienCanThanhToan : _tongGiaTriHoaDon;

  late final String _initialStatus;
  late final num _initialRemainingAmount;

  final Set<String> _seenTxIds = {};
  bool _isFirstSePayCheck = true;
  bool _isCheckingSePay = false;
  int _pollCounter = 0;

  @override
  void initState() {
    super.initState();
    _initialStatus = widget.hoaDon.trangThai;
    _initialRemainingAmount = widget.hoaDon.tongTien;

    // Nếu hóa đơn này đã trả đợt 1 trước đó (đang là Thanh toán một phần), mặc định là trả nốt đợt 2 và không chia nhỏ nữa
    if (_isPayingRemainingDebt) {
      _paymentMode = PaymentMode.payAll;
      _installmentStep = 2;
    } else if (_soNgayQuaHan > 0) {
      // Hóa đơn đã trễ hạn: Khóa hình thức chia đợt, bắt buộc thanh toán toàn bộ
      _paymentMode = PaymentMode.payAll;
    }

    WidgetsBinding.instance.addObserver(this);
    _initAnimations();
    _startCountdown();
    _startAutoDetection();

    // Nếu hóa đơn đã được thanh toán từ trước thì chuyển thẳng sang xem biên lai, tuyệt đối không gọi _handleConfirmPayment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.hoaDon.trangThai == 'Đã thanh toán' &&
          widget.hoaDon.tongTien <= 0) {
        final n = DateTime.now();
        final now =
            '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')} – '
            '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentCompletedScreen(
              hoaDon: widget.hoaDon,
              tenPhong: widget.tenPhong,
              bankName: _bankFullName,
              transactionTime: now,
              amountPaid: widget.hoaDon.tongTienGoc,
            ),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Không tự động gạch nợ khi chuyển app nữa để tránh lỗi chưa thanh toán mà đã xong
  }

  void _startAutoDetection() {
    _autoDetectionTimer?.cancel();
    _pollTimer?.cancel();

    // 1. Lắng nghe thay đổi trạng thái hóa đơn theo thời gian thực (Supabase Realtime)
    try {
      final db = Supabase.instance.client;
      _realtimeSub?.cancel();
      _realtimeSub = db
          .from('hoa_don')
          .stream(primaryKey: ['ma_hoa_don'])
          .eq('ma_hoa_don', widget.hoaDon.maHoaDon)
          .listen(
            (rows) {
              if (!mounted || _isPaymentCompleted || rows.isEmpty) return;
              final st = rows.first['trang_thai']?.toString() ?? '';
              final remaining =
                  num.tryParse(rows.first['tong_tien']?.toString() ?? '0') ?? 0;

              if (_initialStatus == 'Chưa thanh toán') {
                if (st == 'Đã thanh toán' ||
                    (st == 'Thanh toán một phần' &&
                        remaining < _initialRemainingAmount)) {
                  _handleConfirmPayment(
                    reason: st == 'Đã thanh toán'
                        ? 'Tài khoản MB Bank đã ghi nhận thanh toán toàn bộ!'
                        : 'Tài khoản MB Bank đã ghi nhận thanh toán đợt 1!',
                  );
                }
              } else if (_initialStatus == 'Thanh toán một phần') {
                // Khách đang thanh toán đợt 2 còn lại: CHỈ kích hoạt khi số tiền nợ giảm hoặc đã trả hết
                if (st == 'Đã thanh toán' ||
                    remaining < _initialRemainingAmount) {
                  _handleConfirmPayment(
                    reason: 'Tài khoản MB Bank đã ghi nhận thanh toán đợt 2!',
                  );
                }
              }
            },
            onError: (err) {
              debugPrint(
                '[PAYMENT_REALTIME] Stream notice/fallback to polling: $err',
              );
            },
          );

      // 2. Cơ chế Polling dự phòng mỗi 2.5 giây: Kiểm tra Supabase & SePay API MB Bank
      _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (
        timer,
      ) async {
        if (!mounted || _isPaymentCompleted) {
          timer.cancel();
          return;
        }

        // A. Kiểm tra Supabase
        try {
          final res = await db
              .from('hoa_don')
              .select('trang_thai, tong_tien')
              .eq('ma_hoa_don', widget.hoaDon.maHoaDon)
              .maybeSingle();
          if (res != null && mounted && !_isPaymentCompleted) {
            final st = res['trang_thai']?.toString() ?? '';
            final remaining =
                num.tryParse(res['tong_tien']?.toString() ?? '0') ?? 0;

            if (_initialStatus == 'Chưa thanh toán') {
              if (st == 'Đã thanh toán' ||
                  (st == 'Thanh toán một phần' &&
                      remaining < _initialRemainingAmount)) {
                timer.cancel();
                _handleConfirmPayment(
                  reason: st == 'Đã thanh toán'
                      ? 'Tài khoản MB Bank đã ghi nhận thanh toán toàn bộ!'
                      : 'Tài khoản MB Bank đã ghi nhận thanh toán đợt 1!',
                );
                return;
              }
            } else if (_initialStatus == 'Thanh toán một phần') {
              if (st == 'Đã thanh toán' ||
                  remaining < _initialRemainingAmount) {
                timer.cancel();
                _handleConfirmPayment(
                  reason: 'Tài khoản MB Bank đã ghi nhận thanh toán đợt 2!',
                );
                return;
              }
            }
          }
        } catch (_) {}

        // B. Kiểm tra SePay trực tiếp trên Mobile (chu kỳ 5 giây, không gọi dồn dập khi request trước chưa xong)
        _pollCounter++;
        if (_pollCounter % 2 == 0 &&
            !kIsWeb &&
            !_isPaymentCompleted &&
            !_isCheckingSePay &&
            mounted) {
          await _checkSePayTransactions();
        }
      });
    } catch (_) {}
  }

  /// Tự động kiểm tra biến động số dư MB Bank qua SePay v2 API
  Future<void> _checkSePayTransactions() async {
    if (!mounted || _isPaymentCompleted || _isCheckingSePay) return;
    _isCheckingSePay = true;

    try {
      final url = Uri.parse(
        'https://userapi.sepay.vn/v2/transactions?limit=10',
      );
      final response = await http
          .get(
            url,
            headers: {
              'Authorization': 'Bearer $_sepayApiToken',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && mounted && !_isPaymentCompleted) {
        final data = jsonDecode(response.body);
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          // Lần đầu mở màn hình: Ghi nhận tất cả các giao dịch cũ để không bao giờ nhận nhầm giao dịch trong quá khứ
          if (_isFirstSePayCheck) {
            for (final item in list) {
              final id = item['id']?.toString() ?? '';
              if (id.isNotEmpty) _seenTxIds.add(id);
            }
            _isFirstSePayCheck = false;
            return;
          }

          final cleanBill = widget.hoaDon.maHoaDon
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
              .toUpperCase();
          for (final item in list) {
            final txId = item['id']?.toString() ?? '';
            if (_seenTxIds.contains(txId)) continue;
            _seenTxIds.add(txId);

            final content = (item['transaction_content'] ?? '')
                .toString()
                .toUpperCase();
            final amountIn =
                num.tryParse(item['amount_in']?.toString() ?? '0') ?? 0;

            // BẮT BUỘC:
            // 1. Là giao dịch MỚI sau khi mở màn hình thanh toán
            // 2. Khớp đúng mã hóa đơn
            // 3. Số tiền >= số tiền cần thanh toán
            final isMatchBill =
                cleanBill.isNotEmpty && content.contains(cleanBill);
            final isMatchAmount = amountIn >= _soTienCanThanhToan;

            if (isMatchBill && isMatchAmount) {
              _handleConfirmPayment(
                reason:
                    'SePay: MB Bank đã nhận ${FormatUtils.currency(amountIn.toDouble())}đ khớp hóa đơn $cleanBill!',
              );
              break;
            }
          }
        }
      }
    } on TimeoutException {
      // debugPrint('[SEPAY] Timeout kiểm tra giao dịch (đang đợi phản hồi từ SePay, sẽ tự thử lại)...');
    } catch (e) {
      debugPrint('[SEPAY] Kiểm tra giao dịch: $e');
    } finally {
      _isCheckingSePay = false;
    }
  }

  void _initAnimations() {
    // Pulse animation cho hiệu ứng nhấp nháy đèn chờ
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownSec = 15 * 60;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_countdownSec > 0) {
          _countdownSec--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _autoDetectionTimer?.cancel();
    _pollTimer?.cancel();
    _realtimeSub?.cancel();
    super.dispose();
  }

  String get _countdownText {
    final m = _countdownSec ~/ 60;
    final s = _countdownSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Dữ liệu chuỗi mã QR chuẩn EMVCo Napas 24/7 để vẽ Vector (luôn có sẵn số tiền & nội dung)
  String get _qrPayloadData => VietQrHelper.generateVietQrString(
    amount: _soTienCanThanhToan.toDouble(),
    memo: widget.hoaDon.noiDungChuyenKhoan,
    bankBin: _bankCode,
    accountNo: _accountNo,
  );

  /// Tự động cập nhật tài khoản thành 'TamKhoa' trên Supabase nếu trễ hạn >= 10 ngày
  Future<void> _autoLockAccountIfOverdue() async {
    try {
      final db = Supabase.instance.client;
      String? accountId = AuthService.currentUser?.maTaiKhoan;
      if (accountId == null || accountId.isEmpty) {
        final hdRow = await db
            .from('hop_dong')
            .select('ma_khach_dai_dien')
            .eq('ma_hop_dong', widget.hoaDon.maHopDong)
            .maybeSingle();
        if (hdRow != null) {
          final maKhach = hdRow['ma_khach_dai_dien'];
          if (maKhach != null) {
            final ktRow = await db
                .from('khach_thue')
                .select('ma_tai_khoan')
                .eq('ma_khach', maKhach)
                .maybeSingle();
            accountId = ktRow?['ma_tai_khoan']?.toString();
          }
        }
      }

      if (accountId != null && accountId.isNotEmpty) {
        await db
            .from('tai_khoan')
            .update({'trang_thai': 'TamKhoa'})
            .eq('ma_tai_khoan', accountId);
        final cur = AuthService.currentUser;
        if (cur != null && cur.maTaiKhoan == accountId) {
          AuthService.currentUserNotifier.value =
              cur.copyWith(trangThai: 'TamKhoa');
        }
        debugPrint('[AUTO_LOCK] ManHinhThanhToan: Đã cập nhật tai_khoan $accountId sang TamKhoa');
      }
    } catch (e) {
      debugPrint('[AUTO_LOCK] ManHinhThanhToan lỗi khóa tài khoản: $e');
    }
  }

  // VietQR Image URL – mẫu qr_only (vuông 1:1, ma trận QR thuần túy)
  String get _vietQrUrl => VietQrHelper.buildVietQrImageUrl(
    amount: _soTienCanThanhToan.toDouble(),
    memo: widget.hoaDon.noiDungChuyenKhoan,
    bankBin: _bankCode,
    accountNo: _accountNo,
    accountName: _accountName,
  );

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Đã sao chép',
      noiDung: 'Đã sao chép $label: $text vào bộ nhớ tạm!',
      type: ThongBaoType.thongTin,
      duration: const Duration(milliseconds: 1800),
    );
  }

  void _copyAllInfo() {
    final all =
        '''
Ngân hàng: $_bankFullName
Chủ tài khoản: $_accountName
Số tài khoản: $_accountNo
Số tiền: ${FormatUtils.currency(_soTienCanThanhToan.toDouble())} VNĐ
Nội dung: ${widget.hoaDon.noiDungChuyenKhoan}''';
    _copyToClipboard(all.trim(), 'toàn bộ thông tin');
  }

  // ─── Xử lý gạch nợ & hiển thị thông báo, phát chuông thành công ───
  Future<void> _handleConfirmPayment({String? reason}) async {
    if (_isConfirming || _isPaymentCompleted || !mounted) return;
    setState(() {
      _isConfirming = true;
      _isPaymentCompleted = true;
    });
    _autoDetectionTimer?.cancel();
    _pollTimer?.cancel();
    _realtimeSub?.cancel();
    _countdownTimer?.cancel();

    // Xác định đang là đợt 2 / trả hết hay đợt 1
    final bool isAllOrStep2 =
        _isPayingRemainingDebt ||
        _paymentMode == PaymentMode.payAll ||
        _installmentStep == 2;

    // THÊM DÒNG NÀY VÀO ĐÂY:
    final String tenDot = isAllOrStep2
        ? (_isPayingRemainingDebt
              ? 'Đợt 2 / 2 (Tất toán)'
              : 'Thanh toán toàn bộ')
        : 'Đợt 1 / 2 (50%)';

    final db = Supabase.instance.client;
    final maHoaDon = widget.hoaDon.maHoaDon.trim();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // ma_phieu_thu là varchar(10) trong Supabase: 'PT' + 8 số cuối của timestamp
    final maPhieuThu = 'PT${(timestamp % 100000000).toString().padLeft(8, '0')}';
    final maTraCuu = 'FT26${(timestamp % 1000000000000).toString().padLeft(12, '0')}';
    final String hinhThucThu = (reason != null && reason.contains('VNPAY'))
        ? 'Cổng VNPAY'
        : 'Chuyển khoản MB Bank';

    try {
      // 1. CẬP NHẬT TRẠNG THÁI HÓA ĐƠN
      if (isAllOrStep2) {
        await db
            .from('hoa_don')
            .update({'trang_thai': 'Đã thanh toán', 'tong_tien': 0})
            .eq('ma_hoa_don', maHoaDon);
      } else {
        final num soTienConLai = _dotHai;
        final d2 = _hanChotDot2Date;
        final hanChotDot2Str =
            '${d2.year}-${d2.month.toString().padLeft(2, '0')}-${d2.day.toString().padLeft(2, '0')}';

        await db
            .from('hoa_don')
            .update({
              'trang_thai': 'Thanh toán một phần',
              'tong_tien': soTienConLai,
              'han_dong_tien': hanChotDot2Str,
            })
            .eq('ma_hoa_don', maHoaDon);
      }

      // 2. GHI LỊCH SỬ VÀO BẢNG phieu_thu CHO TỪNG ĐỢT RIÊNG BIỆT
      try {
        await db.from('phieu_thu').insert({
          'ma_phieu_thu': maPhieuThu,
          'ma_hoa_don': maHoaDon,
          'ma_tra_cuu': maTraCuu,
          'so_tien_thu': _soTienCanThanhToan,
          'hinh_thuc': hinhThucThu,
          'ngay_thu': DateTime.now().toIso8601String(),
          'trang_thai': 'Đã thanh toán',
        });
        debugPrint('[PHIEU_THU] Đã ghi nhận phiếu thu thành công: $maPhieuThu cho hóa đơn $maHoaDon');
      } catch (ePt) {
        debugPrint('[PHIEU_THU] Lỗi lưu phiếu thu: $ePt');
      }

      // Tự động mở lại tài khoản về HoatDong trên Supabase khi thanh toán hoàn tất
      final curUser = AuthService.currentUser;
      if (curUser != null && curUser.maTaiKhoan.isNotEmpty) {
        try {
          await db
              .from('tai_khoan')
              .update({'trang_thai': 'HoatDong'})
              .eq('ma_tai_khoan', curUser.maTaiKhoan);
          AuthService.currentUserNotifier.value =
              curUser.copyWith(trangThai: 'HoatDong');
          debugPrint('[AUTO_UNLOCK] Đã mở lại HoatDong cho tài khoản ${curUser.maTaiKhoan}');
        } catch (eTk) {
          debugPrint('[AUTO_UNLOCK] Lỗi mở lại tài khoản: $eTk');
        }
      }

      if (mounted) widget.onPaymentSuccess?.call(_soTienCanThanhToan);
    } catch (e) {
      debugPrint('Lỗi xác nhận thanh toán: $e');
    }

    if (!mounted) return;

    // 🔔 3. PHÁT CHUÔNG THANH TOÁN (TING)
    PaymentSoundHelper.playSuccess();

    // 📲 4. ĐẨY THÔNG BÁO XUỐNG THANH TRẠNG THÁI (ĐỢT 1 VÀ ĐỢT 2 ĐỀU HIỆN)
    try {
      final String tieuDeThongBao = isAllOrStep2
          ? (_isPayingRemainingDebt
                ? '🎉 Đã tất toán Đợt 2 thành công!'
                : '🎉 Thanh toán hóa đơn thành công!')
          : '💵 Thanh toán Đợt 1 thành công!';

      final String noiDungThongBao = isAllOrStep2
          ? 'Bạn đã thanh toán xong Đợt 2 (${FormatUtils.currency(_soTienCanThanhToan.toDouble())}). Hóa đơn kỳ ${widget.hoaDon.thangNam} đã được quyết toán đủ.'
          : 'Đã thanh toán Đợt 1 (${FormatUtils.currency(_soTienCanThanhToan.toDouble())}). Hạn nộp Đợt 2: Ngày 15 giữa tháng ($_hanChotDot2Formatted).';

      // Dùng tag kèm timestamp để không bị Android chặn trùng lặp
      final notifTag =
          'pay_${maHoaDon}_${DateTime.now().millisecondsSinceEpoch}';

      SystemNotificationService.show(
        title: tieuDeThongBao,
        body: noiDungThongBao,
        tag: notifTag,
        loai: 'hoa_don',
      );
    } catch (e) {
      debugPrint('Lỗi bắn Local Notification: $e');
    }

    // 📄 5. ĐIỀU HƯỚNG SANG BIÊN LAI
    final n = DateTime.now();
    final now =
        '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')} – '
        '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentCompletedScreen(
          hoaDon: widget.hoaDon,
          tenPhong: widget.tenPhong,
          bankName: _bankFullName,
          transactionTime: now,
          amountPaid: _soTienCanThanhToan, // 2.100.000đ khi trả từng đợt
          tenDot:
              tenDot, // Thêm dòng này để biên lai hiện "Đợt 1 / 2" hoặc "Đợt 2 / 2"
          transactionRef: maTraCuu,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  children: [
                    _buildInvoiceSummaryCard(),
                    const SizedBox(height: 14),
                    _buildPaymentModeSelector(),
                    const SizedBox(height: 14),
                    _buildQrCard(),
                    const SizedBox(height: 14),
                    _buildManualTransferCard(),
                    const SizedBox(height: 14),
                    _buildAutoClearingBanner(),
                  ],
                ),
              ),
            ),
            _buildBottomNavBar(),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── 1. TOP APP BAR ────────────────────────
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: _dongManHinh,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _primary,
                    size: 16,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kiêu Giang',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _primaryDark,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    'Thanh toán hóa đơn',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF475569),
                      size: 20,
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: _primary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: _dongManHinh,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _primary,
                      size: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.apartment_rounded,
                            color: _primary,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${widget.tenPhong} • Kỳ ${widget.hoaDon.thangNam}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Hóa đơn tiền phòng & dịch vụ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_isPayingRemainingDebt)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Text(
                      'Đợt 2/2 • Tất toán nợ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  )
                else if (_paymentMode == PaymentMode.payInstallment)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      'Đợt $_installmentStep/2',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: _primary, size: 6),
                        SizedBox(width: 4),
                        Text(
                          'Thanh toán QR',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────── 3. INVOICE SUMMARY CARD ────────────────────────
  Widget _buildInvoiceSummaryCard() {
    final hd = widget.hoaDon;
    final soNgay = hd.soNgayConLai;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
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
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mã HĐ: #${hd.maHoaDon}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                      Text(
                        'Kỳ tháng ${hd.thangNam}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: soNgay < 0
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: soNgay < 0
                          ? const Color(0xFFFECACA)
                          : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        soNgay < 0
                            ? Icons.error_outline_rounded
                            : Icons.schedule_rounded,
                        color: soNgay < 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF2563EB),
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        soNgay > 0
                            ? 'Còn $soNgay ngày'
                            : soNgay == 0
                            ? 'Đến hạn hôm nay'
                            : 'Quá hạn ${-soNgay} ngày',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: soNgay < 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF2563EB),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDCEAFE)),
            ),
            child: Column(
              children: [
                Text(
                  _isPayingRemainingDebt
                      ? 'Khoản nợ còn lại cần thanh toán (Đợt 2/2)'
                      : _paymentMode == PaymentMode.payAll
                      ? 'Tổng số tiền cần thanh toán'
                      : _installmentStep == 1
                      ? 'Đợt 1 – Tối thiểu 50% (${FormatUtils.currency(_tongTien.toDouble())}đ tổng)'
                      : 'Đợt 2 – Phần còn lại',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        FormatUtils.currency(_soTienCanThanhToan.toDouble()),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: _paymentMode == PaymentMode.payInstallment
                              ? const Color(0xFFD97706)
                              : _textDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'đ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _paymentMode == PaymentMode.payInstallment
                                ? const Color(0xFFD97706)
                                : _primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_soNgayQuaHan >= 5) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _soNgayQuaHan >= 10
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _soNgayQuaHan >= 10
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFFFCD34D),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _isPayingRemainingDebt
                              ? '⚠️ KHOẢN NỢ ĐỢT 2 QUÁ HẠN ' + _soNgayQuaHan.toString() + ' NGÀY'
                              : '⚠️ HÓA ĐƠN ĐANG QUÁ HẠN ' + _soNgayQuaHan.toString() + ' NGÀY',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Quý khách vui lòng thanh toán để hoàn tất nghĩa vụ tiền phòng kỳ này.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF7F1D1D),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      color: Color(0xFF64748B),
                      size: 12,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Hạn chót: ${hd.hanDongTienFormatted}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          InkWell(
            onTap: () {
              setState(() {
                _isFeesExpanded = !_isFeesExpanded;
              });
            },
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.article_outlined, color: _primary, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    _isFeesExpanded
                        ? 'Thu gọn chi tiết'
                        : 'Xem chi tiết các khoản phí',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 250),
                    turns: _isFeesExpanded ? 0.5 : 0,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _primary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _isFeesExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 10),
                  _buildFeeItem('Tiền phòng', hd.tienPhong),
                  _buildFeeItem('Tiền điện & nước', hd.tienDienNuoc),
                  _buildFeeItem('Dịch vụ khác / Wifi / Rác', hd.tienDichVuKhac),
                  if (hd.noCu > 0)
                    _buildFeeItem('Nợ kỳ trước', hd.noCu, isWarning: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeeItem(String label, num amount, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isWarning
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${FormatUtils.currency(amount.toDouble())}đ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isWarning ? const Color(0xFFDC2626) : _textDark,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────── PAYMENT MODE SELECTOR ────────────────────────
  Widget _buildPaymentModeSelector() {
    if (_isPayingRemainingDebt) {
      final isOverdue = _soNgayQuaHan > 0;
      final isLocked = _soNgayQuaHan >= 10;
      final isWarn = _soNgayQuaHan >= 5;

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOverdue ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isOverdue ? const Color(0xFFFECACA) : const Color(0xFFFDE68A),
          ),
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
                    color: isOverdue ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isLocked
                        ? Icons.lock_rounded
                        : (isWarn
                            ? Icons.warning_amber_rounded
                            : (isOverdue
                                ? Icons.error_outline_rounded
                                : Icons.receipt_long_rounded)),
                    color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPayingRemainingDebt
                            ? 'TRỄ HẠN ĐỢT 2 $_soNgayQuaHan NGÀY'
                            : (isOverdue
                                ? 'HÓA ĐƠN QUÁ HẠN $_soNgayQuaHan NGÀY'
                                : 'THANH TOÁN HÓA ĐƠN TIỀN PHÒNG'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isOverdue ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isOverdue
                            ? 'Hạn chót Đợt 2: ${widget.hoaDon.hanDongTienFormatted} (Quá hạn $_soNgayQuaHan ngày)'
                            : 'Hóa đơn đã được thanh toán đợt 1 trước đó',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOverdue ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
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
                    color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isOverdue ? 'Quá hạn $_soNgayQuaHan ngày' : 'Đợt 2/2',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOverdue ? const Color(0xFFFECACA) : const Color(0xFFFDE68A),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isLocked
                        ? Icons.lock_rounded
                        : (isOverdue ? Icons.warning_amber_rounded : Icons.lock_outline_rounded),
                    size: 16,
                    color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOverdue
                          ? 'Khoản nợ đã trễ hạn $_soNgayQuaHan ngày từ ngày ${widget.hoaDon.hanDongTienFormatted}. Quý khách vui lòng thanh toán ${FormatUtils.currency(_tongTien.toDouble())}đ để hoàn tất hóa đơn kỳ này.'
                          : 'Hóa đơn đang còn nợ ${FormatUtils.currency(_tongTien.toDouble())}. Quý khách vui lòng chuyển khoản toàn bộ số tiền này để tất toán hóa đơn.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isOverdue ? const Color(0xFF7F1D1D) : const Color(0xFF78350F),
                        height: 1.35,
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

    // ⛔ Khi hóa đơn đã trễ hạn: Không cho chọn hình thức thanh toán nữa, bắt buộc thanh toán toàn bộ
    if (_soNgayQuaHan > 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFECACA)),
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
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HÓA ĐƠN TRỄ HẠN $_soNgayQuaHan NGÀY',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF991B1B),
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hạn thanh toán: ${widget.hoaDon.hanDongTienFormatted}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB91C1C),
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
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Khóa chia đợt',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hóa đơn đã quá hạn thanh toán nên không áp dụng hình thức chia 2 đợt. Quý khách vui lòng thanh toán toàn bộ số tiền để tránh gián đoạn dịch vụ lưu trú.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF7F1D1D),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _primary, width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: _primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thanh toán toàn bộ (Bắt buộc)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Một lần – ${FormatUtils.currency(_tongTien.toDouble())}đ',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          const Row(
            children: [
              Icon(Icons.payment_rounded, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Chọn hình thức thanh toán',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildModeOption(
            mode: PaymentMode.payAll,
            icon: Icons.check_circle_outline_rounded,
            label: 'Thanh toán toàn bộ',
            sublabel:
                'Một lần – ${FormatUtils.currency(_tongTien.toDouble())}đ',
            accentColor: _primary,
            accentBg: const Color(0xFFE0F2FE),
          ),
          const SizedBox(height: 8),
          _buildModeOption(
            mode: PaymentMode.payInstallment,
            icon: Icons.splitscreen_rounded,
            label: 'Chia thành 2 đợt',
            sublabel:
                'Đợt 1 ≥ ${FormatUtils.currency(_dotMotMin.toDouble())}đ  •  Đợt 2: ${FormatUtils.currency(_dotHai.toDouble())}đ\n⏰ Hạn chót Đợt 2: Ngày 15 giữa tháng ($_hanChotDot2Formatted)',
            accentColor: const Color(0xFFD97706),
            accentBg: const Color(0xFFFFF7ED),
          ),
          if (_paymentMode == PaymentMode.payInstallment) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.alarm_on_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'RÀNG BUỘC HẠN THANH TOÁN ĐỢT 2: NGÀY 15 GIỮA THÁNG ($_hanChotDot2Formatted)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _installmentStep == 1
                        ? '• Đợt 1: Thanh toán ngay hôm nay (tối thiểu ${FormatUtils.currency(_dotMotMin.toDouble())}đ).\n'
                              '• Đợt 2: Phần còn lại ${FormatUtils.currency(_dotHai.toDouble())}đ BẮT BUỘC đóng trước ngày 15 giữa tháng ($_hanChotDot2Formatted), không được để nợ kéo dài.'
                        : 'Đang thanh toán đợt 2 – Số tiền ${FormatUtils.currency(_dotHai.toDouble())}đ (Hạn chót: Ngày 15 giữa tháng - $_hanChotDot2Formatted).',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF92400E),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required PaymentMode mode,
    required IconData icon,
    required String label,
    required String sublabel,
    required Color accentColor,
    required Color accentBg,
  }) {
    final isSelected = _paymentMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _paymentMode = mode;
        _installmentStep = 1;
        _startCountdown();
        _startAutoDetection();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accentBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? accentColor : _textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.radio_button_checked_rounded,
                color: accentColor,
                size: 22,
              )
            else
              const Icon(
                Icons.radio_button_off_rounded,
                color: Color(0xFFCBD5E1),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  // ─── THẺ XÁC NHẬN THANH TOÁN ─────────────────
  Widget _buildLiveAutoDetectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _isConfirming
              ? const Color(0xFF16A34A)
              : const Color(0xFFBAE6FD),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _isConfirming
                          ? const Color(0xFFDCFCE7)
                          : const Color(
                              0xFFE0F2FE,
                            ).withValues(alpha: _pulseAnimation.value),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _isConfirming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Color(0xFF16A34A),
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(
                              Icons.hourglass_top_rounded,
                              color: Color(0xFF0284C7),
                              size: 22,
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isConfirming
                          ? 'Đang xác nhận giao dịch...'
                          : 'Đang chờ giao dịch: $_countdownText',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _isConfirming
                            ? const Color(0xFF16A34A)
                            : _textDark,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _isConfirming
                          ? 'Đang đồng bộ dữ liệu, chuyển màn hình...'
                          : 'Quét mã QR và chuyển khoản – hệ thống tự động xác nhận ngay khi tiền vào.',
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
          ),
          const SizedBox(height: 16),

          // Banner tự động phát hiện (thay thế nút bấm thủ công)
          if (_isConfirming) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Color(0xFF16A34A),
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đang xử lý, chuyển sang màn hình thành công...',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.sensors_rounded,
                    color: Color(0xFF16A34A),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🔄 SePay: Tự động phát hiện thanh toán MB Bank',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Sau khi chuyển khoản thành công vào MB Bank, hệ thống SePay sẽ tự động phát hiện và chuyển trang trong vài giây.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF166534),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────── QR CARD ────────────────────────
  Widget _buildQrCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _mbBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'MB BANK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Quân Đội',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(width: 14),
                _buildVietQrBadge(),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Napas247',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Countdown pill with soft pulse dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFBAE6FD),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF0284C7,
                        ).withValues(alpha: _pulseAnimation.value),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Đang chờ quét mã: $_countdownText',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0369A1),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),

          // ── Khung Mã QR Vector Siêu Nét Có Sẵn Số Tiền ──
          _buildStaticQrBox(),
          const SizedBox(height: 14),

          // Badge hiển thị số tiền chuyển khoản chuẩn & chạm để copy nhanh
          InkWell(
            onTap: () => _copyToClipboard(
              _soTienCanThanhToan.toInt().toString(),
              'số tiền',
            ),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: Color(0xFF16A34A),
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 8),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF334155),
                        ),
                        children: [
                          const TextSpan(text: 'Số tiền chuyển khoản: '),
                          TextSpan(
                            text: FormatUtils.currency(
                              _soTienCanThanhToan.toDouble(),
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15803D),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 12,
                            color: Color(0xFF16A34A),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Sao chép',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveQrImageToGallery,
                  icon: const Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: _primary,
                  ),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Lưu ảnh QR',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2FE),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Sao chép ngầm STK vào clipboard (không hiện SnackBar)
                    Clipboard.setData(ClipboardData(text: _accountNo));
                    _showBankSelectionModal();
                  },
                  icon: const Icon(
                    Icons.account_balance_rounded,
                    size: 16,
                    color: _primary,
                  ),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Mở App Ngân hàng',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2FE),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final double soTienThanhToan = _soTienCanThanhToan.toDouble();
                final paymentUrl = VnPayService.generatePaymentUrl(
                  orderId:
                      '${widget.hoaDon.maHoaDon}${DateTime.now().millisecondsSinceEpoch}',
                  amount: soTienThanhToan,
                  orderInfo: 'Thanh toan tien phong ${widget.tenPhong}',
                );

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VnPayWebViewScreen(
                      paymentUrl: paymentUrl,
                      maHoaDon: widget.hoaDon.maHoaDon,
                      amount: soTienThanhToan,
                      tenPhong: widget.tenPhong,
                      onSuccess: () async {
                        await _handleConfirmPayment(
                          reason: 'Thanh toán qua Cổng VNPAY',
                        );
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.payment_rounded,
                size: 18,
                color: Colors.white,
              ),
              label: const Text(
                'Thanh toán qua Cổng VNPAY',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005BAA),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVietQrBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Viet',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFFDC2626),
            ),
          ),
          Text(
            'QR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF0284C7),
            ),
          ),
        ],
      ),
    );
  }

  // ── Khung mã QR Vector siêu nét chuẩn Napas EMVCo ──
  Widget _buildStaticQrBox() {
    const qrSize = 220.0;

    return Container(
      width: qrSize + 24,
      height: qrSize + 24,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBAE6FD), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: QrImageView(
          data: _qrPayloadData,
          version: QrVersions.auto,
          size: qrSize,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          padding: const EdgeInsets.all(4),
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF0F172A),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }

  // ──────────────────────── 5. MANUAL TRANSFER CARD ────────────────────────
  Widget _buildManualTransferCard() {
    final hd = widget.hoaDon;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
              Expanded(
                child: Text(
                  'THÔNG TIN CHUYỂN KHOẢN THỦ CÔNG',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF334155),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: _copyAllInfo,
                tooltip: 'Sao chép tất cả',
                icon: const Icon(
                  Icons.copy_all_rounded,
                  color: _primary,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildInfoRow(
            title: 'Ngân hàng thụ hưởng',
            value: _bankFullName,
            sub: _bankBranch,
            copyValue: '$_bankFullName - $_bankBranch',
            label: 'Ngân hàng',
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          _buildInfoRow(
            title: 'Tên chủ tài khoản',
            value: _accountName,
            sub: _bqlLabel,
            copyValue: _accountName,
            label: 'Tên chủ TK',
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Số tài khoản',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _accountNo,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _textDark,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _copyToClipboard(_accountNo, 'Số tài khoản'),
                icon: const Icon(Icons.content_copy_rounded, size: 14),
                label: const Text(
                  'Sao chép',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          _buildInfoRow(
            title: 'Số tiền chuyển',
            value: '${FormatUtils.currency(hd.tongTien.toDouble())} VNĐ',
            copyValue: hd.tongTien.toInt().toString(),
            label: 'Số tiền',
            isValueHighlighted: true,
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Nội dung chuyển khoản (bắt buộc)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: () => _copyToClipboard(
                  hd.noiDungChuyenKhoan,
                  'Nội dung chuyển khoản',
                ),
                icon: const Icon(
                  Icons.content_copy_rounded,
                  size: 13,
                  color: _primary,
                ),
                label: const Text(
                  'Sao chép',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: _primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                hd.noiDungChuyenKhoan,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0369A1),
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required String title,
    required String value,
    String? sub,
    required String copyValue,
    required String label,
    bool isValueHighlighted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: isValueHighlighted ? _primary : _textDark,
                ),
              ),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
        InkWell(
          onTap: () => _copyToClipboard(copyValue, label),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Text(
              'Copy',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────── 6. AUTO CLEARING BANNER ────────────────────────
  Widget _buildAutoClearingBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF5FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_user_rounded, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Hệ thống gạch nợ tự động 24/7',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              _buildMiniStepCard('1', 'Mở App ngân hàng bất kỳ'),
              const SizedBox(width: 8),
              _buildMiniStepCard('2', 'Quét mã QR hoặc nhập STK'),
              const SizedBox(width: 8),
              _buildMiniStepCard('3', 'Xác nhận tự động trong 30s'),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  color: Color(0xFF16A34A),
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Không cần chụp màn hình gửi chủ nhà. Khi ngân hàng báo trừ tiền thành công, trạng thái hóa đơn sẽ tự động đổi sang Đã Thanh Toán.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF334155),
                      height: 1.4,
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

  Widget _buildMiniStepCard(String num, String desc) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2FE),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                num,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              desc,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF475569),
                height: 1.25,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── 8. BOTTOM NAVIGATION BAR ────────────────────────
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 2, // Hóa đơn active
        onTap: (index) {
          if (index == 2) {
            _dongManHinh();
          } else {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (_) => TenantHomeScreen(initialTabIndex: index),
              ),
              (route) => false,
            );
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _primary,
        unselectedItemColor: const Color(0xFF94A3B8),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.key_outlined),
            activeIcon: Icon(Icons.key_rounded),
            label: 'Phòng',
          ),
          BottomNavigationBarItem(
            icon:
                (widget.hoaDon.trangThai != 'Đã thanh toán' &&
                    widget.hoaDon.tongTien > 0)
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.receipt_long_outlined),
                      Positioned(
                        top: -2,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE11D48),
                            shape: BoxShape.circle,
                          ),
                          child: const Text(
                            '1',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Icon(Icons.receipt_long_outlined),
            activeIcon: const Icon(Icons.receipt_long_rounded),
            label: 'Hóa đơn',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            activeIcon: Icon(Icons.build_rounded),
            label: 'Yêu cầu',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }

  // ─── 9. MỞ APP NGÂN HÀNG TRỰC TIẾP TỚI MÀN HÌNH CHUYỂN TIỀN CÓ ĐẦY ĐỦ THÔNG TIN ───
  Future<void> _openBankingApp({
    required String bankName,
    required String deepLinkWithData,
    required String baseScheme,
    required String androidPackage,
  }) async {
    // 1. Luôn sao chép STK ngầm vào Clipboard để ngân hàng tự động nhận diện
    try {
      await Clipboard.setData(ClipboardData(text: _accountNo));
    } catch (_) {}

    try {
      // Ưu tiên 1: Thử mở trực tiếp Deep Link chứa đầy đủ thông tin: STK, số tiền, nội dung
      final deepUri = Uri.parse(deepLinkWithData);
      try {
        if (await canLaunchUrl(deepUri)) {
          final launched = await launchUrl(
            deepUri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) return;
        }
      } catch (_) {}

      // Ưu tiên 2: Mở Base Scheme trực tiếp của ứng dụng ngân hàng (vd: mbmobile://, vcbdigibank://)
      final baseUri = Uri.parse(baseScheme);
      try {
        if (await canLaunchUrl(baseUri)) {
          final launchedBase = await launchUrl(
            baseUri,
            mode: LaunchMode.externalApplication,
          );
          if (launchedBase) return;
        }
      } catch (_) {}

      // Ưu tiên 3: Mở trực tiếp App qua Intent URI theo package trên Android
      try {
        final intentUri = Uri.parse(
          'intent://#Intent;package=$androidPackage;action=android.intent.action.MAIN;category=android.intent.category.LAUNCHER;end',
        );
        if (await canLaunchUrl(intentUri)) {
          final launchedIntent = await launchUrl(
            intentUri,
            mode: LaunchMode.externalApplication,
          );
          if (launchedIntent) return;
        }
      } catch (_) {}

      // Nếu không mở được -> Ứng dụng ngân hàng chưa được cài đặt trên máy
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFF09638E),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chưa cài đặt $bankName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Ứng dụng $bankName chưa có trên thiết bị này. Bạn có muốn tải về từ CH Play / App Store không?',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF334155)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text(
                'Để sau',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final marketUri = Uri.parse(
                  'market://details?id=$androidPackage',
                );
                try {
                  if (await canLaunchUrl(marketUri)) {
                    await launchUrl(
                      marketUri,
                      mode: LaunchMode.externalApplication,
                    );
                    return;
                  }
                } catch (_) {}
                final playStoreUri = Uri.parse(
                  'https://play.google.com/store/apps/details?id=$androidPackage',
                );
                await launchUrl(
                  playStoreUri,
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text(
                'Tải ứng dụng',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Lỗi mở app ngân hàng: $e');
      if (!mounted) return;
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Không thể mở ứng dụng',
        noiDung: 'Không thể mở ứng dụng ngân hàng $bankName',
        type: ThongBaoType.thatBai,
      );
    }
  }

  // ─── 2. BẢNG CHỌN NGÂN HÀNG (TONE TRẮNG - XANH ĐỒNG BỘ KIÊU GIANG) ───
  void _showBankSelectionModal() {
    final int amount = _soTienCanThanhToan.toInt();
    final String transferContent = widget.hoaDon.noiDungChuyenKhoan;
    final encodedContent = Uri.encodeComponent(transferContent);

    final List<Map<String, dynamic>> banks = [
      {
        'name': 'MB Bank',
        'sub': 'Ngân hàng Quân Đội (Khuyên dùng)',
        'logoUrl': 'https://cdn.vietqr.io/img/MB.png',
        'color': const Color(0xFF1E40AF),
        'deepLink':
            'mbmobile://transfer?accountNo=$_accountNo&bankCode=$_bankCode&amount=$amount&content=$encodedContent',
        'scheme': 'mbmobile://',
        'package': 'com.mbmobile',
      },
      {
        'name': 'Vietcombank',
        'sub': 'VCB Digibank',
        'logoUrl': 'https://cdn.vietqr.io/img/VCB.png',
        'color': const Color(0xFF15803D),
        'deepLink':
            'vcbdigibank://transfer?accountNumber=$_accountNo&bankCode=$_bankCode&amount=$amount&description=$encodedContent',
        'scheme': 'vcbdigibank://',
        'package': 'com.VCB',
      },
      {
        'name': 'Techcombank',
        'sub': 'Kỹ Thương Việt Nam',
        'logoUrl': 'https://cdn.vietqr.io/img/TCB.png',
        'color': const Color(0xFFDC2626),
        'deepLink':
            'techcombank://transfer?destAccount=$_accountNo&destBank=$_bankCode&amount=$amount&message=$encodedContent',
        'scheme': 'techcombank://',
        'package': 'vn.com.techcombank.bb.app',
      },
      {
        'name': 'VietinBank',
        'sub': 'VietinBank iPay',
        'logoUrl': 'https://cdn.vietqr.io/img/ICB.png',
        'color': const Color(0xFF0284C7),
        'deepLink':
            'vietinbankipay://transfer?receiverAccount=$_accountNo&receiverBank=$_bankCode&amount=$amount&content=$encodedContent',
        'scheme': 'vietinbankipay://',
        'package': 'com.vietinbank.ipay',
      },
      {
        'name': 'BIDV SmartBanking',
        'sub': 'Đầu Tư & Phát Triển Việt Nam',
        'logoUrl': 'https://cdn.vietqr.io/img/BIDV.png',
        'color': const Color(0xFF0D9488),
        'deepLink':
            'bidvsmartbanking://transfer?accountNumber=$_accountNo&bankCode=$_bankCode&amount=$amount&content=$encodedContent',
        'scheme': 'bidvsmartbanking://',
        'package': 'com.vnpay.bidv',
      },
      {
        'name': 'MoMo',
        'sub': 'Ví điện tử MoMo',
        'logoUrl': 'https://cdn.vietqr.io/img/momo.png',
        'color': const Color(0xFFA21CAF),
        'deepLink':
            'momo://transfer?phone=$_accountNo&amount=$amount&comment=$encodedContent',
        'scheme': 'momo://',
        'package': 'com.mservice.momopay',
      },
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thanh gạt nhỏ ở giữa
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tiêu đề
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.account_balance_rounded,
                      color: _primary,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Chọn ứng dụng thanh toán',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Hệ thống sẽ chuyển thẳng tới ứng dụng ngân hàng và sao chép sẵn STK để bạn thanh toán:',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),

            // Danh sách thẻ ngân hàng với icon thật
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: banks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final bank = banks[index];
                return InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBankingApp(
                      bankName: bank['name'] as String,
                      deepLinkWithData: bank['deepLink'] as String,
                      baseScheme: bank['scheme'] as String,
                      androidPackage: bank['package'] as String,
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              bank['logoUrl'] as String,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: bank['color'] as Color,
                                    child: Center(
                                      child: Text(
                                        (bank['name'] as String)
                                            .substring(0, 2)
                                            .toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bank['name'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                bank['sub'] as String,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Hàm lưu / chia sẻ ảnh QR thực tế
  // Hàm lưu ảnh QR trực tiếp vào Bộ sưu tập
  Future<void> _saveQrImageToGallery() async {
    try {
      // 1. Tải ảnh VietQR động với số tiền đã chọn
      List<int> bytesList;
      try {
        final request = await HttpClient().getUrl(Uri.parse(_vietQrUrl));
        final response = await request.close();
        final chunks = <int>[];
        await response.forEach(chunks.addAll);
        bytesList = chunks;
      } catch (_) {
        final byteData = await rootBundle.load(
          'assets/images/mb_qr_myduyen.png',
        );
        bytesList = byteData.buffer.asUint8List();
      }

      // 2. Ghi tạm ra bộ nhớ máy
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/qr_thanhtoan_${widget.hoaDon.maHoaDon}.png',
      );
      await file.writeAsBytes(bytesList);

      // 3. Yêu cầu cấp quyền và lưu trực tiếp vào Bộ sưu tập
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      await Gal.putImage(file.path, album: 'Kiêu Giang');

      if (!mounted) return;
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Đã lưu ảnh QR',
        noiDung: 'Đã lưu mã QR vào Bộ sưu tập thành công!',
        type: ThongBaoType.thanhCong,
      );
    } catch (e) {
      debugPrint('Lỗi lưu ảnh: $e');
      if (!mounted) return;
      // Nếu lỗi quyền hoặc không tìm thấy file ảnh thì fallback copy STK
      _copyToClipboard(_accountNo, 'Số tài khoản');
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Không thể lưu ảnh',
        noiDung: 'Không thể lưu ảnh vào máy, đã sao chép STK!',
        type: ThongBaoType.canhBao,
      );
    }
  }
}

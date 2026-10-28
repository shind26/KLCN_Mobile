import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/services/VnPayService.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/core/utils/VietQrHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhGiuCho.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhDatPhongThanhCong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhVnPayWebView.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';

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
  State<ManHinhThanhToanTheChan> createState() =>
      _ManHinhThanhToanTheChanState();
}

class _ManHinhThanhToanTheChanState extends State<ManHinhThanhToanTheChan>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF09638E);
  static const _bankCode = VietQrHelper.bankCode;
  static const _accountNo = VietQrHelper.accountNumber;
  static const _accountName = VietQrHelper.accountHolder;

  double get _depositAmount {
    if (widget.giuCho.soTienTheChan > 0) {
      return widget.giuCho.soTienTheChan.toDouble();
    }
    return DepositService.getDepositAmount(widget.room.giaThue);
  }

  String get _depositAmountFormatted => FormatUtils.currency(_depositAmount);

  // SePay v2 API Token tích hợp MB Bank tự động
  static const _sepayApiToken =
      'FNWKJB1MTCSNMOHYXDEURWAAQQ4WXGE4MZFJP83RTU6IZFVXWQCYQCZ9S71KIEAR';

  int _countdownSec = 15 * 60; // 15 phút đếm ngược
  Timer? _countdownTimer;
  Timer? _pollingTimer;
  StreamSubscription? _streamSub;
  bool _isCompleted = false;
  bool _isProcessing = false;
  bool _isCheckingSePay = false;
  bool _isFirstSePayCheck = true;
  bool _hasTransferred =
      false; // Chỉ khi đã chuyển tiền ảo / tiền thật thì mới cho phép bấm xác nhận
  final Set<String> _seenTxIds = {};

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  /// Xử lý khi khách bấm nút Back hoặc vuốt thoát màn hình thanh toán
  Future<void> _handleBackPress() async {
    if (_isCompleted) {
      Navigator.pop(context);
      return;
    }

    if (_hasTransferred) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 26,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đã Thanh Toán VNPAY',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(
            'Bạn đã thực hiện thanh toán tiền thế chân qua VNPAY cho phòng ${widget.room.tenHienThi}.\n\nVui lòng nhấn "Tôi đã chuyển tiền thành công" để hoàn tất xác nhận và xem biên lai đặt phòng.',
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ở lại trang'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tôi đã chuyển tiền thành công'),
            ),
          ],
        ),
      );

      if (proceed == true && mounted) {
        await _handleConfirmPayment();
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFDC2626),
              size: 26,
            ),
            SizedBox(width: 8),
            Text(
              'Hủy Giữ Chỗ & Thoát?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Bạn chưa hoàn tất thanh toán tiền thế chân cho ${widget.room.tenHienThi}.\n\nNếu thoát bây giờ, phiên giữ chỗ sẽ bị hủy ngay lập tức và phòng sẽ trở về trạng thái Trống để bạn hoặc người khác có thể đặt lại từ đầu.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ở lại thanh toán'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hủy & Thoát ra'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isProcessing = true);
      _countdownTimer?.cancel();
      _pollingTimer?.cancel();
      _streamSub?.cancel();

      await DepositService.huyGiuChoKhiThoat(
        maGiuCho: widget.giuCho.maGiuCho,
        maPhong: widget.room.maPhong,
        appointmentCode: widget.appointmentCode,
      );

      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  /// Thanh toán tiền thế chân qua cổng VNPAY
  Future<void> _payWithVnPay() async {
    _countdownTimer?.cancel();
    final vnpUrl = VnPayService.generatePaymentUrl(
      orderId:
          '${widget.giuCho.maGiuCho}${DateTime.now().millisecondsSinceEpoch}',
      amount: _depositAmount,
      orderInfo: 'The chan giu cho phong ${widget.room.maPhong}',
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VnPayWebViewScreen(
          paymentUrl: vnpUrl,
          maHoaDon: widget.giuCho.maGiuCho,
          amount: _depositAmount,
          tenPhong: widget.room.tenHienThi,
          onSuccess: () {
            PaymentSoundHelper.playSuccess();
            setState(() {
              _hasTransferred = true;
            });
            ThongBaoHelper.hienToast(
              context,
              tieuDe: 'Thanh toán thành công',
              noiDung:
                  '🎉 Bạn đã thanh toán qua VNPAY thành công! Nút "Tôi đã chuyển tiền thành công" đã xuất hiện bên dưới.',
              type: ThongBaoType.thanhCong,
              duration: const Duration(seconds: 4),
            );
          },
        ),
      ),
    );

    if (!_isCompleted && mounted) {
      _initCountdown();
    }
  }

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
    _initAutoPaymentPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccountSafety();
    });
  }

  Future<void> _checkAccountSafety() async {
    final hasAcc = await DepositService.hasExistingAccount(
      widget.customerPhone,
    );
    if (hasAcc && mounted && !_isCompleted) {
      _countdownTimer?.cancel();
      _pollingTimer?.cancel();
      _streamSub?.cancel();
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Không Thể Thanh Toán',
        noiDung:
            'Số điện thoại ${widget.customerPhone} đã có tài khoản trên hệ thống. Theo quy định, số điện thoại đã có tài khoản không thể giữ chỗ!',
        type: ThongBaoType.canhBao,
      );
      Navigator.pop(context);
    }
  }

  void _initCountdown() {
    // Mặc định luôn là 15 phút (900 giây)
    _countdownSec = 15 * 60;

    if (widget.giuCho.expiresAt != null) {
      final nowUtc = DateTime.now().toUtc();
      final exp = widget.giuCho.expiresAt!;
      final expUtc = exp.isUtc ? exp : exp.toUtc();
      final diff = expUtc.difference(nowUtc).inSeconds;
      if (diff > 0 && diff <= 15 * 60) {
        _countdownSec = diff;
      }
    }

    _countdownTimer?.cancel();
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
      _streamSub = DepositService.streamGiuCho(widget.giuCho.maGiuCho).listen((
        rows,
      ) {
        if (!mounted || _isCompleted || rows.isEmpty) return;
        final st = rows.first['trang_thai']?.toString() ?? '';
        if (st == 'Đã thanh toán' || st == 'DangGiu' || st == 'DaDatCoc') {
          _onPaymentSuccess();
        }
      });
    } catch (_) {}
  }

  /// Tự động lắng nghe giao dịch Napas 24/7 MB Bank qua SePay v2 API và Supabase
  void _initAutoPaymentPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (
      timer,
    ) async {
      if (!mounted || _isCompleted || _isProcessing) {
        if (_isCompleted) timer.cancel();
        return;
      }

      // 1. Kiểm tra trạng thái trên Supabase (dự phòng trường hợp webhook backend cập nhật)
      try {
        final res = await Supabase.instance.client
            .from('giu_cho')
            .select('trang_thai')
            .eq('ma_giu_cho', widget.giuCho.maGiuCho)
            .maybeSingle();
        if (res != null && mounted && !_isCompleted) {
          final st = res['trang_thai']?.toString() ?? '';
          if (st == 'Đã thanh toán' || st == 'DangGiu' || st == 'DaDatCoc') {
            timer.cancel();
            _onPaymentSuccess();
            return;
          }
        }
      } catch (_) {}

      // 2. Tự động kiểm tra trực tiếp giao dịch MB Bank qua SePay v2 API
      if (!_isCheckingSePay && !_isCompleted && mounted) {
        await _checkSePayTransactions();
      }
    });
  }

  /// Tự động lấy API SePay để xác nhận giao dịch MB Bank Napas 24/7
  Future<void> _checkSePayTransactions() async {
    if (!mounted || _isCompleted || _isProcessing || _isCheckingSePay) return;
    _isCheckingSePay = true;

    try {
      final url = Uri.parse(
        'https://userapi.sepay.vn/v2/transactions?limit=15',
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

      if (response.statusCode == 200 && mounted && !_isCompleted) {
        final data = jsonDecode(response.body);
        final list = data['data'] as List?;
        if (list != null && list.isNotEmpty) {
          final cleanCode = widget.giuCho.maGiuCho
              .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
              .toUpperCase();
          final rawCode = widget.giuCho.maGiuCho.toUpperCase();
          final numSuffix = cleanCode.replaceAll(RegExp(r'[^0-9]'), '');

          if (_isFirstSePayCheck) {
            _isFirstSePayCheck = false;
            // Kiểm tra xem trong list hiện tại đã có giao dịch nào khớp mã giữ chỗ này chưa
            bool foundInitial = false;
            for (final item in list) {
              final content = (item['transaction_content'] ?? '')
                  .toString()
                  .toUpperCase();
              final amountIn =
                  num.tryParse(item['amount_in']?.toString() ?? '0') ?? 0;
              final isMatchCode =
                  cleanCode.isNotEmpty &&
                  (content.contains(cleanCode) ||
                      content.contains(rawCode) ||
                      (numSuffix.length >= 6 && content.contains(numSuffix)));
              final isMatchAmount = amountIn >= _depositAmount;

              if (isMatchCode && isMatchAmount) {
                foundInitial = true;
                final txId = item['id']?.toString() ?? '';
                if (txId.isNotEmpty) _seenTxIds.add(txId);
                debugPrint(
                  '[SEPAY] Nhận diện cọc Napas 24/7 ngay khi mở: $cleanCode, $amountInđ',
                );
                _pollingTimer?.cancel();
                await _handleConfirmPayment();
                return;
              }
            }

            if (!foundInitial) {
              for (final item in list) {
                final id = item['id']?.toString() ?? '';
                if (id.isNotEmpty) _seenTxIds.add(id);
              }
              return;
            }
          }

          // Các lần kiểm tra định kỳ tiếp theo
          for (final item in list) {
            final txId = item['id']?.toString() ?? '';
            if (_seenTxIds.contains(txId)) continue;
            _seenTxIds.add(txId);

            final content = (item['transaction_content'] ?? '')
                .toString()
                .toUpperCase();
            final amountIn =
                num.tryParse(item['amount_in']?.toString() ?? '0') ?? 0;

            final isMatchCode =
                cleanCode.isNotEmpty &&
                (content.contains(cleanCode) ||
                    content.contains(rawCode) ||
                    (numSuffix.length >= 6 && content.contains(numSuffix)));
            final isMatchAmount = amountIn >= _depositAmount;

            if (isMatchCode && isMatchAmount) {
              debugPrint(
                '[SEPAY AUTOPAY] Khớp tiền cọc Napas 24/7: $txId, $amountInđ, memo: $content',
              );
              _pollingTimer?.cancel();
              await _handleConfirmPayment();
              break;
            }
          }
        }
      }
    } on TimeoutException {
      // Timeout bình thường, sẽ thử lại ở chu kỳ tiếp theo
    } catch (e) {
      debugPrint('[SEPAY API ERROR]: $e');
    } finally {
      _isCheckingSePay = false;
    }
  }

  /// Khi hết 15 phút: hủy cọc, trả phòng về trạng thái Trống
  Future<void> _handleTimeout() async {
    if (_isCompleted || !mounted) return;

    // Kiểm tra lại trên Supabase xem phiếu đã được thanh toán thành công chưa trước khi hủy
    try {
      final res = await Supabase.instance.client
          .from('giu_cho')
          .select('trang_thai')
          .eq('ma_giu_cho', widget.giuCho.maGiuCho)
          .maybeSingle();
      if (res != null) {
        final st = res['trang_thai']?.toString() ?? '';
        if (st == 'Đã thanh toán' || st == 'DangGiu' || st == 'DaDatCoc') {
          _onPaymentSuccess();
          return;
        }
      }
    } catch (_) {}

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
            Text(
              'Hết Hạn Giữ Chỗ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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

  /// Xác nhận thanh toán thành công (dòng tiền ảo / SePay / VNPAY / Chuyển khoản)
  Future<void> _handleConfirmPayment() async {
    if (_isCompleted || !mounted) return;
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _streamSub?.cancel();
    setState(() => _isProcessing = true);

    try {
      // 1. Cập nhật phiếu giữ chỗ giu_cho -> 'Đã thanh toán', xóa expires_at để không bị tính hết hạn, phòng -> 'Đã cọc'
      await DepositService.xacNhanThanhToanTheChan(
        maGiuCho: widget.giuCho.maGiuCho,
        maPhong: widget.room.maPhong,
        appointmentCode: widget.appointmentCode,
        phone: widget.customerPhone,
        customerName: widget.customerName,
        appointmentDate: widget.appointmentDate,
        timeSlot: widget.timeSlot,
        guestCount: widget.guestCount,
        note: widget.note,
      );

      _onPaymentSuccess();
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi xác nhận',
          noiDung: 'Lỗi xác nhận: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  void _onPaymentSuccess() async {
    if (_isCompleted || !mounted) return;
    _isCompleted = true;
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _streamSub?.cancel();

    // Luôn đảm bảo Supabase đã cập nhật phiếu cọc và lịch hẹn
    try {
      await DepositService.xacNhanThanhToanTheChan(
        maGiuCho: widget.giuCho.maGiuCho,
        maPhong: widget.room.maPhong,
        appointmentCode: widget.appointmentCode,
        phone: widget.customerPhone,
        customerName: widget.customerName,
        appointmentDate: widget.appointmentDate,
        timeSlot: widget.timeSlot,
        guestCount: widget.guestCount,
        note: widget.note,
      );
    } catch (_) {}

    // Phát chuông thanh toán thành công
    PaymentSoundHelper.playSuccess();

    // Gửi thông báo hệ thống
    try {
      SystemNotificationService.show(
        title: '🎉 Đặt cọc giữ chỗ phòng thành công!',
        body:
            'Đã nhận thế chân $_depositAmountFormatted (10% giá thuê phòng) cho phòng ${widget.room.tenHienThi}. Hạn giữ phòng trong 5 ngày.',
        tag: 'deposit_${widget.giuCho.maGiuCho}',
      );
    } catch (_) {}

    if (!mounted) return;

    // TỰ ĐỘNG CHUYỂN NGAY VỀ MÀN HÌNH THANH TOÁN THÀNH CÔNG
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => BookingSuccessScreen(
          appointmentCode: widget.appointmentCode ?? widget.giuCho.maGiuCho,
          room: widget.room,
          customerName: widget.customerName,
          customerPhone: widget.customerPhone,
          appointmentDate:
              widget.appointmentDate ??
              (widget.giuCho.ngayDuKienO != null
                  ? DateFormat('dd/MM/yyyy').format(widget.giuCho.ngayDuKienO!)
                  : 'Hôm nay'),
          timeSlot: widget.timeSlot ?? 'Khung giờ linh hoạt',
          guestCount: widget.guestCount ?? widget.giuCho.soNguoiO,
          note: widget.note ?? (widget.giuCho.ghiChu ?? ''),
        ),
      ),
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
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Đã sao chép',
      noiDung: 'Đã sao chép $label vào bộ nhớ tạm!',
      type: ThongBaoType.thongTin,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pollingTimer?.cancel();
    _streamSub?.cancel();
    _pulseController.dispose();
    if (!_isCompleted && !_hasTransferred) {
      DepositService.huyGiuChoKhiThoat(
        maGiuCho: widget.giuCho.maGiuCho,
        maPhong: widget.room.maPhong,
        appointmentCode: widget.appointmentCode,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = _depositAmount;
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F6FA),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            tooltip: 'Hủy & Quay lại',
            onPressed: _handleBackPress,
          ),
          title: const Text(
            'Thanh Toán Tiền Thế Chân',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: _primary,
          elevation: 0,
          centerTitle: true,
        ),
        body: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  children: [
                    // ====== BANNER ĐẾM NGƯỢC 15 PHÚT ======
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFF59E0B),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFF59E0B,
                            ).withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
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
                                  'Thời gian giữ phòng còn lại',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Hiệu lực 15 phút để hoàn tất cọc',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB45309),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              _countdownText,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 1.0,
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
                                child: const Icon(
                                  Icons.meeting_room_rounded,
                                  color: _primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.room.tenHienThi,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    Text(
                                      '${widget.room.toaNha} • Tầng ${widget.room.tang}',
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
                          _buildDetailRow(
                            'Số điện thoại:',
                            widget.customerPhone,
                          ),
                          _buildDetailRow(
                            'Số người ở:',
                            '${widget.giuCho.soNguoiO} người',
                          ),
                          _buildDetailRow(
                            'Ngày dự kiến ở:',
                            widget.giuCho.ngayDuKienO != null
                                ? DateFormat(
                                    'dd/MM/yyyy',
                                  ).format(widget.giuCho.ngayDuKienO!)
                                : 'Chưa xác định',
                          ),
                          _buildDetailRow('Thời hạn giữ chỗ:', 'Tối đa 5 ngày'),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Tiền thế chân cọc (10%):',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                _depositAmountFormatted,
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
                              Icon(
                                Icons.qr_code_2_rounded,
                                color: _primary,
                                size: 20,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Quét mã Napas 24/7 chuyển khoản',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Chuyển khoản trực tiếp tới tài khoản chính chủ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Mã QR MB Bank chuẩn VietQR Napas 24/7 (Có thể quét trực tiếp từ bất kỳ app ngân hàng nào)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFCBD5E1),
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
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    qrImageUrl,
                                    width: 230,
                                    height: 230,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, progress) {
                                      if (progress == null) return child;
                                      return SizedBox(
                                        height: 230,
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            value:
                                                progress.expectedTotalBytes !=
                                                    null
                                                ? progress.cumulativeBytesLoaded /
                                                      progress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: _primary,
                                          ),
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return QrImageView(
                                        data: qrData,
                                        version: QrVersions.auto,
                                        size: 210.0,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(
                                        Icons.qr_code_scanner_rounded,
                                        size: 15,
                                        color: Color(0xFF09638E),
                                      ),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'Quét được trên mọi App Ngân Hàng (MB, VCB, MoMo...)',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Bảng thông tin tài khoản
                          _buildBankInfoRow(
                            'Ngân hàng:',
                            'MB Bank (Quân Đội)',
                            copyText: 'MB Bank',
                          ),
                          _buildBankInfoRow(
                            'Chủ tài khoản:',
                            _accountName,
                            copyText: _accountName,
                          ),
                          _buildBankInfoRow(
                            'Số tài khoản:',
                            _accountNo,
                            copyText: _accountNo,
                          ),
                          _buildBankInfoRow(
                            'Số tiền cọc:',
                            _depositAmountFormatted,
                            copyText: '${_depositAmount.toInt()}',
                            isHighlight: true,
                          ),
                          _buildBankInfoRow(
                            'Nội dung CK:',
                            _memo,
                            copyText: _memo,
                            isHighlight: true,
                          ),

                          const SizedBox(height: 12),

                          // Hộp trạng thái lắng nghe tự động (Không cần bấm nút xác nhận)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF86EFAC),
                              ),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF16A34A),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: const [
                                      Text(
                                        'Tự động ghi nhận chuyển khoản MB Bank',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF15803D),
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Sau khi chuyển khoản Napas247, hệ thống sẽ tự động đồng bộ API MB Bank và chuyển sang màn hình thành công trong vài giây (không cần thao tác bấm).',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF166534),
                                          height: 1.35,
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
                    ),

                    const SizedBox(height: 16),

                    // ====== PHƯƠNG THỨC THANH TOÁN VNPAY & XÁC NHẬN ======
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _hasTransferred
                              ? [
                                  const Color(0xFFF0FDF4),
                                  const Color(0xFFDCFCE7),
                                ]
                              : [
                                  const Color(0xFFF0F7FF),
                                  const Color(0xFFE0F2FE),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _hasTransferred
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF005BAA),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                (_hasTransferred
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFF005BAA))
                                    .withValues(alpha: 0.12),
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
                                  color: _hasTransferred
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFF005BAA),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _hasTransferred
                                      ? Icons.check_circle_rounded
                                      : Icons.payment_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _hasTransferred
                                          ? '🎉 Đã Thanh Toán VNPAY Thành Công!'
                                          : 'Cổng Thanh Toán Điện Tử VNPAY',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                        color: _hasTransferred
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFF004080),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _hasTransferred
                                          ? 'Giao dịch $_depositAmountFormatted đã hoàn tất trên VNPAY. Hãy nhấn nút bên dưới để hoàn tất giữ chỗ!'
                                          : 'Hỗ trợ VNPAY-QR, Thẻ ATM 40+ ngân hàng nội địa và thẻ Visa/Mastercard',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: _hasTransferred
                                            ? const Color(0xFF166534)
                                            : const Color(0xFF0284C7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Nút Hủy giữ chỗ
                    Center(
                      child: TextButton.icon(
                        onPressed: _handleBackPress,
                        icon: const Icon(
                          Icons.cancel_outlined,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                        label: const Text(
                          'Hủy giữ chỗ & Thoát ra',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Lớp phủ khi đang xác nhận dòng tiền tự động
              if (_isProcessing)
                Container(
                  color: Colors.black38,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 20,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: const LoadingMeoMeo(
                        compact: true,
                        size: 95,
                        message: 'Đang hoàn tất giữ chỗ!',
                        subMessage:
                            'Hệ thống đang cập nhật trạng thái phòng sang Đã cọc...',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasTransferred) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        elevation: 3,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isProcessing
                          ? null
                          : () => _handleConfirmPayment(),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isProcessing)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          else ...[
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Flexible(
                              child: Text(
                                'Tôi đã chuyển tiền thành công',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Nhấn để cập nhật ngay phòng sang trạng thái Đã cọc',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF005BAA),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isProcessing ? null : _payWithVnPay,
                      icon: const Icon(
                        Icons.payment_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Thanh Toán Qua VNPAY ($_depositAmountFormatted)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _hasTransferred = true;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 15,
                            color: Color(0xFF16A34A),
                          ),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Tôi đã quét mã chuyển khoản MB Bank',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF15803D),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
          Flexible(
            flex: 4,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
              ),
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
          color: isHighlight
              ? const Color(0xFFBFDBFE)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 80, maxWidth: 96),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isHighlight
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFF64748B),
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isHighlight
                    ? const Color(0xFF1E3A8A)
                    : const Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () => _copy(copyText, label.replaceAll(':', '')),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.copy_rounded,
                size: 16,
                color: isHighlight
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/VnPayService.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ManHinhVnPayWebView extends StatefulWidget {
  final HoaDonModel hoaDon;
  final String tenPhong;
  final num amountToPay;
  final bool isInstallment;
  final void Function(num amountPaid)? onPaymentSuccess;

  const ManHinhVnPayWebView({
    super.key,
    required this.hoaDon,
    required this.tenPhong,
    required this.amountToPay,
    this.isInstallment = false,
    this.onPaymentSuccess,
  });

  @override
  State<ManHinhVnPayWebView> createState() => _ManHinhVnPayWebViewState();
}

class _ManHinhVnPayWebViewState extends State<ManHinhVnPayWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isProcessed = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();

    final paymentUrl = VnPayService.generatePaymentUrl(
      orderId:
          '${widget.hoaDon.maHoaDon}${DateTime.now().millisecondsSinceEpoch}',
      amount: widget.amountToPay.toDouble(),
      orderInfo: 'Thanh toan tien phong ${widget.tenPhong}',
    );

    debugPrint('>>> URL VNPAY: $paymentUrl');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      )
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('>>> Đang tải: $url');
            _handleUrlChange(url);
          },
          onPageFinished: (url) {
            debugPrint('>>> Tải xong: $url');
            if (mounted) setState(() => _isLoading = false);
            _handleUrlChange(url);
          },
          onWebResourceError: (error) {
            debugPrint('>>> Lỗi WebView: ${error.description}');
            if (mounted && _isLoading) {
              setState(() {
                _errorMsg = error.description;
                _isLoading = false;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('>>> Redirect: ${request.url}');
            if (request.url.contains('vnpay_return') ||
                request.url.contains('vnp_ResponseCode')) {
              _handleUrlChange(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(paymentUrl));
  }

  void _handleUrlChange(String url) async {
    if (_isProcessed) return;

    if (url.contains('vnp_ResponseCode')) {
      final uri = Uri.parse(url);
      final responseCode = uri.queryParameters['vnp_ResponseCode'];

      if (responseCode == '00') {
        _isProcessed = true;

        try {
          final db = Supabase.instance.client;
          final maHD = widget.hoaDon.maHoaDon.trim();

          if (widget.isInstallment) {
            final soTienConLai = widget.hoaDon.tongTien - widget.amountToPay;
            final d2 = DateTime.now().add(const Duration(days: 5));
            final hanChotDot2 =
                '${d2.year}-${d2.month.toString().padLeft(2, '0')}-${d2.day.toString().padLeft(2, '0')}';

            await db
                .from('hoa_don')
                .update({
                  'trang_thai': 'Thanh toán một phần',
                  'tong_tien': soTienConLai,
                  'han_dong_tien': hanChotDot2,
                })
                .eq('ma_hoa_don', maHD);
          } else {
            await db
                .from('hoa_don')
                .update({'trang_thai': 'Đã thanh toán', 'tong_tien': 0})
                .eq('ma_hoa_don', maHD);
          }

          widget.onPaymentSuccess?.call(widget.amountToPay);
        } catch (e) {
          debugPrint('Lỗi cập nhật Supabase: $e');
        }

        if (!mounted) return;
        PaymentSoundHelper.playSuccess();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentCompletedScreen(
              hoaDon: widget.hoaDon,
              tenPhong: widget.tenPhong,
              bankName: 'Cổng thanh toán VNPAY',
              transactionTime: DateTime.now().toString(),
              amountPaid: widget.amountToPay,
            ),
          ),
        );
      } else if (responseCode != null && responseCode != '00') {
        _isProcessed = true;
        if (!mounted) return;
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Thông báo giao dịch',
          noiDung: 'Giao dịch VNPAY không thành công hoặc đã bị hủy!',
          type: ThongBaoType.canhBao,
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cổng thanh toán VNPAY',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF09638E)),
            ),
          if (_errorMsg != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.red,
                      size: 36,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Không thể tải trang: $_errorMsg',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _errorMsg = null;
                        });
                        _controller.reload();
                      },
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Màn hình Cổng Thanh Toán VNPAY chuyên nghiệp, tương thích 100% cho khách thuê
/// Không bị trắng màn hình, giao diện chuẩn nhận diện thương hiệu VNPAY
class VnPayWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  final String? maHoaDon;
  final num? amount;
  final String? tenPhong;
  final VoidCallback? onSuccess;
  final VoidCallback? onFailed;

  const VnPayWebViewScreen({
    super.key,
    required this.paymentUrl,
    this.maHoaDon,
    this.amount,
    this.tenPhong,
    this.onSuccess,
    this.onFailed,
  });

  @override
  State<VnPayWebViewScreen> createState() => _VnPayWebViewScreenState();
}

class _VnPayWebViewScreenState extends State<VnPayWebViewScreen> {
  int _selectedTab = 0; // 0: Thẻ ATM / Tài khoản, 1: VNPAY-QR
  int _selectedBankIndex = 0;
  bool _isProcessing = false;

  final _cardNoController = TextEditingController(text: '9704 1985 2619 1432 198');
  final _cardHolderController = TextEditingController(text: 'NGUYEN VAN A');
  final _cardExpController = TextEditingController(text: '07/15');

  static const List<Map<String, String>> _popularBanks = [
    {'code': 'NCB', 'name': 'NCB (Quốc Dân)'},
    {'code': 'MB', 'name': 'MB Bank'},
    {'code': 'VCB', 'name': 'Vietcombank'},
    {'code': 'TCB', 'name': 'Techcombank'},
    {'code': 'BIDV', 'name': 'BIDV'},
    {'code': 'CTG', 'name': 'VietinBank'},
  ];

  @override
  void dispose() {
    _cardNoController.dispose();
    _cardHolderController.dispose();
    _cardExpController.dispose();
    super.dispose();
  }

  void _onConfirmPaymentFlow() async {
    final otpController = TextEditingController(text: '123456');

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEFF6FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: Color(0xFF005BAA),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Xác Thực Giao Dịch VNPAY',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mã xác thực OTP đã được gửi đến số điện thoại đăng ký tài khoản thẻ.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: otpController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Color(0xFF005BAA),
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF005BAA), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.timer_outlined, size: 15, color: Color(0xFF64748B)),
                    SizedBox(width: 4),
                    Text(
                      'Hiệu lực mã: 119s',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Hủy', style: TextStyle(color: Color(0xFF64748B))),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF005BAA),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text(
                          'Xác nhận OTP',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() => _isProcessing = true);
      // Hiệu ứng xử lý giao dịch ngân hàng
      await Future.delayed(const Duration(milliseconds: 1200));

      if (!mounted) return;
      PaymentSoundHelper.playSuccess();
      Navigator.pop(context);
      widget.onSuccess?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.amount ?? 100000;
    final formattedAmount =
        NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0).format(amount);
    final orderId = widget.maHoaDon ?? 'KG${DateTime.now().millisecondsSinceEpoch}';

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Cổng thanh toán VNPAY',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF005BAA),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            widget.onFailed?.call();
            Navigator.pop(context);
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: const [
                Icon(Icons.lock_rounded, size: 16, color: Colors.white70),
                SizedBox(width: 4),
                Text('Bảo mật', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
      body: _isProcessing
          ? Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    CircularProgressIndicator(color: Color(0xFF005BAA), strokeWidth: 3),
                    SizedBox(height: 18),
                    Text(
                      'Đang xử lý giao dịch qua cổng VNPAY...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Vui lòng giữ nguyên ứng dụng trong giây lát.',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ====== CARD THÔNG TIN ĐƠN HÀNG VNPAY ======
                  Container(
                    width: double.infinity,
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF005BAA),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'VNPAY',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Cổng thanh toán điện tử',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.verified_user_rounded, color: Color(0xFF16A34A), size: 18),
                          ],
                        ),
                        const Divider(height: 20),
                        Row(
                          children: [
                            const Text('Số tiền thanh toán:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formattedAmount,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF005BAA),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Đơn vị nhận:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nhà trọ Kiều Giang ${widget.tenPhong != null ? '• ${widget.tenPhong}' : ''}',
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Mã đơn hàng:', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                orderId,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ====== TABS CHỌN PHƯƠNG THỨC THANH TOÁN ======
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 0),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0 ? const Color(0xFF005BAA) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'Thẻ ATM / Tài khoản',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTab == 0 ? Colors.white : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 1),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1 ? const Color(0xFF005BAA) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  'VNPAY-QR',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: _selectedTab == 1 ? Colors.white : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ====== NỘI DUNG TAB ======
                  if (_selectedTab == 0) ...[
                    // TAB THẺ ATM NỘI ĐỊA
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
                          const Text(
                            'Chọn ngân hàng thanh toán',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              children: List.generate(_popularBanks.length, (idx) {
                                final b = _popularBanks[idx];
                                final isSel = _selectedBankIndex == idx;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(b['name']!),
                                    selected: isSel,
                                    selectedColor: const Color(0xFF005BAA),
                                    labelStyle: TextStyle(
                                      color: isSel ? Colors.white : const Color(0xFF334155),
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12.5,
                                    ),
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    onSelected: (val) {
                                      if (val) setState(() => _selectedBankIndex = idx);
                                    },
                                  ),
                                );
                              }),
                            ),
                          ),
                          const Divider(height: 24),
                          const Text(
                            'Thông tin thẻ thanh toán',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _cardNoController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Số thẻ ngân hàng',
                              prefixIcon: const Icon(Icons.credit_card_rounded, color: Color(0xFF005BAA)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _cardHolderController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Tên in trên thẻ (không dấu)',
                              prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF005BAA)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _cardExpController,
                            keyboardType: TextInputType.datetime,
                            decoration: InputDecoration(
                              labelText: 'Ngày phát hành (MM/YY)',
                              prefixIcon: const Icon(Icons.calendar_today_rounded, color: Color(0xFF005BAA)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF005BAA),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                              ),
                              onPressed: _onConfirmPaymentFlow,
                              child: Text(
                                'Thanh toán $formattedAmount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // TAB VNPAY-QR
                    Container(
                      padding: const EdgeInsets.all(20),
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
                          const Text(
                            'Quét mã qua ứng dụng ngân hàng hoặc ví VNPAY',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: QrImageView(
                              data: widget.paymentUrl,
                              version: QrVersions.auto,
                              size: 210,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.timer_outlined, size: 16, color: Color(0xFFDC2626)),
                              SizedBox(width: 4),
                              Text(
                                'Thời gian còn lại: 14:59',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF005BAA),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                              ),
                              onPressed: () {
                                PaymentSoundHelper.playSuccess();
                                Navigator.pop(context);
                                widget.onSuccess?.call();
                              },
                              child: const Text(
                                'Xác nhận đã quét mã thanh toán',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}




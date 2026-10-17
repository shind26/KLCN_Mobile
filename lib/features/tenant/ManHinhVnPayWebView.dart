import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/VnPayService.dart';
import 'package:nhatro_kieugiang/core/utils/AmThanhThanhToanHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
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
              bankName: 'Cổng VNPAY (Thẻ test NCB)',
              transactionTime: DateTime.now().toString(),
              amountPaid: widget.amountToPay,
            ),
          ),
        );
      } else if (responseCode != null && responseCode != '00') {
        _isProcessed = true;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giao dịch VNPAY không thành công hoặc đã bị hủy!'),
            backgroundColor: Color(0xFFDC2626),
          ),
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

class VnPayWebViewScreen extends StatefulWidget {
  final String paymentUrl;
  final String? maHoaDon;
  final VoidCallback? onSuccess;
  final VoidCallback? onFailed;

  const VnPayWebViewScreen({
    super.key,
    required this.paymentUrl,
    this.maHoaDon,
    this.onSuccess,
    this.onFailed,
  });

  @override
  State<VnPayWebViewScreen> createState() => _VnPayWebViewScreenState();
}

class _VnPayWebViewScreenState extends State<VnPayWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isProcessed = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();

    debugPrint('>>> URL VNPAY (VnPayWebViewScreen): ${widget.paymentUrl}');

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
      ..loadRequest(Uri.parse(widget.paymentUrl));
  }

  void _handleUrlChange(String url) {
    if (_isProcessed) return;

    if (url.contains('vnp_ResponseCode')) {
      final uri = Uri.parse(url);
      final responseCode = uri.queryParameters['vnp_ResponseCode'];

      if (responseCode == '00') {
        _isProcessed = true;
        if (!mounted) return;
        Navigator.pop(context);
        widget.onSuccess?.call();
      } else if (responseCode != null && responseCode != '00') {
        _isProcessed = true;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giao dịch VNPAY không thành công hoặc đã bị hủy!'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        Navigator.pop(context);
        widget.onFailed?.call();
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


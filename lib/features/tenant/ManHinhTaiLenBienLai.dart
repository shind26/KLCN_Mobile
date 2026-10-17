import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bước 2/3: Tải ảnh xác nhận biên lai / giao dịch
/// Hỗ trợ chọn ảnh thật từ Camera / Thư viện thiết bị + RÀNG BUỘC (Validation) chặt chẽ.
class UploadReceiptScreen extends StatefulWidget {
  final HoaDonModel hoaDon;
  final String tenPhong;

  const UploadReceiptScreen({
    super.key,
    required this.hoaDon,
    required this.tenPhong,
  });

  @override
  State<UploadReceiptScreen> createState() => _UploadReceiptScreenState();
}

class _UploadReceiptScreenState extends State<UploadReceiptScreen> {
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  // ─── Form states ───
  String _selectedBank = 'Techcombank (Ngân hàng TMCP Kỹ Thương)';
  final List<String> _bankOptions = [
    'Techcombank (Ngân hàng TMCP Kỹ Thương)',
    'MB Bank (Ngân hàng Quân Đội)',
    'Vietcombank (Ngân hàng Ngoại thương)',
    'ACB (Ngân hàng Á Châu)',
    'VPBank (Ngân hàng Việt Nam Thịnh Vượng)',
    'BIDV (Ngân hàng Đầu tư & Phát triển)',
    'Agribank (Ngân hàng Nông nghiệp)',
    'VietinBank (Ngân hàng Công thương)',
    'TPBank (Ngân hàng Tiên Phong)',
    'Khác / Ví điện tử (Momo, ZaloPay)',
  ];

  late DateTime _selectedDateTime;
  final TextEditingController _noteController = TextEditingController();

  // ─── Image states (Tải ảnh thật) ───
  final ImagePicker _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageFileName;
  String? _imageFileSizeStr;

  // ─── Ràng buộc & Validation states ───
  bool _showImageError = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDateTime = DateTime.now();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _formattedDateTime {
    final d = _selectedDateTime;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} - '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ─── Modal chọn nguồn tải ảnh ───
  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Tải Ảnh Biên Lai Giao Dịch',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Vui lòng cung cấp ảnh chụp màn hình chuyển khoản rõ nét',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: _primary,
                  ),
                ),
                title: const Text(
                  'Chọn ảnh từ Thư viện / Thiết bị',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Hỗ trợ định dạng JPG, PNG (tối đa 10MB)',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Color(0xFF16A34A),
                  ),
                ),
                title: const Text(
                  'Chụp ảnh trực tiếp bằng Camera',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Chụp biên lai giấy hoặc màn hình máy tính',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Hàm chọn ảnh thật qua image_picker ───
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (file != null) {
        final bytes = await file.readAsBytes();
        final sizeKb = bytes.lengthInBytes / 1024;
        final sizeStr = sizeKb > 1024
            ? '${(sizeKb / 1024).toStringAsFixed(1)} MB'
            : '${sizeKb.toStringAsFixed(0)} KB';

        // Ràng buộc dung lượng tối đa 10MB
        if (sizeKb > 10 * 1024) {
          if (!mounted) return;
          _showWarningToast(
            'Dung lượng ảnh vượt quá 10MB. Vui lòng chọn ảnh nhẹ hơn!',
          );
          return;
        }

        setState(() {
          _imageBytes = bytes;
          _imageFileName = file.name.isNotEmpty
              ? file.name
              : 'bien_lai_chuyen_khoan.jpg';
          _imageFileSizeStr = sizeStr;
          _showImageError = false; // Xóa báo lỗi
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đã tải lên: $_imageFileName ($sizeStr)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[UploadReceipt] Lỗi chọn ảnh: $e');
      _showWarningToast('Không thể mở ảnh. Vui lòng cấp quyền truy cập ảnh!');
    }
  }

  // ─── Ràng buộc: Chọn thời gian thực hiện giao dịch ───
  Future<void> _selectTransactionDateTime() async {
    final now = DateTime.now();
    // 1. Chọn ngày (Ràng buộc: Không được chọn ngày trong tương lai)
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
      helpText: 'CHỌN NGÀY CHUYỂN TIỀN',
      cancelText: 'HỦY',
      confirmText: 'TIẾP TỤC',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: Colors.white,
            onSurface: _textDark,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null || !mounted) return;

    // 2. Chọn giờ
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
      helpText: 'CHỌN GIỜ GIAO DỊCH',
      cancelText: 'HỦY',
      confirmText: 'XÁC NHẬN',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: Colors.white,
            onSurface: _textDark,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedTime == null || !mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    // Ràng buộc: Không được chọn thời gian tương lai
    if (newDateTime.isAfter(DateTime.now())) {
      _showWarningToast(
        'Ràng buộc: Thời gian giao dịch không thể ở tương lai!',
      );
      return;
    }

    setState(() {
      _selectedDateTime = newDateTime;
    });
  }

  void _showWarningToast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFE11D48),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Submit Form với RÀNG BUỘC KIỂM TRA TOÀN DIỆN ───
  Future<void> _submitReceipt() async {
    // 🔴 RÀNG BUỘC 1: Bắt buộc phải có ảnh biên lai
    if (_imageBytes == null) {
      setState(() => _showImageError = true);
      _showWarningToast(
        'Ràng buộc: Bạn bắt buộc phải tải lên ảnh chụp màn hình biên lai để BQL đối soát!',
      );
      return;
    }

    // 🔴 RÀNG BUỘC 2: Ngân hàng không được để trống
    if (_selectedBank.trim().isEmpty) {
      _showWarningToast(
        'Ràng buộc: Vui lòng chọn ngân hàng bạn đã dùng để chuyển tiền!',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Cập nhật trạng thái hóa đơn sang "Chờ duyệt" trong Supabase để Admin thấy
      await Supabase.instance.client
          .from('hoa_don')
          .update({'trang_thai': 'Chờ duyệt'})
          .eq('ma_hoa_don', widget.hoaDon.maHoaDon);
    } catch (e) {
      debugPrint('Supabase cập nhật trạng thái hóa đơn: $e');
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentCompletedScreen(
          hoaDon: widget.hoaDon,
          tenPhong: widget.tenPhong,
          bankName: _selectedBank,
          transactionTime: _formattedDateTime,
          imageBytes: _imageBytes,
          imageFileName: _imageFileName ?? 'bien_lai_chuyen_khoan.jpg',
          imageFileSizeStr: _imageFileSizeStr ?? '1.8 MB',
          note: _noteController.text,
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
                    _buildStepIndicator(),
                    const SizedBox(height: 14),
                    _buildInvoiceMiniCard(),
                    const SizedBox(height: 14),
                    _buildUploadImageCard(),
                    const SizedBox(height: 14),
                    _buildReconciliationCard(),
                    const SizedBox(height: 14),
                    _buildQuickProcessBanner(),
                    const SizedBox(height: 16),
                    _buildSubmitButton(),
                    const SizedBox(height: 12),
                    _buildHotlineText(),
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

  // ─── 1. TOP APP BAR ───
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
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
                    'Trang chủ',
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
                  onTap: () => Navigator.pop(context),
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
                        style: TextStyle(
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
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: _primary, size: 6),
                      SizedBox(width: 5),
                      Text(
                        'Bước 2/3',
                        style: TextStyle(
                          fontSize: 11,
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

  // ─── 2. STEP INDICATOR ───
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStepItem(1, 'Quét VietQR', isDone: true, isActive: false),
          _buildStepDivider(isActive: true),
          _buildStepItem(2, 'Tải biên lai', isDone: false, isActive: true),
          _buildStepDivider(isActive: false),
          _buildStepItem(3, 'Hoàn tất', isDone: false, isActive: false),
        ],
      ),
    );
  }

  Widget _buildStepItem(
    int step,
    String title, {
    required bool isDone,
    required bool isActive,
  }) {
    Color bg;
    Widget iconWidget;
    if (isDone) {
      bg = const Color(0xFFBAE6FD);
      iconWidget = const Icon(Icons.check_rounded, color: _primary, size: 14);
    } else if (isActive) {
      bg = _primary;
      iconWidget = Text(
        '$step',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    } else {
      bg = const Color(0xFFE2E8F0);
      iconWidget = Text(
        '$step',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: iconWidget,
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive
                ? _primary
                : (isDone ? _primaryDark : const Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildStepDivider({required bool isActive}) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: isActive ? _primary : const Color(0xFFE2E8F0),
      ),
    );
  }

  // ─── 3. INVOICE MINI SUMMARY CARD ───
  Widget _buildInvoiceMiniCard() {
    final hd = widget.hoaDon;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE).withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Hóa đơn #${hd.maHoaDon}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0369A1),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.verified_rounded,
                color: Color(0xFF0284C7),
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                FormatUtils.currency(hd.tongTien.toDouble()),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0369A1),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'đ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0369A1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _buildMiniRow('Tài khoản nhận:', 'MB Bank • 0865109632'),
                const SizedBox(height: 6),
                _buildMiniRow('Chủ thụ hưởng:', 'HO THI MY DUYEN'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text(
                      'Cú pháp chuyển:',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            hd.noiDungChuyenKhoan,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: _primary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  // ─── 4. UPLOAD IMAGE CARD (CÓ RÀNG BUỘC & PREVIEW THỰC TẾ) ───
  Widget _buildUploadImageCard() {
    final hasImage = _imageBytes != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: _showImageError
            ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: _showImageError
                ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.04),
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
              Icon(
                Icons.phone_iphone_rounded,
                color: _showImageError ? const Color(0xFFEF4444) : _primary,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Hình ảnh biên lai / giao dịch ',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                    children: [
                      TextSpan(
                        text: '*',
                        style: TextStyle(color: Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3.5,
                ),
                decoration: BoxDecoration(
                  color: hasImage
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  hasImage ? '✓ Đã đính kèm ảnh' : 'Bắt buộc',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: hasImage
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dashed border upload container
          InkWell(
            onTap: _showImageSourceActionSheet,
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: hasImage
                    ? const Color(0xFFF0FDF4)
                    : (_showImageError
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFF8FAFC)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _showImageError
                      ? const Color(0xFFEF4444)
                      : (hasImage
                            ? const Color(0xFF22C55E)
                            : const Color(0xFF38BDF8)),
                  width: _showImageError ? 2 : 1.5,
                ),
              ),
              child: hasImage
                  ? Row(
                      children: [
                        // Actual Image Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 60,
                            height: 60,
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _imageFileName ?? 'bien_lai_chuyen_khoan.jpg',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_imageFileSizeStr ?? "1.8 MB"} • Đã sẵn sàng gửi duyệt',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Nhấn vào đây để đổi ảnh khác',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: _primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _imageBytes = null;
                              _imageFileName = null;
                              _imageFileSizeStr = null;
                            });
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 22,
                          ),
                          tooltip: 'Xóa ảnh',
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: _showImageError
                                ? const Color(0xFFFEE2E2)
                                : const Color(0xFFE0F2FE),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.camera_alt_outlined,
                            color: _showImageError
                                ? const Color(0xFFEF4444)
                                : _primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '+ Thêm hình ảnh biên lai',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _showImageError
                                ? const Color(0xFFDC2626)
                                : _primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tải lên ảnh chụp màn hình chuyển khoản hoặc biên lai giao dịch',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // Thông báo ràng buộc đỏ nếu chưa đính kèm ảnh
          if (_showImageError) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFEF4444),
                  size: 14,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Ràng buộc: Bắt buộc đính kèm ảnh chụp biên lai trước khi gửi duyệt!',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── 5. RECONCILIATION CARD ───
  Widget _buildReconciliationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
              Icon(Icons.fact_check_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Thông Tin Đối Soát',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Ngân hàng đã chuyển tiền Dropdown
          const Text(
            'Ngân hàng đã chuyển tiền',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBank,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF64748B),
                ),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textDark,
                ),
                items: _bankOptions.map((bank) {
                  return DropdownMenuItem<String>(
                    value: bank,
                    child: Text(bank, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBank = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Thời gian thực hiện giao dịch (Chọn ngày & giờ)
          Row(
            children: [
              const Text(
                'Thời gian thực hiện giao dịch',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              InkWell(
                onTap: _selectTransactionDateTime,
                child: const Text(
                  'Thay đổi',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _selectTransactionDateTime,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCEAFE)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    color: _primary,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formattedDateTime,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.edit_calendar_rounded,
                    color: _primary,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ghi chú cho BQL
          Row(
            children: [
              const Text(
                'Ghi chú cho BQL',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const Spacer(),
              Text(
                'Không bắt buộc',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText:
                  'Ví dụ: Em chuyển từ tài khoản phụ huynh tên Trần Văn...',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. QUICK PROCESS BANNER ───
  Widget _buildQuickProcessBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 6),
              Text(
                'Quy trình xử lý nhanh',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: _primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hệ thống tự động đối soát qua biến động tài khoản. BQL sẽ xác nhận trong vòng 5 - 15 phút. Trong thời gian chờ, bạn sẽ không bị hệ thống nhắc nợ.',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF334155),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFF64748B),
                size: 12,
              ),
              SizedBox(width: 4),
              Text(
                'Bảo mật 100%',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
              SizedBox(width: 12),
              Text(
                '•',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
              SizedBox(width: 12),
              Icon(
                Icons.support_agent_rounded,
                color: Color(0xFF64748B),
                size: 12,
              ),
              SizedBox(width: 4),
              Text(
                'Hỗ trợ tức thì',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 7. SUBMIT BUTTON ───
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submitReceipt,
        icon: _isSubmitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.play_arrow_rounded, size: 20),
        label: Text(
          _isSubmitting ? 'Đang gửi biên lai...' : 'Gửi Biên Lai Duyệt Ngay',
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _imageBytes == null
              ? Colors.grey.shade400
              : _primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildHotlineText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Gặp sự cố thanh toán? ',
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const Icon(Icons.support_agent_rounded, color: _primary, size: 14),
        const SizedBox(width: 4),
        const Text(
          'Liên hệ Ban Quản Lý',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: _primary,
          ),
        ),
      ],
    );
  }

  // ─── 8. BOTTOM NAVIGATION BAR ───
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
          if (index != 2) Navigator.pop(context);
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
            icon: (widget.hoaDon.trangThai != 'Đã thanh toán' && widget.hoaDon.tongTien > 0)
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
}

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/DichVuQuetCccd.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhCapNhatThongTinCaNhan extends StatefulWidget {
  final UserModel user;
  final String maKhach;
  final String maHopDong;
  final String maPhong;
  final Map<String, dynamic> khachThueData;

  const ManHinhCapNhatThongTinCaNhan({
    super.key,
    required this.user,
    required this.maKhach,
    required this.maHopDong,
    required this.maPhong,
    required this.khachThueData,
  });

  @override
  State<ManHinhCapNhatThongTinCaNhan> createState() =>
      _ManHinhCapNhatThongTinCaNhanState();
}

class _ThongTinXe {
  String loaiXe;
  final TextEditingController bienSoController;
  final TextEditingController ghiChuController;

  _ThongTinXe({
    this.loaiXe = 'Xe tay ga',
    String bienSo = '',
    String ghiChu = '',
  })  : bienSoController = TextEditingController(text: bienSo),
        ghiChuController = TextEditingController(text: ghiChu);

  void dispose() {
    bienSoController.dispose();
    ghiChuController.dispose();
  }
}

class _ManHinhCapNhatThongTinCaNhanState
    extends State<ManHinhCapNhatThongTinCaNhan> {
  static const _primary = Color(0xFF09638E);

  // Controllers thông tin cá nhân
  late TextEditingController _hoTenController;
  late TextEditingController _soDtController;
  final _cccdController = TextEditingController();
  final _diaChiController = TextEditingController();
  final _nguoiLienHeController = TextEditingController();
  final _noiCapController =
      TextEditingController(text: 'Cục Cảnh sát QLHC về TTXH');

  String _gioiTinh = 'Nam';
  DateTime? _ngaySinh;
  DateTime? _ngayCapCccd;

  // Ảnh CCCD
  final _picker = ImagePicker();
  Uint8List? _bytesMatTruoc;
  Uint8List? _bytesMatSau;
  String? _urlMatTruoc;
  String? _urlMatSau;
  bool _isScanningAi = false;

  // Phương tiện xe
  bool _coPhuongTien = true;
  final List<_ThongTinXe> _danhSachXe = [];

  // Trạng thái lưu
  bool _isSubmitting = false;
  String? _submitProgressText;

  @override
  void initState() {
    super.initState();
    final kt = widget.khachThueData;
    _hoTenController = TextEditingController(
      text: kt['ho_ten_khach']?.toString() ?? widget.user.tenHienThi,
    );
    _soDtController = TextEditingController(
      text: kt['so_dt']?.toString() ?? widget.user.tenDangNhap,
    );
    _cccdController.text = kt['cccd']?.toString() ?? '';
    _diaChiController.text = kt['dia_chi_thuong_tru']?.toString() ?? '';
    _gioiTinh = (kt['gioi_tinh']?.toString() == 'Nữ') ? 'Nữ' : 'Nam';
    _nguoiLienHeController.text =
        kt['nguoi_lien_he_khan_cap']?.toString() ?? '';

    if (kt['ngay_sinh'] != null) {
      try {
        _ngaySinh = DateTime.parse(kt['ngay_sinh'].toString());
      } catch (_) {}
    }
    if (kt['ngay_cap_cccd'] != null) {
      try {
        _ngayCapCccd = DateTime.parse(kt['ngay_cap_cccd'].toString());
      } catch (_) {}
    }
    if (kt['noi_cap_cccd'] != null &&
        kt['noi_cap_cccd'].toString().trim().isNotEmpty) {
      _noiCapController.text = kt['noi_cap_cccd'].toString();
    }
    _urlMatTruoc = kt['anh_cccd_mat_truoc']?.toString();
    _urlMatSau = kt['anh_cccd_mat_sau']?.toString();

    // Mặc định khởi tạo 1 xe
    _danhSachXe.add(_ThongTinXe());
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _soDtController.dispose();
    _cccdController.dispose();
    _diaChiController.dispose();
    _nguoiLienHeController.dispose();
    _noiCapController.dispose();
    for (var xe in _danhSachXe) {
      xe.dispose();
    }
    super.dispose();
  }

  // ── XỬ LÝ CHỌN ẢNH & QUÉT AI CCCD ──
  Future<void> _chonAnhCccd(ImageSource source, bool isMatTruoc) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      setState(() {
        if (isMatTruoc) {
          _bytesMatTruoc = bytes;
        } else {
          _bytesMatSau = bytes;
        }
      });

      // Nếu là mặt trước: Kích hoạt quét AI OCR tự động trích xuất thông tin
      if (isMatTruoc) {
        _thucHienQuetAiCccd(bytes);
      }
    } catch (e) {
      debugPrint('Lỗi chọn ảnh CCCD: $e');
    }
  }

  Future<void> _thucHienQuetAiCccd(Uint8List bytes) async {
    setState(() => _isScanningAi = true);

    try {
      final result = await DichVuQuetCccd.quetAnhCccdBytes(bytes);

      if (!mounted) return;
      setState(() => _isScanningAi = false);

      if (result != null && result.hopLe) {
        // Tự động điền các trường bóc tách được
        if (result.soCccd.isNotEmpty) {
          _cccdController.text = result.soCccd;
        }
        if (result.hoTen.isNotEmpty) {
          _hoTenController.text = result.hoTen;
        }
        if (result.gioiTinh != null && result.gioiTinh!.isNotEmpty) {
          _gioiTinh = result.gioiTinh!;
        }
        if (result.diaChiThuongTru != null &&
            result.diaChiThuongTru!.isNotEmpty) {
          _diaChiController.text = result.diaChiThuongTru!;
        }
        if (result.ngaySinh != null && result.ngaySinh!.isNotEmpty) {
          try {
            final parts = result.ngaySinh!.split('/');
            if (parts.length == 3) {
              _ngaySinh = DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              );
            }
          } catch (_) {}
        }

        _showAiSuccessDialog(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể trích xuất tự động từ ảnh. Bạn vui lòng kiểm tra và điền thông tin bên dưới nhé!',
            ),
            backgroundColor: Color(0xFFD97706),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isScanningAi = false);
      debugPrint('Lỗi quét AI CCCD: $e');
    }
  }

  void _showAiSuccessDialog(KetQuaQuetCccd res) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: _primary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'AI Quét CCCD Thành Công',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Đã tự động trích xuất các thông tin sau từ ảnh CCCD:',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _buildDialogRow('Họ và tên:', res.hoTen.isNotEmpty ? res.hoTen : 'Chưa nhận diện'),
            _buildDialogRow('Số CCCD:', res.soCccd.isNotEmpty ? res.soCccd : 'Chưa nhận diện'),
            if (res.gioiTinh != null) _buildDialogRow('Giới tính:', res.gioiTinh!),
            if (res.ngaySinh != null) _buildDialogRow('Ngày sinh:', res.ngaySinh!),
            if (res.diaChiThuongTru != null)
              _buildDialogRow('Thường trú:', res.diaChiThuongTru!),
            const SizedBox(height: 8),
            const Text(
              'Bạn có thể rà soát và chỉnh sửa lại các thông tin nếu cần.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: _primary),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Đã hiểu & Tiếp tục'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── HOÀN TẤT LƯU THÔNG TIN CÁ NHÂN & PHƯƠNG TIỆN ──
  Future<void> _luuThongTinCaNhan() async {
    final hoTen = _hoTenController.text.trim();
    final cccd = _cccdController.text.trim();
    final diaChi = _diaChiController.text.trim();

    if (hoTen.isEmpty || cccd.isEmpty || diaChi.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng điền đầy đủ Họ tên, Số CCCD và Địa chỉ thường trú!'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (cccd.length != 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số CCCD phải có đúng 12 chữ số hợp lệ!'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitProgressText = 'Đang tải ảnh CCCD lên máy chủ...';
    });

    try {
      final db = Supabase.instance.client;

      // 1. TẢI ẢNH CCCD LÊN STORAGE NẾU CÓ
      String? uploadedUrlMatTruoc = _urlMatTruoc;
      String? uploadedUrlMatSau = _urlMatSau;

      if (_bytesMatTruoc != null) {
        try {
          final path =
              'cccd/${widget.maKhach}_truoc_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await db.storage.from('contracts').uploadBinary(
                path,
                _bytesMatTruoc!,
                fileOptions:
                    const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          uploadedUrlMatTruoc = db.storage.from('contracts').getPublicUrl(path);
        } catch (eStorage) {
          debugPrint('Storage upload mặt trước fallback base64: $eStorage');
          uploadedUrlMatTruoc = 'data:image/jpeg;base64,${base64Encode(_bytesMatTruoc!)}';
        }
      }

      if (_bytesMatSau != null) {
        try {
          final path =
              'cccd/${widget.maKhach}_sau_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await db.storage.from('contracts').uploadBinary(
                path,
                _bytesMatSau!,
                fileOptions:
                    const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          uploadedUrlMatSau = db.storage.from('contracts').getPublicUrl(path);
        } catch (eStorage) {
          debugPrint('Storage upload mặt sau fallback base64: $eStorage');
          uploadedUrlMatSau = 'data:image/jpeg;base64,${base64Encode(_bytesMatSau!)}';
        }
      }

      // 2. CẬP NHẬT BẢNG khach_thue
      setState(() => _submitProgressText = 'Cập nhật hồ sơ cư dân...');
      final Map<String, dynamic> updateKt = {
        'ho_ten_khach': hoTen,
        'cccd': cccd,
        'gioi_tinh': _gioiTinh,
        'dia_chi_thuong_tru': diaChi,
        'noi_cap_cccd': _noiCapController.text.trim(),
        'trang_thai_ekyc': 'DaXacThuc',
        'nguoi_lien_he_khan_cap': _nguoiLienHeController.text.trim(),
      };
      if (_ngaySinh != null) {
        updateKt['ngay_sinh'] = DateFormat('yyyy-MM-dd').format(_ngaySinh!);
      }
      if (_ngayCapCccd != null) {
        updateKt['ngay_cap_cccd'] =
            DateFormat('yyyy-MM-dd').format(_ngayCapCccd!);
      }
      if (uploadedUrlMatTruoc != null) {
        updateKt['anh_cccd_mat_truoc'] = uploadedUrlMatTruoc;
      }
      if (uploadedUrlMatSau != null) {
        updateKt['anh_cccd_mat_sau'] = uploadedUrlMatSau;
      }

      await db.from('khach_thue').update(updateKt).eq('ma_khach', widget.maKhach);

      // Cập nhật tên trong tài khoản
      await db.from('tai_khoan').update({
        'ho_ten': hoTen,
      }).eq('ma_tai_khoan', widget.user.maTaiKhoan);

      // 3. ĐĂNG KÝ PHƯƠNG TIỆN XE (NẾU CÓ)
      if (_coPhuongTien && _danhSachXe.isNotEmpty) {
        setState(() => _submitProgressText = 'Đăng ký phương tiện xe...');
        for (final xe in _danhSachXe) {
          final bienSo = xe.bienSoController.text.trim();
          if (bienSo.isNotEmpty) {
            final maPt = 'PT${Random().nextInt(900000) + 100000}';
            await db.from('phuong_tien').upsert({
              'ma_phuong_tien': maPt,
              'ma_khach': widget.maKhach,
              'ma_phong': widget.maPhong,
              'loai_xe': xe.loaiXe,
              'bien_so_xe': bienSo,
              'ma_the_xe': null,
              'trang_thai': 'Hoạt động',
              'ngay_dang_ky': DateTime.now().toIso8601String(),
            });
          }
        }
      }

      // Cập nhật session user trong app
      final updatedUser = widget.user.copyWith(hoTen: hoTen);
      await AuthService.updateCurrentUser(updatedUser);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Hiển thị dialog hoàn tất và chuyển thẳng vào Trang Chủ Cư Dân
      _showSuccessPopup(updatedUser);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi lưu thông tin: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showSuccessPopup(UserModel updatedUser) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: anim, child: child),
      ),
      pageBuilder: (dialogCtx, anim1, anim2) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Hồ Sơ Cư Dân Đã Hoàn Tất!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Chào mừng ${updatedUser.tenHienThi} đã chính thức là cư dân phòng ${widget.maPhong} tại Kiêu Giang House.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TenantHomeScreen(
                            tenantName: updatedUser.tenHienThi,
                          ),
                        ),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Vào quản lý phòng của tôi →',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Thông Tin Cá Nhân & Xe',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 95),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner quét AI CCCD
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE0F2FE), Color(0xFFF0FDF4)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBAE6FD)),
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
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quét AI CCCD tự động điền thông tin',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tải ảnh mặt trước CCCD để AI tự động trích xuất Họ tên, Số CCCD, Địa chỉ & Ngày sinh.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2 Khung tải ảnh CCCD
                Row(
                  children: [
                    Expanded(
                      child: _buildCccdBox(
                        isMatTruoc: true,
                        title: 'Mặt trước CCCD',
                        subtitle: 'AI tự động quét',
                        bytes: _bytesMatTruoc,
                        url: _urlMatTruoc,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCccdBox(
                        isMatTruoc: false,
                        title: 'Mặt sau CCCD',
                        subtitle: 'Chụp rõ nét',
                        bytes: _bytesMatSau,
                        url: _urlMatSau,
                      ),
                    ),
                  ],
                ),

                if (_isScanningAi) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primary,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'AI đang nhận diện và bóc tách dữ liệu CCCD...',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Card Thông tin cá nhân
                _buildCardContainer(
                  title: 'Thông Tin Định Danh Khách Thuê',
                  icon: Icons.person_pin_rounded,
                  children: [
                    _buildTextField(
                      controller: _hoTenController,
                      label: 'Họ và tên khách thuê *',
                      hint: 'Ví dụ: NGUYỄN VĂN A',
                      icon: Icons.person_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _soDtController,
                      label: 'Số điện thoại liên hệ *',
                      hint: 'Số điện thoại',
                      icon: Icons.phone_android_rounded,
                      readOnly: true,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _cccdController,
                      label: 'Số CCCD / Định danh (12 số) *',
                      hint: 'Ví dụ: 079201012345',
                      icon: Icons.badge_rounded,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),

                    // Giới tính
                    const Text(
                      'Giới tính *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildGenderChip('Nam', Icons.male_rounded),
                        const SizedBox(width: 12),
                        _buildGenderChip('Nữ', Icons.female_rounded),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Ngày sinh
                    _buildDatePickerField(
                      label: 'Ngày sinh',
                      currentDate: _ngaySinh,
                      onSelected: (d) => setState(() => _ngaySinh = d),
                      icon: Icons.cake_rounded,
                    ),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _diaChiController,
                      label: 'Địa chỉ thường trú (theo CCCD) *',
                      hint: 'Xã/Phường, Quận/Huyện, Tỉnh/TP',
                      icon: Icons.home_rounded,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),

                    // Ngày cấp & Nơi cấp
                    Row(
                      children: [
                        Expanded(
                          child: _buildDatePickerField(
                            label: 'Ngày cấp CCCD',
                            currentDate: _ngayCapCccd,
                            onSelected: (d) =>
                                setState(() => _ngayCapCccd = d),
                            icon: Icons.event_available_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _noiCapController,
                            label: 'Nơi cấp',
                            hint: 'Cục Cảnh sát...',
                            icon: Icons.account_balance_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildTextField(
                      controller: _nguoiLienHeController,
                      label: 'Người liên hệ khẩn cấp (Tùy chọn)',
                      hint: 'Ví dụ: Bố/Mẹ - 0912345678',
                      icon: Icons.emergency_rounded,
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Card Phương tiện xe
                _buildCardContainer(
                  title: 'Phương Tiện Xe Gửi Tại Trọ',
                  icon: Icons.two_wheeler_rounded,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Tôi có phương tiện xe gửi tại trọ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Switch(
                          value: _coPhuongTien,
                          onChanged: (val) {
                            setState(() {
                              _coPhuongTien = val;
                              if (val && _danhSachXe.isEmpty) {
                                _danhSachXe.add(_ThongTinXe());
                              }
                            });
                          },
                          activeThumbColor: _primary,
                        ),
                      ],
                    ),
                    if (!_coPhuongTien)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Bạn chọn không gửi phương tiện xe tại nhà trọ.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      )
                    else ...[
                      const Divider(height: 20),
                      for (int i = 0; i < _danhSachXe.length; i++) ...[
                        _buildCarCard(i),
                        const SizedBox(height: 10),
                      ],
                      if (_danhSachXe.length < 3)
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() => _danhSachXe.add(_ThongTinXe()));
                          },
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            'Thêm xe thứ ${_danhSachXe.length + 1}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _primary,
                            side: const BorderSide(color: _primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Bottom Bar: Nút Hoàn tất
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _luuThongTinCaNhan,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isSubmitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _submitProgressText ?? 'Đang lưu...',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          )
                        : const Text(
                            'Lưu Hồ Sơ Cư Dân & Hoàn Tất ✓',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarCard(int index) {
    final xe = _danhSachXe[index];
    final loaiXeOptions = [
      'Xe tay ga',
      'Xe máy số',
      'Xe máy điện',
      'Xe đạp điện',
      'Ô tô',
      'Khác',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Xe ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _primary,
                ),
              ),
              if (_danhSachXe.length > 1)
                InkWell(
                  onTap: () {
                    setState(() {
                      xe.dispose();
                      _danhSachXe.removeAt(index);
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
                      size: 18,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: xe.loaiXe,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Loại xe',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: loaiXeOptions
                .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e, style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => xe.loaiXe = val);
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: xe.bienSoController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Biển số xe *',
              hintText: 'Ví dụ: 59-X1 234.56',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: xe.ghiChuController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Hãng / Màu xe (Tùy chọn)',
              hintText: 'Ví dụ: Honda Vision đỏ',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderChip(String gender, IconData icon) {
    final isSelected = _gioiTinh == gender;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gioiTinh = gender),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? _primary : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                gender,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCccdBox({
    required bool isMatTruoc,
    required String title,
    required String subtitle,
    Uint8List? bytes,
    String? url,
  }) {
    final hasImage = bytes != null || (url != null && url.isNotEmpty);

    return InkWell(
      onTap: () => _showPickerModal(isMatTruoc),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? _primary : const Color(0xFFCBD5E1),
            width: hasImage ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (bytes != null)
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            else if (url != null && url.isNotEmpty)
              url.startsWith('data:image')
                  ? Image.memory(
                      base64Decode(url.contains(',') ? url.split(',').last : url),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image_rounded, color: Color(0xFF94A3B8)),
                      ),
                    )
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            if (hasImage)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: _primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPickerModal(bool isMatTruoc) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tải ảnh ${isMatTruoc ? 'Mặt trước' : 'Mặt sau'} CCCD',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: _primary),
                title: const Text('Chụp ảnh từ Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _chonAnhCccd(ImageSource.camera, isMatTruoc);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: _primary),
                title: const Text('Chọn ảnh từ Thư viện'),
                onTap: () {
                  Navigator.pop(ctx);
                  _chonAnhCccd(ImageSource.gallery, isMatTruoc);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardContainer({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _primary, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 13,
            color: readOnly ? const Color(0xFF64748B) : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            prefixIcon: Icon(icon, size: 18, color: _primary),
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime? currentDate,
    required Function(DateTime) onSelected,
    required IconData icon,
  }) {
    final text = currentDate != null
        ? DateFormat('dd/MM/yyyy').format(currentDate)
        : 'Chọn ngày...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: currentDate ?? DateTime(2000, 1, 1),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (picked != null) onSelected(picked);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: _primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      color: currentDate != null
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

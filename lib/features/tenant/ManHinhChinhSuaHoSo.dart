import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhChinhSuaHoSo extends StatefulWidget {
  final Map<String, dynamic>? khachThueData;
  final String tenPhong;
  final String maHopDong;
  final String vaiTro;

  const ManHinhChinhSuaHoSo({
    super.key,
    this.khachThueData,
    this.tenPhong = 'P303',
    this.maHopDong = 'HD001',
    this.vaiTro = 'Trưởng phòng',
  });

  @override
  State<ManHinhChinhSuaHoSo> createState() => _ManHinhChinhSuaHoSoState();
}

class _ManHinhChinhSuaHoSoState extends State<ManHinhChinhSuaHoSo> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _hoTenController;
  late TextEditingController _soDtController;
  late TextEditingController _cccdController;
  late TextEditingController _diaChiController;
  late TextEditingController _emailController;

  bool _isSaving = false;
  late String _maKhach;

  @override
  void initState() {
    super.initState();
    final data = widget.khachThueData;
    _maKhach = data?['ma_khach']?.toString() ?? '';

    final cccdVal = (data?['cccd'] ?? data?['so_cccd'])?.toString() ?? '';
    final hoTenVal = data?['ho_ten_khach']?.toString() ??
        AuthService.currentUser?.hoTen ??
        AuthService.currentUser?.tenHienThi ??
        '';
    final soDtVal = data?['so_dt']?.toString() ??
        AuthService.currentUser?.tenDangNhap ??
        '';
    final diaChiVal = (data?['dia_chi_thuong_tru'] ?? data?['dia_chi'])?.toString() ?? '';
    final emailVal = data?['email']?.toString() ?? '';

    _hoTenController = TextEditingController(text: hoTenVal);
    _soDtController = TextEditingController(text: soDtVal);
    _cccdController = TextEditingController(text: cccdVal);
    _diaChiController = TextEditingController(text: diaChiVal);
    _emailController = TextEditingController(text: emailVal);
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _soDtController.dispose();
    _cccdController.dispose();
    _diaChiController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _luuThongTin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final db = Supabase.instance.client;
      final hoTen = _hoTenController.text.trim();
      final soDt = _soDtController.text.trim();
      final cccd = _cccdController.text.trim();
      final diaChi = _diaChiController.text.trim();
      final user = AuthService.currentUser;

      // 1. Cập nhật bảng khach_thue
      if (_maKhach.isNotEmpty) {
        await db.from('khach_thue').update({
          'ho_ten_khach': hoTen,
          'so_dt': soDt,
          'cccd': cccd,
          'dia_chi_thuong_tru': diaChi,
        }).eq('ma_khach', _maKhach);
      } else if (user != null && user.maTaiKhoan.isNotEmpty) {
        await db.from('khach_thue').update({
          'ho_ten_khach': hoTen,
          'so_dt': soDt,
          'cccd': cccd,
          'dia_chi_thuong_tru': diaChi,
        }).eq('ma_tai_khoan', user.maTaiKhoan);
      }

      // 2. Cập nhật bảng tai_khoan nếu có
      if (user != null && user.maTaiKhoan.isNotEmpty) {
        try {
          await db.from('tai_khoan').update({
            'ho_ten': hoTen,
          }).eq('ma_tai_khoan', user.maTaiKhoan);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      await ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Cập Nhật Hồ Sơ Thành Công!',
        noiDung: 'Thông tin cá nhân và số định danh CCCD của bạn đã được lưu vào hệ thống.',
        type: ThongBaoType.thanhCong,
        nutText: 'Hoàn tất',
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Lỗi lưu hồ sơ: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể lưu thông tin: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Chỉnh Sửa Hồ Sơ',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Card Avatar & Thông tin phòng ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEF08A),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text('🐥', style: TextStyle(fontSize: 32)),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hoTenController.text.isNotEmpty ? _hoTenController.text : 'Cư Dân Kiêu Giang',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.vaiTro,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.tenPhong,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hợp đồng: ${widget.maHopDong}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Phần thông tin cá nhân ──
                const Text(
                  'THÔNG TIN CÁ NHÂN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // Họ và tên
                      _buildTextField(
                        controller: _hoTenController,
                        label: 'Họ và tên',
                        hint: 'Nhập họ và tên đầy đủ',
                        icon: Icons.person_outline_rounded,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập họ và tên';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Số điện thoại
                      _buildTextField(
                        controller: _soDtController,
                        label: 'Số điện thoại',
                        hint: '09xx xxx xxx',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập số điện thoại';
                          }
                          if (v.trim().length < 10) {
                            return 'Số điện thoại tối thiểu 10 chữ số';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Số CCCD
                      _buildTextField(
                        controller: _cccdController,
                        label: 'Số CCCD / CMND',
                        hint: 'Nhập số CCCD',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            if (v.trim().length != 9 && v.trim().length != 12) {
                              return 'Số CCCD phải gồm 12 số (hoặc CMND 9 số)';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Địa chỉ thường trú
                      _buildTextField(
                        controller: _diaChiController,
                        label: 'Địa chỉ thường trú / Quê quán',
                        hint: 'Xã/Phường, Quận/Huyện, Tỉnh/TP',
                        icon: Icons.home_outlined,
                      ),
                      const SizedBox(height: 14),

                      // Email
                      _buildTextField(
                        controller: _emailController,
                        label: 'Email (Tùy chọn)',
                        hint: 'example@gmail.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Nút Lưu Thay Đổi ──
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _luuThongTin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09638E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Lưu Thay Đổi',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF09638E)),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF09638E), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Màn hình Đổi Mật Khẩu dành cho Cư Dân
class ManHinhMatKhauPin extends StatefulWidget {
  final String roomNumber;
  final String buildingName;

  const ManHinhMatKhauPin({
    super.key,
    this.roomNumber = '302',
    this.buildingName = 'Kiêu Giang 2',
  });

  @override
  State<ManHinhMatKhauPin> createState() => _ManHinhMatKhauPinState();
}

class _ManHinhMatKhauPinState extends State<ManHinhMatKhauPin> {
  // Bảng màu chuẩn Kiêu Giang
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF003B5C);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  // Controllers cho Đổi Mật Khẩu
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSavingPassword = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ── KIỂM TRA ĐỘ MẠNH & QUY TẮC MẬT KHẨU ──────────────────────────
  String get _newPass => _newPasswordController.text;
  String get _confirmPass => _confirmPasswordController.text;

  bool get _reqLength => _newPass.length >= 8;
  bool get _reqUpperLowerNumber =>
      RegExp(r'[A-Z]').hasMatch(_newPass) &&
      RegExp(r'[a-z]').hasMatch(_newPass) &&
      RegExp(r'[0-9]').hasMatch(_newPass);
  bool get _reqSpecial => RegExp(r'[@#$%^&*()_+\-=\[\]{};:"\\|,.<>/?!~`]').hasMatch(_newPass);
  bool get _reqMatch => _confirmPass.isNotEmpty && _newPass == _confirmPass;

  int get _passwordStrengthScore {
    int score = 0;
    if (_newPass.isEmpty) return 0;
    if (_reqLength) score++;
    if (_reqUpperLowerNumber) score++;
    if (_reqSpecial) score++;
    if (_newPass.length >= 12) score++;
    return score;
  }

  String get _strengthText {
    if (_newPass.isEmpty) return 'Chưa nhập';
    switch (_passwordStrengthScore) {
      case 1:
        return '• Yếu';
      case 2:
        return '• Trung Bình';
      case 3:
        return '• Khá';
      case 4:
      default:
        return '• Rất Mạnh';
    }
  }

  Color get _strengthColor {
    if (_newPass.isEmpty) return const Color(0xFF94A3B8);
    switch (_passwordStrengthScore) {
      case 1:
        return const Color(0xFFEF4444);
      case 2:
        return const Color(0xFFF59E0B);
      case 3:
        return const Color(0xFF0284C7);
      case 4:
      default:
        return const Color(0xFF16A34A);
    }
  }

  // ── XỬ LÝ ĐỔI MẬT KHẨU TRÊN SUPABASE ─────────────────────────────
  Future<void> _handleSavePassword() async {
    final currentPass = _currentPasswordController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (currentPass.isEmpty) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Thiếu Mật Khẩu Hiện Tại',
        noiDung: 'Vui lòng nhập mật khẩu hiện tại của tài khoản!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (newPass.isEmpty) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Thiếu Mật Khẩu Mới',
        noiDung: 'Vui lòng nhập mật khẩu mới bạn muốn thiết lập!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (!_reqLength) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Mật Khẩu Quá Ngắn',
        noiDung: 'Mật khẩu mới phải có tối thiểu 8 ký tự an toàn.',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (!_reqUpperLowerNumber) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Độ Phức Tạp Chưa Đạt',
        noiDung: 'Mật khẩu phải bao gồm cả chữ hoa, chữ thường và chữ số.',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (!_reqSpecial) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Thiếu Ký Tự Đặc Biệt',
        noiDung: 'Mật khẩu cần ít nhất 1 ký tự đặc biệt (ví dụ: @, #, !, %, ...).',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (newPass != confirmPass) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Xác Nhận Không Khớp',
        noiDung: 'Mật khẩu xác nhận không trùng khớp với mật khẩu mới. Vui lòng kiểm tra lại.',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (currentPass == newPass) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Mật Khẩu Trùng Nhau',
        noiDung: 'Mật khẩu mới phải khác với mật khẩu hiện tại.',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    setState(() => _isSavingPassword = true);

    try {
      final user = AuthService.currentUser;
      if (user == null) {
        throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
      }

      final db = Supabase.instance.client;

      // 1. Kiểm tra mật khẩu hiện tại trong bảng tai_khoan
      final accountData = await db
          .from('tai_khoan')
          .select('ma_tai_khoan, ten_dang_nhap, mat_khau')
          .eq('ma_tai_khoan', user.maTaiKhoan)
          .maybeSingle();

      if (accountData == null) {
        throw Exception('Không tìm thấy tài khoản người dùng trong cơ sở dữ liệu.');
      }

      final dbPassword = accountData['mat_khau']?.toString() ?? '';
      if (!AuthService.verifyPassword(currentPass, dbPassword)) {
        if (!mounted) return;
        setState(() => _isSavingPassword = false);
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Mật Khẩu Cũ Không Đúng',
          noiDung: 'Mật khẩu hiện tại bạn vừa nhập không chính xác. Vui lòng kiểm tra lại!',
          type: ThongBaoType.thatBai,
        );
        return;
      }

      final hashedNewPass = AuthService.hashPassword(newPass);

      // 2. Cập nhật mật khẩu mới trên Supabase
      await db.from('tai_khoan').update({
        'mat_khau': hashedNewPass,
      }).eq('ma_tai_khoan', user.maTaiKhoan);

      // Cập nhật lại AuthService & SharedPreferences
      final updatedUser = UserModel(
        maTaiKhoan: user.maTaiKhoan,
        tenDangNhap: user.tenDangNhap,
        matKhau: hashedNewPass,
        vaiTro: user.vaiTro,
        coSoVanHanh: user.coSoVanHanh,
        ngayTao: user.ngayTao,
        trangThai: user.trangThai,
        hoTen: user.hoTen,
      );
      AuthService.currentUserNotifier.value = updatedUser;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_current_user_json', jsonEncode(updatedUser.toJson()));
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _isSavingPassword = false;
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      });

      // Bắn thông báo chuông hệ thống
      SystemNotificationService.show(
        title: '🔒 Đổi mật khẩu thành công',
        body: 'Mật khẩu tài khoản ${user.tenDangNhap} đã được cập nhật an toàn vào hệ thống Kiêu Giang.',
        tag: 'pwd_update_${DateTime.now().millisecondsSinceEpoch}',
      );

      await ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Đổi Mật Khẩu Thành Công!',
        noiDung: 'Mật khẩu mới đã được cập nhật thành công vào hệ thống. Bạn có thể sử dụng mật khẩu mới này cho những lần đăng nhập tiếp theo.',
        type: ThongBaoType.thanhCong,
        nutText: 'Đã hiểu',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSavingPassword = false);
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Cập Nhật Thất Bại',
        noiDung: 'Lỗi trong quá trình cập nhật mật khẩu: $e',
        type: ThongBaoType.thatBai,
      );
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.help_outline_rounded, color: _primary),
            SizedBox(width: 8),
            Text('Quy Định Bảo Mật', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Để bảo vệ an toàn cho hợp đồng điện tử và dữ liệu hóa đơn của bạn tại Kiêu Giang House:\n\n'
          '• Mật khẩu nên gồm ít nhất 8 ký tự, bao gồm chữ hoa, chữ thường, số và ký tự đặc biệt.\n'
          '• Không dùng mật khẩu trùng với số điện thoại hoặc ngày sinh.\n'
          '• Thay đổi mật khẩu định kỳ 3-6 tháng một lần để đảm bảo an toàn tối đa.',
          style: TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF334155)),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Đã hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.support_agent_rounded, color: _primary),
            SizedBox(width: 8),
            Text('Quên Mật Khẩu?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Nếu bạn quên mật khẩu hiện tại, vui lòng liên hệ trực tiếp với Ban Quản Lý tòa nhà Kiêu Giang để được cấp mã OTP khôi phục.',
          style: TextStyle(fontSize: 13, height: 1.45, color: Color(0xFF334155)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ThongBaoHelper.hienThongBao(
                context,
                tieuDe: 'Hỗ Trợ Ban Quản Lý',
                noiDung: 'Đang kết nối tới Ban Quản Lý Kiêu Giang House để hỗ trợ cấp lại mật khẩu ngay lập tức!',
                type: ThongBaoType.thongTin,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Liên hệ BQL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubHeader(),
                    const SizedBox(height: 18),
                    _buildChangePasswordForm(),
                    const SizedBox(height: 16),
                    _buildSecurityChecklist(),
                    const SizedBox(height: 20),
                    _buildSaveButton(),
                    const SizedBox(height: 16),
                    _buildBottomInfoBanner(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBarMock(),
    );
  }

  // ── HEADER APPBAR TRÊN CÙNG ─────────────────────────────────────
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Kiêu Giang',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _primaryDark,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Cá nhân',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              // Nút chuông thông báo
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_none_rounded, color: Color(0xFF334155), size: 22),
                    Positioned(
                      top: 8,
                      right: 9,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE11D48),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Logo Kiêu Giang
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  color: Colors.white,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Text('KG', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primary)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── SUBHEADER: NÚT QUAY LẠI & TIÊU ĐỀ ────────────────────────────
  Widget _buildSubHeader() {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, color: _primary, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Đổi Mật Khẩu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 13, color: _primary),
                  const SizedBox(width: 4),
                  Text(
                    'Phòng ${widget.roomNumber} • ${widget.buildingName}',
                    style: const TextStyle(
                      fontSize: 12,
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
          onTap: _showHelpDialog,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCBD5E1)),
              color: Colors.white,
            ),
            child: const Icon(Icons.question_mark_rounded, size: 16, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  // ── FORM ĐỔI MẬT KHẨU ───────────────────────────────────────────
  Widget _buildChangePasswordForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Mật khẩu hiện tại
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.key_rounded, size: 16, color: Color(0xFF475569)),
                  SizedBox(width: 6),
                  Text(
                    'Mật khẩu hiện tại',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: _showForgotPasswordDialog,
                child: const Text(
                  'Quên mật khẩu?',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _currentPasswordController,
            hint: 'Nhập mật khẩu hiện tại',
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
          ),
          const SizedBox(height: 18),

          // 2. Mật khẩu mới
          Row(
            children: const [
              Icon(Icons.lock_outline_rounded, size: 16, color: Color(0xFF475569)),
              SizedBox(width: 6),
              Text(
                'Mật khẩu mới',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _newPasswordController,
            hint: 'Nhập mật khẩu mới',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          const SizedBox(height: 12),

          // Thanh đo độ mạnh mật khẩu
          Row(
            children: [
              const Text(
                'Độ mạnh mật khẩu:',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: List.generate(4, (index) {
                    final isFilled = index < _passwordStrengthScore;
                    return Expanded(
                      child: Container(
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: isFilled ? _strengthColor : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _strengthText,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: _strengthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 3. Xác nhận mật khẩu mới
          Row(
            children: const [
              Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF475569)),
              SizedBox(width: 6),
              Text(
                'Xác nhận mật khẩu mới',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPasswordField(
            controller: _confirmPasswordController,
            hint: 'Nhập lại mật khẩu mới',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 14, color: _textDark, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
              color: const Color(0xFF64748B),
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }

  // ── CHECKLIST TIÊU CHUẨN BẢO MẬT ────────────────────────────────
  Widget _buildSecurityChecklist() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yêu cầu bảo mật tiêu chuẩn:',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 10),
          _buildChecklistItem('Tối thiểu 8 ký tự an toàn', _reqLength),
          const SizedBox(height: 8),
          _buildChecklistItem('Gồm chữ hoa, chữ thường & số', _reqUpperLowerNumber),
          const SizedBox(height: 8),
          _buildChecklistItem('Có ít nhất 1 ký tự đặc biệt (@, #, !)', _reqSpecial),
          const SizedBox(height: 8),
          _buildChecklistItem('Khớp chính xác với mật khẩu mới', _reqMatch),
        ],
      ),
    );
  }

  Widget _buildChecklistItem(String title, bool isSatisfied) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: isSatisfied ? const Color(0xFF09638E) : const Color(0xFFE2E8F0),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 13,
            color: isSatisfied ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.w500,
              color: isSatisfied ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  // ── NÚT LƯU & CẬP NHẬT MẬT KHẨU ─────────────────────────────────
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isSavingPassword ? null : _handleSavePassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isSavingPassword
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.assignment_turned_in_outlined, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Lưu & Cập Nhật Mật Khẩu',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── BANNER THÔNG BÁO DƯỚI CÙNG ──────────────────────────────────
  Widget _buildBottomInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, color: Color(0xFF1D4ED8), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hệ thống sẽ duy trì phiên đăng nhập hiện tại trên điện thoại của bạn và gửi mã xác nhận thay đổi mật khẩu qua số Zalo đã đăng ký hợp đồng.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF1E40AF),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── THANH BOTTOM BAR MOCK ĐỒNG BỘ 5 TAB ─────────────────────────
  Widget _buildBottomNavBarMock() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 4, // Tab Cá nhân
        onTap: (index) {
          if (index == 4) return;
          Navigator.pop(context); // Quay về Home để đổi tab
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _primary,
        unselectedItemColor: const Color(0xFF94A3B8),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.key_outlined),
            label: 'Phòng',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Hóa đơn',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            label: 'Yêu cầu',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

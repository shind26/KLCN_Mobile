import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhDoiMatKhauLanDau extends StatefulWidget {
  final String tenDangNhap;

  const ManHinhDoiMatKhauLanDau({super.key, required this.tenDangNhap});

  @override
  State<ManHinhDoiMatKhauLanDau> createState() =>
      _ManHinhDoiMatKhauLanDauState();
}

class _ManHinhDoiMatKhauLanDauState extends State<ManHinhDoiMatKhauLanDau> {
  static const _primary = Color(0xFF09638E);
  final _matKhauMoiController = TextEditingController();
  final _xacNhanController = TextEditingController();

  bool _obscureMoi = true;
  bool _obscureXacNhan = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _matKhauMoiController.dispose();
    _xacNhanController.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _matKhauMoiController.text.length >= 6;
  bool get _hasLetter =>
      RegExp(r'[a-zA-Z]').hasMatch(_matKhauMoiController.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_matKhauMoiController.text);
  bool get _isNotUser {
    final user = widget.tenDangNhap.trim();
    final pass = _matKhauMoiController.text.trim();
    if (user.isEmpty || pass.isEmpty) return true;
    return pass != user;
  }

  bool get _isMatch =>
      _matKhauMoiController.text.isNotEmpty &&
      _matKhauMoiController.text == _xacNhanController.text;

  Future<void> _handleDoiMatKhau() async {
    final passMoi = _matKhauMoiController.text;
    final passXacNhan = _xacNhanController.text;

    if (passMoi.isEmpty || passXacNhan.isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập đầy đủ thông tin mật khẩu');
      return;
    }
    if (!_hasMinLength) {
      setState(() => _errorMessage = 'Mật khẩu mới phải có tối thiểu 6 ký tự');
      return;
    }
    if (!_hasLetter || !_hasDigit) {
      setState(
        () => _errorMessage = 'Mật khẩu phải bao gồm cả chữ cái và chữ số',
      );
      return;
    }
    if (!_isNotUser) {
      setState(
        () => _errorMessage = 'Mật khẩu mới không được trùng với tên đăng nhập',
      );
      return;
    }
    if (!_isMatch) {
      setState(() => _errorMessage = 'Mật khẩu xác nhận không trùng khớp');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = Supabase.instance.client;

      // Cập nhật mật khẩu mới (được mã hóa BCrypt) và set da_doi_mat_khau = true
      final hashedPass = AuthService.hashPassword(passMoi);
      await db
          .from('tai_khoan')
          .update({'mat_khau': hashedPass, 'da_doi_mat_khau': true})
          .eq('ten_dang_nhap', widget.tenDangNhap);

      if (!mounted) return;
      setState(() => _isLoading = false);

      // Thông báo thành công và quay lại màn đăng nhập
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Row(
            children: const [
              Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF16A34A),
                size: 26,
              ),
              SizedBox(width: 8),
              Text(
                'Đổi mật khẩu thành công',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Bạn đã đổi mật khẩu lần đầu thành công! Hệ thống sẽ tự động đăng nhập và đưa bạn vào kiểm tra bàn giao phòng.',
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF334155),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx); // Đóng dialog
                Navigator.pop(
                  context,
                  passMoi,
                ); // Trả về mật khẩu mới để tự động đăng nhập
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Tiếp tục nhận phòng →'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Lỗi cập nhật mật khẩu: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.pop(context, false), // Bỏ qua
          child: const Text(
            'Bỏ qua',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        title: const Text(
          'Đổi mật khẩu lần đầu',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner thông báo yêu cầu bảo mật
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      color: _primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Yêu cầu bảo mật tài khoản',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: _primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Tài khoản ${widget.tenDangNhap} đang dùng mật khẩu mặc định của Chủ trọ cấp. Để đảm bảo an toàn, vui lòng thiết lập mật khẩu cá nhân mới.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFB7185)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFE11D48),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFBE123C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const Text(
                'Mật khẩu mới *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              _buildInputPassword(
                controller: _matKhauMoiController,
                obscure: _obscureMoi,
                onToggle: () => setState(() => _obscureMoi = !_obscureMoi),
                onChanged: (_) => setState(() {}),
                hint: 'Tối thiểu 6 ký tự, gồm cả chữ và số',
              ),
              const SizedBox(height: 16),

              const Text(
                'Xác nhận mật khẩu mới *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              _buildInputPassword(
                controller: _xacNhanController,
                obscure: _obscureXacNhan,
                onToggle: () =>
                    setState(() => _obscureXacNhan = !_obscureXacNhan),
                onChanged: (_) => setState(() {}),
                hint: 'Nhập lại mật khẩu mới',
              ),
              const SizedBox(height: 16),

              // Checklist tiêu chí bảo mật thực tế
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Yêu cầu bảo mật mật khẩu:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCriteriaItem('Tối thiểu 6 ký tự', _hasMinLength),
                    _buildCriteriaItem(
                      'Bao gồm cả chữ cái và chữ số',
                      _hasLetter && _hasDigit,
                    ),
                    _buildCriteriaItem('Khác tên đăng nhập', _isNotUser),
                    _buildCriteriaItem(
                      'Mật khẩu xác nhận trùng khớp',
                      _isMatch,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleDoiMatKhau,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'XÁC NHẬN VÀ LƯU MẬT KHẨU',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCriteriaItem(String label, bool satisfied) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            satisfied
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 15,
            color: satisfied
                ? const Color(0xFF16A34A)
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: satisfied ? FontWeight.w600 : FontWeight.normal,
              color: satisfied
                  ? const Color(0xFF15803D)
                  : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputPassword({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String hint,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: InputBorder.none,
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: Color(0xFF64748B),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
              color: const Color(0xFF94A3B8),
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}

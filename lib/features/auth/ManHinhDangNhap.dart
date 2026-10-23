import 'dart:math';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuSms.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:nhatro_kieugiang/features/auth/ManHinhDoiMatKhauLanDau.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhBanGiaoVaCapNhatHoSo.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/utils/LienHeHelper.dart';

class LoginScreen extends StatefulWidget {
  final String? accountLockedMessage;
  const LoginScreen({super.key, this.accountLockedMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _usernameFocused = false;
  bool _passwordFocused = false;

  late AnimationController _bgController;
  late AnimationController _cardController;
  late AnimationController _orbController;
  late Animation<double> _cardSlide;
  late Animation<double> _cardFade;
  late Animation<double> _orb1;
  late Animation<double> _orb2;

  @override
  void initState() {
    super.initState();

    if (widget.accountLockedMessage != null && widget.accountLockedMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hienThiThongBaoKhoaTaiKhoan(widget.accountLockedMessage!);
      });
    }

    // Background orb pulse animation
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _orb1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOutSine),
    );
    _orb2 = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOutSine),
    );

    // Background slow rotation
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // Card entrance animation
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _cardSlide = Tween<double>(begin: 50, end: 0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );
    _cardFade = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _cardController, curve: Curves.easeOut));

    _cardController.forward();

    // Focus state listeners
    _usernameFocus.addListener(() {
      if (mounted) setState(() => _usernameFocused = _usernameFocus.hasFocus);
    });
    _passwordFocus.addListener(() {
      if (mounted) setState(() => _passwordFocused = _passwordFocus.hasFocus);
    });

    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _bgController.dispose();
    _cardController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    if (AuthService.isLoggedIn && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final currentUser = AuthService.currentUser;
        if (currentUser != null) {
          await _kiemTraVaDieuHuong(currentUser);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => TenantHomeScreen(
                tenantName: AuthService.currentUser?.tenHienThi,
              ),
            ),
          );
        }
      });
      return;
    }

    final savedUser = await AuthService.getSavedUsername();
    final remember = await AuthService.getRememberMe();
    if (savedUser != null && savedUser.isNotEmpty && mounted) {
      setState(() {
        _usernameController.text = savedUser;
        _rememberMe = remember;
      });
    }
  }

  void _hienThiThongBaoKhoaTaiKhoan(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFD97706),
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'TÀI KHOẢN ĐÃ BỊ TẠM KHÓA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB45309),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFEF3C7)),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF78350F),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                LienHeHelper.hienThiLuaChonLienHe(context);
              },
              icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
              label: const Text(
                'Liên hệ Ban Quản Lý (0328.004.663)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Đã hiểu',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() => _errorMessage = null);
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _errorMessage = 'Vui lòng nhập đầy đủ tài khoản và mật khẩu',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await AuthService.login(
        username: username,
        password: password,
        rememberMe: _rememberMe,
      );

      if (!mounted) return;

      if (!result.success || result.user == null) {
        final err = result.error ?? 'Đăng nhập thất bại. Vui lòng thử lại!';
        setState(() {
          _errorMessage = err;
          _isLoading = false;
        });
        if (err.toLowerCase().contains('khóa') || err.toLowerCase().contains('tamkhoa')) {
          _hienThiThongBaoKhoaTaiKhoan(err);
        } else {
          ThongBaoHelper.hienToast(
            context,
            tieuDe: 'Đăng nhập thất bại',
            noiDung: err,
            type: ThongBaoType.thatBai,
          );
        }
        return;
      }

      final user = result.user!;

      // ── KIỂM TRA ĐỔI MẬT KHẨU LẦN ĐẦU ──
      if (!user.daDoiMatKhau) {
        setState(() => _isLoading = false);
        if (!mounted) return;
        final passMoi = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => ManHinhDoiMatKhauLanDau(tenDangNhap: username),
          ),
        );

        if (!mounted) return;

        if (passMoi != null && passMoi.isNotEmpty) {
          _passwordController.text = passMoi;
          setState(() => _isLoading = true);
          final loginMoi = await AuthService.login(
            username: username,
            password: passMoi,
            rememberMe: _rememberMe,
          );
          if (loginMoi.success && loginMoi.user != null) {
            await _kiemTraVaDieuHuong(loginMoi.user!);
            return;
          } else {
            setState(() => _isLoading = false);
            return;
          }
        } else {
          ThongBaoHelper.hienToast(
            context,
            tieuDe: 'Yêu cầu đổi mật khẩu',
            noiDung: 'Bạn bắt buộc phải đổi mật khẩu lần đầu để tiếp tục sử dụng ứng dụng!',
            type: ThongBaoType.canhBao,
          );
          return;
        }
      }

      await _kiemTraVaDieuHuong(user);
    } catch (e) {
      debugPrint('Lỗi _handleLogin: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _kiemTraVaDieuHuong(UserModel user) async {
    // Kiểm tra trực tiếp trạng thái tài khoản từ Supabase
    try {
      final db = Supabase.instance.client;
      final accRes = await db
          .from('tai_khoan')
          .select('trang_thai')
          .eq('ma_tai_khoan', user.maTaiKhoan)
          .maybeSingle();
      final st = accRes?['trang_thai']?.toString() ?? '';
      if (st.toLowerCase() == 'tamkhoa' || (accRes != null && st.toLowerCase() != 'hoatdong')) {
        await AuthService.logout();
        if (!mounted) return;
        setState(() => _isLoading = false);
        _hienThiThongBaoKhoaTaiKhoan(
          'Tài khoản của bạn đã bị TẠM KHÓA do hóa đơn phòng quá hạn từ 10 ngày trở lên theo quy chế tòa nhà.\nVui lòng liên hệ Ban Quản Lý (0328.004.663) để được hỗ trợ mở lại!',
        );
        return;
      }
    } catch (_) {}

    // Nếu là Admin hoặc Quản lý: vào thẳng giao diện tương ứng
    if (user.isAdmin || user.vaiTro.toLowerCase() == 'quanly') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => TenantHomeScreen(tenantName: user.tenHienThi),
        ),
        (route) => false,
      );
      return;
    }

    try {
      final db = Supabase.instance.client;
      // 1. Tìm thông tin khách thuê tương ứng với tài khoản
      Map<String, dynamic>? ktRes;
      if (user.maTaiKhoan.isNotEmpty) {
        try {
          ktRes = await db
              .from('khach_thue')
              .select()
              .eq('ma_tai_khoan', user.maTaiKhoan)
              .maybeSingle();
        } catch (_) {}
      }
      if (ktRes == null && user.tenDangNhap.isNotEmpty) {
        try {
          ktRes = await db
              .from('khach_thue')
              .select()
              .eq('so_dt', user.tenDangNhap)
              .maybeSingle();
        } catch (_) {}
      }

      if (ktRes != null) {
        final maKhach = ktRes['ma_khach']?.toString() ?? '';

        // 2. Tìm hợp đồng của khách thuê (ưu tiên hợp đồng chưa xác nhận bàn giao)
        Map<String, dynamic>? hdRow;
        String? vaiTroFromCthd;

        try {
          final cthdList = await db
              .from('chi_tiet_hop_dong_khach_thue')
              .select('ma_hop_dong, vai_tro')
              .eq('ma_khach', maKhach);

          if (cthdList.isNotEmpty) {
            final maHdList = cthdList
                .map((e) => e['ma_hop_dong']?.toString())
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .toList();

            if (maHdList.isNotEmpty) {
              final rows = await db
                  .from('hop_dong')
                  .select()
                  .inFilter('ma_hop_dong', maHdList)
                  .order('ngay_bd', ascending: false);

              for (final row in rows) {
                if (row['da_xac_nhan_ban_giao'] != true) {
                  hdRow = row;
                  break;
                }
                hdRow ??= row;
              }

              if (hdRow != null) {
                final match = cthdList.firstWhere(
                  (c) => c['ma_hop_dong']?.toString() == hdRow!['ma_hop_dong']?.toString(),
                  orElse: () => <String, dynamic>{},
                );
                vaiTroFromCthd = match['vai_tro']?.toString();
              }
            }
          }
        } catch (eCthd) {
          debugPrint('Lỗi truy vấn chi_tiet_hop_dong_khach_thue: $eCthd');
        }

        // Fallback: tìm qua ma_khach_dai_dien trong hop_dong
        if (hdRow == null) {
          try {
            final hdList = await db
                .from('hop_dong')
                .select()
                .eq('ma_khach_dai_dien', maKhach)
                .order('ngay_bd', ascending: false)
                .limit(5);
            for (final row in (hdList as List)) {
              if (row['da_xac_nhan_ban_giao'] != true) {
                hdRow = Map<String, dynamic>.from(row as Map);
                break;
              }
              hdRow ??= Map<String, dynamic>.from(row as Map);
            }
          } catch (eHd) {
            debugPrint('Lỗi truy vấn hop_dong theo ma_khach_dai_dien: $eHd');
          }
        }

        if (hdRow != null) {
          final daBanGiao = hdRow['da_xac_nhan_ban_giao'] == true;
          final cccd = ktRes['cccd']?.toString();
          final thieuCccd = (cccd == null || cccd.trim().isEmpty || cccd.trim().length != 12);
          final thieuThongTin = (ktRes['ngay_sinh'] == null ||
              ktRes['dia_chi_thuong_tru'] == null ||
              ktRes['dia_chi_thuong_tru'].toString().trim().isEmpty ||
              ktRes['noi_cap_cccd'] == null ||
              ktRes['noi_cap_cccd'].toString().trim().isEmpty ||
              ktRes['nguoi_lien_he_khan_cap'] == null ||
              ktRes['nguoi_lien_he_khan_cap'].toString().trim().isEmpty);

          // Xác định vai trò: Người đại diện hợp đồng vs Khách ở cùng
          bool isDaiDien = false;
          final maDaiDien = hdRow['ma_khach_dai_dien']?.toString();
          if (maDaiDien != null && maDaiDien.isNotEmpty && maDaiDien == maKhach) {
            isDaiDien = true;
          }

          if (!isDaiDien && vaiTroFromCthd != null) {
            final vt = vaiTroFromCthd.toLowerCase();
            if (vt.contains('đại diện') || vt.contains('daidien') || vt.contains('trưởng phòng') || vt.contains('truongphong')) {
              isDaiDien = true;
            }
          }

          if (!isDaiDien) {
            final uRole = user.vaiTro.toLowerCase();
            if (uRole.contains('truongphong') || uRole.contains('daidien') || uRole.contains('đại diện')) {
              isDaiDien = true;
            }
          }

          debugPrint(
            '[_kiemTraVaDieuHuong] maKhach: $maKhach, isDaiDien: $isDaiDien, maHd: ${hdRow['ma_hop_dong']}, daBanGiao: $daBanGiao, thieuCccd: $thieuCccd, thieuThongTin: $thieuThongTin',
          );

          // RÀNG BUỘC THEO VAI TRÒ:
          // - Người đại diện hợp đồng: Bắt buộc hoàn tất hồ sơ cá nhân VÀ ký nhận bàn giao tài sản (!daBanGiao)
          // - Khách ở cùng: CHỈ CẦN điền thông tin cá nhân (thieuCccd || thieuThongTin). Biên bản bàn giao tài sản chỉ có người đại diện hợp đồng xác nhận!
          final canCapNhatHoSo = isDaiDien
              ? (!daBanGiao || thieuCccd || thieuThongTin)
              : (thieuCccd || thieuThongTin);

          if (canCapNhatHoSo) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ManHinhBanGiaoVaCapNhatHoSo(
                  user: user,
                  maKhach: maKhach,
                  maHopDong: hdRow!['ma_hop_dong']?.toString() ?? '',
                  maPhong: hdRow['ma_phong']?.toString() ?? '',
                  khachThueData: ktRes!,
                  isNguoiDaiDien: isDaiDien,
                ),
              ),
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra bàn giao tài sản: $e');
    }

    if (!mounted) return;
    // Đăng nhập hợp lệ: Chuyển thẳng vào Trang Chủ ngay lập tức
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => TenantHomeScreen(
          tenantName: user.tenHienThi,
        ),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ====== ANIMATED GRADIENT BACKGROUND (LIGHT PEARL LUXURY) ======
          AnimatedBuilder(
            animation: _bgController,
            builder: (ctx, child) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFF0F6FA), // Trắng sương mai ánh lam
                      Color(0xFFE4F0F8),
                      Color(0xFFDCEAF5),
                      Color(0xFFEAF4FB),
                    ],
                  ),
                ),
              );
            },
          ),

          // ====== FLOATING GLASS ORBS ======
          AnimatedBuilder(
            animation: _orb1,
            builder: (ctx, child) {
              return Positioned(
                top: -80 + (_orb1.value * 30),
                right: -60 + (_orb2.value * 20),
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        const Color(0xFFBAE6FD).withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _orb2,
            builder: (ctx, child) {
              return Positioned(
                bottom: 80 + (_orb2.value * 40),
                left: -80 + (_orb1.value * 25),
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF0284C7).withValues(alpha: 0.12),
                        const Color(0xFFE0F2FE).withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // ====== GRID DOTS PATTERN ======
          CustomPaint(
            painter: _DotGridPainter(),
            size: Size(
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height,
            ),
          ),

          // ====== MAIN CONTENT ======
          SafeArea(
            child: Column(
              children: [
                // Top Header: Back Button & Title
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFCBD5E1).withValues(alpha: 0.6),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF09638E).withValues(alpha: 0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Color(0xFF09638E),
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Đăng nhập tài khoản',
                        style: TextStyle(
                          color: Color(0xFF0F2942),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: AnimatedBuilder(
                      animation: _cardController,
                      builder: (ctx, child) => Transform.translate(
                        offset: Offset(0, _cardSlide.value),
                        child: Opacity(opacity: _cardFade.value, child: child),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),

                          // ====== LOGO SECTION ======
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFBAE6FD)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF0EA5E9,
                                  ).withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(8),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, st) => const Icon(
                                Icons.home_work_rounded,
                                size: 36,
                                color: Color(0xFF09638E),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          const Text(
                            'Nhà Trọ Kiêu Giang',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0A3A52),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Quản lý thông minh • Sống tiện nghi',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF527084),
                              letterSpacing: 0.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ====== WHITE GLASS FORM CARD ======
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF09638E).withValues(alpha: 0.08),
                                  blurRadius: 32,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Form Title
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFF09638E),
                                              Color(0xFF0EA5E9),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.person_pin_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: const [
                                            Text(
                                              'Đăng nhập Khách thuê',
                                              style: TextStyle(
                                                fontSize: 16.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            Text(
                                              'Cổng thông tin Cư dân & Khách thuê Kiêu Giang',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),

                                  // Error Banner
                                  if (_errorMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 11,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1F2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFFB7185,
                                          ).withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: Color(0xFFE11D48),
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(
                                                fontSize: 12.5,
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

                                  // Username Field
                                  _buildLabel('Tên đăng nhập'),
                                  const SizedBox(height: 7),
                                  _buildInputField(
                                    controller: _usernameController,
                                    focusNode: _usernameFocus,
                                    isFocused: _usernameFocused,
                                    prefixIcon: Icons.person_outline_rounded,
                                    hint: 'Nhập tên đăng nhập của bạn',
                                    keyboardType: TextInputType.text,
                                    onSubmitted: (_) =>
                                        _passwordFocus.requestFocus(),
                                  ),
                                  const SizedBox(height: 16),

                                  // Password Field
                                  _buildLabel('Mật khẩu'),
                                  const SizedBox(height: 7),
                                  _buildPasswordField(),
                                  const SizedBox(height: 14),

                                  // Remember & Forgot Password
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => setState(
                                          () => _rememberMe = !_rememberMe,
                                        ),
                                        child: Row(
                                          children: [
                                            AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 150,
                                              ),
                                              width: 19,
                                              height: 19,
                                              decoration: BoxDecoration(
                                                color: _rememberMe
                                                    ? const Color(0xFF09638E)
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: _rememberMe
                                                      ? const Color(0xFF09638E)
                                                      : const Color(0xFFCBD5E1),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: _rememberMe
                                                  ? const Icon(
                                                      Icons.check_rounded,
                                                      color: Colors.white,
                                                      size: 13,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'Ghi nhớ đăng nhập',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF475569),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: _showForgotDialog,
                                          child: const Text(
                                            'Quên mật khẩu?',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF09638E),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 22),

                                    // Submit Button
                                    _buildSubmitButton(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),

                          // ====== GUEST EXPLORE SHORTCUT ======
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFBAE6FD),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF09638E).withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEBF5FA),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.explore_rounded,
                                      color: Color(0xFF09638E),
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          'Khách vãng lai?',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        SizedBox(height: 1),
                                        Text(
                                          'Xem phòng & Đặt lịch không cần đăng nhập',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0A3A52),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Color(0xFF09638E),
                                    size: 13,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Security Footer
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.lock_clock_rounded,
                                size: 12,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(width: 5),
                              Text(
                                'Bảo mật chuẩn SSL 256-bit • Nhà trọ Kiêu Giang',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF334155),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool isFocused,
    required IconData prefixIcon,
    required String hint,
    TextInputType? keyboardType,
    void Function(String)? onSubmitted,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isFocused ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isFocused ? const Color(0xFF09638E) : const Color(0xFFE2E8F0),
          width: isFocused ? 1.8 : 1,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF09638E).withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          prefixIcon: Icon(
            prefixIcon,
            size: 19,
            color: isFocused
                ? const Color(0xFF09638E)
                : const Color(0xFF94A3B8),
          ),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: _passwordFocused ? Colors.white : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _passwordFocused
              ? const Color(0xFF09638E)
              : const Color(0xFFE2E8F0),
          width: _passwordFocused ? 1.8 : 1,
        ),
        boxShadow: _passwordFocused
            ? [
                BoxShadow(
                  color: const Color(0xFF09638E).withValues(alpha: 0.12),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : [],
      ),
      child: TextField(
        controller: _passwordController,
        focusNode: _passwordFocus,
        obscureText: _obscurePassword,
        onSubmitted: (_) => _handleLogin(),
        decoration: InputDecoration(
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            size: 19,
            color: _passwordFocused
                ? const Color(0xFF09638E)
                : const Color(0xFF94A3B8),
          ),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
              color: const Color(0xFF94A3B8),
            ),
          ),
          hintText: '••••••••',
          hintStyle: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        boxShadow: _isLoading
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF09638E).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            gradient: _isLoading
                ? const LinearGradient(
                    colors: [Color(0xFF64748B), Color(0xFF475569)],
                  )
                : const LinearGradient(
                    colors: [Color(0xFF07516E), Color(0xFF0A8FCA)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
            borderRadius: BorderRadius.circular(13),
          ),
          child: InkWell(
            onTap: _isLoading ? null : _handleLogin,
            borderRadius: BorderRadius.circular(13),
            splashColor: Colors.white.withValues(alpha: 0.2),
            highlightColor: Colors.white.withValues(alpha: 0.1),
            child: Center(
              child: _isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.2,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Đang đăng nhập...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'ĐĂNG NHẬP',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mở bottom sheet quên mật khẩu OTP
  void _showForgotDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ForgotPasswordSheet(
        onCancel: () => Navigator.pop(ctx),
        onSuccess: (tenDangNhap) {
          Navigator.pop(ctx);
          _showResetPasswordSuccessDialog(tenDangNhap);
        },
      ),
    );
  }

  /// Dialog thông báo đổi mật khẩu thành công hiện giữa màn hình
  void _showResetPasswordSuccessDialog(String tenDangNhap) {
    _usernameController.text = tenDangNhap;
    _passwordController.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        elevation: 12,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon khiên xanh bảo mật phát sáng
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),

              const Text(
                'Đổi Mật Khẩu Thành Công!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              const Text(
                'Mật khẩu tài khoản của bạn đã được cập nhật thành công. Vui lòng đăng nhập lại bằng mật khẩu mới vừa tạo.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),

              // Thẻ tóm tắt tài khoản
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded, size: 18, color: Color(0xFF09638E)),
                    const SizedBox(width: 8),
                    const Text(
                      'Tài khoản:',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                    const Spacer(),
                    Text(
                      tenDangNhap,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Nút Đăng nhập ngay
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Tự động focus vào ô mật khẩu
                    _passwordFocus.requestFocus();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09638E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ĐĂNG NHẬP NGAY',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
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
}

// Background painter
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF09638E).withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;
    const spacing = 26.0;
    const radius = 1.1;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}

// ================================================================
// WIDGET QUÊN MẬT KHẨU – 3 bước: SĐT → OTP → Mật khẩu mới
// ================================================================
class _ForgotPasswordSheet extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<String>? onSuccess;
  const _ForgotPasswordSheet({required this.onCancel, this.onSuccess});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  static const _primary = Color(0xFF09638E);

  // Bước hiện tại: 0 = nhập SĐT, 1 = nhập OTP, 2 = đặt mật khẩu mới
  int _step = 0;

  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  String? _errorMsg;
  String _otpCode = '';
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String _tenDangNhapFound = ''; // ten_dang_nhap tìm thấy theo SĐT
  bool _isTestOtp = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _genOtp() {
    final rng = Random();
    return (100000 + rng.nextInt(900000)).toString();
  }

  /// Bước 1: Kiểm tra SĐT có trong DB → gửi OTP qua eSMS
  Future<void> _guiOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMsg = 'Vui lòng nhập số điện thoại');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      // Kiểm tra SĐT có trong bảng tai_khoan (cột ten_dang_nhap)
      final db = Supabase.instance.client;
      final row = await db
          .from('tai_khoan')
          .select('ten_dang_nhap, trang_thai')
          .eq('ten_dang_nhap', phone)
          .maybeSingle();

      if (row == null) {
        setState(() {
          _isLoading = false;
          _errorMsg =
              'Số điện thoại này không có trong hệ thống. Vui lòng liên hệ BQL.';
        });
        return;
      }

      if (row['trang_thai']?.toString().toLowerCase() != 'hoatdong') {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Tài khoản đang bị tạm khóa. Vui lòng liên hệ BQL!';
        });
        return;
      }

      _tenDangNhapFound = row['ten_dang_nhap']?.toString() ?? phone;

      // Tạo mã OTP và gửi SMS
      _otpCode = _genOtp();
      final result = await SmsService.sendOtpSms(
        phone: phone,
        otpCode: _otpCode,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _isLoading = false;
          _errorMsg = result.message ?? 'Gửi OTP thất bại. Thử lại sau!';
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _step = 1;
        _errorMsg = null;
        _isTestOtp = result.isTestOtp;
        if (result.isTestOtp) {
          _otpCtrl.text = _otpCode; // Tự động điền mã OTP để kiểm thử nhanh trên Web
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Lỗi kết nối: $e';
        });
      }
    }
  }

  /// Bước 2: Xác nhận OTP
  void _xacNhanOtp() {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      setState(() => _errorMsg = 'Vui lòng nhập mã OTP');
      return;
    }
    if (otp != _otpCode) {
      setState(() => _errorMsg = 'Mã OTP không đúng. Vui lòng thử lại!');
      return;
    }
    setState(() {
      _step = 2;
      _errorMsg = null;
    });
  }

  bool get _hasMinLength => _passCtrl.text.length >= 6;
  bool get _hasLetter => RegExp(r'[a-zA-Z]').hasMatch(_passCtrl.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_passCtrl.text);
  bool get _isNotPhone {
    final phone = _phoneCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (phone.isEmpty || pass.isEmpty) return true;
    return pass != phone;
  }
  bool get _isMatch =>
      _passCtrl.text.isNotEmpty && _passCtrl.text == _confirmCtrl.text;

  /// Bước 3: Đặt mật khẩu mới
  Future<void> _datMatKhauMoi() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (pass.isEmpty || confirm.isEmpty) {
      setState(() => _errorMsg = 'Vui lòng nhập đầy đủ thông tin mật khẩu');
      return;
    }
    if (!_hasMinLength) {
      setState(() => _errorMsg = 'Mật khẩu phải có tối thiểu 6 ký tự');
      return;
    }
    if (!_hasLetter || !_hasDigit) {
      setState(() => _errorMsg = 'Mật khẩu phải bao gồm cả chữ cái và chữ số');
      return;
    }
    if (!_isMatch) {
      setState(() => _errorMsg = 'Mật khẩu xác nhận không trùng khớp');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final db = Supabase.instance.client;
      final hashedPass = AuthService.hashPassword(pass);
      await db
          .from('tai_khoan')
          .update({'mat_khau': hashedPass, 'da_doi_mat_khau': true})
          .eq('ten_dang_nhap', _tenDangNhapFound);

      if (!mounted) return;
      if (widget.onSuccess != null) {
        widget.onSuccess!(_tenDangNhapFound);
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Lỗi cập nhật mật khẩu: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0EA5E9)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _step == 0
                        ? Icons.phone_android_rounded
                        : _step == 1
                            ? Icons.sms_rounded
                            : Icons.lock_reset_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _step == 0
                            ? 'Quên mật khẩu'
                            : _step == 1
                                ? 'Xác nhận OTP'
                                : 'Đặt mật khẩu mới',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        _step == 0
                            ? 'Nhập số điện thoại đã đăng ký'
                            : _step == 1
                                ? 'Nhập mã 6 số vừa gửi đến điện thoại'
                                : 'Tạo mật khẩu mới cho tài khoản',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: widget.onCancel,
                  child: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF94A3B8),
                    size: 22,
                  ),
                ),
              ],
            ),

            // Step indicator
            const SizedBox(height: 18),
            Row(
              children: List.generate(3, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: active ? _primary : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // Error banner
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFFB7185).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFE11D48),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFBE123C),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Nội dung theo bước
            if (_step == 0) _buildStepPhone(),
            if (_step == 1) _buildStepOtp(),
            if (_step == 2) _buildStepNewPassword(),

            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }

  // ── Bước 1: Nhập SĐT ──────────────────────────────────
  Widget _buildStepPhone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Số điện thoại đã đăng ký',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              // Lá cờ Việt Nam + Mã vùng +84
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDA251D),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFEB3B),
                          size: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '+84',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 1,
                      height: 18,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
              ),

              // Ô nhập SĐT
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Nhập số điện thoại',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Nhập đúng SĐT bạn đã dùng khi ký hợp đồng / được BQL cấp tài khoản.',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), height: 1.4),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _guiOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              elevation: 0,
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
                    'GỬI MÃ OTP QUA SMS',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── Bước 2: Nhập OTP ──────────────────────────────────
  Widget _buildStepOtp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card thông báo tin nhắn SMS xác thực
        Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.mark_chat_unread_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tin nhắn SMS xác thực',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF14532D),
                          ),
                        ),
                        Text(
                          'Gửi đến SĐT: ${_phoneCtrl.text.trim()}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFBBF7D0)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.done_all_rounded,
                          size: 13,
                          color: Color(0xFF16A34A),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Đã gửi',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF15803D),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, thickness: 0.8, color: Color(0xFFBBF7D0)),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF166534),
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'Nha tro Kieu Giang: Ma OTP cua ban la '),
                    TextSpan(
                      text: _otpCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const TextSpan(
                      text: '. Mã có hiệu lực trong 5 phút.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Mã OTP (6 số)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
              color: Color(0xFF09638E),
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '- - - - - -',
              hintStyle: TextStyle(
                fontSize: 20,
                color: Color(0xFFCBD5E1),
                letterSpacing: 6,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _xacNhanOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              elevation: 0,
            ),
            child: const Text(
              'XÁC NHẬN OTP',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => setState(() => _step = 0),
            child: const Text(
              'Gửi lại mã OTP',
              style: TextStyle(
                fontSize: 12.5,
                color: _primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Bước 3: Đặt mật khẩu mới ──────────────────────────
  Widget _buildStepNewPassword() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mật khẩu mới',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 7),
        _buildPasswordInput(
          controller: _passCtrl,
          hint: 'Tối thiểu 6 ký tự, gồm chữ và số',
          obscure: _obscurePass,
          onToggle: () => setState(() => _obscurePass = !_obscurePass),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        const Text(
          'Xác nhận mật khẩu mới',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 7),
        _buildPasswordInput(
          controller: _confirmCtrl,
          hint: 'Nhập lại mật khẩu mới',
          obscure: _obscureConfirm,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),

        // Checklist tiêu chí bảo mật thực tế
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
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
              _buildCriteriaItem('Mật khẩu xác nhận trùng khớp', _isMatch),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _datMatKhauMoi,
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              elevation: 0,
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
                    'LƯU MẬT KHẨU MỚI',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ],
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

  Widget _buildPasswordInput({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.lock_outline_rounded,
            size: 19,
            color: Color(0xFF94A3B8),
          ),
          suffixIcon: GestureDetector(
            onTap: onToggle,
            child: Icon(
              obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 19,
              color: const Color(0xFF94A3B8),
            ),
          ),
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 14,
          ),
        ),
      ),
    );
  }
}
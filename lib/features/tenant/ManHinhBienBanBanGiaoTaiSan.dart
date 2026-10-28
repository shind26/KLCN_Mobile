import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhCapNhatThongTinCaNhan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhBienBanBanGiaoTaiSan extends StatefulWidget {
  final UserModel user;
  final String maKhach;
  final String maHopDong;
  final String maPhong;
  final Map<String, dynamic> khachThueData;
  final bool? daXacNhan;

  const ManHinhBienBanBanGiaoTaiSan({
    super.key,
    required this.user,
    required this.maKhach,
    required this.maHopDong,
    required this.maPhong,
    required this.khachThueData,
    this.daXacNhan,
  });

  @override
  State<ManHinhBienBanBanGiaoTaiSan> createState() =>
      _ManHinhBienBanBanGiaoTaiSanState();
}

class _ManHinhBienBanBanGiaoTaiSanState
    extends State<ManHinhBienBanBanGiaoTaiSan> {
  static const _primary = Color(0xFF09638E);

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _daXacNhanBanGiao = false;
  bool _isDaiDien = false;
  String? _tenNguoiDaiDien;
  String? _ngayXacNhanBanGiao;
  String? _ghiChuCu;
  List<Map<String, dynamic>> _danhSachTaiSan = [];
  final _ghiChuController = TextEditingController();
  bool _camKetKiemTra = false;

  @override
  void initState() {
    super.initState();
    if (widget.daXacNhan == true) {
      _daXacNhanBanGiao = true;
      _camKetKiemTra = true;
    }
    _loadTaiSanPhong();
  }

  @override
  void dispose() {
    _ghiChuController.dispose();
    super.dispose();
  }

  Future<void> _loadTaiSanPhong() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;

      // 1. Kiểm tra trạng thái bàn giao của hợp đồng & thông tin người đại diện
      try {
        final hdRes = await db
            .from('hop_dong')
            .select(
              'da_xac_nhan_ban_giao, ngay_xac_nhan_ban_giao, ma_khach_dai_dien',
            )
            .eq('ma_hop_dong', widget.maHopDong)
            .maybeSingle();

        if (hdRes != null) {
          final isConfirmed = hdRes['da_xac_nhan_ban_giao'] == true;
          final ngayXn = hdRes['ngay_xac_nhan_ban_giao']?.toString();
          final maDaiDien = hdRes['ma_khach_dai_dien']?.toString();
          _daXacNhanBanGiao = isConfirmed;
          _ngayXacNhanBanGiao = ngayXn;
          if (isConfirmed) {
            _camKetKiemTra = true;
          }
          if (maDaiDien != null && maDaiDien.isNotEmpty) {
            _isDaiDien = (maDaiDien == widget.maKhach);
            try {
              final ddKhach = await db
                  .from('khach_thue')
                  .select('ho_ten_khach')
                  .eq('ma_khach', maDaiDien)
                  .maybeSingle();
              if (ddKhach != null) {
                _tenNguoiDaiDien = ddKhach['ho_ten_khach']?.toString();
              }
            } catch (_) {}
          }
        }
      } catch (eHd) {
        debugPrint('Lỗi tải trạng thái bàn giao hợp đồng: $eHd');
      }

      // Kiểm tra thêm vai_tro trong chi_tiet_hop_dong_khach_thue
      try {
        final cthd = await db
            .from('chi_tiet_hop_dong_khach_thue')
            .select('vai_tro')
            .eq('ma_hop_dong', widget.maHopDong)
            .eq('ma_khach', widget.maKhach)
            .maybeSingle();
        if (cthd != null && cthd['vai_tro'] != null) {
          final vt = cthd['vai_tro'].toString().toLowerCase();
          if (vt.contains('đại diện') ||
              vt.contains('daidien') ||
              vt.contains('trưởng phòng')) {
            _isDaiDien = true;
          } else if (vt.contains('ở cùng') ||
              vt.contains('ocung') ||
              vt.contains('thành viên')) {
            _isDaiDien = false;
          }
        }
      } catch (_) {}

      // 2. Tải danh sách thiết bị bàn giao phòng (từ bảng tai_san, tự động fallback sang bảng phong.noi_that_san_co)
      List<Map<String, dynamic>> list = [];
      try {
        final res = await db
            .from('tai_san')
            .select()
            .eq('ma_phong', widget.maPhong)
            .order('ma_tai_san');
        list = List<Map<String, dynamic>>.from(res);
      } catch (eTs) {
        debugPrint('Lỗi tải từ bảng tai_san: $eTs');
      }

      // Nếu bảng tai_san chưa có dữ liệu, lấy trực tiếp danh mục từ thông tin phòng
      if (list.isEmpty) {
        try {
          final pRow = await db
              .from('phong')
              .select('noi_that_san_co, tien_ich')
              .eq('ma_phong', widget.maPhong)
              .maybeSingle();

          if (pRow != null) {
            final Set<String> itemNames = {};
            void parseList(dynamic val) {
              if (val == null) return;
              if (val is List) {
                for (final e in val) {
                  final s = e?.toString().trim() ?? '';
                  if (s.isNotEmpty) itemNames.add(s);
                }
              } else if (val is String) {
                final cleaned = val
                    .replaceAll('{', '')
                    .replaceAll('}', '')
                    .replaceAll('"', '');
                for (final s in cleaned.split(',')) {
                  final t = s.trim();
                  if (t.isNotEmpty) itemNames.add(t);
                }
              }
            }

            parseList(pRow['noi_that_san_co']);
            parseList(pRow['tien_ich']);

            if (itemNames.isNotEmpty) {
              int idx = 1;
              list = itemNames.map((name) {
                final itemMap = {
                  'ma_tai_san': 'TS_${widget.maPhong}_${idx++}',
                  'ten_tai_san': name,
                  'so_luong': 1,
                  'tinh_trang': 'Hoạt động tốt',
                  'thuong_hieu': '',
                  'ma_phong': widget.maPhong,
                };
                return itemMap;
              }).toList();
            }
          }
        } catch (ePhong) {
          debugPrint('Lỗi đọc nội thất từ bảng phong: $ePhong');
        }
      }

      // Fallback danh mục trang thiết bị tiêu chuẩn phòng nếu cả 2 nguồn đều trống
      if (list.isEmpty) {
        final standardItems = [
          'Máy lạnh Inverter',
          'Tủ lạnh riêng 130L',
          'Bình nóng lạnh Ariston',
          'Giường gỗ & Nệm cao su',
          'Kệ bếp nấu ăn & Bồn rửa inox',
          'Quạt trần / Quạt treo tường',
        ];
        int idx = 1;
        list = standardItems.map((name) {
          return {
            'ma_tai_san': 'TS_${widget.maPhong}_${idx++}',
            'ten_tai_san': name,
            'so_luong': 1,
            'tinh_trang': 'Hoạt động tốt',
            'thuong_hieu': '',
            'ma_phong': widget.maPhong,
          };
        }).toList();
      }

      setState(() {
        _danhSachTaiSan = list;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Lỗi tải danh sách tài sản phòng: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _xacNhanBanGiao() async {
    if (!_camKetKiemTra) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Chưa xác nhận cam kết',
        noiDung:
            'Vui lòng tích cam kết đã kiểm tra tình trạng tài sản và trang thiết bị bàn giao!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final nowStr = DateTime.now().toIso8601String();

      // 1. CẬP NHẬT BẢNG hop_dong: da_xac_nhan_ban_giao = true
      await db
          .from('hop_dong')
          .update({
            'da_xac_nhan_ban_giao': true,
            'ngay_xac_nhan_ban_giao': nowStr,
          })
          .eq('ma_hop_dong', widget.maHopDong);

      // 2. LẤY VAI TRÒ TỪ chi_tiet_hop_dong_khach_thue GÁN XUỐNG tai_khoan
      String vaiTroGan = 'KhachThue';
      try {
        final cthd = await db
            .from('chi_tiet_hop_dong_khach_thue')
            .select('vai_tro')
            .eq('ma_hop_dong', widget.maHopDong)
            .eq('ma_khach', widget.maKhach)
            .maybeSingle();

        if (cthd != null && cthd['vai_tro'] != null) {
          vaiTroGan = cthd['vai_tro'].toString();
        } else {
          // Kiểm tra nếu là người ký đại diện trong hop_dong
          final hdCheck = await db
              .from('hop_dong')
              .select('ma_khach_dai_dien')
              .eq('ma_hop_dong', widget.maHopDong)
              .maybeSingle();
          if (hdCheck?['ma_khach_dai_dien']?.toString() == widget.maKhach) {
            vaiTroGan = 'Đại diện hợp đồng';
          }
        }
      } catch (e) {
        debugPrint('Lỗi truy vấn vai trò hợp đồng: $e');
        vaiTroGan = 'Đại diện hợp đồng';
      }

      // Cập nhật vai trò xuống bảng tai_khoan
      await db
          .from('tai_khoan')
          .update({'vai_tro': vaiTroGan})
          .eq('ma_tai_khoan', widget.user.maTaiKhoan);

      // Cập nhật session user trong app
      final updatedUser = widget.user.copyWith(vaiTro: vaiTroGan);
      await AuthService.updateCurrentUser(updatedUser);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Hiển thị Popup xác nhận bàn giao thành công & chuyển sang bước Chỉnh trang cá nhân
      _showSuccessDialog(updatedUser, vaiTroGan);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi xác nhận bàn giao',
          noiDung: 'Lỗi khi xác nhận bàn giao: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  void _showSuccessDialog(UserModel updatedUser, String vaiTro) {
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
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Xác Nhận Bàn Giao Thành Công!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Đã hoàn tất bàn giao tài sản phòng ${widget.maPhong}. Hệ thống đã đồng bộ vai trò "$vaiTro" xuống tài khoản của bạn.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF38BDF8)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_pin_rounded,
                        size: 18,
                        color: Color(0xFF0369A1),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Bước tiếp theo: Cập nhật trang cá nhân',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      // Chuyển sang màn hình Cập nhật thông tin cá nhân
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManHinhCapNhatThongTinCaNhan(
                            user: updatedUser,
                            maKhach: widget.maKhach,
                            maHopDong: widget.maHopDong,
                            maPhong: widget.maPhong,
                            khachThueData: widget.khachThueData,
                          ),
                        ),
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
                      'Cập nhật thông tin cá nhân & Xe →',
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoTenKhach =
        widget.khachThueData['ho_ten_khach']?.toString() ??
        widget.user.tenHienThi;
    final soDtKhach =
        widget.khachThueData['so_dt']?.toString() ?? widget.user.tenDangNhap;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 19,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Biên Bản Bàn Giao Tài Sản',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              _daXacNhanBanGiao ? 28 : 90,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner nếu đã xác nhận bàn giao trước đó
                if (_daXacNhanBanGiao) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF86EFAC)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF16A34A),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ĐÃ XÁC NHẬN BÀN GIAO THÀNH CÔNG',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _ngayXacNhanBanGiao != null
                                    ? 'Cư dân đã kiểm tra và nhận bàn giao toàn bộ thiết bị phòng ngày ${FormatUtils.formatDate(_ngayXacNhanBanGiao)}.'
                                    : 'Biên bản bàn giao đã được ký nhận thành công và có hiệu lực đầy đủ.',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF166534),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Khung biên bản trang trọng
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text(
                        'Độc lập - Tự do - Hạnh phúc',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'BIÊN BẢN BÀN GIAO TRANG THIẾT BỊ & TÀI SẢN',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: _primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Phòng: ${widget.maPhong} • Hợp đồng: ${widget.maHopDong}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: const [
                          Icon(
                            Icons.business_rounded,
                            size: 16,
                            color: _primary,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Bên giao:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'BQL Nhà Trọ Kiêu Giang',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_rounded,
                            size: 16,
                            color: _primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Bên nhận:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$hoTenKhach ($soDtKhach)',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Danh mục tài sản từ bảng tai_san (Đã fix lỗi tràn màn hình)
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_rounded,
                      color: _primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Trang Thiết Bị Bàn Giao',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_danhSachTaiSan.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_danhSachTaiSan.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 11,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Mặc định phòng',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: _primary),
                    ),
                  )
                else if (_danhSachTaiSan.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Center(
                      child: Text(
                        'Phòng hiện chưa có danh mục thiết bị cụ thể.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < _danhSachTaiSan.length; i++)
                        _buildTaiSanItem(i, _danhSachTaiSan[i]),
                    ],
                  ),

                const SizedBox(height: 16),

                // Ghi chú của khách khi nhận phòng
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.edit_note_rounded,
                            color: _primary,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Ghi chú / Nhận xét của cư dân khi nhận phòng (Tùy chọn)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _ghiChuController,
                        readOnly: _daXacNhanBanGiao,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              'Ví dụ: Phòng sạch đẹp, toàn bộ thiết bị hoạt động bình thường...',
                          hintStyle: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Checkbox cam kết & Xác nhận của cư dân (Nếu đã xác nhận thì hiển thị dạng đã ký)
                if (_daXacNhanBanGiao)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFA7F3D0),
                        width: 1.2,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF16A34A),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cư dân đã xác nhận nhận bàn giao',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Đã kiểm tra nguyên trạng 100% trang thiết bị và cam kết bảo quản trong suốt thời gian thuê phòng.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF166534),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_isDaiDien)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF86EFAC),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF16A34A,
                          ).withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Transform.scale(
                          scale: 1.15,
                          child: Checkbox(
                            value: _camKetKiemTra,
                            onChanged: (val) =>
                                setState(() => _camKetKiemTra = val ?? false),
                            activeColor: const Color(0xFF16A34A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cư dân xác nhận nhận bàn giao tài sản',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Tôi xác nhận đã nhận bàn giao đầy đủ toàn bộ trang thiết bị phòng đúng theo danh mục mặc định trên trong tình trạng hoạt động tốt. Tôi cam kết giữ gìn và bảo quản tài sản trong suốt thời gian thuê.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF166534),
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFF09638E),
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Quyền ký nhận bàn giao',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _tenNguoiDaiDien != null
                                    ? 'Bạn là thành viên ở cùng phòng. Biên bản bàn giao tài sản này sẽ do Người đại diện hợp đồng ($_tenNguoiDaiDien) kiểm tra và ký xác nhận với Ban Quản Lý.'
                                    : 'Bạn là thành viên ở cùng phòng. Biên bản bàn giao tài sản này chỉ do Người đại diện hợp đồng kiểm tra và ký xác nhận với Ban Quản Lý.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                  height: 1.45,
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

          // Bottom Bar: Nút Xác Nhận Bàn Giao Của Cư Dân (Chỉ hiển thị khi CHƯA xác nhận và là Người đại diện)
          if (!_daXacNhanBanGiao && _isDaiDien)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _xacNhanBanGiao,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 2,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Cư Dân Xác Nhận Nhận Bàn Giao ✓',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
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

  IconData _getIconForTaiSan(String ten) {
    final t = ten.toLowerCase();
    if (t.contains('lạnh') || t.contains('điều hòa'))
      return Icons.ac_unit_rounded;
    if (t.contains('tủ lạnh')) return Icons.kitchen_rounded;
    if (t.contains('nóng lạnh') || t.contains('nước nóng'))
      return Icons.water_drop_rounded;
    if (t.contains('giường') || t.contains('nệm')) return Icons.bed_rounded;
    if (t.contains('tủ') || t.contains('quần áo'))
      return Icons.checkroom_rounded;
    if (t.contains('bếp') || t.contains('kệ bếp') || t.contains('nấu'))
      return Icons.countertops_rounded;
    if (t.contains('quạt')) return Icons.mode_fan_off_rounded;
    if (t.contains('khóa') || t.contains('chìa')) return Icons.vpn_key_rounded;
    if (t.contains('bàn') || t.contains('ghế'))
      return Icons.table_restaurant_rounded;
    if (t.contains('giặt')) return Icons.local_laundry_service_rounded;
    if (t.contains('đèn')) return Icons.lightbulb_rounded;
    if (t.contains('wifi') || t.contains('router')) return Icons.wifi_rounded;
    return Icons.inventory_2_rounded;
  }

  Color _getColorForTaiSan(String ten) {
    final t = ten.toLowerCase();
    if (t.contains('lạnh') || t.contains('điều hòa'))
      return const Color(0xFF0284C7);
    if (t.contains('tủ lạnh')) return const Color(0xFF0D9488);
    if (t.contains('nóng lạnh') || t.contains('nước nóng'))
      return const Color(0xFFEA580C);
    if (t.contains('giường') || t.contains('nệm'))
      return const Color(0xFF7C3AED);
    if (t.contains('tủ') || t.contains('quần áo'))
      return const Color(0xFFD97706);
    if (t.contains('bếp') || t.contains('kệ')) return const Color(0xFFE11D48);
    if (t.contains('quạt')) return const Color(0xFF059669);
    return const Color(0xFF09638E);
  }

  Widget _buildTaiSanItem(int index, Map<String, dynamic> item) {
    final ten = item['ten_tai_san']?.toString() ?? 'Thiết bị';
    final soLuong = item['so_luong'] ?? 1;
    final tinhTrang = item['tinh_trang']?.toString() ?? 'Hoạt động tốt';
    final thuongHieu = item['thuong_hieu']?.toString() ?? '';
    final color = _getColorForTaiSan(ten);
    final icon = _getIconForTaiSan(ten);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon thiết bị với nền màu chuyên biệt
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Center(child: Icon(icon, color: color, size: 22)),
          ),
          const SizedBox(width: 12),

          // Tên và thông số thiết bị
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ten,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    // Badge Tình trạng Hoạt động tốt
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 12,
                            color: Color(0xFF10B981),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tinhTrang,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Số lượng: $soLuong',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                    if (thuongHieu.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              size: 11,
                              color: Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              thuongHieu,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

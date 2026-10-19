import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/core/utils/LienHeHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhTrangChuKhach.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhBaoSuCo.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhBienBanBanGiaoTaiSan.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChamDutHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiSoDienNuoc.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChinhSuaHoSo.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChuyenPhongThanhCong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhDangKyKhachQuaDem.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhGiaHanHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuChuyenPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuGiaHanHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuHoaDon.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuLuuTru.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhMatKhauPin.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToan.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTimKiemChuyenPhong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantHomeScreen extends StatefulWidget {
  final String? tenantName;
  final String? roomNumber;
  final int initialTabIndex;

  const TenantHomeScreen({
    super.key,
    this.tenantName,
    this.roomNumber,
    this.initialTabIndex = 0,
  });

  @override
  State<TenantHomeScreen> createState() => _TenantHomeScreenState();
}

class _TenantHomeScreenState extends State<TenantHomeScreen>
    with TickerProviderStateMixin {
  late int _selectedTabIndex;

  // ─── Animations cho Thẻ Cư Dân (Hero Room Card) ────────────
  late AnimationController _waveController;
  late Animation<double> _waveAnimation;

  late AnimationController _beaconPulseController;
  late Animation<double> _beaconScaleAnimation;
  late Animation<double> _beaconOpacityAnimation;

  late AnimationController _cardGlowController;
  late Animation<double> _cardGlowAnimation;

  // ─── Dữ liệu thực từ Supabase ──────────────────────────────
  bool _isLoading = true;
  String? _loadError;

  HopDongModel? _hopDong; // hợp đồng đang hiệu lực
  RoomModel? _phong; // thông tin phòng
  HoaDonModel? _hoaDonMoiNhat; // hóa đơn chưa / đã thanh toán gần nhất
  List<HoaDonModel> _danhSachHoaDon =
      []; // toàn bộ danh sách hóa đơn từ Supabase
  List<KhachThueModel> _thanhVienPhong = [];
  List<Map<String, dynamic>> _chiTietHoaDon = [];
  List<Map<String, dynamic>> _danhSachSuCo =
      []; // danh sách sự cố từ bảng su_co_bao_tri
  Map<String, dynamic>? _khachThueData; // thông tin cư dân chi tiết
  List<Map<String, dynamic>> _danhSachTaiSan =
      []; // danh sách tài sản phòng từ Supabase
  List<Map<String, dynamic>> _danhSachPhuongTien =
      []; // danh sách phương tiện xe của cư dân từ Supabase
  bool _thongBaoUngDung = true; // Trạng thái nhận thông báo ứng dụng
  bool _isEkycExpanded = false; // Thu gọn/mở rộng chi tiết hồ sơ định danh cá nhân

  // ─── Realtime & Đồng Bộ Phê Duyệt Tự Động ──────────────────
  RealtimeChannel? _tenantRealtimeChannel;
  Timer? _realtimePollTimer;
  final Set<String> _notifiedApprovalKeys = {};
  String? _lastPhuLucStatus;
  String? _lastYccpStatus;
  final Map<String, String> _lastSuCoStatuses = {};
  final Map<String, String> _lastGuestStatuses = {};

  // ─── Thông báo nổi Heads-Up (Dynamic Island) & Trung tâm thông báo ───
  late AnimationController _bannerAnimController;
  late Animation<Offset> _bannerSlideAnimation;
  Map<String, dynamic>? _floatingNotification;
  Timer? _floatingNotificationTimer;
  final List<Map<String, dynamic>> _danhSachThongBao = [];
  final Set<String> _danhSachIdDaDoc = {};
  int get _soThongBaoChuaDoc => SystemNotificationService.soThongBaoChuaDoc;

  int get _soHoaDonChuaThanhToan {
    // Chỉ đếm hóa đơn BQL đã gửi (loại trừ 'Chờ gửi' — hóa đơn chưa được BQL xác nhận)
    return _danhSachHoaDon
        .where(
          (h) =>
              h.trangThai != 'Đã thanh toán' &&
              h.trangThai != 'Chờ gửi' &&
              h.tongTien > 0,
        )
        .length;
  }

  // ─── Getters hiển thị ──────────────────────────────────────
  String get displayName {
    final user = AuthService.currentUser;
    if (user != null) return user.tenHienThi;
    return widget.tenantName ?? 'Cư dân';
  }

  String get roomDisplay {
    if (_phong != null) {
      return '${_phong!.tenHienThi} • ${_phong!.toaNha} (Tầng ${_phong!.tang})';
    }
    return widget.roomNumber != null
        ? 'Phòng ${widget.roomNumber}'
        : 'Đang tải...';
  }

  String get maPhong => _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
  String get maHopDong => _hopDong?.maHopDong ?? '';

  /// Kiểm tra xem tài khoản đang đăng nhập có phải là Người đại diện (Trưởng phòng) hay không
  bool get _isNguoiDaiDien {
    final user = AuthService.currentUser;
    // 0. Quản trị viên hoặc Chủ trọ luôn có toàn quyền
    final authRole = (user?.vaiTro ?? '').toLowerCase();
    if (authRole.contains('admin') || authRole.contains('chutro') || authRole.contains('quanly')) {
      return true;
    }

    // 1. So khớp mã khách đang đăng nhập với mã khách đại diện của hợp đồng
    final currentMaKhach = _khachThueData?['ma_khach']?.toString();
    final maDaiDien = _hopDong?.maKhachDaiDien;
    if (currentMaKhach != null && currentMaKhach.isNotEmpty &&
        maDaiDien != null && maDaiDien.isNotEmpty) {
      return currentMaKhach == maDaiDien;
    }

    // 2. Kiểm tra vai trò từ chi_tiet_hop_dong_khach_thue (_thanhVienPhong)
    final String tenCuDan = _khachThueData?['ho_ten_khach']?.toString().isNotEmpty == true
        ? _khachThueData!['ho_ten_khach'].toString()
        : displayName;

    final myMember = _thanhVienPhong.where((tv) =>
        (currentMaKhach != null && currentMaKhach.isNotEmpty && tv.maKhach == currentMaKhach) ||
        (user != null && tv.maTaiKhoan != null && tv.maTaiKhoan == user.maTaiKhoan) ||
        (tv.hoTenKhach.trim().toLowerCase() == tenCuDan.trim().toLowerCase())
    ).firstOrNull;

    if (myMember != null && myMember.vaiTro.isNotEmpty) {
      final v = myMember.vaiTro.toLowerCase();
      if (v.contains('đại diện') || v.contains('daidien') || v.contains('trưởng phòng') || v.contains('truongphong') || v.contains('landlord')) {
        return true;
      }
      if (v.contains('ở cùng') || v.contains('ocung') || v.contains('thành viên') || v.contains('thanhvien')) {
        return false;
      }
    }

    // 3. Kiểm tra vai trò từ bảng tài khoản
    if (authRole.contains('truongphong') || authRole.contains('daidien')) {
      return true;
    }
    if (authRole.contains('thanhvien') || authRole.contains('banocung') || authRole.contains('ocung')) {
      return false;
    }

    // 4. Nếu phòng chỉ có 1 người ở thì người đó chính là người đại diện
    if (_thanhVienPhong.length == 1) return true;

    // 5. Nếu phòng có nhiều hơn 1 người và trong phòng đã xác định có người khác làm đại diện
    if (_thanhVienPhong.length > 1) {
      final hasOtherDaiDien = _thanhVienPhong.any((tv) =>
          (maDaiDien != null && maDaiDien.isNotEmpty && tv.maKhach == maDaiDien) ||
          tv.vaiTro.toLowerCase().contains('đại diện') ||
          tv.vaiTro.toLowerCase().contains('trưởng phòng')
      );
      if (hasOtherDaiDien) return false;
    }

    return true;
  }

  /// Hộp thoại thông báo khi bạn cùng phòng cố tình thực hiện thao tác dành riêng cho người đại diện
  void _thongBaoKhongCoQuyen({required String hanhDong}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                color: Color(0xFFD97706),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Quyền Hạn Đại Diện',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn đang đăng nhập với tư cách Thành viên phòng (Bạn cùng phòng).',
              style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF09638E)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Theo quy định của Ban Quản Lý, thủ tục "$hanhDong" chỉ có Người đại diện (Trưởng phòng đứng tên trên hợp đồng) mới có thẩm quyền thực hiện.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vui lòng báo cho Người đại diện của phòng bạn để tiến hành thủ tục này nhé!',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.3),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Đã hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;

    // 1. Animation vẫy tay 👋 mượt mà, tự nhiên
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _waveAnimation = Tween<double>(begin: -0.15, end: 0.18).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOutSine),
    );

    // 2. Animation radar beacon phát sáng cho trạng thái ĐANG THUÊ
    _beaconPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _beaconScaleAnimation = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(
        parent: _beaconPulseController,
        curve: Curves.easeOutQuad,
      ),
    );

    _beaconOpacityAnimation = Tween<double>(begin: 0.75, end: 0.0).animate(
      CurvedAnimation(
        parent: _beaconPulseController,
        curve: Curves.easeOutQuad,
      ),
    );

    // 3. Animation hiệu ứng viền phát sáng nhẹ nhàng
    _cardGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _cardGlowAnimation = Tween<double>(begin: 0.12, end: 0.32).animate(
      CurvedAnimation(parent: _cardGlowController, curve: Curves.easeInOut),
    );

    // 4. Animation banner thông báo nổi kiểu Dynamic Island trên điện thoại
    _bannerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bannerSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _bannerAnimController,
            curve: Curves.easeOutBack,
          ),
        );

    // Khởi tạo danh sách thông báo ban đầu
    _khoiTaoThongBaoMacDinh();

    // Khởi tạo cài đặt thông báo ứng dụng đã lưu
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _thongBaoUngDung =
              prefs.getBool('kieugiang_thong_bao_ung_dung') ?? true;
          SystemNotificationService.isNotificationEnabled = _thongBaoUngDung;
        });
      }
    });

    // Xin quyền gửi thông báo hệ thống khi thoát app / chuyển tab
    SystemNotificationService.requestPermission();

    _fetchTenantData();
  }

  void _khoiTaoThongBaoMacDinh() {
    SystemNotificationService.addInAppNotification(
      id: 'tb_default_1',
      tieuDe: 'Chào mừng cư dân mới đến với Kiêu Giang House!',
      noiDung:
          'Chúc bạn có một không gian sống văn minh, tiện nghi và thoải mái.',
      loai: 'toa_nha',
      thoiGian: DateTime.now().subtract(const Duration(hours: 2)),
    );
    SystemNotificationService.addInAppNotification(
      id: 'tb_default_2',
      tieuDe: 'Lịch sục rửa bồn nước tòa nhà chiều nay',
      noiDung:
          'Quý cư dân lưu ý sục rửa bồn nước chiều nay từ 13h30 đến 15h30.',
      loai: 'toa_nha',
      thoiGian: DateTime.now().subtract(const Duration(hours: 5)),
    );
  }

  /// Đồng bộ toàn bộ thông báo thực từ Supabase vào trung tâm chuông thông báo
  Future<void> _dongBoDanhSachThongBao() async {
    try {
      final db = Supabase.instance.client;
      final activeHd =
          _hopDong?.maHopDong ?? (maHopDong.isNotEmpty ? maHopDong : 'HD001');
      final activeRoom = _hopDong?.maPhong ?? (widget.roomNumber ?? 'P203');

      final List<Map<String, dynamic>> danhSachMoi = [];

      // 1. Lấy thông tin chuyển phòng từ yeu_cau_chuyen_phong
      try {
        final yccpRows = await db
            .from('yeu_cau_chuyen_phong')
            .select()
            .or('ma_hop_dong_ht.eq.$activeHd,ma_phong_cu.eq.$activeRoom')
            .order('ngay_tao', ascending: false);

        for (final row in (yccpRows as List)) {
          final maYeuCau = row['ma_yeu_cau']?.toString() ?? '';
          final status = row['trang_thai_tien_do']?.toString() ?? '';
          final maPhongCu = row['ma_phong_cu']?.toString() ?? activeRoom;
          final maPhongMoi = row['ma_phong_moi']?.toString() ?? '';
          final idNotif = 'yccp_${maYeuCau}_$status';

          String tieuDe = '';
          String noiDung = '';
          bool isError = false;

          void moManHinhChiTietYccp() async {
            // Query giá thực tế của phòng mới từ DB thay vì hardcode
            num giaThuePhongMoi = _hopDong?.giaThueThaoThuan ?? 3800000;
            num tienDatCocPhongMoi = giaThuePhongMoi;
            int tangPhongMoi = 1;
            int dienTichPhongMoi = 22;
            String toaNhaPhongMoi = 'Kiêu Giang';

            try {
              final phongMoiRes = await Supabase.instance.client
                  .from('phong')
                  .select('gia_thue, tien_dat_coc, tang, dien_tich, toa_nha')
                  .eq('ma_phong', maPhongMoi)
                  .maybeSingle();
              if (phongMoiRes != null) {
                giaThuePhongMoi =
                    (phongMoiRes['gia_thue'] as num?) ?? giaThuePhongMoi;
                tienDatCocPhongMoi =
                    (phongMoiRes['tien_dat_coc'] as num?) ?? giaThuePhongMoi;
                tangPhongMoi = (phongMoiRes['tang'] as num?)?.toInt() ?? 1;
                dienTichPhongMoi =
                    (phongMoiRes['dien_tich'] as num?)?.toInt() ?? 22;
                toaNhaPhongMoi =
                    phongMoiRes['toa_nha']?.toString() ?? 'Kiêu Giang';
              }
            } catch (e) {
              debugPrint('[YCCP] Lỗi query giá phòng mới $maPhongMoi: ');
            }

            if (!mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RoomTransferSuccessScreen(
                  ticketCode: maYeuCau,
                  targetRoom: {
                    'maPhong': maPhongMoi,
                    'toaNha': toaNhaPhongMoi,
                    'tang': tangPhongMoi,
                    'dienTich': dienTichPhongMoi,
                    'giaThue': giaThuePhongMoi,
                    'tienDatCoc': tienDatCocPhongMoi,
                  },
                  currentRoomNumber: maPhongCu,
                  currentPrice:
                      (row['tien_coc_bao_luu'] as num?) ??
                      _hopDong?.giaThueThaoThuan ??
                      3800000,
                  moveInDateFormatted: row['thoi_gian_hen'] ?? '',
                  reason: 'Chuyển phòng theo yêu cầu',
                  note: '',
                ),
              ),
            );
          }

          if (status == 'Chờ khách xác nhận' || status == 'Đã kiểm tra') {
            final huHai = (row['tien_hu_hai_cu'] as num?)?.toDouble() ?? 0.0;
            final dienNuoc =
                (row['tien_dien_nuoc_cu'] as num?)?.toDouble() ?? 0.0;
            tieuDe = '📋 Biên Bản Nghiệm Thu Phòng $maPhongCu Sẵn Sàng';
            if (huHai > 0 || dienNuoc > 0) {
              noiDung =
                  'BQL đã kiểm tra thiết bị phòng $maPhongCu. Có phát sinh chi phí điện nước/khấu trừ. Vui lòng bấm vào xem và xác nhận biên bản!';
            } else {
              noiDung =
                  '100% thiết bị phòng $maPhongCu đạt chuẩn. Vui lòng bấm vào xác nhận biên bản để gửi lên chủ trọ duyệt!';
            }
          } else if (status == 'Đang xử lý') {
            tieuDe = '⏳ BQL Đang Lên Lịch Nghiệm Thu Phòng $maPhongCu';
            noiDung =
                'BQL Kiều Giang đã tiếp nhận yêu cầu chuyển sang phòng $maPhongMoi và đang sắp xếp lịch kiểm tra phòng cũ.';
          } else if (status == 'Chờ duyệt') {
            tieuDe = '📝 Yêu Cầu Chuyển Phòng Đang Chờ Duyệt';
            noiDung =
                'Yêu cầu chuyển từ phòng $maPhongCu sang phòng $maPhongMoi đã gửi thành công và đang chờ BQL tiếp nhận.';
          } else if (status == 'Khách đã xác nhận' ||
              status == 'Chờ chủ duyệt') {
            tieuDe = '📤 Đã Gửi Biên Bản Nghiệm Thu Cho Chủ Trọ';
            noiDung =
                'Bạn đã xác nhận biên bản nghiệm thu phòng $maPhongCu. Đang chờ chủ trọ duyệt chính thức.';
          } else if (status == 'Đã duyệt' || status == 'Hoàn tất') {
            tieuDe = '🎉 BQL Đã Phê Duyệt Chuyển Phòng $maPhongMoi!';
            noiDung =
                'Yêu cầu chuyển phòng đã hoàn tất. Phụ lục hợp đồng mới đã có hiệu lực!';
          } else if (status == 'Từ chối') {
            tieuDe = '⚠️ Yêu Cầu Chuyển Phòng Bị Từ Chối';
            noiDung =
                'BQL chưa thể duyệt chuyển sang phòng $maPhongMoi. Vui lòng liên hệ BQL.';
            isError = true;
          }

          if (tieuDe.isNotEmpty) {
            final daDoc =
                _danhSachIdDaDoc.contains(idNotif) || (status == 'Chờ duyệt');
            danhSachMoi.add({
              'id': idNotif,
              'tieu_de': tieuDe,
              'noi_dung': noiDung,
              'loai': 'chuyen_phong',
              'thoi_gian':
                  DateTime.tryParse(row['ngay_tao']?.toString() ?? '') ??
                  DateTime.now(),
              'da_doc': daDoc,
              'is_error': isError,
              'on_xem': moManHinhChiTietYccp,
            });
          }
        }
      } catch (e) {
        debugPrint('[NOTIF] Lỗi tải yccp: ');
      }

      // 2. Lấy thông báo hóa đơn chưa thanh toán
      // Chỉ push thông báo khi BQL đã xác nhận gửi (trang_thai != 'Chờ gửi')
      if (_hoaDonMoiNhat != null &&
          _hoaDonMoiNhat!.trangThai != 'Đã thanh toán' &&
          _hoaDonMoiNhat!.trangThai != 'Chờ gửi' &&
          _hoaDonMoiNhat!.tongTien > 0) {
        final idHd = 'hd_${_hoaDonMoiNhat!.maHoaDon}';
        final daDoc = _danhSachIdDaDoc.contains(idHd);
        final isOverdue = _hoaDonMoiNhat!.soNgayConLai < 0;
        final overdueDays = -_hoaDonMoiNhat!.soNgayConLai;
        final isPartialDebt = _hoaDonMoiNhat!.trangThai == 'Thanh toán một phần';

        if (isOverdue) {
          // Bắn thông báo chuông và banner hệ thống nhắc nhở quá hạn
          if (overdueDays >= 10) {
            SystemNotificationService.show(
              title: isPartialDebt
                  ? '🔒 ĐÃ KHÓA VÂN TAY (Nợ Đợt 2 trễ hạn $overdueDays ngày)'
                  : '🔒 ĐÃ KHÓA VÂN TAY (Trễ hạn $overdueDays ngày)',
              body: isPartialDebt
                  ? 'Vân tay của bạn ĐÃ BỊ TẠM KHÓA do nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn $overdueDays ngày. Vui lòng thanh toán hoặc liên hệ BQL qua SĐT/Zalo ${LienHeHelper.defaultHotlineDisplay} để được hỗ trợ mở khóa.'
                  : 'Vân tay của bạn ĐÃ BỊ TẠM KHÓA do hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn $overdueDays ngày. Vui lòng thanh toán hoặc liên hệ BQL qua SĐT/Zalo ${LienHeHelper.defaultHotlineDisplay} để được hỗ trợ mở khóa.',
              tag: 'bill_locked_${_hoaDonMoiNhat!.maHoaDon}',
              loai: 'hoa_don',
            );
          } else if (overdueDays >= 5) {
            SystemNotificationService.show(
              title: isPartialDebt
                  ? '⚠️ CẢNH BÁO TRỄ HẠN ĐỢT 2 $overdueDays NGÀY: SẮP KHÓA VÂN TAY'
                  : '⚠️ CẢNH BÁO TRỄ HẠN $overdueDays NGÀY: SẮP KHÓA VÂN TAY',
              body: isPartialDebt
                  ? 'Khoản nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} đã quá hạn $overdueDays ngày. Nếu không tiếp tục đóng tiền, hệ thống sẽ tạm khóa vân tay ra vào phòng của bạn. Vui lòng thanh toán ngay!'
                  : 'Hóa đơn ${_hoaDonMoiNhat!.maHoaDon} đã quá hạn $overdueDays ngày. Nếu không tiếp tục đóng tiền, hệ thống sẽ tạm khóa vân tay ra vào phòng của bạn. Vui lòng thanh toán ngay!',
              tag: 'bill_warn_5d_${_hoaDonMoiNhat!.maHoaDon}',
              loai: 'hoa_don',
            );
          } else {
            SystemNotificationService.show(
              title: isPartialDebt
                  ? '⚠️ Nợ Đợt 2 quá hạn $overdueDays ngày'
                  : '⚠️ Hóa đơn quá hạn $overdueDays ngày',
              body: isPartialDebt
                  ? 'Khoản nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} đã trễ hạn từ ${_hoaDonMoiNhat!.hanDongTienFormatted}. Số tiền nợ còn lại: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Vui lòng thanh toán sớm.'
                  : 'Hóa đơn ${_hoaDonMoiNhat!.maHoaDon} đã trễ hạn từ ${_hoaDonMoiNhat!.hanDongTienFormatted}. Tổng cần đóng: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Vui lòng thanh toán sớm.',
              tag: 'bill_overdue_${_hoaDonMoiNhat!.maHoaDon}',
              loai: 'hoa_don',
            );
          }
        }

        String tieuDeNotif;
        String noiDungNotif;
        if (!isOverdue) {
          tieuDeNotif = isPartialDebt
              ? '💵 Nhắc Nợ Tiền Phòng Đợt 2'
              : '💵 Hóa Đơn Tiền Phòng & Dịch Vụ';
          noiDungNotif = isPartialDebt
              ? 'Khoản nợ Đợt 2 (${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}) chưa thanh toán. Hạn nộp: ${_hoaDonMoiNhat!.hanDongTienFormatted}.'
              : 'Hóa đơn tháng này (${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}) chưa thanh toán. Hạn nộp: ${_hoaDonMoiNhat!.hanDongTienFormatted}.';
        } else if (overdueDays >= 10) {
          tieuDeNotif = isPartialDebt
              ? '🔒 ĐÃ KHÓA VÂN TAY (NỢ ĐỢT 2 QUÁ HẠN $overdueDays NGÀY)'
              : '🔒 ĐÃ KHÓA VÂN TAY (QUÁ HẠN $overdueDays NGÀY)';
          noiDungNotif = isPartialDebt
              ? 'Vân tay ra vào phòng ĐÃ BỊ TẠM KHÓA do nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} trễ hạn $overdueDays ngày. Vui lòng liên hệ BQL qua SĐT hoặc Zalo: ${LienHeHelper.defaultHotlineDisplay} (hoặc thanh toán để mở lại).'
              : 'Vân tay ra vào phòng ĐÃ BỊ TẠM KHÓA do hóa đơn ${_hoaDonMoiNhat!.maHoaDon} trễ hạn $overdueDays ngày. Vui lòng liên hệ BQL qua SĐT hoặc Zalo: ${LienHeHelper.defaultHotlineDisplay} (hoặc thanh toán để mở lại).';
        } else if (overdueDays >= 5) {
          tieuDeNotif = isPartialDebt
              ? '⚠️ TRỄ HẠN ĐỢT 2 $overdueDays NGÀY (CẢNH BÁO KHÓA VÂN TAY)'
              : '⚠️ TRỄ HẠN $overdueDays NGÀY (CẢNH BÁO KHÓA VÂN TAY)';
          noiDungNotif = isPartialDebt
              ? 'Khoản nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn $overdueDays ngày. Nếu không tiếp tục đóng tiền, BQL sẽ tạm khóa vân tay ra vào. Số tiền còn nợ: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Bấm để thanh toán.'
              : 'Hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn $overdueDays ngày. Nếu không tiếp tục đóng tiền, BQL sẽ tạm khóa vân tay ra vào. Tổng tiền: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Bấm để thanh toán.';
        } else {
          tieuDeNotif = isPartialDebt
              ? '⚠️ NỢ ĐỢT 2 QUÁ HẠN $overdueDays NGÀY'
              : '⚠️ HÓA ĐƠN QUÁ HẠN $overdueDays NGÀY';
          noiDungNotif = isPartialDebt
              ? 'Khoản nợ Đợt 2 hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn từ ${_hoaDonMoiNhat!.hanDongTienFormatted}. Số tiền còn nợ: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Bấm để thanh toán.'
              : 'Hóa đơn ${_hoaDonMoiNhat!.maHoaDon} quá hạn từ ${_hoaDonMoiNhat!.hanDongTienFormatted}. Tổng thanh toán: ${FormatUtils.currency(_hoaDonMoiNhat!.tongTien)}. Bấm để thanh toán.';
        }

        danhSachMoi.add({
          'id': idHd,
          'tieu_de': tieuDeNotif,
          'noi_dung': noiDungNotif,
          'loai': 'hoa_don',
          'thoi_gian': DateTime.now().subtract(const Duration(hours: 1)),
          'da_doc': daDoc,
          'is_error': isOverdue,
          'on_xem': () {
            if (overdueDays >= 10) {
              _showThongBaoKhoaVanTayModal(_hoaDonMoiNhat!);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    hoaDon: _hoaDonMoiNhat!,
                    tenPhong: 'Phòng $activeRoom',
                    onPaymentSuccess: (_) {
                      _fetchTenantData();
                    },
                  ),
                ),
              );
            }
          },
        });
      } else if (_hoaDonMoiNhat != null &&
          _hoaDonMoiNhat!.trangThai == 'Đã thanh toán') {
        final idHd = 'hd_paid_${_hoaDonMoiNhat!.maHoaDon}';
        final daDoc = _danhSachIdDaDoc.contains(idHd);
        danhSachMoi.add({
          'id': idHd,
          'tieu_de': '✅ Hóa Đơn Đã Được Thanh Toán',
          'noi_dung':
              'Hóa đơn tháng ${_hoaDonMoiNhat!.thangNam} (${FormatUtils.currency(_hoaDonMoiNhat!.tongTienGoc)}) đã được quyết toán thành công.',
          'loai': 'hoa_don',
          'thoi_gian': DateTime.now().subtract(const Duration(hours: 2)),
          'da_doc': daDoc,
          'is_error': false,
          'on_xem': () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentCompletedScreen(
                  hoaDon: _hoaDonMoiNhat!,
                  tenPhong: 'Phòng $activeRoom',
                  bankName: 'MB Bank (Quân Đội)',
                  transactionTime: _hoaDonMoiNhat!.hanDongTienFormatted,
                  amountPaid: _hoaDonMoiNhat!.tongTienGoc,
                ),
              ),
            );
          },
        });
      }

      // 3. Lấy thông báo sự cố bảo trì
      for (final sc in _danhSachSuCo) {
        final st = sc['trang_thai']?.toString() ?? '';
        final maSc = sc['ma_su_co']?.toString() ?? '';
        final tieuDeSc = sc['tieu_de']?.toString() ?? 'Sự cố bảo trì';
        if (st == 'Đã xử lý' || st == 'Đã hoàn thành') {
          final idSc = 'sc_${maSc}_$st';
          final daDoc = _danhSachIdDaDoc.contains(idSc);
          danhSachMoi.add({
            'id': idSc,
            'tieu_de': '🛠️ Sự Cố "$tieuDeSc" Đã Được Khắc Phục',
            'noi_dung':
                'Kỹ thuật viên đã xử lý xong sự cố của phòng $activeRoom. Bạn có thể kiểm tra lại tại phòng nhé!',
            'loai': 'su_co',
            'thoi_gian':
                DateTime.tryParse(sc['ngay_bao_cao']?.toString() ?? '') ??
                DateTime.now(),
            'da_doc': daDoc,
            'is_error': false,
            'on_xem': () => setState(() => _selectedTabIndex = 3),
          });
        }
      }

      // 3.5. Đồng bộ thông báo đăng ký khách lưu trú qua đêm từ Supabase
      try {
        final pDigits = activeRoom.replaceAll(RegExp(r'[^0-9]'), '');
        final guestNotifRes = await db
            .from('dang_ky_khach_qua_dem')
            .select()
            .or('ma_phong.eq.P$pDigits,ma_phong.eq.$pDigits,ma_phong.eq.$activeRoom')
            .order('tu_ngay', ascending: false)
            .limit(5);

        for (final g in (guestNotifRes as List)) {
          final st = g['trang_thai']?.toString() ?? '';
          final maDk = g['ma_dang_ky']?.toString() ?? '';
          final tenKhach = g['ho_ten_khach_ngoai']?.toString() ?? 'Khách';
          final tuNgay = g['tu_ngay']?.toString() ?? '';
          final denNgay = g['den_ngay']?.toString() ?? '';
          final idNotif = 'notif_guest_${maDk}_$st';
          final daDoc = _danhSachIdDaDoc.contains(idNotif) || (st == 'Chờ duyệt');

          String tieuDe = '';
          String noiDung = '';
          bool isError = false;
          int targetTab = 0;

          final stLower = st.toLowerCase();
          if (st == 'Đã duyệt' || stLower.contains('duyệt') || stLower.contains('duyet')) {
            tieuDe = '🎉 Chủ Trọ Đã Duyệt Khách Lưu Trú';
            noiDung =
                'Đơn đăng ký cho khách $tenKhach ($tuNgay đến $denNgay) phòng $activeRoom đã được chủ trọ duyệt thành công!';
            targetTab = 2;
          } else if (st == 'Từ chối' || stLower.contains('từ chối') || stLower.contains('tu choi')) {
            tieuDe = '⚠️ Đăng Ký Khách Bị Từ Chối';
            noiDung =
                'Chủ trọ chưa thể phê duyệt khách $tenKhach ($tuNgay đến $denNgay). Vui lòng liên hệ BQL.';
            isError = true;
            targetTab = 3;
          }

          if (tieuDe.isNotEmpty) {
            danhSachMoi.add({
              'id': idNotif,
              'tieu_de': tieuDe,
              'noi_dung': noiDung,
              'loai': 'khach_luu_tru',
              'thoi_gian': DateTime.tryParse(tuNgay) ?? DateTime.now(),
              'da_doc': daDoc,
              'is_error': isError,
              'on_xem': () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManHinhLichSuLuuTru(
                      tenPhong: activeRoom,
                      toaNha: _phong?.toaNha ?? 'Kiêu Giang',
                      initialTabIndex: targetTab,
                    ),
                  ),
                );
              },
            });
          }
        }
      } catch (e) {
        debugPrint('[NOTIF] Lỗi tải thông báo khách lưu trú: $e');
      }

      // 3.8. Đồng bộ thông báo hợp đồng thuê chưa ký (nếu chưa ký thì hiển thị, đã ký thì thôi)
      if (_hopDong != null && !_hopDong!.daKyBenB) {
        final idNotif = 'hd_chua_ky_${_hopDong!.maHopDong}';
        final daDoc = _danhSachIdDaDoc.contains(idNotif);
        danhSachMoi.add({
          'id': idNotif,
          'tieu_de': '📝 Hợp Đồng Thuê Chưa Ký Xác Nhận',
          'noi_dung':
              'Bạn chưa ký tên vào hợp đồng điện tử phòng $activeRoom. Vui lòng bấm vào để ký tay xác nhận hoàn tất hợp đồng.',
          'loai': 'hop_dong',
          'thoi_gian': DateTime.tryParse(_hopDong!.ngayKy) ?? DateTime.now(),
          'da_doc': daDoc,
          'is_error': true,
          'on_xem': () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ContractDetailScreen(
                  maHopDong: _hopDong!.maHopDong,
                ),
              ),
            ).then((_) => _fetchTenantData());
          },
        });
      }

      // 4. Thông báo tòa nhà mặc định
      danhSachMoi.addAll([
        {
          'id': 'tb_default_1',
          'tieu_de': 'Chào mừng cư dân mới đến với Kiêu Giang House!',
          'noi_dung':
              'Chúc bạn có một không gian sống văn minh, tiện nghi và thoải mái.',
          'loai': 'toa_nha',
          'thoi_gian': DateTime.now().subtract(const Duration(days: 1)),
          'da_doc': true,
          'is_error': false,
        },
        {
          'id': 'tb_default_2',
          'tieu_de': 'Lịch sục rửa bồn nước tòa nhà chiều nay',
          'noi_dung':
              'Quý cư dân lưu ý sục rửa bồn nước chiều nay từ 13h30 đến 15h30.',
          'loai': 'toa_nha',
          'thoi_gian': DateTime.now().subtract(const Duration(hours: 5)),
          'da_doc': true,
          'is_error': false,
        },
      ]);

      if (mounted) {
        for (final item in danhSachMoi) {
          SystemNotificationService.addInAppNotification(
            id: item['id']?.toString() ?? '',
            tieuDe: item['tieu_de']?.toString() ?? '',
            noiDung: item['noi_dung']?.toString() ?? '',
            loai: item['loai']?.toString() ?? 'thong_bao',
            isError: item['is_error'] == true,
            thoiGian: item['thoi_gian'] as DateTime?,
            onXem: item['on_xem'] as VoidCallback?,
          );
        }
        setState(() {
          _danhSachThongBao.clear();
          _danhSachThongBao.addAll(danhSachMoi);
        });
      }
    } catch (e) {
      debugPrint('[NOTIF] Lỗi đồng bộ thông báo: ');
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _beaconPulseController.dispose();
    _cardGlowController.dispose();
    _bannerAnimController.dispose();
    _floatingNotificationTimer?.cancel();
    _realtimePollTimer?.cancel();
    if (_tenantRealtimeChannel != null) {
      Supabase.instance.client.removeChannel(_tenantRealtimeChannel!);
    }
    super.dispose();
  }

  /// Tải toàn bộ dữ liệu cư dân từ Supabase theo tài khoản đăng nhập
  Future<void> _fetchTenantData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final db = Supabase.instance.client;
      final user = AuthService.currentUser;

      // ── 1. Tìm khách thuê theo ma_tai_khoan ─────────────────
      Map<String, dynamic>? khachThueRow;
      if (user != null && user.maTaiKhoan.isNotEmpty) {
        khachThueRow = await db
            .from('khach_thue')
            .select()
            .eq('ma_tai_khoan', user.maTaiKhoan)
            .maybeSingle();
      }

      // ── 2. Tìm hợp đồng đang hiệu lực ──────────────────────
      Map<String, dynamic>? hopDongRow;
      if (khachThueRow != null) {
        final maKhach = khachThueRow['ma_khach']?.toString() ?? '';
        // Tìm qua bảng chi_tiet_hop_dong_khach_thue
        final chiTietList = await db
            .from('chi_tiet_hop_dong_khach_thue')
            .select('ma_hop_dong')
            .eq('ma_khach', maKhach);

        if (chiTietList.isNotEmpty) {
          final maHopDongs = (chiTietList as List)
              .map((e) => e['ma_hop_dong']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList();

          if (maHopDongs.isNotEmpty) {
            hopDongRow = await db
                .from('hop_dong')
                .select()
                .inFilter('ma_hop_dong', maHopDongs)
                .eq('trang_thai', 'Còn hạn')
                .order('ngay_bd', ascending: false)
                .limit(1)
                .maybeSingle();
          }
        }
      }

      // fallback: lấy hợp đồng theo ma_hop_dong truyền vào widget
      hopDongRow ??= maHopDong.isNotEmpty
          ? await db
                .from('hop_dong')
                .select()
                .eq('ma_hop_dong', maHopDong)
                .maybeSingle()
          : null;

      if (hopDongRow == null && mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Không tìm thấy hợp đồng hiệu lực.';
        });
        return;
      }

      final hd = HopDongModel.fromJson(Map<String, dynamic>.from(hopDongRow!));

      // Fallback: nếu khachThueRow null theo ma_tai_khoan, tìm theo ma_khach_dai_dien của hợp đồng
      if (khachThueRow == null && hd.maKhachDaiDien.isNotEmpty) {
        try {
          khachThueRow = await db
              .from('khach_thue')
              .select()
              .eq('ma_khach', hd.maKhachDaiDien)
              .maybeSingle();
        } catch (_) {}
      }

      // ── 3. Tải thông tin phòng ───────────────────────────────
      final phongRow = await db
          .from('phong')
          .select()
          .eq('ma_phong', hd.maPhong)
          .maybeSingle();

      // ── 4. Tải danh sách hóa đơn từ Supabase ─────────────────
      final hoaDonRows = await db
          .from('hoa_don')
          .select()
          .eq('ma_hop_dong', hd.maHopDong)
          .order('ngay_lap', ascending: false);

      final List<HoaDonModel> allBills = (hoaDonRows as List)
          .map((r) => HoaDonModel.fromJson(Map<String, dynamic>.from(r)))
          .toList();

      // Ưu tiên hóa đơn BQL đã gửi mà chưa thanh toán
      // 'Chờ gửi' = BQL vừa tạo chưa xác nhận gửi → KHÔNG hiện cho khách
      final unpaidBill = allBills
          .where(
            (h) =>
                h.trangThai != 'Đã thanh toán' &&
                h.trangThai != 'Chờ gửi' &&
                h.tongTien > 0,
          )
          .firstOrNull;
      // latestBill: lấy hóa đơn mới nhất đã được gửi (bỏ qua 'Chờ gửi')
      final latestBill = allBills
          .where((h) => h.trangThai != 'Chờ gửi')
          .firstOrNull;
      var selectedBill = unpaidBill ?? latestBill;

      // ── 5. Tải chi tiết hóa đơn ──
      List<Map<String, dynamic>> chiTietHD = [];
      if (selectedBill != null && selectedBill.maHoaDon.isNotEmpty) {
        final rows = await db
            .from('chi_tiet_hoa_don')
            .select()
            .eq('ma_hoa_don', selectedBill.maHoaDon);
        chiTietHD = List<Map<String, dynamic>>.from(rows);
      }

      // ── 6. Tải thành viên phòng ─────────────────────────────
      final thanhVienRows = await db
          .from('chi_tiet_hop_dong_khach_thue')
          .select(
            'ma_khach, vai_tro, trang_thai_luu_tru, khach_thue(ho_ten_khach, so_dt)',
          )
          .eq('ma_hop_dong', hd.maHopDong);

      final thanhVien = (thanhVienRows as List).map((row) {
        final kt = row['khach_thue'];
        final m = Map<String, dynamic>.from(row);
        if (kt != null) {
          m['ho_ten_khach'] = kt['ho_ten_khach'];
          m['so_dt'] = kt['so_dt'];
        }
        return KhachThueModel.fromJson(m);
      }).toList();

      // ── 7. Lấy danh sách sự cố bảo trì của phòng từ Supabase ──────────
      List<Map<String, dynamic>> suCoList = [];
      try {
        final suCoRows = await db
            .from('su_co_bao_tri')
            .select()
            .eq('ma_phong', hd.maPhong)
            .order('ngay_bao_cao', ascending: false);
        suCoList = List<Map<String, dynamic>>.from(suCoRows as List);
      } catch (err) {
        debugPrint('Lỗi tải su_co_bao_tri: rr');
      }

      // ── 8. Tải danh sách tài sản phòng từ Supabase ──────────
      List<Map<String, dynamic>> taiSanList = [];
      try {
        final tsRows = await db
            .from('tai_san')
            .select()
            .eq('ma_phong', hd.maPhong);
        taiSanList = List<Map<String, dynamic>>.from(tsRows as List);
      } catch (err) {
        debugPrint('Lỗi tải tai_san: $err');
      }

      // ── 9. Tải danh sách phương tiện xe của cư dân từ Supabase ──
      List<Map<String, dynamic>> phuongTienList = [];
      if (khachThueRow != null) {
        final maKhach = khachThueRow['ma_khach']?.toString() ?? '';
        if (maKhach.isNotEmpty) {
          try {
            final ptRows = await db
                .from('phuong_tien')
                .select()
                .eq('ma_khach', maKhach);
            phuongTienList = List<Map<String, dynamic>>.from(ptRows as List);
          } catch (err) {
            debugPrint('Lỗi tải phuong_tien: $err');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _hopDong = hd;
        _phong = phongRow != null
            ? RoomModel.fromJson(Map<String, dynamic>.from(phongRow))
            : null;
        _hoaDonMoiNhat = selectedBill;
        _danhSachHoaDon = allBills;
        _chiTietHoaDon = chiTietHD;
        _thanhVienPhong = thanhVien;
        _danhSachSuCo = suCoList;
        _khachThueData = khachThueRow;
        _danhSachTaiSan = taiSanList;
        _danhSachPhuongTien = phuongTienList;
        _isLoading = false;
      });
      await _dongBoDanhSachThongBao();
      _initRealtimeTracking();
    } catch (e, st) {
      debugPrint('Lỗi _fetchTenantData: \n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = 'Lỗi kết nối dữ liệu.';
        });
      }
    }
  }

  // ─── REALTIME TRACKING KHI BQL BẤM DUYỆT ────────────────────
  void _initRealtimeTracking() {
    if (_tenantRealtimeChannel != null) return;

    try {
      final client = Supabase.instance.client;
      final channelName =
          'public:tenant_rt_${DateTime.now().millisecondsSinceEpoch}';
      _tenantRealtimeChannel = client.channel(channelName)
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'phu_luc_hop_dong',
          callback: (payload) {
            debugPrint(
              '[REALTIME] Thay đổi phu_luc_hop_dong: ${payload.newRecord}',
            );
            _checkPhuLucRealtimeUpdate(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'yeu_cau_chuyen_phong',
          callback: (payload) {
            debugPrint(
              '[REALTIME] Thay đổi yeu_cau_chuyen_phong: ${payload.newRecord}',
            );
            _checkChuyenPhongRealtimeUpdate(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'su_co_bao_tri',
          callback: (payload) {
            debugPrint(
              '[REALTIME] Thay đổi su_co_bao_tri: ${payload.newRecord}',
            );
            _checkSuCoRealtimeUpdate(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hop_dong',
          callback: (payload) {
            debugPrint('[REALTIME] Thay đổi hop_dong: ${payload.newRecord}');
            _fetchTenantData();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hoa_don',
          callback: (payload) {
            debugPrint('[REALTIME] Thay đổi hoa_don: ${payload.newRecord}');
            _checkHoaDonRealtimeUpdate(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dang_ky_khach_qua_dem',
          callback: (payload) {
            debugPrint('[REALTIME] Thay đổi dang_ky_khach_qua_dem: ${payload.newRecord}');
            _checkKhachQuaDemRealtimeUpdate(payload.newRecord);
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('[REALTIME] Lỗi đăng ký kênh Realtime: ');
    }

    // Polling dự phòng mỗi 2.5 giây đảm bảo 100% không bỏ lỡ sự kiện khi mạng lag hoặc Publication chưa bật
    _realtimePollTimer?.cancel();
    _realtimePollTimer = Timer.periodic(const Duration(milliseconds: 2500), (
      _,
    ) {
      _pollCheckApprovals();
    });
    // Kích hoạt kiểm tra ngay lập tức
    _pollCheckApprovals();
  }

  // ── BẮN THÔNG BÁO NỔI HEAVY-DUTY (HEADS-UP DYNAMIC BANNER TRÊN ĐIỆN THOẠI) ──
  void _hienThongBaoHeThong({
    required String tieuDe,
    required String noiDung,
    String loai = 'thong_bao',
    bool isError = false,
    VoidCallback? onXem,
    String? tag,
  }) {
    if (!mounted) return;
    if (!_thongBaoUngDung) {
      debugPrint('[NOTIF] Đang tắt thông báo ứng dụng, bỏ qua: $tieuDe');
      return;
    }

    final effectiveTag = tag ?? 'tb_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Bắn thông báo ngoài hệ thống (trên thanh thông báo điện thoại thiệt)
    // và TỰ ĐỘNG ĐỒNG BỘ VÀO CÁI CHUÔNG của app (chống trùng lặp 1 lần duy nhất)
    SystemNotificationService.show(
      title: tieuDe,
      body: noiDung,
      tag: effectiveTag,
      loai: loai,
      isError: isError,
      onXem: onXem,
    );

    // 2. Cập nhật Banner nổi trong app
    setState(() {
      _floatingNotification = {
        'tieu_de': tieuDe,
        'noi_dung': noiDung,
        'is_error': isError,
        'on_xem': onXem,
        'loai': loai,
      };
    });

    // 3. Hiển thị Banner nổi (Heads-Up Banner trượt từ đỉnh màn hình điện thoại)
    _bannerAnimController.forward(from: 0.0);
    _floatingNotificationTimer?.cancel();
    _floatingNotificationTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _floatingNotification != null) {
        _bannerAnimController.reverse().then((_) {
          if (mounted) setState(() => _floatingNotification = null);
        });
      }
    });
  }

  Widget _buildHeadsUpNotificationBanner() {
    final notif = _floatingNotification;
    if (notif == null) return const SizedBox.shrink();

    final isError = notif['is_error'] == true;
    final tieuDe = notif['tieu_de'] as String? ?? 'Thông báo từ Ban Quản Lý';
    final noiDung = notif['noi_dung'] as String? ?? '';
    final onXem = notif['on_xem'] as VoidCallback?;

    return Positioned(
      top: 10,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: _bannerSlideAnimation,
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: () {
              _bannerAnimController.reverse().then((_) {
                if (mounted) setState(() => _floatingNotification = null);
              });
              if (onXem != null) onXem();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isError
                      ? const Color(0xFFEF4444).withValues(alpha: 0.5)
                      : const Color(0xFF10B981).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isError
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF09638E))
                            .withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isError
                          ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                          : const Color(0xFF10B981).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isError
                            ? Icons.warning_amber_rounded
                            : Icons.notifications_active_rounded,
                        color: isError
                            ? const Color(0xFFF87171)
                            : const Color(0xFF34D399),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                isError
                                    ? 'BAN QUẢN LÝ • TỪ CHỐI'
                                    : 'BAN QUẢN LÝ • ĐÃ PHÊ DUYỆT',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isError
                                      ? const Color(0xFFF87171)
                                      : const Color(0xFF34D399),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Vừa xong',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tieuDe,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          noiDung,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFFCBD5E1),
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                      size: 18,
                    ),
                    onPressed: () {
                      _bannerAnimController.reverse().then((_) {
                        if (mounted)
                          setState(() => _floatingNotification = null);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _checkPhuLucRealtimeUpdate(Map<String, dynamic> record) {
    if (record.isEmpty || !mounted) return;
    final maHD = _hopDong?.maHopDong ?? maHopDong;
    final recMaHD = record['ma_hop_dong']?.toString() ?? '';
    if (maHD.isNotEmpty && recMaHD.isNotEmpty && recMaHD != maHD) return;

    final maPhuLuc = record['ma_phu_luc']?.toString() ?? '';
    final status = record['trang_thai']?.toString() ?? '';
    final isChuyenPhong =
        record['ma_phong_moi'] != null &&
        record['ma_phong_moi'].toString().isNotEmpty;

    final approvalKey = 'phu_luc_${maPhuLuc}_$status';
    if (_notifiedApprovalKeys.contains(approvalKey) ||
        ThongBaoHelper.daXem(approvalKey))
      return;

    if (status == 'Đã duyệt') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _fetchTenantData();

      if (isChuyenPhong) {
        final maPhongMoi = record['ma_phong_moi']?.toString() ?? '';
        _hienThongBaoHeThong(
          tieuDe: '🎉 BQL Đã Phê Duyệt Chuyển Phòng!',
          noiDung:
              'BQL đã phê duyệt chuyển sang phòng $maPhongMoi. Toàn bộ tiền cọc và hợp đồng đã được bảo lưu.',
          loai: 'chuyen_phong',
          tag: approvalKey,
          onXem: () {
            setState(() => _selectedTabIndex = 1);
          },
        );

        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Ban Quản Lý Đã Duyệt Chuyển Phòng!',
          noiDung:
              'Yêu cầu chuyển sang phòng $maPhongMoi đã được Ban Quản Lý phê duyệt thành công! Thông tin hợp đồng mới và tiền cọc đã được tự động bảo lưu.',
          type: ThongBaoType.thanhCong,
          nutText: 'Tuyệt vời',
          tag: approvalKey,
        );
      } else {
        final ngayGiaHanDen = record['ngay_gia_han_den']?.toString() ?? '';
        _hienThongBaoHeThong(
          tieuDe: '🎉 Hợp Đồng Gia Hạn Đã Được Duyệt!',
          noiDung:
              'Hợp đồng phòng $maPhong đã được BQL duyệt thành công${ngayGiaHanDen.isNotEmpty ? " đến ngày $ngayGiaHanDen" : ""}!',
          loai: 'gia_han',
          tag: approvalKey,
          onXem: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContractDetailScreen()),
            );
          },
        );

        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Gia Hạn Hợp Đồng Đã Được Duyệt!',
          noiDung:
              'Ban Quản Lý đã phê duyệt yêu cầu gia hạn hợp đồng phòng $maPhong${ngayGiaHanDen.isNotEmpty ? " đến ngày $ngayGiaHanDen" : ""} thành công! Hợp đồng mới đã có hiệu lực.',
          type: ThongBaoType.thanhCong,
          nutText: 'Xem Hợp Đồng',
          tag: approvalKey,
          onConfirm: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContractDetailScreen()),
            );
          },
        );
      }
    } else if (status == 'Từ chối') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _fetchTenantData();

      if (isChuyenPhong) {
        _hienThongBaoHeThong(
          tieuDe: '⚠️ Yêu Cầu Chuyển Phòng Bị Từ Chối',
          noiDung:
              'Ban Quản Lý chưa thể phê duyệt yêu cầu chuyển phòng vào thời điểm này. Vui lòng liên hệ BQL.',
          loai: 'chuyen_phong',
          isError: true,
          tag: approvalKey,
        );

        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Yêu Cầu Chuyển Phòng Bị Từ Chối',
          noiDung:
              'Ban Quản Lý chưa thể phê duyệt yêu cầu chuyển phòng vào thời điểm này. Vui lòng liên hệ BQL để biết thêm chi tiết.',
          type: ThongBaoType.thatBai,
          nutText: 'Đã hiểu',
          tag: approvalKey,
        );
      } else {
        _hienThongBaoHeThong(
          tieuDe: '⚠️ Yêu Cầu Gia Hạn Bị Từ Chối',
          noiDung:
              'Ban Quản Lý chưa thể phê duyệt gia hạn theo đề xuất hiện tại của bạn.',
          loai: 'gia_han',
          isError: true,
          tag: approvalKey,
        );

        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Yêu Cầu Gia Hạn Bị Từ Chối',
          noiDung:
              'Ban Quản Lý chưa thể phê duyệt gia hạn theo đề xuất hiện tại của bạn. Bạn có thể chọn phòng khác để chuyển hoặc đề xuất lại kỳ hạn phù hợp hơn!',
          type: ThongBaoType.thatBai,
          nutText: 'Đã hiểu',
          tag: approvalKey,
        );
      }
    }
  }

  void _checkChuyenPhongRealtimeUpdate(Map<String, dynamic> record) async {
    if (record.isEmpty || !mounted) return;
    final maHD = _hopDong?.maHopDong ?? maHopDong;
    final recMaHD = record['ma_hop_dong_ht']?.toString() ?? '';
    if (maHD.isNotEmpty && recMaHD.isNotEmpty && recMaHD != maHD) return;

    final maYeuCau = record['ma_yeu_cau']?.toString() ?? '';
    final status = record['trang_thai_tien_do']?.toString() ?? '';
    final approvalKey = 'yccp_${maYeuCau}_$status';
    if (_notifiedApprovalKeys.contains(approvalKey) ||
        ThongBaoHelper.daXem(approvalKey))
      return;

    final maPhongCu = record['ma_phong_cu']?.toString() ?? maPhong;
    final maPhongMoi = record['ma_phong_moi']?.toString() ?? '';

    void moManHinhChiTietYccp() async {
      Map<String, dynamic>? phongMoiData;
      try {
        if (maPhongMoi.isNotEmpty) {
          final res = await Supabase.instance.client
              .from('phong')
              .select()
              .eq('ma_phong', maPhongMoi)
              .maybeSingle();
          if (res != null) phongMoiData = res;
        }
      } catch (_) {}

      final giaThueMoi = (phongMoiData?['gia_thue'] as num?) ?? 3500000;
      final tienCocMoi = (phongMoiData?['tien_dat_coc'] as num?) ?? giaThueMoi;
      final tangMoi = (phongMoiData?['tang'] as num?)?.toInt() ?? 2;
      final dienTichMoi = (phongMoiData?['dien_tich'] as num?)?.toInt() ?? 26;

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomTransferSuccessScreen(
            ticketCode: maYeuCau,
            targetRoom: {
              'maPhong': maPhongMoi,
              'toaNha': phongMoiData?['toa_nha']?.toString() ?? 'Kiêu Giang',
              'tang': tangMoi,
              'dienTich': dienTichMoi,
              'giaThue': giaThueMoi,
              'tienDatCoc': tienCocMoi,
            },
            currentRoomNumber: maPhongCu,
            currentPrice:
                (record['tien_coc_bao_luu'] as num?) ??
                _hopDong?.giaThueThaoThuan ??
                3800000,
            moveInDateFormatted: record['thoi_gian_hen'] ?? '',
            reason: 'Chuyển phòng theo yêu cầu',
            note: '',
          ),
        ),
      );
    }

    if (status == 'Chờ khách xác nhận' || status == 'Đã kiểm tra') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      final huHai = (record['tien_hu_hai_cu'] as num?)?.toDouble() ?? 0.0;
      final dienNuoc = (record['tien_dien_nuoc_cu'] as num?)?.toDouble() ?? 0.0;

      String noiDungKiemTra =
          'BQL đã kiểm tra hiện trạng thiết bị phòng $maPhongCu. ';
      if (huHai > 0 || dienNuoc > 0) {
        noiDungKiemTra +=
            'Có phát sinh chi phí điện nước/khấu trừ. Vui lòng bấm vào xem và xác nhận biên bản!';
      } else {
        noiDungKiemTra +=
            '100% thiết bị đạt chuẩn. Vui lòng bấm vào xác nhận biên bản để gửi lên chủ trọ duyệt!';
      }

      _hienThongBaoHeThong(
        tieuDe: '📋 Biên Bản Nghiệm Thu Phòng $maPhongCu Sẵn Sàng',
        noiDung: noiDungKiemTra,
        loai: 'chuyen_phong',
        tag: approvalKey,
        onXem: moManHinhChiTietYccp,
      );

      if (!mounted) return;
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Biên Bản Nghiệm Thu Đã Sẵn Sàng',
        noiDung: noiDungKiemTra,
        type: ThongBaoType.thongTin,
        nutText: 'Xem & Xác Nhận',
        tag: approvalKey,
        onConfirm: moManHinhChiTietYccp,
      );
    } else if (status == 'Khách đã xác nhận' || status == 'Chờ chủ duyệt') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _hienThongBaoHeThong(
        tieuDe: '📤 Đã Gửi Biên Bản Lên Chủ Trọ',
        noiDung:
            'Bạn đã xác nhận biên bản nghiệm thu phòng $maPhongCu. Hồ sơ chuyển sang phòng $maPhongMoi đang chờ chủ trọ duyệt chính thức.',
        loai: 'chuyen_phong',
        tag: approvalKey,
        onXem: moManHinhChiTietYccp,
      );
    } else if (status == 'Đang xử lý') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _hienThongBaoHeThong(
        tieuDe: '⏳ BQL Đang Xử Lý Đơn Chuyển Phòng',
        noiDung:
            'BQL Kiều Giang đã tiếp nhận yêu cầu chuyển sang phòng $maPhongMoi và đang sắp xếp lịch kiểm tra phòng cũ.',
        loai: 'chuyen_phong',
        tag: approvalKey,
        onXem: moManHinhChiTietYccp,
      );
    } else if (status == 'Đã duyệt' || status == 'Hoàn tất') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);

      // 1. TỰ ĐỘNG ĐỒNG BỘ DUYỆT 1 CHẠM:
      // Tự động sinh Phụ lục hợp đồng ĐÃ DUYỆT + Đổi phòng trong hợp đồng + Đổi trạng thái phòng
      await _dongBoDuyetChuyenPhongTuDong(record);
      await _fetchTenantData();

      _hienThongBaoHeThong(
        tieuDe: '🎉 BQL Đã Duyệt Chuyển Phòng $maPhongMoi!',
        noiDung:
            'Yêu cầu chuyển từ phòng $maPhongCu sang phòng $maPhongMoi đã được phê duyệt. Phụ lục hợp đồng mới đã có hiệu lực!',
        loai: 'chuyen_phong',
        tag: approvalKey,
        onXem: () {
          setState(() => _selectedTabIndex = 1);
        },
      );

      if (!mounted) return;
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Ban Quản Lý Đã Duyệt Chuyển Phòng!',
        noiDung:
            'Yêu cầu chuyển từ phòng $maPhongCu sang phòng $maPhongMoi đã được Ban Quản Lý phê duyệt thành công! Phụ lục hợp đồng mới đã được cập nhật và phòng mới đã sẵn sàng.',
        type: ThongBaoType.thanhCong,
        nutText: 'Xem Phòng Mới',
        tag: approvalKey,
        onConfirm: () {
          setState(() => _selectedTabIndex = 1);
        },
      );
    } else if (status == 'Từ chối') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      await _fetchTenantData();

      _hienThongBaoHeThong(
        tieuDe: '⚠️ Yêu Cầu Chuyển Phòng Bị Từ Chối',
        noiDung: 'BQL chưa thể duyệt yêu cầu chuyển sang phòng $maPhongMoi.',
        loai: 'chuyen_phong',
        isError: true,
        tag: approvalKey,
      );

      if (!mounted) return;
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Yêu Cầu Chuyển Phòng Bị Từ Chối',
        noiDung:
            'Ban Quản Lý chưa thể phê duyệt yêu cầu chuyển sang phòng $maPhongMoi. Vui lòng liên hệ BQL để được hỗ trợ.',
        type: ThongBaoType.thatBai,
        nutText: 'Đã hiểu',
        tag: approvalKey,
      );
    }
  }

  /// TỰ ĐỘNG ĐỒNG BỘ KHI BQL BẤM "ĐÃ DUYỆT" TRÊN BẢNG yeu_cau_chuyen_phong:
  /// - Sinh bản ghi pháp lý trong phu_luc_hop_dong với trạng thái 'Đã duyệt'
  /// - Cập nhật ma_phong trong bảng hop_dong
  /// - Cập nhật trạng thái phòng cũ thành 'Trống' và phòng mới thành 'Đang thuê'
  Future<void> _dongBoDuyetChuyenPhongTuDong(
    Map<String, dynamic> record,
  ) async {
    try {
      final db = Supabase.instance.client;
      final maYeuCau = record['ma_yeu_cau']?.toString() ?? '';
      final recMaHD = record['ma_hop_dong_ht']?.toString() ?? '';
      final maPhongCu = record['ma_phong_cu']?.toString() ?? '';
      final maPhongMoi = record['ma_phong_moi']?.toString() ?? '';
      if (recMaHD.isEmpty || maPhongMoi.isEmpty) return;

      // 1. Lấy thông tin giá phòng mới
      num giaPhongMoi = 0;
      try {
        final phongMoiRes = await db
            .from('phong')
            .select('gia_thue')
            .eq('ma_phong', maPhongMoi)
            .maybeSingle();
        if (phongMoiRes != null && phongMoiRes['gia_thue'] != null) {
          giaPhongMoi = num.tryParse(phongMoiRes['gia_thue'].toString()) ?? 0;
        }
      } catch (_) {}

      // 2. Lấy ngày kết thúc của hợp đồng hiện tại
      String? ngayKt;
      try {
        final hdRes = await db
            .from('hop_dong')
            .select('ngay_kt')
            .eq('ma_hop_dong', recMaHD)
            .maybeSingle();
        if (hdRes != null) {
          ngayKt = hdRes['ngay_kt']?.toString();
        }
      } catch (_) {}

      // 3. Tự động sinh Phụ lục hợp đồng ĐÃ DUYỆT
      final now = DateTime.now();
      final ngayLapDateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final cleanHd = recMaHD.replaceAll(' ', '');
      String maPhuLuc = 'PLCP_$cleanHd';
      if (maPhuLuc.length > 10) {
        maPhuLuc = maPhuLuc.substring(0, 10);
      }

      final diffDeposit = record['tien_phat_sinh'] ?? 0;
      final noiDungPl =
          'Phụ lục chuyển đổi phòng từ $maPhongCu sang phòng $maPhongMoi theo phiếu yêu cầu chuyển phòng $maYeuCau. Toàn bộ tiền cọc bảo lưu theo thỏa thuận.';

      await db.from('phu_luc_hop_dong').upsert({
        'ma_phu_luc': maPhuLuc,
        'ngay_lap': ngayLapDateStr,
        'noi_dung_dieu_chinh': noiDungPl,
        'gia_thue_moi': giaPhongMoi,
        'chenh_lech_tien_coc': diffDeposit,
        'ngay_gia_han_den': ngayKt ?? ngayLapDateStr,
        'ma_hop_dong': recMaHD,
        'ma_phong_moi': maPhongMoi,
        'trang_thai': 'Đã duyệt',
      });
      debugPrint(
        '[CHUYEN_PHONG] Đã tự động sinh phụ lục hợp đồng ĐÃ DUYỆT: $maPhuLuc',
      );

      // 4. Cập nhật mã phòng mới vào bảng hop_dong
      await db
          .from('hop_dong')
          .update({'ma_phong': maPhongMoi})
          .eq('ma_hop_dong', recMaHD);
      debugPrint(
        '[CHUYEN_PHONG] Đã cập nhật hợp đồng $recMaHD sang phòng $maPhongMoi',
      );

      // 5. Cập nhật trạng thái phòng: cũ -> Trống, mới -> Đang thuê
      if (maPhongCu.isNotEmpty) {
        await db
            .from('phong')
            .update({'trang_thai': 'Trống'})
            .eq('ma_phong', maPhongCu);
      }
      await db
          .from('phong')
          .update({'trang_thai': 'Đang thuê'})
          .eq('ma_phong', maPhongMoi);
      debugPrint(
        '[CHUYEN_PHONG] Đã cập nhật trạng thái phòng: $maPhongCu -> Trống, $maPhongMoi -> Đang thuê',
      );

      // 6. Cập nhật biên bản kiểm tra phòng -> Đã xác nhận
      try {
        await db
            .from('bien_ban_kiem_tra_phong')
            .update({'trang_thai': 'Đã xác nhận'})
            .eq('ma_yeu_cau', maYeuCau);
      } catch (_) {}

      // 7. TỰ ĐỘNG ĐỒNG BỘ HÓA ĐƠN KỲ TỚI (CẬP NHẬT HOẶC TẠO MỚI)
      try {
        final tienDienNuocCu =
            (record['tien_dien_nuoc_cu'] as num?)?.toDouble() ?? 0.0;
        final tienHuHaiCu =
            (record['tien_hu_hai_cu'] as num?)?.toDouble() ?? 0.0;
        final tienPhatSinh =
            (record['tien_phat_sinh'] as num?)?.toDouble() ?? 0.0;

        final unpaidBills = await db
            .from('hoa_don')
            .select()
            .eq('ma_hop_dong', recMaHD)
            .eq('trang_thai', 'Chưa thanh toán')
            .order('ngay_lap', ascending: false)
            .limit(1);

        if (unpaidBills.isNotEmpty) {
          final bill = unpaidBills.first;
          final billCode = bill['ma_hoa_don'].toString();
          final curDienNuoc =
              (bill['tien_dien_nuoc'] as num?)?.toDouble() ?? 0.0;
          final curDichVu =
              (bill['tien_dich_vu_khac'] as num?)?.toDouble() ?? 0.0;
          final curNoCu = (bill['no_cu'] as num?)?.toDouble() ?? 0.0;

          final newDienNuoc = curDienNuoc + tienDienNuocCu;
          final newDichVu = curDichVu + tienHuHaiCu + tienPhatSinh;
          final newTienPhong = giaPhongMoi > 0
              ? giaPhongMoi.toDouble()
              : ((bill['tien_phong'] as num?)?.toDouble() ?? 0.0);
          final newTongTien = newTienPhong + newDienNuoc + newDichVu + curNoCu;

          await db
              .from('hoa_don')
              .update({
                'tien_phong': newTienPhong,
                'tien_dien_nuoc': newDienNuoc,
                'tien_dich_vu_khac': newDichVu,
                'tong_tien': newTongTien,
              })
              .eq('ma_hoa_don', billCode);

          final suffix = maYeuCau.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
          final shortCode = suffix.length > 6
              ? suffix.substring(suffix.length - 6)
              : suffix;
          final cthdDn = 'CD_$shortCode';
          final cthdHh = 'CH_$shortCode';
          final cthdCoc = 'CC_$shortCode';

          if (tienDienNuocCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdDn,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Điện nước chốt bàn giao phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': tienDienNuocCu,
              'thanh_tien': tienDienNuocCu,
            });
          }
          if (tienHuHaiCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdHh,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Khấu trừ hư hại thiết bị phòng $maPhongCu',
              'so_luong': 1,
              'don_gia': tienHuHaiCu,
              'thanh_tien': tienHuHaiCu,
            });
          }
          if (tienPhatSinh > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Bù chênh lệch tiền cọc phòng mới $maPhongMoi',
              'so_luong': 1,
              'don_gia': tienPhatSinh,
              'thanh_tien': tienPhatSinh,
            });
          }
        } else {
          final newBillCode =
              'HDCP_${cleanHd.substring(0, cleanHd.length > 5 ? 5 : cleanHd.length)}';
          final newTienPhong = giaPhongMoi > 0 ? giaPhongMoi.toDouble() : 0.0;
          final newDichVu = tienHuHaiCu + tienPhatSinh;
          final newTong = newTienPhong + tienDienNuocCu + newDichVu;

          await db.from('hoa_don').upsert({
            'ma_hoa_don': newBillCode,
            'ngay_lap': ngayLapDateStr,
            'han_dong_tien': DateTime.now()
                .add(const Duration(days: 5))
                .toIso8601String()
                .substring(0, 10),
            'tien_phong': newTienPhong,
            'tien_dien_nuoc': tienDienNuocCu,
            'tien_dich_vu_khac': newDichVu,
            'no_cu': 0,
            'tong_tien': newTong,
            'trang_thai': 'Chưa thanh toán',
            'loai_giao_dich': 'Tiền phòng & Dịch vụ',
            'ma_hop_dong': recMaHD,
          });

          final suffix = maYeuCau.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
          final shortCode = suffix.length > 6
              ? suffix.substring(suffix.length - 6)
              : suffix;
          final cthdPhong = 'CP_$shortCode';
          final cthdDn = 'CD_$shortCode';
          final cthdHh = 'CH_$shortCode';
          final cthdCoc = 'CC_$shortCode';

          await db.from('chi_tiet_hoa_don').upsert({
            'ma_cthd': cthdPhong,
            'ma_hoa_don': newBillCode,
            'ten_khoan_thu': 'Tiền thuê phòng mới $maPhongMoi',
            'so_luong': 1,
            'don_gia': newTienPhong,
            'thanh_tien': newTienPhong,
          });

          if (tienDienNuocCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdDn,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Điện nước chốt bàn giao phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': tienDienNuocCu,
              'thanh_tien': tienDienNuocCu,
            });
          }
          if (tienHuHaiCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdHh,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Khấu trừ hư hại thiết bị phòng $maPhongCu',
              'so_luong': 1,
              'don_gia': tienHuHaiCu,
              'thanh_tien': tienHuHaiCu,
            });
          }
          if (tienPhatSinh > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Bù chênh lệch tiền cọc phòng mới $maPhongMoi',
              'so_luong': 1,
              'don_gia': tienPhatSinh,
              'thanh_tien': tienPhatSinh,
            });
          }
        }
        debugPrint(
          '[CHUYEN_PHONG] Đã tự động cập nhật hóa đơn kỳ tới thành công!',
        );
      } catch (billErr) {
        debugPrint('[CHUYEN_PHONG] Lỗi tự động tính hóa đơn: $billErr');
      }
    } catch (e) {
      debugPrint('[CHUYEN_PHONG] Lỗi tự động sinh phụ lục và đổi phòng: ');
    }
  }

  void _checkSuCoRealtimeUpdate(Map<String, dynamic> record) {
    if (record.isEmpty || !mounted) return;
    final mPhong = maPhong.replaceAll('P.', '').replaceAll('P', '').trim();
    final recMaPhong =
        record['ma_phong']
            ?.toString()
            .replaceAll('P.', '')
            .replaceAll('P', '')
            .trim() ??
        '';
    if (recMaPhong.isNotEmpty && recMaPhong != mPhong) return;

    final maSuCo = record['ma_su_co']?.toString() ?? '';
    final status = record['trang_thai']?.toString() ?? '';
    final approvalKey = 'su_co_${maSuCo}_$status';
    if (_notifiedApprovalKeys.contains(approvalKey) ||
        ThongBaoHelper.daXem(approvalKey))
      return;

    if (status == 'Đã xử lý' || status == 'Đã duyệt') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _fetchTenantData();

      final tieuDe = record['tieu_de']?.toString() ?? 'Sự cố bảo trì';

      _hienThongBaoHeThong(
        tieuDe: '🛠️ Sự Cố Đã Được BQL Xử Lý!',
        noiDung: 'Sự cố "$tieuDe" của phòng $maPhong đã được xử lý hoàn tất.',
        loai: 'su_co',
        tag: approvalKey,
        onXem: () {
          setState(() => _selectedTabIndex = 3);
        },
      );

      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Sự Cố Đã Được BQL Xử Lý!',
        noiDung:
            'Sự cố "$tieuDe" của phòng $maPhong đã được Ban Quản Lý xử lý hoàn tất. Bạn có thể kiểm tra lại tại phòng nhé!',
        type: ThongBaoType.thanhCong,
        nutText: 'Đã kiểm tra',
        tag: approvalKey,
      );
    }
  }

  void _checkHoaDonRealtimeUpdate(Map<String, dynamic> record) {
    if (record.isEmpty || !mounted) return;
    final maHD = _hopDong?.maHopDong ?? maHopDong;
    final recMaHD = record['ma_hop_dong']?.toString() ?? '';
    if (maHD.isNotEmpty && recMaHD.isNotEmpty && recMaHD != maHD) return;

    final maHoaDon = record['ma_hoa_don']?.toString() ?? '';
    final status = record['trang_thai']?.toString() ?? '';
    final tongTien = num.tryParse(record['tong_tien']?.toString() ?? '0') ?? 0;
    final thangNam = record['thang_nam']?.toString() ?? '';
    final hanDongTien = record['han_dong_tien']?.toString() ?? '';

    // Luôn nạp lại dữ liệu trang chủ ngay nếu trạng thái hoặc mã hóa đơn khác hiện tại
    if (_hoaDonMoiNhat == null ||
        _hoaDonMoiNhat!.trangThai != status ||
        _hoaDonMoiNhat!.maHoaDon != maHoaDon) {
      _fetchTenantData();
    }

    final approvalKey = 'hd_${maHoaDon}_$status';
    if (_notifiedApprovalKeys.contains(approvalKey) ||
        ThongBaoHelper.daXem(approvalKey))
      return;

    // Reset key đối nghịch để sẵn sàng nhận thông báo nếu đổi qua lại
    if (status == 'Đã thanh toán') {
      _notifiedApprovalKeys.remove('hd_${maHoaDon}_Chưa thanh toán');
    } else {
      _notifiedApprovalKeys.remove('hd_${maHoaDon}_Đã thanh toán');
      _notifiedApprovalKeys.remove('hoa_don_paid_$maHoaDon');
    }

    if (status != 'Chờ gửi' && status != 'Đã thanh toán' && tongTien > 0) {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _fetchTenantData();

      final activeRoom = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
      _hienThongBaoHeThong(
        tieuDe: '💵 Hóa Đơn Tiền Phòng Tháng $thangNam',
        noiDung:
            'BQL đã gửi hóa đơn tháng $thangNam (${FormatUtils.currency(tongTien)}). Hạn nộp: $hanDongTien.',
        loai: 'hoa_don',
        tag: approvalKey,
        onXem: () {
          if (_hoaDonMoiNhat != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentScreen(
                  hoaDon: _hoaDonMoiNhat!,
                  tenPhong: 'Phòng $activeRoom',
                  onPaymentSuccess: (_) => _fetchTenantData(),
                ),
              ),
            );
          }
        },
      );
    } else if (status == 'Đã thanh toán') {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _fetchTenantData();

      _hienThongBaoHeThong(
        tieuDe: '✅ Hóa Đơn Tháng $thangNam Đã Thanh Toán',
        noiDung:
            'Giao dịch thanh toán hóa đơn tháng $thangNam đã được xác nhận thành công!',
        loai: 'hoa_don',
        tag: 'hoa_don_paid_$maHoaDon',
        onXem: () {
          if (_hoaDonMoiNhat != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PaymentCompletedScreen(
                  hoaDon: _hoaDonMoiNhat!,
                  tenPhong: roomDisplay,
                  bankName: 'MB Bank (Quân Đội)',
                  transactionTime: _hoaDonMoiNhat!.hanDongTienFormatted,
                  amountPaid: _hoaDonMoiNhat!.tongTienGoc,
                ),
              ),
            );
          }
        },
      );
    }
  }

  void _checkKhachQuaDemRealtimeUpdate(Map<String, dynamic> record) {
    if (record.isEmpty || !mounted) return;
    final mPhong = maPhong.replaceAll('P.', '').replaceAll('P', '').trim();
    final recMaPhong = record['ma_phong']?.toString().replaceAll('P.', '').replaceAll('P', '').trim() ?? '';
    if (mPhong.isNotEmpty && recMaPhong.isNotEmpty && recMaPhong != mPhong) return;

    final maDangKy = record['ma_dang_ky']?.toString() ?? '';
    final status = record['trang_thai']?.toString() ?? '';
    final tenKhach = record['ho_ten_khach_ngoai']?.toString() ?? 'Khách';
    final tuNgay = record['tu_ngay']?.toString() ?? '';
    final denNgay = record['den_ngay']?.toString() ?? '';
    final approvalKey = 'guest_${maDangKy}_$status';

    if (_notifiedApprovalKeys.contains(approvalKey) || ThongBaoHelper.daXem(approvalKey)) return;

    final stLower = status.toLowerCase();
    final isDaDuyet = status == 'Đã duyệt' || stLower.contains('duyệt') || stLower.contains('duyet');
    final isTuChoi = status == 'Từ chối' || stLower.contains('từ chối') || stLower.contains('tu choi');

    if (isDaDuyet) {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _dongBoDanhSachThongBao();

      final activeRoom = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
      _hienThongBaoHeThong(
        tieuDe: '🎉 Chủ Trọ Đã Duyệt Khách Qua Đêm!',
        noiDung: 'Phiếu đăng ký cho khách $tenKhach ($tuNgay - $denNgay) phòng $activeRoom đã được chủ trọ duyệt thành công!',
        loai: 'khach_luu_tru',
        tag: approvalKey,
        onXem: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ManHinhLichSuLuuTru(
                tenPhong: activeRoom,
                initialTabIndex: 2, // Mở tab Đã duyệt
              ),
            ),
          );
        },
      );

      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Chủ Trọ Đã Phê Duyệt Khách!',
        noiDung: 'Phiếu đăng ký lưu trú của khách $tenKhach phòng $activeRoom ($tuNgay - $denNgay) đã được chủ trọ phê duyệt thành công!',
        type: ThongBaoType.thanhCong,
        nutText: 'Xem Lịch Sử Lưu Trú',
        tag: approvalKey,
        onConfirm: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ManHinhLichSuLuuTru(
                tenPhong: activeRoom,
                initialTabIndex: 2, // Mở tab Đã duyệt
              ),
            ),
          );
        },
      );
    } else if (isTuChoi) {
      _notifiedApprovalKeys.add(approvalKey);
      ThongBaoHelper.danhDauDaXem(approvalKey);
      _dongBoDanhSachThongBao();

      final activeRoom = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
      _hienThongBaoHeThong(
        tieuDe: '⚠️ Yêu Cầu Lưu Trú Bị Từ Chối',
        noiDung: 'Yêu cầu đăng ký khách qua đêm cho $tenKhach chưa được chủ trọ phê duyệt.',
        loai: 'khach_luu_tru',
        isError: true,
        tag: approvalKey,
        onXem: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ManHinhLichSuLuuTru(
                tenPhong: activeRoom,
                initialTabIndex: 3, // Mở tab Từ chối
              ),
            ),
          );
        },
      );
    }
  }

  Future<void> _pollCheckApprovals() async {
    if (!mounted) return;
    final maHD = _hopDong?.maHopDong ?? maHopDong;
    if (maHD.isEmpty) return;

    try {
      final db = Supabase.instance.client;

      // 1. Kiểm tra phụ lục mới nhất
      final phuLucRes = await db
          .from('phu_luc_hop_dong')
          .select()
          .eq('ma_hop_dong', maHD)
          .order('ngay_lap', ascending: false)
          .limit(1);

      if (phuLucRes.isNotEmpty) {
        final row = phuLucRes.first;
        final st = row['trang_thai']?.toString() ?? '';
        final myId = row['ma_phu_luc']?.toString() ?? '';
        final approvalKey = 'phu_luc_${myId}_$st';

        if (_lastPhuLucStatus != null && _lastPhuLucStatus != st) {
          if (!_notifiedApprovalKeys.contains(approvalKey) &&
              !ThongBaoHelper.daXem(approvalKey)) {
            _checkPhuLucRealtimeUpdate(row);
          }
        }
        _lastPhuLucStatus = st;
      }

      // 2. Kiểm tra yêu cầu chuyển phòng
      final activeRoom = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
      final yccpRes = await db
          .from('yeu_cau_chuyen_phong')
          .select()
          .or('ma_hop_dong_ht.eq.$maHD,ma_phong_cu.eq.$activeRoom')
          .order('ngay_tao', ascending: false)
          .limit(1);

      if (yccpRes.isNotEmpty) {
        final row = yccpRes.first;
        final st = row['trang_thai_tien_do']?.toString() ?? '';
        final myId = row['ma_yeu_cau']?.toString() ?? '';
        final approvalKey = 'yccp_${myId}_$st';

        // CHỈ THÔNG BÁO KHI TRẠNG THÁI THỰC SỰ THAY ĐỔI VÀ CHƯA TỪNG BẤM 'ĐÃ HIỂU'
        if (_lastYccpStatus != null && _lastYccpStatus != st) {
          if (!_notifiedApprovalKeys.contains(approvalKey) &&
              !ThongBaoHelper.daXem(approvalKey)) {
            _checkChuyenPhongRealtimeUpdate(row);
          }
        }
        _lastYccpStatus = st;
      }
      // _dongBoDanhSachThongBao(); // Tranh goi lien tuc moi 2.5s khi polling

      // 3. Kiểm tra sự cố bảo trì
      final mPhong = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
      final suCoRes = await db
          .from('su_co_bao_tri')
          .select()
          .eq('ma_phong', mPhong)
          .order('ngay_bao_cao', ascending: false);

      if (suCoRes.isNotEmpty) {
        for (final row in suCoRes) {
          final id = row['ma_su_co']?.toString() ?? '';
          final st = row['trang_thai']?.toString() ?? '';
          final lastSt = _lastSuCoStatuses[id];
          final approvalKey = 'su_co_${id}_$st';

          if (lastSt != null && lastSt != st) {
            if (!_notifiedApprovalKeys.contains(approvalKey) &&
                !ThongBaoHelper.daXem(approvalKey)) {
              _checkSuCoRealtimeUpdate(row);
            }
          }
          _lastSuCoStatuses[id] = st;
        }
      }

      // 4. Kiểm tra hóa đơn mới từ BQL
      if (maHD.isNotEmpty) {
        final hdRes = await db
            .from('hoa_don')
            .select()
            .eq('ma_hop_dong', maHD)
            .order('ngay_lap', ascending: false)
            .limit(1);
        if (hdRes.isNotEmpty) {
          _checkHoaDonRealtimeUpdate(hdRes.first);
        }
      }

      // 5. Kiểm tra đăng ký khách qua đêm từ BQL
      final pDigits = activeRoom.replaceAll(RegExp(r'[^0-9]'), '');
      final guestRes = await db
          .from('dang_ky_khach_qua_dem')
          .select()
          .or('ma_phong.eq.P$pDigits,ma_phong.eq.$pDigits,ma_phong.eq.$activeRoom')
          .order('tu_ngay', ascending: false)
          .limit(3);

      if (guestRes.isNotEmpty) {
        for (final row in guestRes) {
          final id = row['ma_dang_ky']?.toString() ?? '';
          final st = row['trang_thai']?.toString() ?? '';
          final lastSt = _lastGuestStatuses[id];
          final approvalKey = 'guest_${id}_$st';

          if (lastSt != null && lastSt != st) {
            if (!_notifiedApprovalKeys.contains(approvalKey) &&
                !ThongBaoHelper.daXem(approvalKey)) {
              _checkKhachQuaDemRealtimeUpdate(row);
            }
          }
          _lastGuestStatuses[id] = st;
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      body: SafeArea(
        child: Stack(
          children: [
            _isLoading
                ? _buildLoadingState()
                : _loadError != null
                ? _buildErrorState()
                : _buildCurrentTabContent(),
            if (_floatingNotification != null)
              _buildHeadsUpNotificationBanner(),
          ],
        ),
      ),
      bottomNavigationBar: _isLoading || _loadError != null
          ? null
          : _buildBottomNavBar(),
    );
  }

  Widget _buildLoadingState() {
    return const LoadingMeoMeo(
      message: 'Đang tải dữ liệu...',
      subMessage: 'Đợi mèo con nạp thông tin cư dân xíu nha~ 🐾',
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 56,
              color: Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Lỗi không xác định',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _fetchTenantData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    Widget currentTab;
    switch (_selectedTabIndex) {
      case 0:
        currentTab = _buildHomeTab();
        break;
      case 1:
        currentTab = _buildRoomTab();
        break;
      case 2:
        currentTab = _buildBillTab();
        break;
      case 3:
        currentTab = _buildIncidentTab();
        break;
      case 4:
        currentTab = _buildProfileTab();
        break;
      default:
        currentTab = _buildHomeTab();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_selectedTabIndex),
        child: currentTab,
      ),
    );
  }

  Widget _animateEntrance({required Widget child, int delayMs = 0}) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(delayMs),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: child,
    );
  }

  // ==================== TAB 1: TRANG CHỦ ====================
  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _fetchTenantData,
      color: const Color(0xFF09638E),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TOP HEADER
            _animateEntrance(child: _buildTopHeader(), delayMs: 0),
            const SizedBox(height: 14),

            // 2. HERO GREETING & ROOM INFO CARD
            _animateEntrance(child: _buildHeroRoomCard(), delayMs: 80),
            const SizedBox(height: 16),

            // 3. HÓA ĐƠN THÁNG (MONTHLY BILL CARD)
            _animateEntrance(child: _buildMonthlyBillCard(), delayMs: 160),
            const SizedBox(height: 22),

            // 4. LỐI TẮT THAO TÁC (QUICK SHORTCUTS GRID)
            _animateEntrance(
              child: _buildQuickShortcutsSection(),
              delayMs: 240,
            ),
            const SizedBox(height: 22),

            // 5. THÀNH VIÊN PHÒNG
            _animateEntrance(child: _buildRoomMembersSection(), delayMs: 320),
            const SizedBox(height: 22),

            // 6. THÔNG BÁO NHÀ TRỌ
            _animateEntrance(
              child: _buildBuildingNoticesSection(),
              delayMs: 400,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // 1. TOP HEADER
  Widget _buildTopHeader() {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Kiêu Giang',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF09638E),
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Trang chủ',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const Spacer(),

        // Notification Bell Icon with Badge
        ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: SystemNotificationService.danhSachThongBaoNotifier,
          builder: (context, notifList, _) {
            final unreadCount = notifList
                .where((t) => t['da_doc'] == false)
                .length;
            return GestureDetector(
              onTap: () => _showNotificationModal(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF5FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF09638E).withValues(alpha: 0.15),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF09638E),
                      size: 22,
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 10),

        // Avatar Profile Button
        GestureDetector(
          onTap: () => setState(() => _selectedTabIndex = 4),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEBF5FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF09638E).withValues(alpha: 0.15),
              ),
            ),
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF08A),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('🐥', style: TextStyle(fontSize: 18)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 2. HERO ROOM CARD (NÂNG CẤP CHUYÊN NGHIỆP CÓ ANIMATION THU HÚT)
  Widget _buildHeroRoomCard() {
    return AnimatedBuilder(
      animation: _cardGlowAnimation,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFBAE6FD).withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(
                  0xFF0284C7,
                ).withValues(alpha: _cardGlowAnimation.value * 0.35),
                blurRadius: 22,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Họa tiết trang trí nền tinh tế (Glass orbs)
              Positioned(
                top: -24,
                right: -24,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFE0F2FE).withValues(alpha: 0.45),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 48,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFBAE6FD).withValues(alpha: 0.25),
                  ),
                ),
              ),

              // Nội dung chính của Thẻ Cư Dân
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hàng 1: Trạng thái thuê & Hạn hợp đồng ──
                    Row(
                      children: [
                        // Live Radar Beacon: Đang thuê hoạt động
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFBAE6FD)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Radar pulse animation
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedBuilder(
                                      animation: _beaconPulseController,
                                      builder: (context, child) => Container(
                                        width: 7 * _beaconScaleAnimation.value,
                                        height: 7 * _beaconScaleAnimation.value,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFF0284C7)
                                              .withValues(
                                                alpha: _beaconOpacityAnimation
                                                    .value,
                                              ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 6.5,
                                      height: 6.5,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: const Color(0xFF0284C7),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF0284C7,
                                            ).withValues(alpha: 0.6),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'ĐANG THUÊ HOẠT ĐỘNG',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0284C7),
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Pill Hạn hợp đồng
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 13,
                                  color: Color(0xFF0284C7),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    _hopDong != null
                                        ? 'HĐ đến ${_hopDong!.ngayKtFormatted}'
                                        : 'HĐ đến 31/12/2026',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // ── Hàng 2: Lời chào thân thiện + Animation vẫy tay 👋 + Huy hiệu VIP ──
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            'Xin chào, $displayName',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Animation vẫy tay 👋 sinh động
                        AnimatedBuilder(
                          animation: _waveAnimation,
                          builder: (context, child) => Transform.rotate(
                            angle: _waveAnimation.value,
                            origin: const Offset(6, 12),
                            child: const Text(
                              '👋',
                              style: TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Huy hiệu Cư dân chính thức
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF0EA5E9)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0284C7,
                                ).withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 11,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'CƯ DÂN',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── Hàng 3: Thẻ căn hộ / Phòng thông minh ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFBFDBFE),
                              ),
                            ),
                            child: const Icon(
                              Icons.meeting_room_rounded,
                              size: 16,
                              color: Color(0xFF0284C7),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roomDisplay,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(height: 1),
                                const Text(
                                  'Căn hộ dịch vụ cao cấp • Tòa nhà Kiêu Giang',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Hàng 4: Hợp đồng điện tử chính thức (Nút bấm tương tác) ──
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showContractModal(),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.white, Color(0xFFF8FAFC)],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(
                                0xFFBAE6FD,
                              ).withValues(alpha: 0.9),
                              width: 1.1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF0284C7,
                                ).withValues(alpha: 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.verified_user_rounded,
                                  size: 16,
                                  color: Color(0xFF0284C7),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Hợp đồng điện tử chính thức',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    SizedBox(height: 1),
                                    Text(
                                      'Đã ký số an toàn • Pháp lý bảo đảm',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Chi tiết',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0284C7),
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 10,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ],
                                ),
                              ),
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
      },
    );
  }

  // 3. MONTHLY BILL CARD
  Widget _buildMonthlyBillCard() {
    final hd = _hoaDonMoiNhat;
    // Khi đã thanh toán tất cả (hoặc không có hóa đơn nợ / số tiền còn lại <= 0)
    // -> Ẩn hoàn toàn card thông báo hóa đơn trên trang chủ
    if (hd == null || hd.trangThai == 'Đã thanh toán' || hd.tongTien <= 0) {
      return const SizedBox.shrink();
    }

    final isPaid = hd.trangThai == 'Đã thanh toán';
    final isPartial = hd.trangThai == 'Thanh toán một phần';
    final remainingDays = hd.soNgayConLai;
    final overdueDays = remainingDays < 0 ? -remainingDays : 0;
    final phiPhatTreHan = 0;
    num tongTienThucTe = hd.tongTien;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE6F3F9), Color(0xFFF1F8FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFBAE6FD).withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF09638E).withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bill Header Tags
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Tag HÓA ĐƠN
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFBAE6FD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'HÓA ĐƠN ${hd.thangNam}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),

              // 2. Mã hóa đơn
              Text(
                '#${hd.maHoaDon}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),

              // 3. Tag trạng thái: Nếu thanh toán 1 phần thì báo Đợt 2, ngược lại đếm ngược ngày
              if (isPartial)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: remainingDays < 0
                        ? const Color(0xFFFEE2E2)
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        remainingDays < 0
                            ? (overdueDays >= 10
                                ? Icons.lock_rounded
                                : Icons.warning_amber_rounded)
                            : Icons.hourglass_top_rounded,
                        size: 12,
                        color: remainingDays < 0
                            ? const Color(0xFFDC2626)
                            : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        remainingDays < 0
                            ? (overdueDays >= 10
                                ? 'ĐỢT 2 • KHÓA VÂN TAY'
                                : 'ĐỢT 2 • TRỄ $overdueDays NGÀY')
                            : 'ĐỢT 2 • CÒN NỢ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: remainingDays < 0
                              ? const Color(0xFFDC2626)
                              : const Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        remainingDays > 0
                            ? 'Còn $remainingDays ngày'
                            : remainingDays == 0
                            ? 'Hôm nay đến hạn'
                            : 'Quá hạn ${-remainingDays} ngày',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Total Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPartial
                          ? 'Số tiền còn lại (Đợt 2)'
                          : isPaid
                          ? 'Số tiền đã thanh toán'
                          : 'Tổng tiền cần thanh toán',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: Text(
                            FormatUtils.currency(
                              tongTienThucTe,
                            ).replaceAll('đ', '').trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: isPartial
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF0F172A),
                              letterSpacing: -0.5,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'VNĐ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF09638E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isPaid ? 'Ngày TT:' : 'Hạn:',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      hd.hanDongTienFormatted,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Line Items Breakdown Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ...(_chiTietHoaDon.isNotEmpty
                    ? _chiTietHoaDon.map((item) {
                        final name =
                            item['ten_khoan_thu'] ??
                            item['khoan_muc'] ??
                            item['ten_khoan_muc'] ??
                            'Khoản mục';
                        final tien =
                            num.tryParse(
                              item['thanh_tien']?.toString() ?? '0',
                            ) ??
                            0;
                        IconData ic = Icons.receipt_outlined;
                        Color c = const Color(0xFF09638E);
                        final nameLower = name.toString().toLowerCase();
                        if (nameLower.contains('phòng') ||
                            nameLower.contains('thuê')) {
                          ic = Icons.bed_outlined;
                          c = const Color(0xFF0F2042);
                        } else if (nameLower.contains('điện')) {
                          ic = Icons.bolt_rounded;
                          c = const Color(0xFFD97706);
                        } else if (nameLower.contains('nước')) {
                          ic = Icons.water_drop_outlined;
                          c = const Color(0xFF0284C7);
                        } else if (nameLower.contains('rác') ||
                            nameLower.contains('vệ sinh') ||
                            nameLower.contains('dịch vụ')) {
                          ic = Icons.cleaning_services_outlined;
                          c = const Color(0xFF0D9488);
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildBillItem(
                            ic,
                            name.toString(),
                            FormatUtils.currency(tien),
                            c,
                          ),
                        );
                      }).toList()
                    : [
                        _buildBillItem(
                          Icons.bed_outlined,
                          'Tiền phòng cơ bản',
                          FormatUtils.currency(hd.tienPhong),
                          const Color(0xFF0F2042),
                        ),
                        const SizedBox(height: 8),
                        _buildBillItem(
                          Icons.bolt_rounded,
                          'Điện & Nước sử dụng',
                          FormatUtils.currency(hd.tienDienNuoc),
                          const Color(0xFFD97706),
                        ),
                        const SizedBox(height: 8),
                        _buildBillItem(
                          Icons.cleaning_services_outlined,
                          'Dịch vụ & rác chung',
                          FormatUtils.currency(hd.tienDichVuKhac),
                          const Color(0xFF0D9488),
                        ),
                        if (hd.noCu > 0) ...[
                          const SizedBox(height: 8),
                          _buildBillItem(
                            Icons.warning_amber_rounded,
                            'Nợ tháng trước',
                            FormatUtils.currency(hd.noCu),
                            Colors.red,
                          ),
                        ],
                      ]),
                if (phiPhatTreHan > 0 &&
                    !_chiTietHoaDon.any(
                      (i) => (i['ten_khoan_thu'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains('phạt'),
                    )) ...[
                  const Divider(height: 16, color: Color(0xFFF1F5F9)),
                  _buildBillItem(
                    Icons.warning_amber_rounded,
                    'Phí phạt trễ hạn ($overdueDays ngày x 50.000đ)',
                    FormatUtils.currency(phiPhatTreHan),
                    const Color(0xFFDC2626),
                  ),
                ],
              ],
            ),
          ),
          if (!isPaid && remainingDays < 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          overdueDays >= 10
                              ? Icons.lock_rounded
                              : (overdueDays >= 5
                                  ? Icons.warning_amber_rounded
                                  : Icons.error_outline_rounded),
                          color: const Color(0xFFDC2626),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              overdueDays >= 10
                                  ? (isPartial
                                      ? '🔒 ĐÃ KHÓA VÂN TAY (Trễ Đợt 2 $overdueDays ngày)'
                                      : '🔒 ĐÃ KHÓA VÂN TAY (Quá hạn $overdueDays ngày)')
                                  : (overdueDays >= 5
                                      ? (isPartial
                                          ? '⚠️ Cảnh báo: Trễ Đợt 2 $overdueDays ngày (Sắp khóa vân tay)'
                                          : '⚠️ Cảnh báo: Quá hạn $overdueDays ngày (Sắp khóa vân tay)')
                                      : (isPartial
                                          ? 'Khoản nợ Đợt 2 đã quá hạn $overdueDays ngày'
                                          : 'Hóa đơn đã quá hạn $overdueDays ngày')),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            Text(
                              overdueDays >= 10
                                  ? 'Vân tay đã bị tạm khóa. Vui lòng thanh toán hoặc liên hệ BQL'
                                  : (isPartial
                                      ? 'Hạn chót Đợt 2: ${hd.hanDongTienFormatted}'
                                      : 'Hạn thanh toán: ${hd.hanDongTienFormatted}'),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7F1D1D),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFFECACA)),
                  const SizedBox(height: 8),
                  const Text(
                    'Quy định & Hướng xử lý bắt buộc:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    overdueDays >= 10
                        ? (isPartial
                            ? '• QUÁ HẠN ĐỢT 2 10 NGÀY: Hệ thống ĐÃ KHÓA VÂN TAY ra vào phòng của bạn theo quy chế tòa nhà.\n'
                              '• Vui lòng thanh toán số tiền còn lại (${FormatUtils.currency(tongTienThucTe)}) hoặc liên hệ BQL qua SĐT/Zalo: ${LienHeHelper.defaultHotlineDisplay} để được hỗ trợ mở lại vân tay.\n'
                              '• Bấm "Thanh toán Đợt 2 / VietQR" bên dưới để gạch nợ tự động 24/7.'
                            : '• QUÁ HẠN 10 NGÀY: Hệ thống ĐÃ KHÓA VÂN TAY ra vào phòng của bạn theo quy chế tòa nhà.\n'
                              '• Vui lòng thanh toán tiền phòng (${FormatUtils.currency(tongTienThucTe)}) hoặc liên hệ BQL qua SĐT/Zalo: ${LienHeHelper.defaultHotlineDisplay} để được hỗ trợ mở lại vân tay.\n'
                              '• Bấm "Thanh toán / VietQR" bên dưới để gạch nợ tự động 24/7.')
                        : (overdueDays >= 5
                            ? (isPartial
                                ? '• CẢNH BÁO TRỄ HẠN ĐỢT 2 $overdueDays NGÀY: Nếu không tiếp tục đóng tiền còn lại (${FormatUtils.currency(tongTienThucTe)}), hệ thống sẽ TẠM KHÓA VÂN TAY ra vào phòng của bạn!\n'
                                  '• Nhà trọ KHÔNG áp dụng chính sách gia hạn tiền phòng.\n'
                                  '• Hướng giải quyết: Bấm "Thanh toán Đợt 2 / VietQR" bên dưới để đóng tiền ngay lập tức, tránh bị khóa vân tay.'
                                : '• CẢNH BÁO QUÁ HẠN $overdueDays NGÀY: Nếu không tiếp tục đóng tiền (${FormatUtils.currency(tongTienThucTe)}), hệ thống sẽ TẠM KHÓA VÂN TAY ra vào phòng của bạn!\n'
                                  '• Nhà trọ KHÔNG áp dụng chính sách gia hạn tiền phòng.\n'
                                  '• Hướng giải quyết: Bấm "Thanh toán / VietQR" bên dưới để đóng tiền ngay lập tức, tránh bị khóa vân tay.')
                            : (isPartial
                                ? '• Khoản nợ Đợt 2 chưa được thanh toán (${FormatUtils.currency(tongTienThucTe)}).\n'
                                  '• Trễ hạn 5 ngày: Cảnh báo sắp khóa vân tay nếu không đóng tiền.\n'
                                  '• Trễ hạn 10 ngày: Hệ thống sẽ khóa vân tay ra vào phòng.\n'
                                  '• Bấm "Thanh toán Đợt 2 / VietQR" bên dưới để hoàn tất đóng tiền ngay lập tức.'
                                : '• Hóa đơn tiền phòng tháng này chưa được thanh toán (${FormatUtils.currency(tongTienThucTe)}).\n'
                                  '• Trễ hạn 5 ngày: Cảnh báo sắp khóa vân tay nếu không đóng tiền.\n'
                                  '• Trễ hạn 10 ngày: Hệ thống sẽ khóa vân tay ra vào phòng.\n'
                                  '• Bấm "Thanh toán / VietQR" bên dưới để hoàn tất đóng tiền ngay lập tức.')),
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                  if (overdueDays >= 10) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: ElevatedButton.icon(
                              onPressed: () => LienHeHelper.moZaloChat(context),
                              icon: const Icon(Icons.chat_bubble_rounded, size: 14),
                              label: const Text(
                                'Zalo BQL',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: OutlinedButton.icon(
                              onPressed: () => LienHeHelper.goiDien(context),
                              icon: const Icon(Icons.phone_in_talk_rounded, size: 14),
                              label: const Text(
                                'Gọi Hotline',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(color: Color(0xFFF87171)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: () => _showHuongDanQuaHanModal(hd),
                      icon: const Icon(Icons.gavel_rounded, size: 16),
                      label: const Text(
                        'Xem quy định xử lý quá hạn & Hotline BQL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFF87171)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // Payment Actions Row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showVietQrModal(),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0F2042), Color(0xFF09638E)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF0F2042,
                          ).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isPaid
                                  ? Icons.verified_rounded
                                  : Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isPaid
                                  ? 'Xem biên lai / QR'
                                  : isPartial
                                  ? 'Thanh toán Đợt 2 / VietQR'
                                  : 'Thanh toán / VietQR',
                              style: const TextStyle(
                                fontSize: 14,
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
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _showDownloadBillToast(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    color: Color(0xFF0F2042),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBillItem(
    IconData icon,
    String label,
    String value,
    Color iconColor,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // 4. LỐI TẮT THAO TÁC (QUICK SHORTCUTS GRID)
  Widget _buildQuickShortcutsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Text(
              'Lối tắt thao tác',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            Spacer(),
            Text(
              'Hỗ trợ 24/7',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0284C7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Grid 2 Columns
        Row(
          children: [
            Expanded(
              child: _buildShortcutCard(
                icon: Icons.build_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBg: const Color(0xFFFEE2E2),
                title: 'Báo sự cố',
                subtitle: 'Điện nước, điều hòa',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManHinhBaoSuCo(
                        tenPhong: 'Phòng 203 • Gác lửng',
                        toaNha: 'Tòa A (Tầng 2)',
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildShortcutCard(
                icon: Icons.person_add_alt_1_rounded,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFE0F2FE),
                title: 'Khách qua đêm',
                subtitle: 'Đăng ký & chờ duyệt',
                onTap: () {
                  final curRoomDigits =
                      maPhong.replaceAll(RegExp(r'[^0-9]'), '');
                  final curRoomName = _phong?.tenHienThi ??
                      (curRoomDigits.isNotEmpty
                          ? 'Phòng $curRoomDigits'
                          : (widget.roomNumber != null &&
                                  widget.roomNumber!.isNotEmpty
                              ? 'Phòng ${widget.roomNumber}'
                              : 'Phòng 203'));
                  final curToaNha = _phong?.toaNha.isNotEmpty == true
                      ? _phong!.toaNha
                      : 'Kiêu Giang 2';
                  _showLuaChonKhachQuaDem(
                    context,
                    curRoomName,
                    curToaNha,
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_isNguoiDaiDien) ...[
          // Giao diện đầy đủ cho Người đại diện
          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.speed_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Chỉ số điện nước',
                  subtitle: 'Chốt số ngày 28',
                  onTap: () => _showMeterReadingModal(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.assignment_outlined,
                  iconColor: const Color(0xFF8B5CF6),
                  iconBg: const Color(0xFFF3E8FF),
                  title: 'Gia hạn hợp đồng',
                  subtitle: 'Ký điện tử & cọc',
                  onTap: () => _showExtendContractModal(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  iconBg: const Color(0xFFCFFAFE),
                  title: 'Chuyển phòng',
                  subtitle: 'Đổi phòng trong hệ thống',
                  onTap: () => _showChangeRoomModal(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.history_edu_rounded,
                  iconColor: const Color(0xFF0F766E),
                  iconBg: const Color(0xFFCCFBF1),
                  title: 'Lịch sử đổi phòng',
                  subtitle: 'Theo dõi đơn & tiến độ',
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomTransferHistoryScreen(
                          currentRoomNumber: curRoom,
                          maHopDong: _hopDong?.maHopDong ?? maHopDong,
                          hopDong: _hopDong,
                        ),
                      ),
                    ).then((_) => _fetchTenantData());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.history_edu_rounded,
                  iconColor: const Color(0xFF09638E),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Lịch sử gia hạn',
                  subtitle: 'Phụ lục & đơn đã nộp',
                  onTap: () => _showExtendContractHistoryModal(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.assignment_return_rounded,
                  iconColor: const Color(0xFFE11D48),
                  iconBg: const Color(0xFFFFE4E6),
                  title: _hopDong?.trangThai == 'Đã thanh lý'
                      ? 'Biên bản thanh lý'
                      : 'Trả phòng & Cọc',
                  subtitle: _hopDong?.trangThai == 'Đã thanh lý'
                      ? 'Hợp đồng kết thúc'
                      : 'Chốt số & hoàn cọc',
                  onTap: () => _showTerminateContractModal(),
                ),
              ),
            ],
          ),
        ] else ...[
          // Giao diện cho Bạn ở cùng (Thành viên): Ẩn hoàn toàn các chức năng Gia hạn, Chuyển phòng, Thanh lý
          Row(
            children: [
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.speed_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Chỉ số điện nước',
                  subtitle: 'Chốt số ngày 28',
                  onTap: () => _showMeterReadingModal(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildShortcutCard(
                  icon: Icons.shield_outlined,
                  iconColor: const Color(0xFF16A34A),
                  iconBg: const Color(0xFFDCFCE7),
                  title: 'Nội quy tòa nhà',
                  subtitle: 'Quy định & cam kết',
                  onTap: () => _showRulesModal(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildShortcutCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 128, // <-- Cố định chiều cao để các ô luôn bằng phẳng nhau
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 16,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // MODAL LỰA CHỌN KHÁCH QUA ĐÊM (ĐĂNG KÝ MỚI HOẶC XEM CHỜ DUYỆT)
  void _showLuaChonKhachQuaDem(
    BuildContext context,
    String roomName,
    String toaNhaName,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.night_shelter_rounded,
                      color: Color(0xFF0284C7),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Khách Lưu Trú Qua Đêm',
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$roomName • $toaNhaName',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Nút 1: Đăng ký khách mới (Quét AI)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManHinhDangKyKhachQuaDem(
                        tenPhong: roomName,
                        toaNha: toaNhaName,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Color(0xFF0284C7),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Đăng ký khách qua đêm mới',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Quét ảnh CCCD tự động điền thông tin',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Nút 2: Xem danh sách & Chờ duyệt
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManHinhLichSuLuuTru(
                        tenPhong: roomName,
                        toaNha: toaNhaName,
                        initialTabIndex: 0, // Mở tab Tất cả để luôn thấy đầy đủ cả khách đã duyệt & chờ duyệt
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.history_edu_rounded,
                          color: Color(0xFFD97706),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Danh sách khách & Lịch sử lưu trú',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Xem danh sách khách đã duyệt, chờ duyệt & hủy yêu cầu',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFD97706),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 5. THÀNH VIÊN PHÒNG
  Widget _buildRoomMembersSection() {
    final memberCount = _thanhVienPhong.isNotEmpty ? _thanhVienPhong.length : 1;
    final emojis = ['🐥', '🐷', '🦊', '🐻', '🐼'];
    final bgColors = [
      const Color(0xFFFEF08A),
      const Color(0xFFFCE7F3),
      const Color(0xFFCFFAFE),
      const Color(0xFFE0E7FF),
      const Color(0xFFDCFCE7),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.groups_rounded,
                color: Color(0xFF09638E),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Thành viên ${_phong?.tenHienThi ?? 'phòng $maPhong'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$memberCount người',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (_thanhVienPhong.isNotEmpty) ...[
            for (int i = 0; i < _thanhVienPhong.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _buildMemberRow(
                emoji: emojis[i % emojis.length],
                emojiBg: bgColors[i % bgColors.length],
                name: _thanhVienPhong[i].hoTenKhach.isNotEmpty
                    ? _thanhVienPhong[i].hoTenKhach
                    : displayName,
                role: _thanhVienPhong[i].vaiTro.isNotEmpty
                    ? _thanhVienPhong[i].vaiTro
                    : (i == 0
                          ? 'Trưởng phòng (Đại diện thuê)'
                          : 'Người ở cùng'),
                isLeader:
                    _thanhVienPhong[i].vaiTro.toLowerCase().contains(
                      'trưởng',
                    ) ||
                    i == 0,
              ),
            ],
          ] else ...[
            _buildMemberRow(
              emoji: '🐥',
              emojiBg: const Color(0xFFFEF08A),
              name: displayName,
              role: 'Trưởng phòng (Đại diện thuê)',
              isLeader: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMemberRow({
    required String emoji,
    required Color emojiBg,
    required String name,
    required String role,
    required bool isLeader,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: emojiBg, shape: BoxShape.circle),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isLeader
                        ? const Color(0xFFE0F2FE)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    role,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isLeader
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF64748B),
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

  // 6. THÔNG BÁO NHÀ TRỌ
  Widget _buildBuildingNoticesSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Color(0xFF0284C7),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Thông báo nhà trọ',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Mới',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE11D48),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showNotificationModal(),
                child: const Text(
                  'Tất cả >',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF09638E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Notice items
          ...(() {
            final activeList = _danhSachThongBao.take(2).toList();
            if (activeList.isEmpty) {
              return [
                _buildNoticeItem(
                  icon: Icons.plumbing_rounded,
                  iconBg: const Color(0xFF0F766E),
                  title: 'Bảo trì hệ thống máy bơm mái',
                  time: 'Hôm nay',
                  content:
                      'Tạm ngắt nguồn nước sinh hoạt từ 13:30 - 15:30 ngày 28/10 để sục rửa bồn chứa. Quý cư dân vui lòng dự trữ nước.',
                ),
                const SizedBox(height: 10),
                _buildNoticeItem(
                  icon: Icons.lock_outline_rounded,
                  iconBg: const Color(0xFF0284C7),
                  title: 'Quy định an ninh sau 23h00',
                  time: '2 ngày trước',
                  content:
                      'Cổng chính khóa tự động sau 23:00. Vui lòng quét vân tay khi ra vào và không giữ cửa cho người lạ.',
                ),
              ];
            }
            return activeList.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              final loai = item['loai']?.toString() ?? '';
              IconData icon = Icons.campaign_rounded;
              Color bg = const Color(0xFF09638E);
              if (loai == 'chuyen_phong') {
                icon = Icons.swap_horiz_rounded;
                bg = const Color(0xFF0284C7);
              } else if (loai == 'hoa_don') {
                icon = Icons.receipt_long_rounded;
                bg = const Color(0xFFD97706);
              } else if (loai == 'su_co') {
                icon = Icons.handyman_rounded;
                bg = const Color(0xFF0F766E);
              }
              final onXem = item['on_xem'] as VoidCallback?;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (idx > 0) const SizedBox(height: 10),
                  _buildNoticeItem(
                    icon: icon,
                    iconBg: bg,
                    title: item['tieu_de']?.toString() ?? '',
                    time: item['da_doc'] == false ? 'Mới' : 'Đã xem',
                    content: item['noi_dung']?.toString() ?? '',
                    onTap: () {
                      setState(() {
                        item['da_doc'] = true;
                        final id = item['id']?.toString();
                        if (id != null) _danhSachIdDaDoc.add(id);
                      });
                      if (onXem != null) {
                        onXem();
                      } else {
                        _showNotificationModal();
                      }
                    },
                  ),
                ],
              );
            }).toList();
          })(),
        ],
      ),
    );
  }

  Widget _buildNoticeItem({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String time,
    required String content,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          fontSize: 11,
                          color: time == 'Mới'
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF0284C7),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 2: PHÒNG (ROOM DETAILS) ====================
  Widget _buildRoomTab() {
    final roomName = _phong?.tenHienThi ?? 'Phòng $maPhong';
    final toaNhaName = _phong?.toaNha.isNotEmpty == true
        ? _phong!.toaNha
        : 'Tòa Kiêu Giang 2';
    final tangNum = _phong?.tang ?? 3;
    final giaThue = _phong?.giaThue ?? _hopDong?.giaThueThaoThuan ?? 2800000;
    final tienCoc = _phong?.tienDatCoc ?? _hopDong?.tienDatCoc ?? 2800000;
    final loaiPhong = _phong?.maLoaiPhong ?? 'Studio Ban Công (2 người)';
    final ngayKt = _hopDong?.ngayKtFormatted ?? '15/12/2025';

    // Tính số tháng còn lại
    int monthsLeft = 7;
    if (_hopDong?.ngayKt != null) {
      try {
        final dt = DateTime.parse(_hopDong!.ngayKt);
        final diff = dt.difference(DateTime.now()).inDays;
        if (diff > 0) monthsLeft = (diff / 30).ceil();
      } catch (_) {}
    }

    final memberCount = _thanhVienPhong.isNotEmpty ? _thanhVienPhong.length : 2;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. TOP HEADER PHÒNG
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Kiêu Giang',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF09638E),
                      letterSpacing: 0.2,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Phòng',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Notification Bell
              GestureDetector(
                onTap: () => _showNotificationModal(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF5FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF09638E).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.notifications_none_rounded,
                        color: Color(0xFF09638E),
                        size: 22,
                      ),
                      if (_soThongBaoChuaDoc > 0)
                        Positioned(
                          top: 5,
                          right: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE11D48),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              _soThongBaoChuaDoc > 9
                                  ? '9+'
                                  : '$_soThongBaoChuaDoc',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Profile Avatar
              GestureDetector(
                onTap: () => setState(() => _selectedTabIndex = 4),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF5FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF09638E).withValues(alpha: 0.15),
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF08A),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🐥', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2. HERO ROOM CARD (GRADIENT XANH DƯƠNG CAO CẤP)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0C5A8A), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0C5A8A).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Status Badge & Giá thuê
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Đang thuê • Còn $monthsLeft tháng',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Giá thuê tháng',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              FormatUtils.currency(giaThue.toDouble()),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'đ',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Room Name & Tầng
                Text(
                  roomName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tầng $tangNum • $toaNhaName',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 14),

                // 2 Chips thông tin (Loại phòng & Tiền cọc)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.meeting_room_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Loại phòng',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  Text(
                                    loaiPhong,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Tiền cọc giữ chỗ',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  Text(
                                    '${FormatUtils.currency(tienCoc.toDouble())}đ',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Expiry Date
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Hạn hợp đồng: $ngayKt',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2 Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showContractModal(),
                        icon: const Icon(
                          Icons.description_outlined,
                          size: 15,
                          color: Color(0xFF09638E),
                        ),
                        label: const Text(
                          'Chi tiết',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF09638E),
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF09638E),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    if (_isNguoiDaiDien) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showExtendContractModal(),
                          icon: const Icon(
                            Icons.autorenew_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Gia hạn',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withValues(alpha: 0.22),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _showTerminateContractModal(),
                          icon: const Icon(
                            Icons.assignment_return_outlined,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: Text(
                            _hopDong?.trangThai == 'Đã thanh lý'
                                ? 'Biên bản'
                                : 'Trả phòng',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(
                              0xFFE11D48,
                            ).withValues(alpha: 0.55),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. SECTION: LỐI TẮT QUẢN LÝ PHÒNG (ĐÃ BỎ THẺ TỪ)
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: Color(0xFF09638E),
                size: 19,
              ),
              const SizedBox(width: 6),
              const Text(
                'Lối tắt quản lý phòng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const Spacer(),
              const Text(
                'Thao tác nhanh',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hàng 1: [Đăng ký khách] & [Nội quy tòa nhà]
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      _showLuaChonKhachQuaDem(context, roomName, toaNhaName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_add_alt_1_rounded,
                            color: Color(0xFF2563EB),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Đăng ký khách',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Lưu trú qua đêm',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showRulesModal(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shield_outlined,
                            color: Color(0xFF16A34A),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Nội quy tòa nhà',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Quy định chung',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isNguoiDaiDien) ...[
            const SizedBox(height: 10),

            // Hàng 2: [Chuyển phòng] & [Lịch sử đổi phòng]
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showChangeRoomModal(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCFFAFE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: Color(0xFF06B6D4),
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Chuyển phòng',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Đổi phòng khác',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      final curRoom =
                          _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RoomTransferHistoryScreen(
                            currentRoomNumber: curRoom,
                            maHopDong: _hopDong?.maHopDong ?? maHopDong,
                            hopDong: _hopDong,
                          ),
                        ),
                      ).then((_) => _fetchTenantData());
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFCCFBF1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.history_edu_rounded,
                              color: Color(0xFF0F766E),
                              size: 22,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Lịch sử đổi phòng',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Tiến độ & biên bản',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // 4. SECTION: THÀNH VIÊN PHÒNG (BỎ ICON GỌI)
          Row(
            children: [
              const Text(
                'Thành viên phòng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$memberCount người',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showAddMemberModal(),
                child: Row(
                  children: const [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      size: 14,
                      color: Color(0xFF09638E),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Thêm thành viên',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF09638E),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Danh sách thành viên (ĐÃ BỎ ICON GỌI)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                if (_thanhVienPhong.isNotEmpty) ...[
                  for (int i = 0; i < _thanhVienPhong.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 20, color: Color(0xFFF1F5F9)),
                    _buildRoomMemberItem(
                      emoji: i == 0 ? '🐥' : (i == 1 ? '🐷' : '🦊'),
                      emojiBg: i == 0
                          ? const Color(0xFFFEF08A)
                          : const Color(0xFFFCE7F3),
                      name: _thanhVienPhong[i].hoTenKhach.isNotEmpty
                          ? _thanhVienPhong[i].hoTenKhach
                          : (i == 0 ? displayName : 'Thành viên $i'),
                      role: i == 0 ? 'TRƯỞNG PHÒNG' : 'Ở CÙNG',
                      isLeader: i == 0,
                    ),
                  ],
                ] else ...[
                  _buildRoomMemberItem(
                    emoji: '🐥',
                    emojiBg: const Color(0xFFFEF08A),
                    name: displayName,
                    role: 'TRƯỞNG PHÒNG',
                    isLeader: true,
                  ),
                  const Divider(height: 20, color: Color(0xFFF1F5F9)),
                  _buildRoomMemberItem(
                    emoji: '🐷',
                    emojiBg: const Color(0xFFFCE7F3),
                    name: 'Phượng Uyên',
                    role: 'Ở CÙNG',
                    isLeader: false,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 5. SECTION: THIẾT BỊ & TIỆN NGHI
          Row(
            children: [
              const Flexible(
                child: Text(
                  'Thiết bị & Tiện nghi',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Trang bị sẵn có',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildDeviceRow(
                  icon: Icons.ac_unit_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Máy lạnh Daikin Inverter 1.5 HP',
                  subtitle: 'Treo tường • Điều khiển từ xa',
                  status: 'Tốt',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDeviceRow(
                  icon: Icons.kitchen_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Tủ lạnh Aqua 130L',
                  subtitle: 'Hai cánh • Đóng tuyết tự xả',
                  status: 'Tốt',
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildDeviceRow(
                  icon: Icons.water_damage_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Bình nước nóng Ariston 20L',
                  subtitle: 'Chống giật ELCB an toàn',
                  status: 'Tốt',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRoomMemberItem({
    required String emoji,
    required Color emojiBg,
    required String name,
    required String role,
    required bool isLeader,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: emojiBg, shape: BoxShape.circle),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: isLeader
                          ? const Color(0xFF09638E)
                          : const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isLeader
                            ? Colors.white
                            : const Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String status,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                status,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF15803D),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TAB 3: HÓA ĐƠN ====================
  Widget _buildBillTab() {
    return RefreshIndicator(
      onRefresh: _fetchTenantData,
      color: const Color(0xFF09638E),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hóa đơn & Thanh toán',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 14),
            if (_soHoaDonChuaThanhToan > 0)
              _buildMonthlyBillCard()
            else
              _buildAllPaidBanner(),
            const SizedBox(height: 20),
            Row(
              children: [
                const Flexible(
                  child: Text(
                    'Lịch sử thanh toán gần đây',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvoiceHistoryScreen(
                          roomName: roomDisplay,
                          maHopDong: maHopDong,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Xem tất cả >',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F2042),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_danhSachHoaDon.isNotEmpty) ...[
              for (final bill in _danhSachHoaDon) ...[
                _buildBillItemCard(bill),
                const SizedBox(height: 8),
              ],
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 28,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 36,
                      color: Color(0xFF94A3B8),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Chưa có lịch sử hóa đơn nào trên hệ thống',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
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

  Widget _buildAllPaidBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF86EFAC)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0xFF16A34A),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Không có hóa đơn nợ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF14532D),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _hoaDonMoiNhat != null
                      ? 'Kỳ ${_hoaDonMoiNhat!.thangNam.isNotEmpty ? _hoaDonMoiNhat!.thangNam : "#${_hoaDonMoiNhat!.maHoaDon}"} đã quyết toán đủ.'
                      : 'Bạn đã hoàn tất thanh toán mọi khoản phí.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF15803D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBillItemCard(HoaDonModel bill) {
    final isPaid = bill.trangThai == 'Đã thanh toán';
    final isPartial = bill.trangThai == 'Thanh toán một phần';
    final amountToDisplay = isPaid ? bill.tongTienGoc : bill.tongTien;
    final dateDisplay = isPaid
        ? 'Đã thanh toán ngày ${bill.hanDongTienFormatted}'
        : 'Hạn đóng: ${bill.hanDongTienFormatted}';

    return GestureDetector(
      onTap: () {
        if (isPaid) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentCompletedScreen(
                hoaDon: bill,
                tenPhong: roomDisplay,
                bankName: 'MB Bank (Quân Đội)',
                transactionTime: bill.hanDongTienFormatted,
                amountPaid: bill.tongTienGoc,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentScreen(
                hoaDon: bill,
                tenPhong: roomDisplay,
                onPaymentSuccess: (_) => _fetchTenantData(),
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPaid
                ? const Color(0xFFE2E8F0)
                : (isPartial
                      ? const Color(0xFFFCD34D)
                      : const Color(0xFFFCA5A5)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isPaid
                    ? const Color(0xFFDCFCE7)
                    : (isPartial
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPaid
                    ? Icons.check_circle_rounded
                    : (isPartial
                          ? Icons.hourglass_top_rounded
                          : Icons.pending_actions_rounded),
                color: isPaid
                    ? const Color(0xFF16A34A)
                    : (isPartial
                          ? const Color(0xFFD97706)
                          : const Color(0xFFE11D48)),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          bill.thangNam.isNotEmpty
                              ? 'Hóa đơn ${bill.thangNam}'
                              : 'Hóa đơn #${bill.maHoaDon}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? const Color(0xFFDCFCE7)
                              : (isPartial
                                    ? const Color(0xFFFEF3C7)
                                    : const Color(0xFFFFE4E6)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          bill.trangThai,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: isPaid
                                ? const Color(0xFF16A34A)
                                : (isPartial
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFFE11D48)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    dateDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              FormatUtils.currency(amountToDisplay),
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: isPaid
                    ? const Color(0xFF0F2042)
                    : const Color(0xFFE11D48),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 4: SỰ CỐ & YÊU CẦU SỬA CHỮA ====================
  Widget _buildIncidentTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Tiêu đề và Nút Báo sự cố mới (Chuyển sang màn hình chụp ảnh thật)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quản lý sự cố',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      roomDisplay,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManHinhBaoSuCo(
                        tenPhong: _phong?.tenHienThi ?? 'Phòng $maPhong',
                        toaNha: _phong?.toaNha ?? 'Kiêu Giang 1',
                        maPhong: maPhong,
                      ),
                    ),
                  );
                  _fetchTenantData();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'Báo sự cố mới',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Banner Hỗ trợ kỹ thuật 24/7
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFBAE6FD),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Color(0xFF09638E),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Kỹ thuật tòa nhà túc trực 24/7',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Ban Quản Lý hỗ trợ khẩn cấp 24/7',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 3. Danh sách sự cố gần đây
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Lịch sử yêu cầu sửa chữa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_danhSachSuCo.length} sự cố',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_danhSachSuCo.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: const [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 44,
                    color: Color(0xFF10B981),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Hiện chưa có sự cố nào cần xử lý',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Mọi trang thiết bị phòng trọ đều đang hoạt động tốt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _danhSachSuCo.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final suCo = _danhSachSuCo[index];
                return _buildIncidentCardFromData(suCo);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIncidentCardFromData(Map<String, dynamic> suCo) {
    final rawNoiDung = suCo['noi_dung']?.toString() ?? '';
    String moTa = rawNoiDung;
    List<String> listHinhAnh = [];

    try {
      if (rawNoiDung.startsWith('{') && rawNoiDung.endsWith('}')) {
        final decoded = jsonDecode(rawNoiDung);
        moTa = decoded['mo_ta']?.toString() ?? rawNoiDung;
        if (decoded['hinh_anh'] is List) {
          listHinhAnh = List<String>.from(decoded['hinh_anh']);
        }
      }
    } catch (_) {}

    if (listHinhAnh.isEmpty && suCo['hinh_anh'] != null) {
      listHinhAnh.add(suCo['hinh_anh'].toString());
    }

    final category = suCo['danh_muc']?.toString() ?? 'Khác';
    final status = suCo['trang_thai']?.toString() ?? 'Chờ xử lý';
    final priority = suCo['muc_do_uu_tien']?.toString() ?? 'Bình thường';
    final maSuCo = suCo['ma_su_co']?.toString() ?? '';

    // Định dạng ngày
    String dateStr = '';
    final rawDate = suCo['ngay_bao_cao']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      try {
        final dt = DateTime.parse(rawDate).toLocal();
        dateStr =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {
        dateStr = rawDate.split('T').first;
      }
    }

    // Màu trạng thái
    Color statusColor;
    Color statusBg;
    if (status == 'Đã hoàn thành' || status == 'Đã xử lý xong') {
      statusColor = const Color(0xFF16A34A);
      statusBg = const Color(0xFFDCFCE7);
    } else if (status == 'Đang xử lý' || status == 'Đang sửa chữa') {
      statusColor = const Color(0xFF0284C7);
      statusBg = const Color(0xFFE0F2FE);
    } else {
      statusColor = const Color(0xFFD97706);
      statusBg = const Color(0xFFFEF3C7);
    }

    // Icon danh mục
    IconData icon;
    switch (category) {
      case 'Điện':
      case 'Điện - Nước':
        icon = Icons.bolt_rounded;
        break;
      case 'Nước':
        icon = Icons.science_outlined;
        break;
      case 'Điều hòa':
        icon = Icons.ac_unit_rounded;
        break;
      case 'Cửa/Khóa':
        icon = Icons.lock_open_rounded;
        break;
      case 'Wifi/Mạng':
        icon = Icons.wifi_rounded;
        break;
      default:
        icon = Icons.build_rounded;
        break;
    }

    return InkWell(
      onTap: () => _showIncidentDetailModal(suCo, moTa, listHinhAnh),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF09638E), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              moTa,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _xacNhanXoaSuCo(suCo),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.all(3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: Color(0xFFDC2626),
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              category,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          if (priority == 'Khẩn cấp') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Khẩn cấp',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            dateStr.isNotEmpty
                                ? 'Ngày: $dateStr'
                                : 'Mã: $maSuCo',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (listHinhAnh.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 14,
                    color: Color(0xFF09638E),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Đính kèm ${listHinhAnh.length} ảnh hiện trạng (Bấm để xem)',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF09638E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 55,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: listHinhAnh.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (ctx, i) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 55,
                        height: 55,
                        color: const Color(0xFFF1F5F9),
                        child: _buildIncidentImageWidget(listHinhAnh[i]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showIncidentDetailModal(
    Map<String, dynamic> suCo,
    String moTa,
    List<String> listHinhAnh,
  ) {
    final category = suCo['danh_muc']?.toString() ?? 'Khác';
    final status = suCo['trang_thai']?.toString() ?? 'Chờ xử lý';
    final priority = suCo['muc_do_uu_tien']?.toString() ?? 'Bình thường';
    final maSuCo = suCo['ma_su_co']?.toString() ?? '';
    final maPhong = suCo['ma_phong']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chi tiết sự cố ($maSuCo)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'Đã hoàn thành'
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: status == 'Đã hoàn thành'
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                    Row(
                      children: [
                        Text(
                          'Phòng: $maPhong',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Text(
                          'Danh mục: $category',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ưu tiên: $priority',
                      style: TextStyle(
                        color: priority == 'Khẩn cấp'
                            ? Colors.red
                            : Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const Divider(height: 16),
                    const Text(
                      'Mô tả hiện trạng:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      moTa,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
              if (listHinhAnh.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Hình ảnh hiện trường do cư dân gửi (${listHinhAnh.length} ảnh):',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: listHinhAnh.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      return InkWell(
                        onTap: () =>
                            _showZoomImageDialog(context, listHinhAnh[i]),
                        borderRadius: BorderRadius.circular(10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 140,
                            height: 110,
                            color: const Color(0xFFF1F5F9),
                            child: _buildIncidentImageWidget(listHinhAnh[i]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '* Nhấn vào ảnh để xem kích thước lớn',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _xacNhanXoaSuCo(suCo);
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Xóa Báo Cáo',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        backgroundColor: const Color(0xFFFFF1F2),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Đóng',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _xacNhanXoaSuCo(Map<String, dynamic> suCo) async {
    final maSuCo = suCo['ma_su_co']?.toString() ?? '';
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFDC2626),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Xóa Báo Cáo Sự Cố?',
                  style: TextStyle(
                    fontSize: 17.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bạn có chắc chắn muốn xóa phiếu báo sự cố $maSuCo không? (Thao tác này giúp bạn gỡ bỏ sự cố khi lỡ tải nhầm ảnh hoặc thông tin).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text(
                          'Giữ lại',
                          style: TextStyle(color: Color(0xFF475569)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text(
                          'Xác nhận xóa',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client
            .from('su_co_bao_tri')
            .delete()
            .eq('ma_su_co', maSuCo);

        if (mounted) {
          setState(() {
            _danhSachSuCo.removeWhere((item) => item['ma_su_co'] == maSuCo);
          });
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Đã Xóa Báo Cáo',
            noiDung:
                'Phiếu báo sự cố $maSuCo đã được xóa thành công khỏi hệ thống.',
            type: ThongBaoType.thanhCong,
          );
        }
      } catch (err) {
        if (mounted) {
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Không Thể Xóa',
            noiDung: 'Đã xảy ra lỗi khi xóa: rr',
            type: ThongBaoType.thatBai,
          );
        }
      }
    }
  }

  Widget _buildIncidentImageWidget(String imgStr) {
    if (imgStr.startsWith('data:image')) {
      try {
        final b64 = imgStr.contains(',') ? imgStr.split(',').last : imgStr;
        return Image.memory(base64Decode(b64), fit: BoxFit.cover);
      } catch (_) {
        return const Icon(Icons.broken_image_rounded, color: Colors.grey);
      }
    } else if (imgStr.startsWith('http')) {
      return Image.network(
        imgStr,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image_rounded, color: Colors.grey),
      );
    }
    return const Icon(Icons.image_rounded, color: Colors.grey);
  }

  void _showZoomImageDialog(BuildContext context, String imgStr) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: _buildIncidentImageWidget(imgStr),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                radius: 16,
                child: Icon(Icons.close, color: Colors.white, size: 18),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentItem(
    String title,
    String status,
    String date,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Ngày báo: $date',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== TAB 5: CÁ NHÂN ====================
  /// Chuyển đổi mã vai trò kỹ thuật → nhãn hiển thị thân thiện
  String _formatVaiTro(String raw) {
    final clean = raw.toLowerCase().replaceAll(' ', '').replaceAll('_', '');
    if (clean.contains('daidien') || clean.contains('đạidiện') || clean.contains('truongphong') || clean.contains('trưởngphòng') || clean == 'landlord') {
      return 'Người đại diện';
    }
    if (clean.contains('ocung') || clean.contains('ởcùng') || clean.contains('thanhvien') || clean.contains('thànhviên')) {
      return 'Bạn ở cùng';
    }
    switch (clean) {
      case 'cudan':
      case 'khachthue':
      case 'tenant':
        return 'Cư dân';
      case 'admin':
        return 'Quản trị viên';
      case 'quanly':
      case 'manager':
        return 'Quản lý';
      default:
        return raw.isEmpty ? 'Cư dân' : raw;
    }
  }

  Widget _buildProfileTab() {
    final String tenCuDan =
        _khachThueData?['ho_ten_khach']?.toString().isNotEmpty == true
        ? _khachThueData!['ho_ten_khach'].toString()
        : displayName;

    // Lấy vai trò từ chi_tiet_hop_dong_khach_thue (ưu tiên) hoặc tài khoản
    String vaiTroLabel;
    {
      final currentMaKhach = _khachThueData?['ma_khach']?.toString();
      final myMember = _thanhVienPhong.where((tv) =>
          (currentMaKhach != null && currentMaKhach.isNotEmpty && tv.maKhach == currentMaKhach) ||
          (tv.hoTenKhach.trim().toLowerCase() == tenCuDan.trim().toLowerCase())
      ).firstOrNull;
      final rawVaiTro = (myMember != null && myMember.vaiTro.isNotEmpty)
          ? myMember.vaiTro
          : (AuthService.currentUser?.vaiTro ?? '');
      vaiTroLabel = _formatVaiTro(rawVaiTro);
    }

    // Bạn cùng phòng (loại trừ chính mình nếu có)
    String banCungPhongTen = 'Phượng Uyên';
    if (_thanhVienPhong.isNotEmpty) {
      final khacMinh = _thanhVienPhong
          .where((tv) => tv.hoTenKhach != tenCuDan)
          .toList();
      if (khacMinh.isNotEmpty) {
        banCungPhongTen = khacMinh.first.hoTenKhach;
      } else {
        banCungPhongTen = _thanhVienPhong.first.hoTenKhach;
      }
    }

    final String phongVaTang = _phong != null
        ? 'P.${_phong!.maPhong} • Tầng ${_phong!.tang}'
        : 'P.${_hopDong?.maPhong ?? '203'} • Tầng 2';

    final String maHdDisplay = _hopDong?.maHopDong ?? 'HD-KG2-203-2024';
    String hanHopDongDisplay = '15/12/2025';
    if (_hopDong != null && _hopDong!.ngayKt.isNotEmpty) {
      try {
        final p = DateTime.parse(_hopDong!.ngayKt);
        hanHopDongDisplay =
            '${p.day.toString().padLeft(2, '0')}/${p.month.toString().padLeft(2, '0')}/${p.year}';
      } catch (_) {
        hanHopDongDisplay = _hopDong!.ngayKt;
      }
    }

    String billSummary = 'Tháng 02/2025 • Đã hoàn tất';
    if (_hoaDonMoiNhat != null) {
      try {
        final p = DateTime.parse(_hoaDonMoiNhat!.ngayLap);
        billSummary =
            'Tháng ${p.month.toString().padLeft(2, '0')}/${p.year} • ${_hoaDonMoiNhat!.trangThai}';
      } catch (_) {
        billSummary =
            '${_hoaDonMoiNhat!.ngayLap} • ${_hoaDonMoiNhat!.trangThai}';
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Header Profile (Kiêu Giang - Cá Nhân) ──────────
          Row(
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
                      color: Color(0xFF09638E),
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Cá Nhân',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _showNotificationModal(),
                    child: Container(
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
                            size: 20,
                            color: Color(0xFF334155),
                          ),
                          if (_soThongBaoChuaDoc > 0)
                            Positioned(
                              top: 8,
                              right: 9,
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
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    padding: const EdgeInsets.all(5),
                    child: Image.asset(
                      'assets/images/logo.png',
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.home_work_rounded,
                        size: 20,
                        color: Color(0xFF09638E),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Profile Card ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF1F5F9)),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar Vịt vàng + badge active xanh lá
                    Stack(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: const BoxDecoration(
                            color: Color(0xFFFEF08A),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('🐥', style: TextStyle(fontSize: 28)),
                          ),
                        ),
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Tên, Role, SĐT, CCCD
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tenCuDan,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2FE),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  vaiTroLabel,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  phongVaTang,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Icon Edit Profile
                    GestureDetector(
                      onTap: () async {
                        final updated = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManHinhChinhSuaHoSo(
                              khachThueData: _khachThueData,
                              tenPhong: _phong?.maPhong != null
                                  ? 'P.${_phong!.maPhong}'
                                  : 'P303',
                              maHopDong: _hopDong?.maHopDong ?? 'HD001',
                              vaiTro: vaiTroLabel,
                            ),
                          ),
                        );
                        if (updated == true) {
                          _fetchTenantData();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 10),
                // Bạn cùng phòng
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEDD5),
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text('🌸', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: [
                            const TextSpan(
                              text: 'Bạn cùng phòng: ',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text: banCungPhongTen,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF09638E),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDBEAFE)),
                      ),
                      child: const Text(
                        'Hợp lệ',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Section: HỒ SƠ ĐỊNH DANH CÁ NHÂN (XÁC THỰC eKYC) ──────────
          _buildEkycProfileCard(),
          const SizedBox(height: 18),

          // ── Section: PHƯƠNG TIỆN XE ĐĂNG KÝ ─────────────────────────
          _buildRegisteredVehiclesCard(),
          const SizedBox(height: 18),

          // ── Section 1: CĂN HỘ & HỢP ĐỒNG ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CĂN HỘ & HỢP ĐỒNG',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                  letterSpacing: 0.3,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  phongVaTang,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Card các mục Căn hộ & hợp đồng
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. Hợp đồng thuê điện tử
                _buildContractItem(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Hợp đồng thuê điện tử',
                  badge: (_hopDong != null && !_hopDong!.daKyBenB) ? 'CHƯA KÝ' : 'ACTIVE',
                  badgeColor: (_hopDong != null && !_hopDong!.daKyBenB)
                      ? const Color(0xFFD97706)
                      : const Color(0xFF059669),
                  badgeBg: (_hopDong != null && !_hopDong!.daKyBenB)
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFD1FAE5),
                  subtitle: '$maHdDisplay • Hết hạn: $hanHopDongDisplay',
                  onTap: () {
                    if (_hopDong != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ContractDetailScreen(
                            maHopDong: _hopDong!.maHopDong,
                          ),
                        ),
                      ).then((_) => _fetchTenantData());
                    } else {
                      ThongBaoHelper.hienToast(
                        context,
                        tieuDe: 'Chưa có hợp đồng',
                        noiDung: 'Chưa có thông tin hợp đồng của bạn.',
                        type: ThongBaoType.canhBao,
                      );
                    }
                  },
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

                // 2. Biên bản bàn giao thiết bị & tài sản phòng
                _buildContractItem(
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF16A34A),
                  iconBg: const Color(0xFFDCFCE7),
                  title: 'Biên bản bàn giao thiết bị & tài sản',
                  badge: _hopDong?.daXacNhanBanGiao == true ? 'ĐÃ BÀN GIAO' : 'CHỜ XÁC NHẬN',
                  badgeColor: _hopDong?.daXacNhanBanGiao == true ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                  badgeBg: _hopDong?.daXacNhanBanGiao == true ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  subtitle: _hopDong?.daXacNhanBanGiao == true
                      ? 'Đã kiểm tra & nhận đầy đủ ${_danhSachTaiSan.length} thiết bị phòng'
                      : 'Cần kiểm tra và ký xác nhận tài sản',
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    final user = AuthService.currentUser;
                    if (user != null && _khachThueData != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManHinhBienBanBanGiaoTaiSan(
                            user: user,
                            maKhach: _khachThueData!['ma_khach']?.toString() ?? '',
                            maHopDong: _hopDong?.maHopDong ?? maHopDong,
                            maPhong: curRoom,
                            khachThueData: _khachThueData!,
                            daXacNhan: _hopDong?.daXacNhanBanGiao == true,
                          ),
                        ),
                      ).then((_) => _fetchTenantData());
                    }
                  },
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

                // 3. Lịch sử hóa đơn & thanh toán
                _buildContractItem(
                  icon: Icons.receipt_long_outlined,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Lịch sử hóa đơn & thanh toán',
                  subtitle: billSummary,
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InvoiceHistoryScreen(
                          maHopDong: maHopDong,
                          roomName: _phong?.tenHienThi ?? 'Phòng $curRoom',
                        ),
                      ),
                    ).then((_) => _fetchTenantData());
                  },
                ),
                if (_isNguoiDaiDien) ...[
                  const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

                  // 4. Chấm dứt hợp đồng & Trả phòng
                  _buildContractItem(
                    icon: Icons.assignment_return_outlined,
                    iconColor: const Color(0xFFE11D48),
                    iconBg: const Color(0xFFFFE4E6),
                    title: 'Chấm dứt hợp đồng & Trả phòng',
                    badge: _hopDong?.trangThai == 'Đã thanh lý'
                        ? 'ĐÃ THANH LÝ'
                        : null,
                    badgeColor: const Color(0xFFE11D48),
                    badgeBg: const Color(0xFFFFE4E6),
                    subtitle: _hopDong?.trangThai == 'Đã thanh lý'
                        ? 'Xem biên bản bàn giao & hoàn cọc'
                        : 'Báo trả phòng, chốt điện nước & quyết toán hợp đồng',
                    onTap: () => _showTerminateContractModal(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Section 2: TIỆN ÍCH NHANH ───────────────────────
          const Text(
            'TIỆN ÍCH NHANH',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF475569),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // 1. Tạm trú (Khách qua đêm)
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.group_outlined,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Tạm trú',
                  subtitle: 'Khách qua đêm',
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManHinhDangKyKhachQuaDem(
                          tenPhong: _phong?.tenHienThi ?? 'Phòng $curRoom',
                          toaNha: _phong?.toaNha ?? 'Kiêu Giang 2',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),

              // 2. Báo hỏng (Kỹ thuật)
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.business_center_outlined,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Báo hỏng',
                  subtitle: 'Kỹ thuật',
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManHinhBaoSuCo(
                          tenPhong: _phong?.tenHienThi ?? 'Phòng $curRoom',
                          toaNha: _phong?.toaNha ?? 'Kiêu Giang 2',
                          maPhong: curRoom,
                        ),
                      ),
                    ).then((_) => _fetchTenantData());
                  },
                ),
              ),
              const SizedBox(width: 10),

              // 3. Điện nước (Chốt số)
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.speed_outlined,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Điện nước',
                  subtitle: 'Chốt số',
                  onTap: () {
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MeterReadingScreen(
                          maPhong: curRoom,
                          tenPhong: _phong?.tenHienThi ?? 'Phòng $curRoom',
                          maHopDong: maHopDong,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Section 3: CÀI ĐẶT & HỖ TRỢ ─────────────────────
          const Text(
            'CÀI ĐẶT & HỖ TRỢ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF475569),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. Thông báo ứng dụng (Switch)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.notifications_none_rounded,
                          size: 20,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Thông báo ứng dụng',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: 0.85,
                        child: Switch(
                          value: _thongBaoUngDung,
                          activeThumbColor: const Color(0xFF09638E),
                          activeTrackColor: const Color(0xFFBAE6FD),
                          onChanged: (val) async {
                            setState(() => _thongBaoUngDung = val);
                            await SystemNotificationService.setNotificationEnabled(
                              val,
                            );
                            if (mounted) {
                              ThongBaoHelper.hienToast(
                                context,
                                tieuDe: 'Thông báo ứng dụng',
                                noiDung: val
                                    ? 'Đã bật thông báo ứng dụng'
                                    : 'Đã tắt thông báo ứng dụng',
                                type: ThongBaoType.thongTin,
                                duration: const Duration(milliseconds: 1500),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, indent: 56, color: Color(0xFFF1F5F9)),

                // 2. Mật khẩu & PIN mở khóa
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManHinhMatKhauPin(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.security_rounded,
                            size: 19,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Đổi mật khẩu',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ── Nút Đăng xuất tài khoản ─────────────────────────
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _handleLogout(),
              icon: const Icon(
                Icons.logout_rounded,
                size: 18,
                color: Color(0xFFE11D48),
              ),
              label: const Text(
                'Đăng xuất tài khoản',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE11D48),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFE4E6),
                foregroundColor: const Color(0xFFE11D48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Footer phiên bản ────────────────────────────────
          const Center(
            child: Text(
              'Kiêu Giang House v2.0.4 • Tòa KG 2',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildContractItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    String? badge,
    Color? badgeColor,
    Color? badgeBg,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg ?? const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: badgeColor ?? const Color(0xFF059669),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF94A3B8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 10.5,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── THẺ HỒ SƠ ĐỊNH DANH CÁ NHÂN & CCCD eKYC (Được tinh gọn 2 cột sang trọng) ──
  Widget _buildEkycProfileCard() {
    final kt = _khachThueData ?? {};
    final soCccd = kt['cccd']?.toString() ?? kt['so_cccd']?.toString() ?? 'Chưa cập nhật';
    final hoTen = kt['ho_ten_khach']?.toString() ?? displayName;
    final soDt = kt['so_dt']?.toString() ?? (AuthService.currentUser?.tenDangNhap ?? 'Chưa cập nhật');
    final gioiTinh = kt['gioi_tinh']?.toString() ?? 'Nam';
    final diaChi = kt['dia_chi_thuong_tru']?.toString() ?? kt['dia_chi']?.toString() ?? 'Chưa cập nhật';
    final noiCap = kt['noi_cap_cccd']?.toString() ?? 'Cục Cảnh sát QLHC về TTXH';
    final nguoiLienHe = kt['nguoi_lien_he_khan_cap']?.toString() ?? 'Chưa cập nhật';
    
    String ngaySinhDisplay = 'Chưa cập nhật';
    if (kt['ngay_sinh'] != null) {
      try {
        final d = DateTime.parse(kt['ngay_sinh'].toString());
        ngaySinhDisplay = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        ngaySinhDisplay = kt['ngay_sinh'].toString();
      }
    }

    String ngayCapDisplay = 'Chưa cập nhật';
    if (kt['ngay_cap_cccd'] != null) {
      try {
        final d = DateTime.parse(kt['ngay_cap_cccd'].toString());
        ngayCapDisplay = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        ngayCapDisplay = kt['ngay_cap_cccd'].toString();
      }
    }

    final urlMatTruoc = kt['anh_cccd_mat_truoc']?.toString();
    final urlMatSau = kt['anh_cccd_mat_sau']?.toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Card ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_outlined, color: Color(0xFF0284C7), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HỒ SƠ ĐỊNH DANH CÁ NHÂN',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      'Dữ liệu hồ sơ số lưu trên hệ thống',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF16A34A)),
                    SizedBox(width: 4),
                    Text(
                      'Đã xác thực',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          // ── BỐ CỤC 2 CỘT GỌN GÀNG, ĐẸP MẮT ──
          // Hàng 1: Họ tên + Số CCCD
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCompactInfoTile(
                  label: 'HỌ VÀ TÊN',
                  value: hoTen,
                  icon: Icons.person_outline_rounded,
                  isBold: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SỐ CCCD ĐỊNH DANH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.fingerprint_rounded, size: 14, color: Color(0xFF09638E)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            soCccd,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF09638E),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (soCccd != 'Chưa cập nhật')
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: soCccd));
                              ThongBaoHelper.hienToast(
                                context,
                                tieuDe: 'Đã sao chép',
                                noiDung: 'Đã lưu số CCCD vào bộ nhớ tạm',
                                type: ThongBaoType.thanhCong,
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.copy_rounded, size: 13, color: Color(0xFF64748B)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Hàng 2: Số điện thoại + Giới tính & Ngày sinh
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCompactInfoTile(
                  label: 'SỐ ĐIỆN THOẠI',
                  value: soDt,
                  icon: Icons.phone_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactInfoTile(
                  label: 'GIỚI TÍNH & NGÀY SINH',
                  value: '$gioiTinh • $ngaySinhDisplay',
                  icon: Icons.cake_outlined,
                ),
              ),
            ],
          ),

          // ── PHẦN CHI TIẾT MỞ RỘNG (THƯỜNG TRÚ, NƠI CẤP, ẢNH CCCD) ──
          if (_isEkycExpanded) ...[
            const Divider(height: 22, color: Color(0xFFF1F5F9)),
            _buildCompactDetailRow(Icons.home_outlined, 'Thường trú:', diaChi),
            const SizedBox(height: 8),
            _buildCompactDetailRow(Icons.account_balance_outlined, 'Cấp ngày & Nơi cấp:', '$ngayCapDisplay • $noiCap'),
            const SizedBox(height: 8),
            _buildCompactDetailRow(Icons.emergency_outlined, 'Liên hệ khẩn cấp:', nguoiLienHe, valueColor: const Color(0xFFDC2626)),

            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.photo_camera_front_rounded, size: 14, color: Color(0xFF09638E)),
                const SizedBox(width: 6),
                const Text(
                  'Hình ảnh CCCD định danh lưu trữ:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                ),
                const Spacer(),
                if ((urlMatTruoc == null || urlMatTruoc.isEmpty) || (urlMatSau == null || urlMatSau.isEmpty))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Cần bổ sung',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: (urlMatTruoc != null && urlMatTruoc.isNotEmpty)
                      ? _buildCccdThumb('Mặt trước', urlMatTruoc)
                      : _buildCccdPlaceholder('Mặt trước CCCD'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: (urlMatSau != null && urlMatSau.isNotEmpty)
                      ? _buildCccdThumb('Mặt sau', urlMatSau)
                      : _buildCccdPlaceholder('Mặt sau CCCD'),
                ),
              ],
            ),
          ],

          // ── NÚT BẤM THU GỌN / XEM THÊM CHI TIẾT ──
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _isEkycExpanded = !_isEkycExpanded),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isEkycExpanded ? 'Thu gọn thông tin' : 'Xem chi tiết thường trú & ảnh CCCD',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF09638E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isEkycExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 17,
                    color: const Color(0xFF09638E),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoTile({
    required String label,
    required String value,
    required IconData icon,
    bool isBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF64748B)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xFF09638E)),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? const Color(0xFF0F172A),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCccdPlaceholder(String label) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        color: const Color(0xFFF8FAFC),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.add_a_photo_outlined, size: 18, color: Color(0xFF94A3B8)),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 1),
          const Text(
            'Chưa tải lên',
            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildCccdThumb(String label, String url) {
    return InkWell(
      onTap: () => _showZoomImageDialog(context, url),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFCBD5E1)),
          color: const Color(0xFFF8FAFC),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
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
                  ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Positioned(
              right: 6,
              top: 4,
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: const BoxDecoration(
                  color: Color(0xFF09638E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── THẺ PHƯƠNG TIỆN XE ĐĂNG KÝ ──
  Widget _buildRegisteredVehiclesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFD97706), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'PHƯƠNG TIỆN XE GỬI TẠI TRỌ',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_danhSachPhuongTien.length} xe',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          if (_danhSachPhuongTien.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.directions_walk_rounded, color: Color(0xFF94A3B8), size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hiện tại bạn chưa đăng ký phương tiện xe gửi tại trọ.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < _danhSachPhuongTien.length; i++) ...[
                  _buildVehicleRowItem(i, _danhSachPhuongTien[i]),
                  if (i < _danhSachPhuongTien.length - 1)
                    const Divider(height: 16, color: Color(0xFFF1F5F9)),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleRowItem(int index, Map<String, dynamic> xe) {
    final bienSo = xe['bien_so_xe']?.toString() ?? 'Chưa có biển số';
    final loaiXe = xe['loai_xe']?.toString() ?? 'Xe máy';
    final ghiChu = xe['ghi_chu']?.toString() ?? '';
    final trangThai = xe['trang_thai']?.toString() ?? 'Hoạt động';

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Center(
            child: Icon(Icons.moped_rounded, color: Color(0xFF09638E), size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bienSo,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 2),
              Text(
                '$loaiXe${ghiChu.isNotEmpty ? " • $ghiChu" : ""}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Text(
            trangThai,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
          ),
        ),
      ],
    );
  }

  // ==================== BOTTOM NAVIGATION BAR ====================
  Widget _buildActiveNavIcon(IconData icon) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.15),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Icon(icon),
    );
  }

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
        currentIndex: _selectedTabIndex,
        onTap: (index) {
          setState(() => _selectedTabIndex = index);
          if (index == 0 || index == 2) {
            _fetchTenantData();
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF09638E),
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
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: _buildActiveNavIcon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.key_outlined),
            activeIcon: _buildActiveNavIcon(Icons.key_rounded),
            label: 'Phòng',
          ),
          BottomNavigationBarItem(
            icon: _soHoaDonChuaThanhToan > 0
                ? Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.receipt_long_outlined),
                      Positioned(
                        top: -2,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE11D48),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$_soHoaDonChuaThanhToan',
                            style: const TextStyle(
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
            activeIcon: _buildActiveNavIcon(Icons.receipt_long_rounded),
            label: 'Hóa đơn',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.build_outlined),
            activeIcon: _buildActiveNavIcon(Icons.build_rounded),
            label: 'Sự cố',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person_outline_rounded),
            activeIcon: _buildActiveNavIcon(Icons.person_rounded),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }

  // ==================== MODALS & DIALOGS ====================

  /// Modal hướng dẫn giải quyết khi hóa đơn bị trễ hạn
  void _showHuongDanQuaHanModal(HoaDonModel hd) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFDC2626),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hướng Dẫn Xử Lý Quá Hạn',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Hóa đơn ${hd.maHoaDon} • Trễ ${-hd.soNgayConLai} ngày',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quy định nghiêm ngặt về tiền phòng & Quá hạn:',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '• Hạn nộp định kỳ: Bắt buộc hoàn tất trước hoặc đúng ngày 04 hàng tháng.\n'
                    '• Tòa nhà KHÔNG có chính sách cho gia hạn nợ tiền phòng.\n'
                    '• Trễ hạn từ 5 ngày: BQL gửi thông báo cảnh báo nếu không tiếp tục đóng tiền sẽ bị tạm khóa vân tay ra vào.\n'
                    '• Trễ hạn từ 10 ngày: Hệ thống ĐÃ KHÓA VÂN TAY ra vào phòng. Cư dân vui lòng liên hệ BQL qua SĐT hoặc Zalo ${LienHeHelper.defaultHotlineDisplay} để được hỗ trợ mở lại.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            if (hd.soNgayConLai <= -10) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: Color(0xFFDC2626), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'VÂN TAY ĐÃ BỊ TẠM KHÓA',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hd.trangThai == 'Thanh toán một phần'
                                ? 'Do khoản nợ Đợt 2 trễ hạn ${-hd.soNgayConLai} ngày, quyền vân tay ra vào đã bị tạm khóa. Vui lòng thanh toán hoặc liên hệ BQL qua SĐT/Zalo ${LienHeHelper.defaultHotlineDisplay} để mở lại.'
                                : 'Do trễ hạn ${-hd.soNgayConLai} ngày, quyền vân tay ra vào đã bị tạm khóa. Vui lòng thanh toán hoặc liên hệ BQL qua SĐT/Zalo ${LienHeHelper.defaultHotlineDisplay} để mở lại.',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (hd.soNgayConLai <= -5) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD34D)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CẢNH BÁO: SẮP KHÓA VÂN TAY',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            hd.trangThai == 'Thanh toán một phần'
                                ? 'Khoản nợ Đợt 2 đã trễ hạn ${-hd.soNgayConLai} ngày. Nếu không tiếp tục đóng tiền, hệ thống sẽ tạm khóa vân tay khi trễ 10 ngày.'
                                : 'Hóa đơn đã trễ hạn ${-hd.soNgayConLai} ngày. Nếu không tiếp tục đóng tiền, hệ thống sẽ tạm khóa vân tay khi trễ 10 ngày.',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Hướng xử lý bắt buộc:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),

            // Phương án 1: Thanh toán ngay VietQR
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF09638E), width: 1.2),
              ),
              tileColor: const Color(0xFFF0FDF4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Color(0xFF16A34A),
                  size: 22,
                ),
              ),
              title: const Text(
                'Thanh toán ngay bằng VietQR (Khuyên dùng)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF15803D),
                ),
              ),
              subtitle: const Text(
                'Quét mã 24/7 gạch nợ tự động trong 30 giây để tránh bị phạt',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF166534)),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF16A34A),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showVietQrModal();
              },
            ),
            const SizedBox(height: 10),

            // Phương án 2: Gọi Hotline BQL khiếu nại sai số
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.phone_in_talk_rounded,
                  color: Color(0xFF0F172A),
                  size: 20,
                ),
              ),
              title: const Text(
                'Hotline Ban Quản Lý (0328.004.663)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              subtitle: const Text(
                'Liên hệ trực tiếp nếu có thắc mắc/sai lệch về chỉ số điện nước',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
              ),
              onTap: () {
                Navigator.pop(ctx);
                LienHeHelper.hienThiLuaChonLienHe(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Modal thông báo chuyên biệt khi vân tay đã bị khóa do trễ hạn >= 10 ngày
  void _showThongBaoKhoaVanTayModal(HoaDonModel hd) {
    final overdueDays = hd.soNgayConLai < 0 ? -hd.soNgayConLai : 0;
    final activeRoom = _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFFDC2626),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ĐÃ KHÓA VÂN TAY RA VÀO',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      Text(
                        hd.trangThai == 'Thanh toán một phần'
                            ? 'Hóa đơn ${hd.maHoaDon} • Trễ hạn Đợt 2 $overdueDays ngày'
                            : 'Hóa đơn ${hd.maHoaDon} • Trễ hạn $overdueDays ngày',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thông báo từ Ban Quản Lý Kiều Giang:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hd.trangThai == 'Thanh toán một phần'
                        ? 'Quyền mở cổng bằng vân tay của bạn đã bị TẠM KHÓA do khoản nợ Đợt 2 quá hạn $overdueDays ngày (từ 10 ngày trở lên theo quy chế tòa nhà).\n\n'
                          'Để kích hoạt lại vân tay ra vào, vui lòng thanh toán toàn bộ số tiền nợ còn lại (${FormatUtils.currency(hd.tongTien)}) hoặc liên hệ ngay với Ban Quản Lý qua SĐT hoặc Zalo.'
                        : 'Quyền mở cổng bằng vân tay của bạn đã bị TẠM KHÓA do hóa đơn quá hạn $overdueDays ngày (từ 10 ngày trở lên theo quy chế tòa nhà).\n\n'
                          'Để kích hoạt lại vân tay ra vào, vui lòng thanh toán toàn bộ tiền phòng hoặc liên hệ ngay với Ban Quản Lý qua SĐT hoặc Zalo.',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: Color(0xFF7F1D1D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Các phương án hỗ trợ mở khóa:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),

            // Nút 1: Nhắn tin Zalo BQL
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF0284C7), width: 1.2),
              ),
              tileColor: const Color(0xFFF0F9FF),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.chat_bubble_rounded, color: Color(0xFF0284C7), size: 22),
              ),
              title: const Text(
                'Nhắn tin qua Zalo BQL (0328.004.663)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0369A1)),
              ),
              subtitle: const Text(
                'Nhắn tin gửi biên lai để BQL kích hoạt lại vân tay ngay',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF075985)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF0284C7)),
              onTap: () {
                Navigator.pop(ctx);
                LienHeHelper.moZaloChat(context);
              },
            ),
            const SizedBox(height: 8),

            // Nút 2: Gọi điện thoại Hotline
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              tileColor: Colors.white,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF0F172A), size: 22),
              ),
              title: const Text(
                'Gọi điện Hotline (0328.004.663)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              subtitle: const Text(
                'Hỗ trợ khẩn cấp mở cửa và kiểm tra hóa đơn 24/7',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
              onTap: () {
                Navigator.pop(ctx);
                LienHeHelper.goiDien(context);
              },
            ),
            const SizedBox(height: 8),

            // Nút 3: Thanh toán ngay VietQR
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF16A34A), width: 1.2),
              ),
              tileColor: const Color(0xFFF0FDF4),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF16A34A), size: 22),
              ),
              title: const Text(
                'Thanh toán nợ phòng bằng VietQR',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF15803D)),
              ),
              subtitle: const Text(
                'Gạch nợ tự động trong 30 giây để đủ điều kiện mở lại vân tay',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF166534)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF16A34A)),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PaymentScreen(
                      hoaDon: hd,
                      tenPhong: 'Phòng $activeRoom',
                      onPaymentSuccess: (_) => _fetchTenantData(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // VietQR Modal -> Navigate to full animated PaymentScreen
  void _showVietQrModal() {
    final hoaDon =
        _hoaDonMoiNhat ??
        HoaDonModel(
          maHoaDon: 'KG-$maPhong-${DateTime.now().month}',
          ngayLap: DateTime.now().toIso8601String().substring(0, 10),
          hanDongTien: DateTime.now()
              .add(const Duration(days: 5))
              .toIso8601String()
              .substring(0, 10),
          tienPhong: _hopDong?.giaThueThaoThuan ?? 2800000,
          tienDienNuoc: 307500,
          tienDichVuKhac: 100000,
          noCu: 0,
          tongTien: (_hopDong?.giaThueThaoThuan ?? 2800000) + 307500 + 100000,
          trangThai: 'Chưa thanh toán',
          loaiGiaoDich: 'Tiền phòng & Dịch vụ',
          maHopDong: maHopDong.isNotEmpty ? maHopDong : 'HD001',
        );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          hoaDon: hoaDon,
          tenPhong:
              _phong?.tenHienThi ??
              (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
                  ? 'Phòng ${widget.roomNumber}'
                  : 'Phòng 203'),
          onPaymentSuccess: (_) {
            _fetchTenantData();
          },
        ),
      ),
    ).then((_) {
      _fetchTenantData();
    });
  }

  void _showReportIncidentModal() {
    final titleRoom = _phong?.tenHienThi ?? 'phòng $maPhong';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Báo sự cố $titleRoom',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Loại sự cố (Điện, Nước, Khóa...)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Mô tả chi tiết sự cố',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ThongBaoHelper.hienToast(
                    context,
                    tieuDe: 'Yêu cầu hỗ trợ',
                    noiDung: 'Đã gửi yêu cầu hỗ trợ đến kỹ thuật tòa nhà!',
                    type: ThongBaoType.thanhCong,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Gửi báo cáo sự cố',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOvernightGuestModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Đăng ký khách qua đêm',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Họ và tên khách',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Số CCCD / CMND của khách',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ThongBaoHelper.hienToast(
                    context,
                    tieuDe: 'Đăng ký tạm trú',
                    noiDung: 'Đã đăng ký tạm trú thành công cho khách!',
                    type: ThongBaoType.thanhCong,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Xác nhận đăng ký',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMeterReadingModal() {
    // Xác định kỳ tháng hiện tại
    final now = DateTime.now();
    final kyThang = '${now.month}/${now.year}';
    final tenPhong =
        _phong?.tenHienThi ??
        (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
            ? 'Phòng ${widget.roomNumber}'
            : 'Phòng 203');
    final pCode =
        _hopDong?.maPhong ??
        (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
            ? 'P${widget.roomNumber}'
            : 'P203');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeterReadingScreen(
          maPhong: pCode,
          tenPhong: tenPhong,
          kyThang: kyThang,
          maHopDong: _hopDong?.maHopDong ?? 'HD001',
        ),
      ),
    );
  }

  void _showExtendContractHistoryModal() {
    final tenPhong = _phong?.maPhong != null
        ? 'Phòng ${_phong!.maPhong.replaceAll(RegExp(r'[^0-9]'), '')}'
        : (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
              ? 'Phòng ${widget.roomNumber}'
              : 'Phòng 203');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManHinhLichSuGiaHanHopDong(
          hopDong: _hopDong,
          tenPhong: tenPhong,
          maHopDong: _hopDong?.maHopDong ?? maHopDong,
        ),
      ),
    ).then((_) => _fetchTenantData());
  }

  void _showChuaDenHanGiaHanModal(
    BuildContext context,
    int daysLeft,
    DateTime? ngayKt,
    String tenPhong,
    String pCode,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Color(0xFFDC2626),
                  size: 38,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Chưa Đến Hạn Gia Hạn',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Hợp đồng phòng $pCode hiện còn $daysLeft ngày (hạn đến ${ngayKt != null ? '${ngayKt.day.toString().padLeft(2, '0')}/${ngayKt.month.toString().padLeft(2, '0')}/${ngayKt.year}' : ''}).',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '📌 Quy định gia hạn hợp đồng:',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• Chỉ được gửi yêu cầu khi hợp đồng sắp hết hạn (trong vòng 30 ngày cuối / còn 1 tháng).\n• Thời hạn gia hạn: Tối thiểu 6 tháng, tối đa 1 năm (12 tháng).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showExtendContractHistoryModal();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      child: const Text(
                        'Xem lịch sử',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Đã hiểu',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showExtendContractModal() {
    if (!_isNguoiDaiDien) {
      _thongBaoKhongCoQuyen(hanhDong: 'Gia hạn hợp đồng');
      return;
    }

    final tenPhong = _phong?.maPhong != null
        ? 'Phòng ${_phong!.maPhong.replaceAll(RegExp(r'[^0-9]'), '')}'
        : (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
              ? 'Phòng ${widget.roomNumber}'
              : 'Phòng 203');
    final pCode = _hopDong?.maPhong ?? _phong?.maPhong ?? 'P203';

    // Ràng buộc: Còn 1 tháng (<= 30 ngày) mới cho gia hạn, không cho gửi yêu cầu luôn nếu chưa đến hạn
    int daysLeft = 999;
    DateTime? ngayKtDt;
    if (_hopDong?.ngayKt != null && _hopDong!.ngayKt.isNotEmpty) {
      try {
        ngayKtDt = DateTime.parse(_hopDong!.ngayKt);
        daysLeft = ngayKtDt.difference(DateTime.now()).inDays;
      } catch (_) {}
    }

    if (daysLeft > 30) {
      _showChuaDenHanGiaHanModal(context, daysLeft, ngayKtDt, tenPhong, pCode);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManHinhGiaHanHopDong(
          hopDong: _hopDong,
          tenPhong: tenPhong,
          maPhong: pCode,
        ),
      ),
    );
  }

  void _showTerminateContractModal() {
    if (_hopDong?.trangThai != 'Đã thanh lý' && !_isNguoiDaiDien) {
      _thongBaoKhongCoQuyen(hanhDong: 'Chấm dứt hợp đồng & Trả phòng');
      return;
    }

    final tenPhong = _phong?.maPhong != null
        ? 'Phòng ${_phong!.maPhong.replaceAll(RegExp(r'[^0-9]'), '')}'
        : (widget.roomNumber != null && widget.roomNumber!.isNotEmpty
              ? 'Phòng ${widget.roomNumber}'
              : 'Phòng 203');
    final pCode = _hopDong?.maPhong ?? _phong?.maPhong ?? 'P203';
    final tenKhach = _khachThueData?['ho_ten_khach']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManHinhChamDutHopDong(
          hopDong: _hopDong,
          tenPhong: tenPhong,
          maPhong: pCode,
          tenKhachThue: tenKhach,
        ),
      ),
    ).then((updated) {
      if (updated == true) {
        _fetchTenantData();
      }
    });
  }

  Future<void> _showChangeRoomModal() async {
    if (!_isNguoiDaiDien) {
      _thongBaoKhongCoQuyen(hanhDong: 'Chuyển phòng');
      return;
    }

    final curRoom =
        _phong?.maPhong ??
        (widget.roomNumber != null ? 'P${widget.roomNumber}' : 'P203');
    final curPrice = _hopDong?.giaThueThaoThuan.toDouble() ?? 3800000.0;
    final maHD = _hopDong?.maHopDong ?? 'HD001';

    // ── RÀNG BUỘC 1: THỜI GIAN LƯU TRÚ TỐI THIỂU (60 ngày / 2 tháng) ──
    if (_hopDong != null && !_hopDong!.duDieuKienThoiGianChuyenPhong) {
      _showChuaDuDieuKienThoiGianModal(context, _hopDong!);
      return;
    }

    // ── RÀNG BUỘC 2: KIỂM TRA ĐƠN ĐANG XỬ LÝ & GIÃN CÁCH SAU KHI ĐÃ CHUYỂN PHÒNG ──
    try {
      final db = Supabase.instance.client;
      final yccpRows = await db
          .from('yeu_cau_chuyen_phong')
          .select()
          .or('ma_hop_dong_ht.eq.$maHD,ma_phong_cu.eq.$curRoom')
          .order('ngay_tao', ascending: false);

      if (yccpRows.isNotEmpty) {
        // 2.1. Đang có đơn trong quá trình xét duyệt / xác nhận (CHỐNG GỬI LẦN 2)
        const inProgressStatuses = [
          'Chờ duyệt',
          'Đang xử lý',
          'Chờ khách xác nhận',
          'Đã kiểm tra',
          'Khách đã xác nhận',
          'Chờ chủ duyệt',
        ];

        final pending = yccpRows.firstWhere(
          (r) =>
              inProgressStatuses.contains(r['trang_thai_tien_do']?.toString()),
          orElse: () => {},
        );

        if (pending.isNotEmpty) {
          if (!mounted) return;
          _showDonDangChoDuyetModal(
            context,
            Map<String, dynamic>.from(pending),
          );
          return;
        }

        // 2.2. Nếu đã từng chuyển phòng thành công ('Đã duyệt', 'Đã hoàn thành', 'Hoàn tất') -> phải ở phòng mới tối thiểu 2-3 tháng (60 ngày)
        const completedStatuses = ['Đã duyệt', 'Đã hoàn thành', 'Hoàn tất'];
        final recentCompleted = yccpRows.firstWhere(
          (r) =>
              completedStatuses.contains(r['trang_thai_tien_do']?.toString()),
          orElse: () => {},
        );

        if (recentCompleted.isNotEmpty) {
          DateTime? transferDate;

          // Ưu tiên 1: Ngày lập phụ lục hợp đồng chuyển phòng
          try {
            final pl = await db
                .from('phu_luc_hop_dong')
                .select('ngay_lap')
                .eq('ma_hop_dong', maHD)
                .order('ngay_lap', ascending: false)
                .limit(1)
                .maybeSingle();
            if (pl != null && pl['ngay_lap'] != null) {
              transferDate = DateTime.tryParse(pl['ngay_lap'].toString());
            }
          } catch (_) {}

          // Ưu tiên 2: Ngày duyệt hoặc ngày tạo đơn chuyển phòng (ngày cư dân thực tế nộp đơn và chuyển sang phòng mới)
          if (transferDate == null && recentCompleted['ngay_duyet'] != null) {
            transferDate = DateTime.tryParse(
              recentCompleted['ngay_duyet'].toString(),
            );
          }
          if (transferDate == null && recentCompleted['ngay_tao'] != null) {
            transferDate = DateTime.tryParse(
              recentCompleted['ngay_tao'].toString(),
            );
          }

          // Ưu tiên 3: Nếu thoi_gian_hen ở quá khứ (không dùng ngày hẹn trong tương lai vì cư dân đã chuyển vào ở rồi)
          if (transferDate == null &&
              recentCompleted['thoi_gian_hen'] != null) {
            final dtHen = DateTime.tryParse(
              recentCompleted['thoi_gian_hen'].toString(),
            );
            if (dtHen != null && !dtHen.isAfter(DateTime.now())) {
              transferDate = dtHen;
            }
          }

          // Fallback: ngay_tao
          transferDate ??= recentCompleted['ngay_tao'] != null
              ? DateTime.tryParse(recentCompleted['ngay_tao'].toString())
              : null;

          if (transferDate != null) {
            final now = DateTime.now();
            final nowDay = DateTime(now.year, now.month, now.day);
            final moveDay = DateTime(
              transferDate.year,
              transferDate.month,
              transferDate.day,
            );
            final diffDays = nowDay.difference(moveDay).inDays;
            // Cư dân đã được duyệt và chuyển vào ở: số ngày đã ở tối thiểu 1 ngày (hoặc tính theo số ngày đã trôi qua)
            final daysStayed = diffDays < 1 ? 1 : diffDays;

            if (daysStayed < 60) {
              if (!mounted) return;
              _showChuaDuThoiGianOPhongMoiModal(
                context,
                Map<String, dynamic>.from(recentCompleted),
                daysStayed,
                60 - daysStayed,
                ngayChuyen: transferDate,
              );
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra đơn chuyển phòng: $e');
    }

    // ── RÀNG BUỘC 3: BẮT BUỘC PHẢI THANH TOÁN HÓA ĐƠN KỲ TRƯỚC (NẾU CÓ) ──
    try {
      final db = Supabase.instance.client;
      final unpaidRows = await db
          .from('hoa_don')
          .select('ma_hoa_don, tong_tien, trang_thai, han_dong_tien')
          .eq('ma_hop_dong', maHD)
          .neq('trang_thai', 'Đã thanh toán')
          .neq('trang_thai', 'Chờ gửi')
          .gt('tong_tien', 0)
          .order('han_dong_tien', ascending: true);

      if (unpaidRows.isNotEmpty) {
        if (!mounted) return;
        _showChuaThanhToanHoaDonModal(
          context,
          List<Map<String, dynamic>>.from(unpaidRows),
        );
        return;
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra hóa đơn chưa thanh toán: $e');
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomTransferSearchScreen(
          currentRoomNumber: curRoom,
          currentPrice: curPrice,
          maHopDong: maHD,
          hopDong: _hopDong,
        ),
      ),
    );
  }

  /// Modal cảnh báo khi cư dân chưa ở đủ 60 ngày (2 tháng)
  void _showChuaDuDieuKienThoiGianModal(BuildContext context, HopDongModel hd) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Color(0xFFD97706),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chưa Đủ Điều Kiện Chuyển Phòng',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quy định thời gian lưu trú tối thiểu',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Ngày bắt đầu hợp đồng:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        hd.ngayBdFormatted,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Thời gian đã ở thực tế:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '${hd.soNgayDaO} ngày',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quy định tối thiểu BQL:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '60 ngày (2 tháng)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: Color(0xFFFDE68A)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Cần lưu trú thêm:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      Text(
                        '${hd.soNgayConThieuChuyenPhong} ngày nữa',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '📌 Giải thích quy định BQL:\nĐể đảm bảo ổn định an ninh và công tác bàn giao, dọn dẹp vệ sinh phòng trọ, cư dân cần ở tối thiểu 2 đến 3 tháng (ít nhất 60 ngày) tại phòng hiện tại trước khi làm thủ tục chuyển phòng. Nếu bạn có lý do đặc biệt bất khả kháng (sức khỏe, công tác khẩn), vui lòng liên hệ trực tiếp BQL để được hỗ trợ diện ngoại lệ.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF475569),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Đã hiểu quy định',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modal cảnh báo khi cư dân chưa ở đủ 2-3 tháng tại phòng vừa mới chuyển đến
  void _showChuaDuThoiGianOPhongMoiModal(
    BuildContext context,
    Map<String, dynamic> lastTransfer,
    int daysSince,
    int daysRemaining, {
    DateTime? ngayChuyen,
  }) {
    final movedRoom = lastTransfer['ma_phong_moi'] ?? 'phòng mới';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.timelapse_rounded,
                    color: Color(0xFFD97706),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chưa Đủ Thời Gian Ở Phòng Mới',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Quy định giãn cách giữa 2 lần chuyển phòng',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Phòng vừa chuyển đến:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        movedRoom,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                  if (ngayChuyen != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Ngày chuyển vào phòng mới:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF78350F),
                          ),
                        ),
                        Text(
                          '${ngayChuyen.day.toString().padLeft(2, '0')}/${ngayChuyen.month.toString().padLeft(2, '0')}/${ngayChuyen.year}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF78350F),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Thời gian đã ở tại phòng này:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '$daysSince ngày',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Quy định giãn cách tối thiểu:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF78350F),
                        ),
                      ),
                      Text(
                        '60 ngày (2 tháng)',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF78350F),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: Color(0xFFFDE68A)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Cần ở thêm tối thiểu:',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      Text(
                        '$daysRemaining ngày nữa',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '📌 Quy định BQL:\nSau khi được phê duyệt chuyển phòng thành công, cư dân cần lưu trú ổn định tối thiểu 2 đến 3 tháng (ít nhất 60 ngày) tại phòng mới trước khi tiếp tục làm thủ tục chuyển phòng tiếp theo. Quy định này nhằm đảm bảo tính ổn định trong công tác quản lý tài sản, chốt chỉ số điện nước và hợp đồng thuê.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF475569),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Đã hiểu quy định',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Modal cảnh báo khi cư dân còn hóa đơn kỳ trước chưa thanh toán
  void _showChuaThanhToanHoaDonModal(
    BuildContext parentContext,
    List<Map<String, dynamic>> invoices,
  ) {
    final first = invoices.first;
    final maHD = first['ma_hoa_don'] ?? '';
    final num tongTien = invoices.fold<num>(
      0,
      (prev, e) => prev + ((e['tong_tien'] as num?) ?? 0),
    );
    final hanDong = first['han_dong_tien']?.toString() ?? 'Hôm nay';

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: Color(0xFFDC2626),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chưa Thanh Toán Hóa Đơn Kỳ Trước',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Ràng buộc hoàn tất công nợ trước khi đổi phòng',
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Mã hóa đơn tồn đọng:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        '#$maHD',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng tiền cần thanh toán:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        FormatUtils.currency(tongTien.toInt()),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Hạn đóng tiền:',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                        ),
                      ),
                      Text(
                        hanDong,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7F1D1D),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '📌 Quy định Ban Quản Lý:\nTheo quy định thực tế, cư dân bắt buộc phải thanh toán toàn bộ hóa đơn tiền phòng và dịch vụ của kỳ trước (nếu có) trước khi tạo đơn xin chuyển phòng. Việc này nhằm quyết toán dứt điểm công nợ kỳ cũ trước khi chuyển giao quyền sử dụng phòng.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF475569),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(modalCtx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Để sau',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final rootNav = Navigator.of(parentContext);
                      Navigator.pop(modalCtx);
                      if (_hoaDonMoiNhat != null) {
                        rootNav
                            .push(
                              MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                  hoaDon: _hoaDonMoiNhat!,
                                  tenPhong:
                                      'Phòng ${widget.roomNumber ?? _hopDong?.maPhong ?? '203'}',
                                ),
                              ),
                            )
                            .then((_) => _fetchTenantData());
                      } else {
                        setState(() {
                          _selectedTabIndex = 2; // Chuyển sang Tab Hóa Đơn
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Thanh toán ngay',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Modal cảnh báo khi cư dân đã có 1 đơn chuyển phòng đang chờ BQL duyệt (Chống gửi lần 2)
  /// Modal cảnh báo khi cư dân đã có 1 đơn chuyển phòng đang chờ BQL duyệt (Chống gửi lần 2)
  void _showDonDangChoDuyetModal(
    BuildContext parentContext,
    Map<String, dynamic> don,
  ) {
    final maYC = don['ma_yeu_cau'] ?? '';
    final targetRoom = don['ma_phong_moi'] ?? '';
    final curRoom = don['ma_phong_cu'] ?? '';
    final status = don['trang_thai_tien_do']?.toString() ?? 'Chờ duyệt';
    String thoiGianHen = 'Trong tuần này';
    if (don['thoi_gian_hen'] != null) {
      try {
        final dt = DateTime.parse(don['thoi_gian_hen']);
        thoiGianHen =
            "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
      } catch (_) {}
    }

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.pending_actions_rounded,
                      color: Color(0xFF0284C7),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Đơn Chuyển Phòng Đang Chờ Duyệt',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã hồ sơ: #$maYC',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Phòng hiện tại:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          curRoom,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Phòng xin chuyển đến:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          targetRoom,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Ngày hẹn dọn:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          thoiGianHen,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Trạng thái BQL:',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                status == 'Chờ khách xác nhận' ||
                                    status == 'Đã kiểm tra'
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status == 'Chờ khách xác nhận'
                                ? 'Chờ bạn xác nhận nghiệm thu'
                                : (status == 'Chờ duyệt'
                                      ? 'Chờ Ban Quản Lý tiếp nhận'
                                      : status),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color:
                                  status == 'Chờ khách xác nhận' ||
                                      status == 'Đã kiểm tra'
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️ Ràng buộc gửi đơn:\nTheo quy định, mỗi cư dân chỉ được tạo duy nhất 1 yêu cầu chuyển phòng tại một thời điểm để BQL kiểm tra hiện trạng và chuẩn bị phòng mới. Bạn không thể tạo thêm đơn thứ 2 khi đơn cũ chưa được giải quyết.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        // Xác nhận hủy đơn
                        final confirm = await showDialog<bool>(
                          context: parentContext,
                          builder: (c) => AlertDialog(
                            title: const Text('Hủy yêu cầu chuyển phòng?'),
                            content: Text(
                              'Bạn có chắc chắn muốn hủy yêu cầu chuyển sang phòng $targetRoom (#$maYC) không?\n\nSau khi hủy, bạn có thể tạo lại yêu cầu chọn phòng khác.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Không'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(c, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Đồng ý hủy đơn'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('yeu_cau_chuyen_phong')
                                .update({'trang_thai_tien_do': 'Đã hủy'})
                                .eq('ma_yeu_cau', maYC);
                            if (!mounted) return;
                            Navigator.pop(modalCtx);
                            ThongBaoHelper.hienThongBao(
                              parentContext,
                              tieuDe: 'Đã Hủy Yêu Cầu',
                              noiDung:
                                  'Yêu cầu chuyển phòng #$maYC đã được hủy. Bây giờ bạn có thể chọn phòng mới!',
                              type: ThongBaoType.thanhCong,
                            );
                            _showChangeRoomModal();
                          } catch (e) {
                            ThongBaoHelper.hienThongBao(
                              parentContext,
                              tieuDe: 'Lỗi',
                              noiDung: 'Không thể hủy yêu cầu: $e',
                              type: ThongBaoType.thatBai,
                            );
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Hủy đơn này',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // 1. Lưu root Navigator trước khi đóng bottom sheet
                        final rootNav = Navigator.of(parentContext);
                        Navigator.pop(modalCtx);

                        // 2. Query thông tin phòng mới (nếu có)
                        Map<String, dynamic>? phongMoiData;
                        try {
                          final res = await Supabase.instance.client
                              .from('phong')
                              .select()
                              .eq('ma_phong', targetRoom)
                              .maybeSingle();
                          if (res != null) phongMoiData = res;
                        } catch (_) {}

                        final giaThueMoi =
                            (phongMoiData?['gia_thue'] as num?) ?? 3100000;
                        final tienCocMoi =
                            (phongMoiData?['tien_dat_coc'] as num?) ??
                            giaThueMoi;
                        final tangMoi =
                            (phongMoiData?['tang'] as num?)?.toInt() ?? 1;
                        final dienTichMoi =
                            (phongMoiData?['dien_tich'] as num?)?.toInt() ?? 20;

                        if (!mounted) return;
                        rootNav.push(
                          MaterialPageRoute(
                            builder: (_) => RoomTransferSuccessScreen(
                              ticketCode: maYC,
                              targetRoom: {
                                'maPhong': targetRoom,
                                'toaNha':
                                    phongMoiData?['toa_nha']?.toString() ??
                                    'Tòa A',
                                'tang': tangMoi,
                                'dienTich': dienTichMoi,
                                'giaThue': giaThueMoi,
                                'tienDatCoc': tienCocMoi,
                              },
                              currentRoomNumber: curRoom,
                              currentPrice:
                                  _hopDong?.giaThueThaoThuan ?? 3800000,
                              moveInDateFormatted: thoiGianHen,
                              reason:
                                  don['ly_do_chuyen']?.toString() ??
                                  'Chuyển phòng theo yêu cầu',
                              note: '',
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Xem tiến độ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    final rootNav = Navigator.of(parentContext);
                    Navigator.pop(modalCtx);
                    final curRoom =
                        _hopDong?.maPhong ?? widget.roomNumber ?? 'P203';
                    if (!mounted) return;
                    rootNav
                        .push(
                          MaterialPageRoute(
                            builder: (_) => RoomTransferHistoryScreen(
                              currentRoomNumber: curRoom,
                              maHopDong: _hopDong?.maHopDong ?? maHopDong,
                              hopDong: _hopDong,
                            ),
                          ),
                        )
                        .then((_) => _fetchTenantData());
                  },
                  icon: const Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Color(0xFF09638E),
                  ),
                  label: const Text(
                    'Xem tất cả lịch sử chuyển phòng',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF09638E),
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

  void _showNotificationModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: SystemNotificationService.danhSachThongBaoNotifier,
        builder: (context, danhSachNotif, _) {
          final unreadCount = danhSachNotif
              .where((t) => t['da_doc'] == false)
              .length;
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                // Thanh kéo modal
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Tiêu đề Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF5FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Color(0xFF09638E),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Thông Báo Cư Dân',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$unreadCount mới',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () {
                            SystemNotificationService.markAllAsRead();
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Đã đọc hết',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF09638E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(
                  height: 24,
                  thickness: 1,
                  color: Color(0xFFE2E8F0),
                ),

                // Danh sách thông báo
                Expanded(
                  child: danhSachNotif.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 56,
                                color: Color(0xFFCBD5E1),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Chưa có thông báo nào',
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: danhSachNotif.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = danhSachNotif[index];
                            final daDoc = item['da_doc'] == true;
                            final isError = item['is_error'] == true;
                            final loai =
                                item['loai']?.toString() ?? 'thong_bao';
                            final tieuDe = item['tieu_de']?.toString() ?? '';
                            final noiDung = item['noi_dung']?.toString() ?? '';
                            final onXem = item['on_xem'] as VoidCallback?;
                            final thoiGian = item['thoi_gian'] as DateTime?;

                            Color iconBg;
                            Color iconColor;
                            IconData iconData;

                            if (loai == 'chuyen_phong') {
                              iconBg = const Color(0xFFE0F2FE);
                              iconColor = const Color(0xFF0284C7);
                              iconData = Icons.swap_horiz_rounded;
                            } else if (loai == 'gia_han') {
                              iconBg = const Color(0xFFDCFCE7);
                              iconColor = const Color(0xFF16A34A);
                              iconData = Icons.edit_calendar_rounded;
                            } else if (loai == 'su_co') {
                              iconBg = const Color(0xFFFEF3C7);
                              iconColor = const Color(0xFFD97706);
                              iconData = Icons.handyman_rounded;
                            } else if (loai == 'hoa_don') {
                              iconBg = const Color(0xFFFEF3C7);
                              iconColor = const Color(0xFFD97706);
                              iconData = Icons.receipt_long_rounded;
                            } else {
                              iconBg = const Color(0xFFF3E8FF);
                              iconColor = const Color(0xFF9333EA);
                              iconData = Icons.campaign_rounded;
                            }

                            if (isError) {
                              iconBg = const Color(0xFFFEE2E2);
                              iconColor = const Color(0xFFDC2626);
                              iconData = Icons.error_outline_rounded;
                            }

                            String timeDisplay = 'Vừa xong';
                            if (thoiGian != null) {
                              final diff = DateTime.now().difference(thoiGian);
                              if (diff.inMinutes < 1) {
                                timeDisplay = 'Vừa xong';
                              } else if (diff.inHours < 1) {
                                timeDisplay = '${diff.inMinutes} phút trước';
                              } else if (diff.inDays < 1) {
                                timeDisplay = '${diff.inHours} giờ trước';
                              } else if (diff.inDays < 7) {
                                timeDisplay = '${diff.inDays} ngày trước';
                              } else {
                                timeDisplay =
                                    '${thoiGian.day.toString().padLeft(2, '0')}/${thoiGian.month.toString().padLeft(2, '0')}/${thoiGian.year}';
                              }
                            }

                            return InkWell(
                              onTap: () {
                                final id = item['id']?.toString() ?? '';
                                SystemNotificationService.markAsRead(id);
                                if (onXem != null) {
                                  Navigator.pop(ctx);
                                  onXem();
                                }
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: daDoc
                                      ? Colors.white
                                      : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: daDoc
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFF86EFAC),
                                    width: daDoc ? 1 : 1.3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: iconBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        iconData,
                                        color: iconColor,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  tieuDe,
                                                  style: TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: daDoc
                                                        ? FontWeight.w600
                                                        : FontWeight.bold,
                                                    color: const Color(
                                                      0xFF0F172A,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (!daDoc)
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  margin: const EdgeInsets.only(
                                                    left: 6,
                                                  ),
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Color(
                                                          0xFFE11D48,
                                                        ),
                                                        shape: BoxShape.circle,
                                                      ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            noiDung,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.access_time_rounded,
                                                size: 12,
                                                color: Color(0xFF94A3B8),
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                timeDisplay,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                              ),
                                              const Spacer(),
                                              if (onXem != null)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFF09638E,
                                                    ).withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: const Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        'Xem ngay',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Color(
                                                            0xFF09638E,
                                                          ),
                                                        ),
                                                      ),
                                                      Icon(
                                                        Icons
                                                            .arrow_forward_ios_rounded,
                                                        size: 10,
                                                        color: Color(
                                                          0xFF09638E,
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
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRulesModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.shield_outlined, color: Color(0xFF16A34A), size: 24),
            SizedBox(width: 8),
            Text(
              'Nội quy tòa nhà',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Giữ trật tự chung sau 22h00 đêm, không tụ tập gây ồn ào.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '2. Khóa cửa và tắt các thiết bị điện/nước khi rời phòng.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '3. Đăng ký khách lưu trú qua đêm đúng quy định trên ứng dụng.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '4. Giữ gìn vệ sinh chung tại hành lang, cầu thang và khu vực rác.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              SizedBox(height: 8),
              Text(
                '5. Không hút thuốc lá, sử dụng chất cấm trong khuôn viên tòa nhà.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF09638E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Đã hiểu',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberModal() {
    final sdtController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Thêm thành viên phòng',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nhập số điện thoại của người bạn muốn thêm vào cùng phòng:',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sdtController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'VD: 0912345678',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(
                  Icons.phone_outlined,
                  size: 20,
                  color: Color(0xFF09638E),
                ),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Hủy',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ThongBaoHelper.hienToast(
                context,
                tieuDe: 'Thêm thành viên',
                noiDung: 'Đã gửi yêu cầu thêm thành viên vào phòng!',
                type: ThongBaoType.thanhCong,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF09638E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Gửi yêu cầu',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showContractModal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractDetailScreen(
          maHopDong: maHopDong.isNotEmpty ? maHopDong : 'HD001',
        ),
      ),
    );
  }

  Future<void> _showDownloadBillToast() async {
    final hd = _hoaDonMoiNhat;

    // Nạp phông chữ Unicode hỗ trợ đầy đủ tiếng Việt: ưu tiên assets cục bộ
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      final fontRegularData = await rootBundle.load('assets/fonts/arial.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/arialbd.ttf');
      fontRegular = pw.Font.ttf(fontRegularData);
      fontBold = pw.Font.ttf(fontBoldData);
    } catch (_) {
      try {
        fontRegular = await PdfGoogleFonts.robotoRegular();
        fontBold = await PdfGoogleFonts.robotoBold();
      } catch (_) {
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }
    }

    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);

    final pdf = pw.Document(theme: theme);

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(24),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text(
                    'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM\nĐộc lập - Tự do - Hạnh phúc\n---o0o---',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Center(
                  child: pw.Text(
                    'HÓA ĐƠN TIỀN PHÒNG VÀ DỊCH VỤ',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'Kỳ: ${hd?.thangNam ?? "Tháng 09/2026"} - Mã HĐ: #${hd?.maHoaDon ?? "HD09_203"}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Text('Phòng: $roomDisplay'),
                pw.Text('Khách thuê: Hồ Thị Mỹ Duyên'),
                pw.Text(
                  'Hạn đóng tiền: ${hd?.hanDongTienFormatted ?? "27/09/2026"}',
                ),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('1. Tiền thuê phòng:'),
                    pw.Text(
                      FormatUtils.currency(
                        (hd?.tienPhong ?? 3800000).toDouble(),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('2. Tiền điện & nước:'),
                    pw.Text(
                      FormatUtils.currency(
                        (hd?.tienDienNuoc ?? 330000).toDouble(),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('3. Dịch vụ & vệ sinh:'),
                    pw.Text(
                      FormatUtils.currency(
                        (hd?.tienDichVuKhac ?? 50000).toDouble(),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Divider(),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TỔNG CỘNG CẦN THANH TOÁN:',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      FormatUtils.currency(
                        (hd?.tongTien ?? 4180000).toDouble(),
                      ),
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 25),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('ĐẠI DIỆN BAN QUẢN LÝ\n[ĐÃ XÁC NHẬN HÓA ĐƠN]'),
                    pw.Text('NGƯỜI THUÊ PHÒNG\n[HỒ THỊ MỸ DUYÊN]'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    // Mở trực tiếp màn hình In / Tải PDF của hệ điều hành
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'HoaDon_${hd?.maHoaDon ?? "KG"}.pdf',
    );
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const GuestHomeScreen()),
      (route) => false,
    );
  }
}

class ContainerBadgeDot extends StatelessWidget {
  const ContainerBadgeDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xFF0284C7),
        shape: BoxShape.circle,
      ),
    );
  }
}

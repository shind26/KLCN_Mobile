import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuGiaHanHopDong.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTimKiemChuyenPhong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';

class ManHinhGiaHanHopDong extends StatefulWidget {
  final HopDongModel? hopDong;
  final String tenPhong;
  final String maPhong;

  const ManHinhGiaHanHopDong({
    super.key,
    this.hopDong,
    this.tenPhong = 'Phòng 302',
    this.maPhong = 'P302',
  });

  @override
  State<ManHinhGiaHanHopDong> createState() => _ManHinhGiaHanHopDongState();
}

class _ManHinhGiaHanHopDongState extends State<ManHinhGiaHanHopDong> {
  // 0: Form chọn kỳ hạn, 1: Trạng thái yêu cầu / Thành công
  int _step = 0;

  // Lựa chọn gói: '6', '9', '12', 'khac'
  String _selectedPackage = '6';

  // Khi chọn 'khac': số tháng (tối thiểu 6, tối đa 12)
  int _customMonths = 6;
  final TextEditingController _lyDoController = TextEditingController();

  bool _isSubmitting = false;

  // Thông tin hợp đồng
  late String _maHd;
  late DateTime _ngayHetHan;
  late double _giaThue;
  late double _tienCoc;
  late int _soThangConLai;
  Map<String, dynamic>? _pendingPhuLuc;
  bool _isLoadingCheck = true;

  // Lắng nghe Realtime & Polling
  StreamSubscription? _phuLucSub;
  Timer? _phuLucPollTimer;
  bool _hasNotifiedApproval = false;

  /// Số ngày còn lại đến khi hợp đồng hết hạn
  int get _soNgayConLai => _ngayHetHan.difference(DateTime.now()).inDays;

  /// Ràng buộc: Sắp hết hạn (còn <= 30 ngày hoặc đã hết hạn) mới được gửi đơn gia hạn
  bool get _duDieuKienGiaHan => _soNgayConLai <= 30;

  @override
  void initState() {
    super.initState();
    _maHd = widget.hopDong?.maHopDong ?? 'HD-KG2-302-2024';
    _giaThue = widget.hopDong?.giaThueThaoThuan.toDouble() ?? 2800000;
    _tienCoc = widget.hopDong?.tienDatCoc.toDouble() ?? 2800000;

    try {
      if (widget.hopDong?.ngayKt != null && widget.hopDong!.ngayKt.isNotEmpty) {
        _ngayHetHan = DateTime.parse(widget.hopDong!.ngayKt);
      } else {
        _ngayHetHan = DateTime(2025, 12, 15);
      }
    } catch (_) {
      _ngayHetHan = DateTime(2025, 12, 15);
    }

    final now = DateTime.now();
    _soThangConLai = ((_ngayHetHan.year - now.year) * 12 + (_ngayHetHan.month - now.month)).clamp(1, 24);

    _kiemTraYeuCauChoDuyet();
  }

  String get _realMaHopDong {
    final raw = widget.hopDong?.maHopDong ?? _maHd;
    if (raw.isNotEmpty && raw != 'HD-KG2-302-2024') {
      return raw;
    }
    return 'HD001';
  }

  void _danhDauDaXemThanhCong() {
    if (_pendingPhuLuc != null) {
      final st = _pendingPhuLuc!['trang_thai']?.toString() ?? '';
      final maPl = _pendingPhuLuc!['ma_phu_luc']?.toString() ?? '';
      if (maPl.isNotEmpty && (st == 'Đã duyệt' || st == 'Từ chối')) {
        final daXemKey = 'da_xem_man_hinh_gia_han_${maPl}_$st';
        ThongBaoHelper.danhDauDaXem(daXemKey);
      }
    }
  }

  // ── KIỂM TRA XEM PHÒNG ĐÃ CÓ YÊU CẦU GIA HẠN (CHỜ DUYỆT HOẶC ĐÃ DUYỆT) CHƯA ──
  Future<void> _kiemTraYeuCauChoDuyet() async {
    try {
      final db = Supabase.instance.client;
      final res = await db
          .from('phu_luc_hop_dong')
          .select()
          .eq('ma_hop_dong', _realMaHopDong)
          .order('ngay_lap', ascending: false);

      if ((res as List).isNotEmpty && mounted) {
        // Chỉ lọc phụ lục gia hạn (bỏ qua phụ lục chuyển phòng có mã PLCP hoặc ma_phong_moi)
        final giaHanList = res.where((item) {
          final pMoi = item['ma_phong_moi']?.toString() ?? '';
          final code = item['ma_phu_luc']?.toString() ?? '';
          final loai = item['loai_phu_luc']?.toString().toLowerCase() ?? '';
          if (pMoi.isNotEmpty || code.startsWith('PLCP') || loai.contains('chuyển phòng')) {
            return false;
          }
          return true;
        }).toList();

        if (giaHanList.isNotEmpty) {
          final latest = giaHanList.first;
          final st = latest['trang_thai']?.toString() ?? '';
          final maPl = latest['ma_phu_luc']?.toString() ?? '';
          final daXemKey = 'da_xem_man_hinh_gia_han_${maPl}_$st';

          // Đồng bộ lại ngày hết hạn mới nếu phụ lục đã được duyệt
          if (st == 'Đã duyệt') {
            final ngayGiaHanDenStr = latest['ngay_gia_han_den']?.toString();
            if (ngayGiaHanDenStr != null && ngayGiaHanDenStr.isNotEmpty) {
              final d = DateTime.tryParse(ngayGiaHanDenStr);
              if (d != null && d.isAfter(_ngayHetHan)) {
                _ngayHetHan = d;
                final now = DateTime.now();
                _soThangConLai = ((_ngayHetHan.year - now.year) * 12 + (_ngayHetHan.month - now.month)).clamp(1, 24);
              }
            }
          }

          if (st == 'Chờ duyệt') {
            // Đang chờ duyệt thì luôn hiển thị màn hình tiến độ chờ BQL
            setState(() {
              _pendingPhuLuc = latest;
              _step = 1;
              _isLoadingCheck = false;
            });
            _batDauLangNghePhuLuc();
            return;
          } else if (st == 'Đã duyệt' || st == 'Từ chối') {
            // Chỉ hiển thị màn hình Gia Hạn Thành Công / Từ Chối ĐÚNG 1 LẦN
            // Nếu người dùng đã từng xem rồi, vào thẳng form gia hạn (_step = 0)
            final daXem = ThongBaoHelper.daXem(daXemKey);
            setState(() {
              _pendingPhuLuc = latest;
              _step = daXem ? 0 : 1;
              _isLoadingCheck = false;
            });
            _batDauLangNghePhuLuc();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra phụ lục chờ duyệt: $e');
    }

    if (mounted) {
      setState(() => _isLoadingCheck = false);
      _batDauLangNghePhuLuc();
    }
  }

  // ── LẮNG NGHE REALTIME & POLLING TỰ ĐỘNG CẬP NHẬT KHI BQL BẤM DUYỆT ──
  void _batDauLangNghePhuLuc() {
    _phuLucSub?.cancel();
    _phuLucPollTimer?.cancel();

    try {
      final db = Supabase.instance.client;
      // 1. Supabase Realtime Stream
      _phuLucSub = db
          .from('phu_luc_hop_dong')
          .stream(primaryKey: ['ma_phu_luc'])
          .eq('ma_hop_dong', _realMaHopDong)
          .listen(
        (rows) {
          if (!mounted || rows.isEmpty) return;
          _xuLyCapNhatPhuLuc(rows);
        },
        onError: (err) {
          debugPrint('Realtime stream phu_luc notice/fallback to polling: $err');
        },
      );
    } catch (e) {
      debugPrint('Realtime stream phu_luc error: $e');
    }

    // 2. Polling dự phòng nhẹ nhàng mỗi 15 giây (kết hợp cùng Realtime stream)
    _phuLucPollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      try {
        final res = await Supabase.instance.client
            .from('phu_luc_hop_dong')
            .select()
            .eq('ma_hop_dong', _realMaHopDong)
            .order('ngay_lap', ascending: false)
            .limit(1);
        if (mounted && (res as List).isNotEmpty) {
          _xuLyCapNhatPhuLuc(res);
        }
      } catch (_) {}
    });
  }

  void _xuLyCapNhatPhuLuc(List<dynamic> rows) {
    if (rows.isEmpty || !mounted) return;
    // Bỏ qua nếu là phụ lục chuyển phòng
    final giaHanRows = rows.where((item) {
      final pMoi = item['ma_phong_moi']?.toString() ?? '';
      final code = item['ma_phu_luc']?.toString() ?? '';
      final loai = item['loai_phu_luc']?.toString().toLowerCase() ?? '';
      if (pMoi.isNotEmpty || code.startsWith('PLCP') || loai.contains('chuyển phòng')) {
        return false;
      }
      return true;
    }).toList();

    if (giaHanRows.isEmpty) return;
    final latest = giaHanRows.first as Map<String, dynamic>;
    final stMoi = latest['trang_thai']?.toString() ?? '';
    final stCu = _pendingPhuLuc?['trang_thai']?.toString();

    if (stMoi == 'Chờ duyệt' || stMoi == 'Đã duyệt' || stMoi == 'Từ chối') {
      final isRealStatusChange = stCu != null && stCu != stMoi;
      if (isRealStatusChange) {
        setState(() {
          _pendingPhuLuc = latest;
          _step = 1;
          _isLoadingCheck = false;
        });
      } else {
        _pendingPhuLuc = latest;
      }

      // Khi BQL bấm Đã duyệt -> Tự động đồng bộ ngày kết thúc mới vào bảng hop_dong
      if (stMoi == 'Đã duyệt') {
        final ngayGiaHanDen = latest['ngay_gia_han_den']?.toString();
        if (ngayGiaHanDen != null && ngayGiaHanDen.isNotEmpty) {
          Supabase.instance.client.from('hop_dong').update({
            'ngay_kt': ngayGiaHanDen,
          }).eq('ma_hop_dong', _realMaHopDong).then((_) {
            debugPrint('[GIA_HAN] Đã tự động cập nhật ngay_kt vào hop_dong: $ngayGiaHanDen');
          }).catchError((err) {
            debugPrint('[GIA_HAN] Lỗi cập nhật hop_dong: $err');
          });
        }

        final plId = _pendingPhuLuc?["ma_phu_luc"] ?? _realMaHopDong;
        final approvalKey = 'phu_luc_${plId}_$stMoi';

        if (stCu == 'Chờ duyệt' && !_hasNotifiedApproval && !ThongBaoHelper.daXem(approvalKey) && mounted) {
          _hasNotifiedApproval = true;
          ThongBaoHelper.danhDauDaXem(approvalKey);
          SystemNotificationService.show(
            title: '🎉 Yêu cầu gia hạn được phê duyệt!',
            body: 'Ban Quản Lý đã duyệt hợp đồng gia hạn phòng ${widget.tenPhong}. Hợp đồng mới đã có hiệu lực!',
            tag: approvalKey,
          );
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Ban Quản Lý Đã Phê Duyệt!',
            noiDung:
                'Yêu cầu gia hạn hợp đồng phòng ${widget.tenPhong} đã được Ban Quản Lý phê duyệt thành công. Hợp đồng đã có hiệu lực mới!',
            type: ThongBaoType.thanhCong,
            nutText: 'Xem Chi Tiết Hợp Đồng',
            tag: approvalKey,
            onConfirm: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContractDetailScreen()),
              );
            },
          );
        }
      } else if (stMoi == 'Từ chối') {
        final plId = _pendingPhuLuc?["ma_phu_luc"] ?? _realMaHopDong;
        final approvalKey = 'phu_luc_${plId}_$stMoi';

        if (stCu == 'Chờ duyệt' && !_hasNotifiedApproval && !ThongBaoHelper.daXem(approvalKey) && mounted) {
          _hasNotifiedApproval = true;
          ThongBaoHelper.danhDauDaXem(approvalKey);
          SystemNotificationService.show(
            title: '⚠️ Yêu cầu gia hạn bị từ chối',
            body: 'Ban Quản Lý chưa thể phê duyệt gia hạn theo đề xuất hiện tại của bạn.',
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
  }

  @override
  void dispose() {
    _phuLucSub?.cancel();
    _phuLucPollTimer?.cancel();
    _lyDoController.dispose();
    super.dispose();
  }

  int get _selectedMonths {
    if (_selectedPackage == '6') return 6;
    if (_selectedPackage == '9') return 9;
    if (_selectedPackage == '12') return 12;
    return _customMonths.clamp(6, 12);
  }

  DateTime get _ngayBatDauMoi {
    return _ngayHetHan.add(const Duration(days: 1));
  }

  DateTime get _ngayKetThucMoi {
    final start = _ngayBatDauMoi;
    // Cộng thêm số tháng, lùi 1 ngày
    var y = start.year;
    var m = start.month + _selectedMonths;
    while (m > 12) {
      y += 1;
      m -= 12;
    }
    final daysInMonth = DateTime(y, m + 1, 0).day;
    final day = start.day > daysInMonth ? daysInMonth : start.day;
    return DateTime(y, m, day).subtract(const Duration(days: 1));
  }

  String _formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _formatCurrency(double v) {
    final s = v.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return '${s.replaceAllMapped(reg, (m) => '${m[1]}.')} đ';
  }

  // ── RÀNG BUỘC & GỬI YÊU CẦU LƯU VÀO SUPABASE ──────────────
  Future<void> _guiYeuCauGiaHan() async {
    // 1. Ràng buộc: Sắp hết hạn mới được gửi đơn gia hạn hợp đồng (trong vòng 30 ngày)
    if (!_duDieuKienGiaHan) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Chưa Đến Hạn Gia Hạn',
        noiDung:
            'Hợp đồng còn $_soNgayConLai ngày (đến ngày ${_formatDate(_ngayHetHan)}). Theo quy định, chỉ được gửi đơn gia hạn khi hợp đồng sắp hết hạn (trong vòng 30 ngày cuối)!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    // 2. Ràng buộc: Thời gian gia hạn tối thiểu 6 tháng, tối đa 1 năm (12 tháng)
    if (_selectedMonths < 6 || _selectedMonths > 12) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Kỳ Hạn Chưa Hợp Lệ',
        noiDung:
            'Quy định thời gian gia hạn hợp đồng tối thiểu là 6 tháng và tối đa là 1 năm (12 tháng)!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    // Ràng buộc bảo mật: Chỉ Người đại diện (Trưởng phòng) mới được gửi đơn gia hạn
    final user = AuthService.currentUser;
    if (user != null) {
      final role = user.vaiTro.toLowerCase();
      if (role.contains('thanhvien') || role.contains('banocung') || role.contains('ocung')) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Không Có Quyền Thực Hiện',
          noiDung: 'Bạn đang đăng nhập với tư cách Thành viên phòng (Bạn cùng phòng). Thủ tục gia hạn hợp đồng chỉ có Người đại diện (Trưởng phòng) mới có thẩm quyền thực hiện!',
          type: ThongBaoType.canhBao,
        );
        return;
      }
    }

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final now = DateTime.now();
      final soThangStr = _selectedMonths.toString().padLeft(2, '0');
      final maHdReal = _realMaHopDong;
      final hdSuffix = maHdReal.replaceAll(' ', '');
      String maPhuLuc = 'PL${soThangStr}_$hdSuffix';
      if (maPhuLuc.length > 10) {
        maPhuLuc = maPhuLuc.substring(0, 10);
      }

      final giaThueMoi = _giaThue;
      final ngayLapDateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final ngayGiaHanDenStr = '${_ngayKetThucMoi.year}-${_ngayKetThucMoi.month.toString().padLeft(2, '0')}-${_ngayKetThucMoi.day.toString().padLeft(2, '0')}';

      String noiDung = 'Gia hạn thời hạn hợp đồng thêm $_selectedMonths tháng (${_formatDate(_ngayBatDauMoi)} đến ${_formatDate(_ngayKetThucMoi)}). ';
      if (_selectedPackage == 'khac' && _lyDoController.text.trim().isNotEmpty) {
        noiDung += 'Ghi chú đề xuất: ${_lyDoController.text.trim()}';
      } else {
        noiDung += 'Giữ nguyên giá gốc hợp đồng.';
      }

      // Ghi nhận trực tiếp vào bảng phu_luc_hop_dong trên Supabase đầy đủ 9 cột
      try {
        final res = await db.from('phu_luc_hop_dong').upsert({
          'ma_phu_luc': maPhuLuc,
          'ngay_lap': ngayLapDateStr,
          'noi_dung_dieu_chinh': noiDung,
          'gia_thue_moi': giaThueMoi,
          'chenh_lech_tien_coc': 0, // Gia hạn bảo lưu 100% tiền cọc
          'ngay_gia_han_den': ngayGiaHanDenStr,
          'ma_hop_dong': maHdReal,
          'ma_phong_moi': null, // Gia hạn không đổi phòng
          'trang_thai': 'Chờ duyệt',
        }).select();
        debugPrint('[PHU_LUC] Đã lưu thành công vào bảng phu_luc_hop_dong: $res');
        _pendingPhuLuc = {
          'ma_phu_luc': maPhuLuc,
          'ngay_lap': ngayLapDateStr,
          'noi_dung_dieu_chinh': noiDung,
          'gia_thue_moi': giaThueMoi,
          'chenh_lech_tien_coc': 0,
          'ngay_gia_han_den': ngayGiaHanDenStr,
          'ma_hop_dong': maHdReal,
          'trang_thai': 'Chờ duyệt',
        };
      } catch (errDb) {
        debugPrint('Lỗi lưu phu_luc_hop_dong: $errDb');
        if (mounted) {
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Không Thể Gửi Yêu Cầu',
            noiDung: 'Lỗi lưu dữ liệu: $errDb. Vui lòng kiểm tra lại kết nối mạng!',
            type: ThongBaoType.thatBai,
          );
          setState(() => _isSubmitting = false);
        }
        return;
      }
    } catch (e) {
      debugPrint('Lỗi gửi yêu cầu gia hạn: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _step = 1;
    });
    _batDauLangNghePhuLuc();
  }

  @override
  Widget build(BuildContext context) {
    final isDaDuyet = _pendingPhuLuc?['trang_thai'] == 'Đã duyệt';
    final isTuChoi = _pendingPhuLuc?['trang_thai'] == 'Từ chối';

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _danhDauDaXemThanhCong();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
            onPressed: () {
              _danhDauDaXemThanhCong();
              Navigator.pop(context);
            },
          ),
        title: Column(
          children: [
            Text(
              _step == 0
                  ? 'Gia Hạn Hợp Đồng'
                  : (isDaDuyet
                      ? 'Gia Hạn Thành Công'
                      : (isTuChoi ? 'Yêu Cầu Bị Từ Chối' : 'Trạng Thái Yêu Cầu Gia Hạn')),
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            Text(
              '${widget.tenPhong} • Tòa Kiêu Giang 2',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Color(0xFF09638E), size: 24),
            tooltip: 'Lịch sử gia hạn',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManHinhLichSuGiaHanHopDong(
                    hopDong: widget.hopDong,
                    tenPhong: widget.tenPhong,
                    maHopDong: _realMaHopDong,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline_rounded, color: Color(0xFF64748B), size: 22),
            onPressed: () => _showPolicyModal(),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoadingCheck
            ? const LoadingMeoMeo(
                message: 'Đang kiểm tra hợp đồng...',
                subMessage: 'Mèo con đang tải chính sách gia hạn~ 🐾',
              )
            : (_step == 0 ? _buildFormGiaHan() : _buildManHinhThanhCong()),
      ),
    ));
  }

  // ============================================================
  // FORM CHỌN GÓI GIA HẠN
  // ============================================================
  Widget _buildFormGiaHan() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── THÔNG BÁO GIA HẠN THÀNH CÔNG GẦN NHẤT (NẾU CÓ) ──
          if (_pendingPhuLuc?['trang_thai'] == 'Đã duyệt') ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hợp đồng đã gia hạn thành công',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        Text(
                          'Hiệu lực mới đến ${_formatDate(_ngayHetHan)}. Bạn có thể chọn kỳ hạn dưới đây nếu muốn gia hạn tiếp.',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF047857), height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => setState(() => _step = 1),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Xem phiếu', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                  ),
                ],
              ),
            ),
          ],

          // ── THÔNG TIN HỢP ĐỒNG HIỆN TẠI ──
          _buildHopDongHienTaiCard(),

          // ── RÀNG BUỘC THỜI GIAN GIA HẠN: CÒN <= 30 NGÀY (1 THÁNG) MỚI CHO GIA HẠN ──
          if (!_duDieuKienGiaHan)
            _buildChuaDenHanGiaHanView()
          else ...[
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hợp đồng sắp hết hạn (còn $_soNgayConLai ngày). Đủ điều kiện gửi đơn gia hạn!',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── TIÊU ĐỀ CHỌN THỜI GIAN GIA HẠN (TỐI THIỂU 6 THÁNG, TỐI ĐA 1 NĂM) ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Thời gian muốn gia hạn thêm',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.auto_awesome, color: Color(0xFF2563EB), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Tối thiểu 6th - Tối đa 1 năm',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2563EB),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 3 LỰA CHỌN GÓI: 6 THÁNG, 9 THÁNG, 12 THÁNG (1 NĂM) ──
            Row(
              children: [
                Expanded(
                  child: _buildPackageCard(
                    id: '6',
                    title: '6 Th',
                    subtitle: 'Tối thiểu 6th',
                    priceSub: '${(_giaThue / 1000000).toStringAsFixed(1)}M/th',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPackageCard(
                    id: '9',
                    title: '9 Th',
                    subtitle: 'Tiêu chuẩn',
                    priceSub: '${(_giaThue / 1000000).toStringAsFixed(1)}M/th',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPackageCard(
                    id: '12',
                    title: '12 Th',
                    subtitle: 'Tối đa 1 năm',
                    tag: 'Ưu đãi nhất',
                    priceSub: '${(_giaThue / 1000000).toStringAsFixed(1)}M/th',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tùy chọn số tháng khác (trong khoảng 6 - 12 tháng)
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedPackage = _selectedPackage == 'khac' ? '6' : 'khac';
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _selectedPackage == 'khac' ? Icons.check_circle_rounded : Icons.tune_rounded,
                        size: 14,
                        color: const Color(0xFF0284C7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _selectedPackage == 'khac' ? 'Đang chọn số tháng tùy chỉnh' : 'Tùy chọn số tháng khác (6 - 12 th)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── NẾU CHỌN TÙY CHỌN KHÁC ──
            if (_selectedPackage == 'khac') ...[
              _buildCustomSection(),
              const SizedBox(height: 16),
            ],

            // ── KỲ HẠN MỚI DỰ KIẾN ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range_rounded, color: Color(0xFF0284C7), size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Kỳ hạn mới:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_formatDate(_ngayBatDauMoi)} → ${_formatDate(_ngayKetThucMoi)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // ── CAM KẾT QUYỀN LỢI KHÁCH THUÊ ──
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cam kết quyền lợi khách thuê',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tiền cọc bảo lưu 100%. BQL Kiêu Giang duyệt & gửi phụ lục ký điện tử qua ứng dụng trong 24 giờ làm việc.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF166534),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── NÚT GỬI YÊU CẦU (CHỈ HIỆN KHI ĐỦ ĐIỀU KIỆN) ──
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _guiYeuCauGiaHan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _selectedPackage == 'khac' ? 'Gửi Đề Xuất Gia Hạn' : 'Gửi Yêu Cầu Gia Hạn',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  // ── GIAO DIỆN KHÓA: CHƯA ĐẾN HẠN GIA HẠN HỢP ĐỒNG ──
  Widget _buildChuaDenHanGiaHanView() {
    return Column(
      children: [
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFCA5A5), width: 1.4),
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
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Color(0xFFDC2626),
                  size: 42,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'CHƯA ĐẾN THỜI HẠN GIA HẠN',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFB91C1C),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Text(
                  'Hợp đồng còn $_soNgayConLai ngày (đến ${_formatDate(_ngayHetHan)})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0284C7)),
                        SizedBox(width: 6),
                        Text(
                          'Ràng buộc quy định gia hạn:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• Thời điểm gia hạn: Cư dân chỉ được gửi đơn gia hạn khi hợp đồng sắp hết hạn (trong vòng 30 ngày cuối / còn 1 tháng).\n\n• Thời gian gia hạn: Quy định tối thiểu 6 tháng và tối đa 1 năm (12 tháng).\n\n• Trạng thái hiện tại: Hợp đồng của bạn đang có hiệu lực dài hạn. Hệ thống tạm khóa chức năng gửi đơn để đảm bảo hợp đồng. Vui lòng quay lại khi hợp đồng bước vào tháng cuối cùng.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF475569),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManHinhLichSuGiaHanHopDong(
                              hopDong: widget.hopDong,
                              tenPhong: widget.tenPhong,
                              maHopDong: _realMaHopDong,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history_rounded, size: 17),
                      label: const Text(
                        'Xem lịch sử',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF334155),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, size: 17),
                      label: const Text(
                        'Quay lại',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── CARD THÔNG TIN HỢP ĐỒNG ──
  Widget _buildHopDongHienTaiCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_user_rounded, color: Color(0xFF0284C7), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mã HD: $_maHd',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Ngày hết hạn: ${_formatDate(_ngayHetHan)}',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Text(
                  'Còn $_soThangConLai tháng',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Giá thuê hiện tại', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    const SizedBox(height: 3),
                    Text(
                      '${_formatCurrency(_giaThue)}/th',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tiền cọc bảo lưu', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                    const SizedBox(height: 3),
                    Text(
                      _formatCurrency(_tienCoc),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── THẺ CHỌN GÓI GIA HẠN ──
  Widget _buildPackageCard({
    required String id,
    required String title,
    required String subtitle,
    String? priceSub,
    String? tag,
    String? extraBenefit,
    bool isHighlight = false,
  }) {
    final isSelected = _selectedPackage == id;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 130,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? (isHighlight ? const Color(0xFF0284C7) : const Color(0xFF09638E)) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isHighlight ? const Color(0xFF0284C7) : const Color(0xFF09638E))
                : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF09638E).withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Stack(
          children: [
            if (tag != null)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFBBF24) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFF78350F) : const Color(0xFFB45309),
                    ),
                  ),
                ),
              ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ),
                if (priceSub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    priceSub,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white60 : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
                if (extraBenefit != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    extraBenefit,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFFBAE6FD) : const Color(0xFF0284C7),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── PHẦN CHỌN TÙY CHỌN KHÁC ──
  Widget _buildCustomSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chọn nhanh kỳ hạn:',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMonthChip(6),
              const SizedBox(width: 8),
              _buildMonthChip(8),
              const SizedBox(width: 8),
              _buildMonthChip(10),
              const SizedBox(width: 8),
              _buildMonthChip(12, label: '1 Năm'),
            ],
          ),
          const SizedBox(height: 14),

          // Stepper tăng giảm
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kỳ hạn thỏa thuận:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: _customMonths > 6
                          ? () => setState(() => _customMonths -= 1)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$_customMonths Tháng',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: _customMonths < 12
                          ? () => setState(() => _customMonths += 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Ô nhập lý do
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Lý do / Nguyện vọng thỏa thuận với BQL',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              Text(
                'Tùy chọn',
                style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _lyDoController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'VD: Em dự định ở thêm 6 tháng hoặc 1 năm đến khi hoàn thành khóa luận, hoặc mong muốn thỏa thuận lịch thanh toán...',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
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
                borderSide: const BorderSide(color: Color(0xFF0284C7)),
              ),
            ),
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),

          // Lưu ý policy
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lưu ý: Thời gian gia hạn tối thiểu 6 tháng và tối đa 1 năm (12 tháng) theo quy định của Kiêu Giang House.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF0369A1), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthChip(int m, {String? label}) {
    final isSel = _customMonths == m;
    return GestureDetector(
      onTap: () => setState(() => _customMonths = m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF0284C7) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label ?? '$m Tháng',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: isSel ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // MÀN HÌNH GỬI THÀNH CÔNG (SCREEN 3)
  // ============================================================
  Widget _buildManHinhThanhCong() {
    final now = DateTime.now();
    final isDaDuyet = _pendingPhuLuc?['trang_thai'] == 'Đã duyệt';
    final isTuChoi = _pendingPhuLuc?['trang_thai'] == 'Từ chối';
    final maYeuCau = _pendingPhuLuc?['ma_phu_luc']?.toString() ??
        '#GH-${widget.maPhong.replaceAll('P', '')}-${now.year}';
    final ngayTaoStr = _pendingPhuLuc?['ngay_lap']?.toString() ??
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    final ngayGiaHanDenStr = _pendingPhuLuc?['ngay_gia_han_den']?.toString();
    DateTime? ngayGiaHanDenDate;
    if (ngayGiaHanDenStr != null && ngayGiaHanDenStr.isNotEmpty) {
      ngayGiaHanDenDate = DateTime.tryParse(ngayGiaHanDenStr);
    }

    String thoiGianText = '$_selectedMonths Tháng';
    if (ngayGiaHanDenDate != null) {
      final diffMonths = ((ngayGiaHanDenDate.year - _ngayHetHan.year) * 12 +
          (ngayGiaHanDenDate.month - _ngayHetHan.month));
      if (diffMonths > 0) {
        thoiGianText = '$diffMonths Tháng';
      }
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          // Icon tròn tích xanh / verified / cancel
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: isDaDuyet
                  ? const Color(0xFFDCFCE7)
                  : (isTuChoi ? const Color(0xFFFFE4E6) : const Color(0xFFE0F2FE)),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDaDuyet
                    ? const Color(0xFF86EFAC)
                    : (isTuChoi ? const Color(0xFFFDA4AF) : const Color(0xFFBAE6FD)),
                width: 3,
              ),
            ),
            child: Icon(
              isDaDuyet
                  ? Icons.verified_rounded
                  : (isTuChoi ? Icons.cancel_rounded : Icons.hourglass_top_rounded),
              color: isDaDuyet
                  ? const Color(0xFF16A34A)
                  : (isTuChoi ? const Color(0xFFE11D48) : const Color(0xFF0284C7)),
              size: 42,
            ),
          ),
          const SizedBox(height: 14),

          // Trạng thái badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDaDuyet
                  ? const Color(0xFFECFDF5)
                  : (isTuChoi ? const Color(0xFFFFF1F2) : const Color(0xFFEFF6FF)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDaDuyet
                    ? const Color(0xFFA7F3D0)
                    : (isTuChoi ? const Color(0xFFFECDD3) : const Color(0xFFBFDBFE)),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fiber_manual_record,
                  color: isDaDuyet
                      ? const Color(0xFF10B981)
                      : (isTuChoi ? const Color(0xFFE11D48) : const Color(0xFF2563EB)),
                  size: 10,
                ),
                const SizedBox(width: 6),
                Text(
                  isDaDuyet
                      ? 'BQL ĐÃ PHÊ DUYỆT THÀNH CÔNG'
                      : (isTuChoi ? 'BQL KHÔNG ĐỒNG Ý GIA HẠN' : 'Đang chờ BQL xét duyệt'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDaDuyet
                        ? const Color(0xFF047857)
                        : (isTuChoi ? const Color(0xFFBE123C) : const Color(0xFF1D4ED8)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            isDaDuyet
                ? 'Hợp Đồng Đã Được Gia Hạn!'
                : (isTuChoi ? 'Yêu Cầu Gia Hạn Bị Từ Chối' : 'Đã Gửi Yêu Cầu Gia Hạn!'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDaDuyet
                ? 'Ban Quản Lý đã phê duyệt yêu cầu gia hạn cho ${widget.tenPhong}. Hợp đồng đã được cập nhật hiệu lực mới!'
                : (isTuChoi
                    ? 'Ban Quản Lý chưa thể phê duyệt gia hạn theo đề xuất này. Hợp đồng hiện tại của bạn vẫn giữ nguyên kỳ hạn đến ${_formatDate(_ngayHetHan)}.'
                    : 'Yêu cầu gia hạn hợp đồng ${widget.tenPhong} đã gửi đến Ban Quản Lý Nhà trọ Kiêu Giang.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
          ),
          const SizedBox(height: 18),

          // Card chi tiết đề xuất
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDaDuyet
                    ? const Color(0xFFA7F3D0)
                    : (isTuChoi ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
              ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          color: isDaDuyet
                              ? const Color(0xFF16A34A)
                              : (isTuChoi ? const Color(0xFFE11D48) : const Color(0xFF0284C7)),
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          maYeuCau,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: isDaDuyet
                                ? const Color(0xFF16A34A)
                                : (isTuChoi ? const Color(0xFFE11D48) : const Color(0xFF0284C7)),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      ngayTaoStr,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),
                _summaryRow(Icons.meeting_room_outlined, 'Phòng thuê', '${widget.tenPhong} (Tòa Kiêu Giang 2)'),
                const SizedBox(height: 10),
                _summaryRow(Icons.schedule_rounded, 'Thời gian đề xuất', thoiGianText),
                const SizedBox(height: 10),
                _summaryRow(
                  Icons.calendar_month_outlined,
                  isDaDuyet
                      ? 'Kỳ hạn mới sau gia hạn'
                      : (isTuChoi ? 'Hạn hợp đồng hiện tại' : 'Kỳ hạn mới dự kiến'),
                  isDaDuyet
                      ? (ngayGiaHanDenDate != null
                          ? '${_formatDate(_ngayBatDauMoi)} → ${_formatDate(ngayGiaHanDenDate)}'
                          : '${_formatDate(_ngayBatDauMoi)} → ${_formatDate(_ngayKetThucMoi)}')
                      : (isTuChoi
                          ? 'Đến ${_formatDate(_ngayHetHan)} (Giữ nguyên)'
                          : '${_formatDate(_ngayBatDauMoi)} → ${_formatDate(_ngayKetThucMoi)}'),
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  Icons.shield_outlined,
                  'Trạng thái cọc',
                  isDaDuyet
                      ? 'Bảo lưu 100% (${_formatCurrency(_tienCoc)}) • Có hiệu lực'
                      : (isTuChoi
                          ? 'Bảo lưu 100% (${_formatCurrency(_tienCoc)}) • Hoàn khi trả phòng'
                          : 'Bảo lưu 100% (${_formatCurrency(_tienCoc)})'),
                  isGreen: isDaDuyet,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Box Hướng dẫn hoặc Quy trình
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isTuChoi ? const Color(0xFFFECDD3) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isTuChoi ? Icons.lightbulb_outline_rounded : Icons.alt_route_rounded,
                      color: isTuChoi ? const Color(0xFFE11D48) : const Color(0xFF0284C7),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isTuChoi ? 'CÁC LỰA CHỌN DÀNH CHO BẠN' : 'QUY TRÌNH XỬ LÝ',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: isTuChoi ? const Color(0xFF9F1239) : const Color(0xFF0C4A6E),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (isTuChoi) ...[
                  _buildGuidanceItem(
                    1,
                    'Đăng ký chuyển sang phòng khác',
                    'Tìm các phòng trống khác trong tòa nhà Kiêu Giang và chuyển tiền cọc sang phòng mới.',
                  ),
                  const SizedBox(height: 10),
                  _buildGuidanceItem(
                    2,
                    'Đề xuất kỳ hạn khác',
                    'Bạn có thể gửi lại đề xuất với số tháng khác (ví dụ: 6 tháng hoặc 12 tháng) để BQL xem xét.',
                  ),
                  const SizedBox(height: 10),
                  _buildGuidanceItem(
                    3,
                    'Trả phòng đúng hạn',
                    'Đến ${_formatDate(_ngayHetHan)}, BQL kiểm tra phòng và hoàn trả lại 100% tiền cọc cho bạn.',
                  ),
                ] else ...[
                  _buildProcessStep(1, 'Tiếp nhận yêu cầu', 'Đã xong', isDone: true),
                  const SizedBox(height: 10),
                  _buildProcessStep(
                    2,
                    'BQL xét duyệt & lập Phụ lục',
                    isDaDuyet ? 'Đã duyệt' : 'Trong 24h',
                    isDone: isDaDuyet,
                  ),
                  const SizedBox(height: 10),
                  _buildProcessStep(
                    3,
                    isDaDuyet ? 'Hiệu lực kỳ hạn hợp đồng mới' : 'Ký phụ lục trực tiếp trên app Kiêu Giang',
                    isDaDuyet ? 'Hoàn tất' : 'Chờ duyệt',
                    isDone: isDaDuyet,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (isTuChoi) ...[
            // Nút 1: Tìm phòng để chuyển
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RoomTransferSearchScreen(
                        currentRoomNumber: widget.maPhong,
                        currentPrice: _giaThue,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.meeting_room_rounded, size: 18),
                label: const Text(
                  'Tìm Phòng Trống Để Chuyển',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Nút 2: Gửi lại đề xuất kỳ hạn khác
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  _danhDauDaXemThanhCong();
                  setState(() {
                    _step = 0;
                    _pendingPhuLuc = null;
                  });
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Gửi Đề Xuất Kỳ Hạn Khác', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF09638E),
                  side: const BorderSide(color: Color(0xFF09638E)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Nút 3: Quay về trang chủ
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton.icon(
                onPressed: () {
                  _danhDauDaXemThanhCong();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Quay Về Trang Chủ', style: TextStyle(fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                ),
              ),
            ),
          ] else ...[
            // Nút 1: Xem chi tiết hợp đồng
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  _danhDauDaXemThanhCong();
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ContractDetailScreen()),
                  );
                },
                icon: Icon(
                  isDaDuyet ? Icons.verified_user_rounded : Icons.description_outlined,
                  size: 18,
                ),
                label: Text(
                  isDaDuyet ? 'Xem Chi Tiết Hợp Đồng Mới' : 'Xem Chi Tiết Hợp Đồng',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDaDuyet ? const Color(0xFF16A34A) : const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Nút 2: Quay về trang chủ
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  _danhDauDaXemThanhCong();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Quay Về Trang Chủ', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF09638E),
                  side: const BorderSide(color: Color(0xFF09638E)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            if (isDaDuyet) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  _danhDauDaXemThanhCong();
                  setState(() {
                    _step = 0;
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text(
                  'Tạo đề xuất gia hạn mới',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                ),
              ),
            ],
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGuidanceItem(int number, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1F2),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFDA4AF)),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE11D48),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value, {bool isGreen = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: const Color(0xFF64748B), size: 15),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isGreen ? const Color(0xFF16A34A) : const Color(0xFF0F172A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcessStep(int stepNum, String title, String timeNote, {bool isDone = false}) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isDone ? const Color(0xFF16A34A) : const Color(0xFFEFF6FF),
            shape: BoxShape.circle,
            border: Border.all(
              color: isDone ? const Color(0xFF16A34A) : const Color(0xFF93C5FD),
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, color: Colors.white, size: 14)
                : Text(
                    '$stepNum',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0284C7),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Bước $stepNum: $title',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isDone ? FontWeight.bold : FontWeight.w500,
              color: const Color(0xFF0F172A),
            ),
          ),
        ),
        if (timeNote.isNotEmpty)
          Text(
            timeNote,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDone ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            ),
          ),
      ],
    );
  }

  // ── MODAL QUY ĐỊNH GIA HẠN ──
  void _showPolicyModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quy định Gia Hạn Hợp Đồng',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Khi gia hạn, tiền đặt cọc của bạn được bảo lưu 100% sang chu kỳ mới mà không cần nộp lại.\n'
              '2. BQL sẽ phát hành Phụ lục Hợp đồng điện tử trong 24 giờ sau khi tiếp nhận yêu cầu.\n'
              '3. Bạn và Chủ trọ sẽ ký xác nhận trực tiếp qua app để phụ lục có hiệu lực pháp lý đầy đủ.\n'
              '4. Nếu muốn thỏa thuận số tháng linh hoạt hoặc điều kiện riêng, hãy chọn mục "Khác".',
              style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Đã Hiểu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

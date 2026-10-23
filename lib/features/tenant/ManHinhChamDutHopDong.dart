import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhBienBanThanhLy.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

class ManHinhChamDutHopDong extends StatefulWidget {
  final HopDongModel? hopDong;
  final String tenPhong;
  final String maPhong;
  final String? tenKhachThue;

  const ManHinhChamDutHopDong({
    super.key,
    this.hopDong,
    this.tenPhong = 'Phòng 303',
    this.maPhong = 'P303',
    this.tenKhachThue,
  });

  @override
  State<ManHinhChamDutHopDong> createState() => _ManHinhChamDutHopDongState();
}

class _ManHinhChamDutHopDongState extends State<ManHinhChamDutHopDong> {
  static const Color _primary = Color(0xFF09638E);
  static const Color _bgLight = Color(0xFFF8FAFC);
  static const Color _textDark = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFE2E8F0);

  bool _isLoading = true;
  bool _isSubmitting = false;

  late HopDongModel _hd;
  BienBanThanhLyModel? _bienBan;

  // 4 thành phần chính của form
  bool _isDungHan = false; // Đúng hạn vs Trước hạn (tự động tính toán theo ngày hết hạn)
  late DateTime _ngayDuKien; // Mặc định sau 15 ngày
  final TextEditingController _lyDoController = TextEditingController();

  /// Số ngày từ ngày dọn đi đến ngày hết hạn hợp đồng:
  /// = (Ngày hết hạn HĐ) - (Ngày dự kiến dọn đi)
  int get _soNgayConLaiDenHetHan {
    try {
      final kt = DateTime.tryParse(_hd.ngayKt);
      if (kt == null) return 0;
      // So sánh chỉ tính phần ngày (bỏ qua giờ phút)
      final dKt = DateTime(kt.year, kt.month, kt.day);
      final dDk = DateTime(_ngayDuKien.year, _ngayDuKien.month, _ngayDuKien.day);
      return dKt.difference(dDk).inDays;
    } catch (_) {
      return 0;
    }
  }

  /// Nghiệp vụ cọc:
  /// - Nếu ngày dọn đi trước hạn hợp đồng > 30 ngày: Khóa "Đúng hạn", bắt buộc "Trước hạn", hoàn cọc 0đ.
  /// - Chỉ khi hợp đồng sắp hết hạn (còn <= 30 ngày) hoặc ngày dọn đi >= ngày hết hạn: mới kích hoạt "Đúng hạn".
  bool get _duDieuKienDungHan {
    return _soNgayConLaiDenHetHan <= 30;
  }

  /// Tự động cập nhật lựa chọn hình thức dựa trên ngày dự kiến dọn đi
  void _capNhatTrangThaiDungHan() {
    if (!_duDieuKienDungHan) {
      _isDungHan = false; // Bắt buộc Trước hạn
    } else {
      _isDungHan = true; // Đủ điều kiện Đúng hạn
    }
  }

  @override
  void initState() {
    super.initState();
    // Mặc định sau 15 ngày theo quy định báo trước
    _ngayDuKien = DateTime.now().add(const Duration(days: 15));
    _taiDuLieu();
  }

  @override
  void dispose() {
    _lyDoController.dispose();
    super.dispose();
  }

  /// Tải thông tin hợp đồng và kiểm tra xem đã có đơn thanh lý phòng chưa
  Future<void> _taiDuLieu() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final maHD = widget.hopDong?.maHopDong ?? 'HD001';

      // 1. Tải hợp đồng
      if (widget.hopDong != null) {
        _hd = widget.hopDong!;
      } else {
        final hdRow = await db
            .from('hop_dong')
            .select()
            .eq('ma_hop_dong', maHD)
            .maybeSingle();
        if (hdRow != null) {
          _hd = HopDongModel.fromJson(Map<String, dynamic>.from(hdRow));
        } else {
          _hd = HopDongModel(
            maHopDong: maHD,
            ngayBd: '2026-04-01',
            ngayKt: '2026-10-01',
            tienDatCoc: 3800000,
            giaThueThaoThuan: 3800000,
            chuKyThuTien: 1,
            trangThai: 'Còn hạn',
            maPhong: widget.maPhong,
            maKhachDaiDien: 'KH001',
            ngayKy: '2026-03-28',
          );
        }
      }

      // Tự động kiểm tra điều kiện Đúng hạn / Trước hạn
      _capNhatTrangThaiDungHan();

      // 2. Kiểm tra biên bản thanh lý gần nhất của hợp đồng này
      try {
        final bbRows = await db
            .from('bien_ban_thanh_ly')
            .select()
            .eq('ma_hop_dong', _hd.maHopDong)
            .order('ngay_tra_phong', ascending: false)
            .limit(1);

        if ((bbRows as List).isNotEmpty) {
          _bienBan = BienBanThanhLyModel.fromJson(
            Map<String, dynamic>.from(bbRows.first),
          );
        } else {
          _bienBan = null;
        }
      } catch (e) {
        debugPrint('Lỗi tải bien_ban_thanh_ly: $e');
        _bienBan = null;
      }
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu chấm dứt hợp đồng: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Gửi đơn yêu cầu trả phòng lên Supabase
  Future<void> _guiYeuCauTraPhong() async {
    // 0. Kiểm tra ngày dự kiến dọn đi: Phải trong vòng 30 ngày tới kể từ hôm nay
    final nowCheck = DateTime.now();
    final todayOnly = DateTime(nowCheck.year, nowCheck.month, nowCheck.day);
    final chosenOnly = DateTime(_ngayDuKien.year, _ngayDuKien.month, _ngayDuKien.day);
    final diffDays = chosenOnly.difference(todayOnly).inDays;

    if (diffDays < 1 || diffDays > 30) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            diffDays > 30
                ? 'Ngày dự kiến dọn đi chỉ được chọn trong vòng 30 ngày tới kể từ hôm nay (không được chọn ngày quá xa).'
                : 'Ngày dự kiến dọn đi phải từ ngày mai trở đi.',
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // Đảm bảo logic trước khi gửi: nếu không đủ điều kiện đúng hạn thì luôn là Trước hạn
    if (!_duDieuKienDungHan && _isDungHan) {
      _isDungHan = false;
    }

    final tienCocHoan = _isDungHan ? _hd.tienDatCoc.toDouble() : 0.0;
    final loaiHinhStr = _isDungHan ? 'Đúng hạn' : 'Trước hạn';

    final xacNhan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.help_outline_rounded, color: _primary, size: 24),
            SizedBox(width: 8),
            Text(
              'Xác nhận gửi đơn',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn xác nhận gửi đơn trả phòng vào ngày ${FormatUtils.formatDate(_ngayDuKien)}?',
              style: const TextStyle(fontSize: 13.5, color: _textDark, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isDungHan ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isDungHan ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• Hình thức: $loaiHinhStr',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _isDungHan ? const Color(0xFF16A34A) : const Color(0xFFB45309),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '• Hoàn cọc dự kiến: ${FormatUtils.currency(tienCocHoan)}${_isDungHan ? "" : " (Mất cọc theo HĐ)"}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _isDungHan ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Vào ngày dọn đi, Ban Quản Lý và bạn sẽ gặp trực tiếp tại phòng để chốt điện nước và tất toán.',
              style: TextStyle(fontSize: 12, color: _textMuted, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Xem lại', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Gửi đơn', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (xacNhan != true) return;

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final tsStr = DateTime.now().millisecondsSinceEpoch.toString();
      final maTL = 'TL${tsStr.substring(tsStr.length - 8)}';
      final ngayTraStr =
          '${_ngayDuKien.year}-${_ngayDuKien.month.toString().padLeft(2, '0')}-${_ngayDuKien.day.toString().padLeft(2, '0')}';
      final lyDo = _lyDoController.text.trim();

      // Tải chỉ số điện nước mới nhất từ bảng phong
      double chiSoDienCuoi = 0.0;
      double chiSoNuocCuoi = 0.0;
      try {
        final pRow = await db
            .from('phong')
            .select('chi_so_dien, chi_so_nuoc')
            .eq('ma_phong', _hd.maPhong)
            .maybeSingle();
        if (pRow != null) {
          chiSoDienCuoi = double.tryParse(pRow['chi_so_dien']?.toString() ?? '') ?? 0.0;
          chiSoNuocCuoi = double.tryParse(pRow['chi_so_nuoc']?.toString() ?? '') ?? 0.0;
        }
      } catch (errP) {
        debugPrint('Lỗi tải chỉ số điện nước từ bảng phong khi tạo biên bản thanh lý: $errP');
      }

      final bbData = <String, dynamic>{
        'ma_thanh_ly': maTL,
        'ma_hop_dong': _hd.maHopDong,
        'ngay_tra_phong': ngayTraStr,
        'chi_so_dien_cuoi': chiSoDienCuoi,
        'chi_so_nuoc_cuoi': chiSoNuocCuoi,
        'tien_kh_tra_them': 0,
        'tien_coc_hoan_lai': tienCocHoan,
        'trang_thai': 'CHO_DUYET',
        'ghi_chu': lyDo.isNotEmpty ? lyDo : 'Yêu cầu trả phòng từ cư dân',
      };

      try {
        await db.from('bien_ban_thanh_ly').insert(bbData);
      } catch (e) {
        debugPrint('Insert có cột trang_thai lỗi, thử fallback: $e');
        // Fallback ghi chú có tag trạng thái nếu bảng chưa thêm cột trang_thai
        final fallbackData = Map<String, dynamic>.from(bbData)..remove('trang_thai');
        fallbackData['ghi_chu'] =
            '[Trạng thái: CHO_DUYET] ${bbData['ghi_chu']}';
        await db.from('bien_ban_thanh_ly').insert(fallbackData);
      }

      // Thông báo hệ thống
      SystemNotificationService.show(
        title: 'Đã gửi yêu cầu trả phòng',
        body: 'Đơn trả phòng ${_hd.maPhong} đã được gửi tới Ban Quản Lý (Trạng thái: Chờ duyệt).',
        tag: 'tl_${_hd.maHopDong}',
        loai: 'hop_dong',
      );

      // Nạp lại dữ liệu để chuyển sang chế độ hiển thị trạng thái
      await _taiDuLieu();

      if (mounted) {
        await _hienPopupThanhCong(
          maTL: maTL,
          ngayTraStr: ngayTraStr,
          isDungHan: _isDungHan,
          tienCocHoan: tienCocHoan,
        );
      }
    } catch (e) {
      debugPrint('Lỗi gửi yêu cầu thanh lý: $e');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi gửi yêu cầu',
          noiDung: '$e',
          type: ThongBaoType.thatBai,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Hủy yêu cầu trả phòng đang chờ duyệt
  Future<void> _huyYeuCau() async {
    final xacNhan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hủy yêu cầu trả phòng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: const Text(
          'Bạn có chắc chắn muốn hủy đơn xin trả phòng này không?',
          style: TextStyle(fontSize: 13.5, color: _textDark),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xác nhận hủy', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (xacNhan != true) return;

    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      if (_bienBan != null && _bienBan!.maThanhLy.isNotEmpty) {
        await db.from('bien_ban_thanh_ly').delete().eq('ma_thanh_ly', _bienBan!.maThanhLy);
      } else {
        await db.from('bien_ban_thanh_ly').delete().eq('ma_hop_dong', _hd.maHopDong);
      }

      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Đã hủy đơn',
          noiDung: 'Đã hủy đơn yêu cầu trả phòng thành công.',
          type: ThongBaoType.thongTin,
        );
      }

      await _taiDuLieu();
    } catch (e) {
      debugPrint('Lỗi hủy yêu cầu: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi hủy yêu cầu: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Chọn ngày dự kiến dọn đi
  Future<void> _chonNgayDuKien() async {
    final now = DateTime.now();
    final minDate = now.add(const Duration(days: 1));
    final maxDate = now.add(const Duration(days: 30));

    DateTime initialDate = _ngayDuKien;
    if (initialDate.isBefore(minDate)) {
      initialDate = minDate;
    } else if (initialDate.isAfter(maxDate)) {
      initialDate = maxDate;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: minDate,
      lastDate: maxDate,
      helpText: 'CHỌN NGÀY DỰ KIẾN DỌN ĐI (TỐI ĐA 30 NGÀY)',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primary,
              onPrimary: Colors.white,
              onSurface: _textDark,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _ngayDuKien = picked;
        // Tự động kiểm tra lại logic cọc tương ứng với ngày mới chọn
        _capNhatTrangThaiDungHan();
      });
    }
  }

  /// Làm sạch các tiền tố kỹ thuật nếu có trong chuỗi ghi chú
  String _lamSachGhiChu(String raw) {
    return raw
        .replaceAll(RegExp(r'\[Trạng thái:[^\]]*\]\s*'), '')
        .replaceAll(RegExp(r'\[Loại:[^\]]*\]\s*'), '')
        .trim();
  }

  // ─── POPUP THÔNG BÁO GỬI ĐƠN THÀNH CÔNG (THIẾT KẾ HIỆN ĐẠI, BO GÓC) ───
  Future<void> _hienPopupThanhCong({
    required String maTL,
    required String ngayTraStr,
    required bool isDungHan,
    required double tienCocHoan,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 10,
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon tròn với hiệu ứng ánh sáng xanh
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF16A34A).withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Tiêu đề popup
                const Text(
                  'Gửi Yêu Cầu Thành Công!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Đơn trả phòng của bạn đã được chuyển tới Ban Quản Lý và đang chờ xét duyệt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),

                // Bảng tóm tắt thông tin đơn yêu cầu
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Trạng thái đơn',
                            style: TextStyle(fontSize: 12, color: _textMuted),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.hourglass_top_rounded, size: 11, color: Color(0xFFD97706)),
                                SizedBox(width: 4),
                                Text(
                                  'CHỜ DUYỆT',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD97706),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildPopupRow('Mã yêu cầu', maTL),
                      const SizedBox(height: 8),
                      _buildPopupRow('Phòng', '${widget.tenPhong} (${widget.maPhong})'),
                      const SizedBox(height: 8),
                      _buildPopupRow('Ngày dự kiến dọn', FormatUtils.formatDate(ngayTraStr)),
                      const SizedBox(height: 8),
                      _buildPopupRow(
                        'Hình thức',
                        isDungHan ? 'Đúng hạn' : 'Trước hạn',
                        valueColor: isDungHan ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                      ),
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildPopupRow(
                        'Tiền cọc hoàn lại',
                        isDungHan && tienCocHoan > 0
                            ? FormatUtils.currency(tienCocHoan)
                            : '0đ (Mất cọc theo HĐ)',
                        valueColor: isDungHan && tienCocHoan > 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        isBold: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Lời dặn thực tế
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Color(0xFF16A34A), size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Vào ngày dọn đi (${FormatUtils.formatDate(ngayTraStr)}), Ban Quản Lý sẽ gặp trực tiếp bạn tại phòng để chốt điện nước, kiểm tra nội thất và tất toán hợp đồng.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF15803D),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Nút hành động
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Đã hiểu & Xem chi tiết đơn',
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
        );
      },
    );
  }

  Widget _buildPopupRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: _textMuted),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? _textDark,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgLight,
        body: LoadingMeoMeo(
          message: 'Đang tải thông tin...',
          subMessage: 'Mèo con đang kiểm tra dữ liệu phòng~ 🐾',
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: const Text(
          'Yêu Cầu Trả Phòng',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: _textDark),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 21, color: _primary),
            tooltip: 'Làm mới',
            onPressed: _taiDuLieu,
          ),
        ],
      ),
      body: SafeArea(
        child: _bienBan != null ? _buildTrangThaiView() : _buildFormView(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 1: TRẠNG THÁI YÊU CẦU (Chờ duyệt / Đã duyệt / Từ chối)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildTrangThaiView() {
    final bb = _bienBan!;
    // Đảm bảo: Nếu biên bản đang ở trạng thái chờ duyệt (CHO_DUYET) thì TUYỆT ĐỐI KHÔNG hiển thị ĐÃ DUYỆT
    final isChoDuyet = bb.isChoDuyet;
    final isDaDuyet = !isChoDuyet && (bb.isDaDuyet || _hd.trangThai == 'Đã thanh lý');
    final lyDoHienThi = _lamSachGhiChu(bb.ghiChu);

    // Tính toán hình thức trả phòng thuần túy dựa vào logic ngày dọn đi so với ngày hết hạn HĐ trên App
    bool isDungHanTheoNgay = false;
    try {
      final kt = DateTime.tryParse(_hd.ngayKt);
      final tra = DateTime.tryParse(bb.ngayTraPhong);
      if (kt != null && tra != null) {
        final dKt = DateTime(kt.year, kt.month, kt.day);
        final dTra = DateTime(tra.year, tra.month, tra.day);
        final diff = dKt.difference(dTra).inDays;
        isDungHanTheoNgay = diff <= 30; // Còn <= 30 ngày hoặc đã qua hạn thì coi là đúng hạn
      } else {
        isDungHanTheoNgay = bb.tienCocHoanLai > 0;
      }
    } catch (_) {
      isDungHanTheoNgay = bb.tienCocHoanLai > 0;
    }
    final hinhThucHienThi = isDungHanTheoNgay ? 'Đúng hạn' : 'Trước hạn';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          // ── ICON & TIÊU ĐỀ TRẠNG THÁI ──
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: isDaDuyet
                  ? const Color(0xFFDCFCE7)
                  : isChoDuyet
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFFEE2E2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDaDuyet
                  ? Icons.check_circle_rounded
                  : isChoDuyet
                      ? Icons.hourglass_top_rounded
                      : Icons.cancel_rounded,
              size: 40,
              color: isDaDuyet
                  ? const Color(0xFF16A34A)
                  : isChoDuyet
                      ? const Color(0xFFD97706)
                      : const Color(0xFFDC2626),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isDaDuyet
                ? 'Thanh Lý Phòng Thành Công 🎉'
                : isChoDuyet
                    ? 'Đang Chờ Ban Quản Lý Duyệt'
                    : 'Yêu Cầu Chưa Được Duyệt',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDaDuyet
                ? 'Chủ trọ / Ban quản lý đã xác nhận thanh lý phòng thành công. Cảm ơn bạn đã đồng hành cùng tòa nhà!'
                : isChoDuyet
                    ? 'Đơn trả phòng đã được gửi lên hệ thống. Ban Quản Lý sẽ xem xét duyệt lịch hẹn, sau đó ngày dọn đi sẽ xuống nghiệm thu và tất toán cọc.'
                    : 'Yêu cầu của bạn chưa được duyệt. Bạn có thể gửi lại yêu cầu hoặc liên hệ trực tiếp BQL.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: _textMuted, height: 1.45),
          ),
          const SizedBox(height: 24),

          // ── CARD THÔNG TIN CHI TIẾT (Tránh tuyệt đối lỗi tràn màn hình) ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'CHI TIẾT ĐƠN YÊU CẦU',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDaDuyet
                            ? const Color(0xFFDCFCE7)
                            : isChoDuyet
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isDaDuyet
                            ? 'ĐÃ DUYỆT'
                            : isChoDuyet
                                ? 'CHỜ DUYỆT'
                                : 'TỪ CHỐI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDaDuyet
                              ? const Color(0xFF16A34A)
                              : isChoDuyet
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20, color: Color(0xFFF1F5F9)),

                _buildInfoRow('Mã yêu cầu', bb.maThanhLy.isNotEmpty ? bb.maThanhLy : 'TL001'),
                _buildInfoRow('Phòng', '${widget.tenPhong} (${widget.maPhong})'),
                _buildInfoRow('Hợp đồng', _hd.maHopDong),
                _buildInfoRow('Ngày dự kiến dọn đi', FormatUtils.formatDate(bb.ngayTraPhong)),
                _buildInfoRow(
                  'Hình thức',
                  hinhThucHienThi,
                  badgeColor: isDungHanTheoNgay
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
                if (lyDoHienThi.isNotEmpty)
                  _buildInfoRow('Lý do', lyDoHienThi),

                const Divider(height: 20, color: Color(0xFFF1F5F9)),
                _buildInfoRow(
                  'Tiền cọc hoàn lại',
                  isDungHanTheoNgay && bb.tienCocHoanLai > 0
                      ? FormatUtils.currency(bb.tienCocHoanLai)
                      : '0đ (Mất cọc theo HĐ)',
                  isBold: true,
                  valueColor: isDungHanTheoNgay && bb.tienCocHoanLai > 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── NÚT HÀNH ĐỘNG ──
          if (isDaDuyet) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Về Trang Chủ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
              ),
            ),
          ] else if (isChoDuyet) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _huyYeuCau,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Hủy Đơn', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _taiDuLieu,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Làm Mới', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _bienBan = null);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Gửi Lại Yêu Cầu Mới', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // VIEW 2: FORM TINH GỌN (Đúng 4 thành phần chính)
  // ══════════════════════════════════════════════════════════════════
  Widget _buildFormView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─────────────────────────────────────────────────────────────
                // 1. THẺ THÔNG TIN PHÒNG NGẮN GỌN
                // ─────────────────────────────────────────────────────────────
                _buildRoomInfoCard(),
                const SizedBox(height: 20),

                // ─────────────────────────────────────────────────────────────
                // 2. CHỌN NGÀY DỰ KIẾN DỌN ĐI (DatePicker, mặc định sau 15 ngày)
                // ─────────────────────────────────────────────────────────────
                const Text(
                  'Ngày dự kiến dọn đi',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildDatePickerCard(),
                const SizedBox(height: 20),

                // ─────────────────────────────────────────────────────────────
                // 3. CHỌN LÝ DO / HÌNH THỨC (Có khóa tự động nếu chưa tới hạn)
                // ─────────────────────────────────────────────────────────────
                const Text(
                  'Hình thức trả phòng',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildHinhThucSelector(),
                const SizedBox(height: 20),

                // ─────────────────────────────────────────────────────────────
                // 4. MỘT Ô NHẬP LÝ DO NGẮN GỌN
                // ─────────────────────────────────────────────────────────────
                const Text(
                  'Lý do trả phòng',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 10),
                _buildLyDoInput(),
                const SizedBox(height: 14),

                // Ghi chú quy trình thực tế
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: _textMuted),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Quy định trả phòng: Vui lòng chọn ngày dự kiến dọn đi trong vòng 30 ngày tới (thông báo trước tối thiểu 15 ngày). Vào ngày dọn đi, Ban Quản Lý sẽ gặp bạn trực tiếp tại phòng để chốt điện nước, kiểm tra đồ đạc và tất toán tiền cọc.',
                          style: TextStyle(fontSize: 12, color: _textMuted, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─────────────────────────────────────────────────────────────
        // NÚT BẤM: "Gửi yêu cầu trả phòng"
        // ─────────────────────────────────────────────────────────────
        _buildBottomButton(),
      ],
    );
  }

  /// 1. Thẻ thông tin phòng ngắn gọn (Mã phòng, Hạn hợp đồng, Tiền cọc)
  Widget _buildRoomInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
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
        children: [
          // Header phòng
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.meeting_room_rounded, color: _primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.tenPhong,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Mã phòng: ${widget.maPhong} • HĐ: ${_hd.maHopDong}',
                      style: const TextStyle(fontSize: 12, color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Color(0xFFF1F5F9)),

          // 2 cột: Hạn hợp đồng & Tiền cọc
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Hạn hợp đồng', style: TextStyle(fontSize: 11.5, color: _textMuted)),
                    const SizedBox(height: 3),
                    Text(
                      _hd.ngayKtFormatted.isNotEmpty ? _hd.ngayKtFormatted : 'Theo hợp đồng',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tiền cọc giữ chỗ', style: TextStyle(fontSize: 11.5, color: _textMuted)),
                    const SizedBox(height: 3),
                    Text(
                      FormatUtils.currency(_hd.tienDatCoc),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _primary,
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

  /// 2. Chọn ngày dự kiến dọn đi (DatePicker, mặc định sau 15 ngày)
  Widget _buildDatePickerCard() {
    final diffDays = _ngayDuKien.difference(DateTime.now()).inDays + 1;

    return InkWell(
      onTap: _chonNgayDuKien,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borderColor),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.calendar_month_rounded, color: _primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    FormatUtils.formatDate(_ngayDuKien),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    diffDays > 0 ? 'Dự kiến sau $diffDays ngày (tối đa trong vòng 30 ngày)' : 'Hôm nay',
                    style: const TextStyle(fontSize: 11.5, color: _textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor),
              ),
              child: const Row(
                children: [
                  Text('Đổi ngày', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _primary)),
                  SizedBox(width: 4),
                  Icon(Icons.edit_calendar_rounded, size: 14, color: _primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Chọn hình thức: Tự động khóa "Đúng hạn" nếu ngày dọn đi trước hạn > 30 ngày
  Widget _buildHinhThucSelector() {
    final duDieuKien = _duDieuKienDungHan;
    final soNgayConLai = _soNgayConLaiDenHetHan;

    return Column(
      children: [
        Row(
          children: [
            // Lựa chọn 1: Đúng hạn (Khóa nếu ngày dọn đi cách ngày hết hạn > 30 ngày)
            Expanded(
              child: InkWell(
                onTap: duDieuKien
                    ? () => setState(() => _isDungHan = true)
                    : () {
                        ThongBaoHelper.hienToast(
                          context,
                          tieuDe: 'Trả Phòng Trước Hạn',
                          noiDung: 'Hợp đồng còn $soNgayConLai ngày. Bạn chỉ có thể chọn Trước hạn.',
                          type: ThongBaoType.canhBao,
                        );
                      },
                borderRadius: BorderRadius.circular(14),
                child: Opacity(
                  opacity: duDieuKien ? 1.0 : 0.45,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: duDieuKien
                          ? (_isDungHan ? const Color(0xFFF0FDF4) : Colors.white)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: duDieuKien
                            ? (_isDungHan ? const Color(0xFF16A34A) : _borderColor)
                            : const Color(0xFFCBD5E1),
                        width: (duDieuKien && _isDungHan) ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              !duDieuKien
                                  ? Icons.lock_outline_rounded
                                  : (_isDungHan
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded),
                              size: 18,
                              color: !duDieuKien
                                  ? _textMuted
                                  : (_isDungHan ? const Color(0xFF16A34A) : _textMuted),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Đúng hạn',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: duDieuKien ? _textDark : _textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          duDieuKien
                              ? 'Được hoàn cọc sau nghiệm thu'
                              : 'Khóa (HĐ còn $soNgayConLai ngày)',
                          style: const TextStyle(fontSize: 11, color: _textMuted, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Lựa chọn 2: Trước hạn (Tự động tích chọn khi bị khóa Đúng hạn)
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _isDungHan = false),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: !_isDungHan ? const Color(0xFFFEF2F2) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !_isDungHan ? const Color(0xFFDC2626) : _borderColor,
                      width: !_isDungHan ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            !_isDungHan
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: !_isDungHan ? const Color(0xFFDC2626) : _textMuted,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Trước hạn',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mất cọc theo hợp đồng',
                        style: TextStyle(fontSize: 11, color: _textMuted, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),

        // Cảnh báo nhẹ nhàng nếu chọn trước hạn: Đúng 1 dòng nhẹ nhàng theo yêu cầu
        if (!_isDungHan) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !duDieuKien
                        ? 'Trả phòng trước hạn sẽ mất cọc (HĐ còn $soNgayConLai ngày).'
                        : 'Trả phòng trước hạn sẽ mất cọc theo hợp đồng.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFB45309),
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 4. Một ô nhập lý do ngắn gọn
  Widget _buildLyDoInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: TextField(
        controller: _lyDoController,
        maxLines: 2,
        maxLength: 120,
        style: const TextStyle(fontSize: 13.5, color: _textDark),
        decoration: const InputDecoration(
          hintText: 'Ví dụ: Chuyển công tác, về quê, mua nhà mới...',
          hintStyle: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          contentPadding: EdgeInsets.all(14),
          border: InputBorder.none,
          counterStyle: TextStyle(fontSize: 10.5, color: _textMuted),
        ),
      ),
    );
  }

  /// Nút bấm: "Gửi yêu cầu trả phòng"
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _isSubmitting ? null : _guiYeuCauTraPhong,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _primary.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Gửi yêu cầu trả phòng',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Dòng thông tin phụ trợ dạng Label: Value (Cố định nhãn và co giãn nội dung để KHÔNG BAO GIỜ bị tràn màn hình)
  Widget _buildInfoRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
    Color? badgeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: _textMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: badgeColor != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    )
                  : Text(
                      value,
                      textAlign: TextAlign.end,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                        color: valueColor ?? _textDark,
                        height: 1.35,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

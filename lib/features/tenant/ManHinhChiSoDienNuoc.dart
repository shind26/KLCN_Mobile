import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nhatro_kieugiang/core/services/DichVuQuetDongHo.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ============================================================
// MODEL
// ============================================================
class ChiSoDienNuocModel {
  final String maPhong;
  final String tenPhong;
  final String kyThang; // "10/2024"
  final DateTime ngayChot;

  // Chỉ số điện
  final String maCongToDien;
  final double chiSoDienTruoc; // kWh
  final double chiSoDienMoi; // kWh – nhập
  final double donGiaDien; // VND/kWh

  // Chỉ số nước
  final String maDongHoNuoc;
  final double chiSoNuocTruoc; // m³
  final double chiSoNuocMoi; // m³ – nhập
  final double donGiaNuoc; // VND/m³

  ChiSoDienNuocModel({
    required this.maPhong,
    required this.tenPhong,
    required this.kyThang,
    required this.ngayChot,
    required this.maCongToDien,
    required this.chiSoDienTruoc,
    required this.chiSoDienMoi,
    required this.donGiaDien,
    required this.maDongHoNuoc,
    required this.chiSoNuocTruoc,
    required this.chiSoNuocMoi,
    required this.donGiaNuoc,
  });

  double get tieu_thu_dien =>
      (chiSoDienMoi - chiSoDienTruoc).clamp(0, double.infinity);
  double get tieu_thu_nuoc =>
      (chiSoNuocMoi - chiSoNuocTruoc).clamp(0, double.infinity);
  double get thanh_tien_dien => tieu_thu_dien * donGiaDien;
  double get thanh_tien_nuoc => tieu_thu_nuoc * donGiaNuoc;
  double get tong_tien => thanh_tien_dien + thanh_tien_nuoc;
}

// ============================================================
// SCREEN CHÍNH: 3 bước
// ============================================================
class MeterReadingScreen extends StatefulWidget {
  final String maPhong;
  final String tenPhong;
  final String kyThang;
  final String maHopDong;

  const MeterReadingScreen({
    super.key,
    this.maPhong = 'P302',
    this.tenPhong = 'Phòng 302',
    this.kyThang = '10/2026',
    this.maHopDong = 'HD001',
  });

  @override
  State<MeterReadingScreen> createState() => _MeterReadingScreenState();
}

class _MeterReadingScreenState extends State<MeterReadingScreen>
    with TickerProviderStateMixin {
  // Bước hiện tại: 0 = nhập, 1 = xác nhận, 2 = thành công
  int _step = 0;

  // Controllers
  final _dienController = TextEditingController();
  final _nuocController = TextEditingController();

  // Bảng bytes ảnh (cross-platform: web + mobile)
  Uint8List? _bytesDien;
  Uint8List? _bytesNuoc;

  // Trạng thái quét AI OCR
  bool _isScanningDien = false;
  bool _isScanningNuoc = false;
  String? _thongBaoQuetDien;
  String? _thongBaoQuetNuoc;

  // Dữ liệu tải từ Supabase
  bool _isLoading = true;
  double _chiSoDienTruoc = 210.0;
  double _chiSoNuocTruoc = 36.0;
  double _donGiaDien = 3500;
  double _donGiaNuoc = 4000;
  String _maCongTo = '#CTO-P302';
  String _maDongHo = '#DHN-P302';

  // Trạng thái đơn chốt số kỳ này (mỗi tháng chỉ gửi 1 đơn từ ngày 28)
  Map<String, dynamic>? _daGuiDonKyNay;
  String? _urlAnhDienDaGui;
  String? _urlAnhNuocDaGui;

  // Animation
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  late AnimationController _successController;
  late Animation<double> _successScale;

  // Giờ gửi
  String _thoiGianGui = '';

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _successController, curve: Curves.elasticOut),
    );
    _slideController.forward();
    _loadFromSupabase();
  }

  @override
  void dispose() {
    _dienController.dispose();
    _nuocController.dispose();
    _slideController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _loadFromSupabase() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = Supabase.instance.client;

      // 1. Tải đơn giá dịch vụ điện & nước
      try {
        final dvRows = await db
            .from('dich_vu')
            .select('ma_dich_vu, don_gia')
            .inFilter('ma_dich_vu', ['DV_DIEN', 'DV_NUOC']);

        for (final r in (dvRows as List)) {
          final code = r['ma_dich_vu']?.toString();
          final price = double.tryParse(r['don_gia']?.toString() ?? '');
          if (price != null) {
            if (code == 'DV_DIEN') _donGiaDien = price;
            if (code == 'DV_NUOC') _donGiaNuoc = price;
          }
        }
      } catch (e) {
        debugPrint('Lỗi tải đơn giá dịch vụ: $e');
      }

      final cleanHd = (widget.maHopDong.trim().isEmpty ? 'HD001' : widget.maHopDong).replaceAll(' ', '');
      final now = DateTime.now();
      final thang = now.month.toString().padLeft(2, '0');
      final nam = now.year.toString();
      final thangNam = '$thang/$nam';
      final cleanPhong = widget.maPhong.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final pPart = cleanPhong.length > 5 ? cleanPhong.substring(cleanPhong.length - 5) : cleanPhong;
      final maKyPhong = 'KY${thang}_$pPart';
      final hdPart = cleanHd.length > 5 ? cleanHd.substring(cleanHd.length - 5) : cleanHd;
      final maKyHd = 'KY${thang}_$hdPart';

      // 1.1 Kiểm tra xem phòng này có phải là phòng mới sau khi chuyển phòng hay không
      DateTime? ngayChuyenPhong;
      try {
        final plList = await db
            .from('phu_luc_hop_dong')
            .select()
            .eq('ma_hop_dong', cleanHd)
            .order('ngay_lap', ascending: false);
        for (final pl in (plList as List)) {
          final pMoi = pl['ma_phong_moi']?.toString() ?? '';
          final code = pl['ma_phu_luc']?.toString() ?? '';
          if (pMoi.isNotEmpty || code.startsWith('PLCP')) {
            if (pMoi.trim().toLowerCase() == widget.maPhong.trim().toLowerCase() ||
                pMoi.replaceAll(RegExp(r'[^0-9]'), '') == widget.maPhong.replaceAll(RegExp(r'[^0-9]'), '')) {
              final nl = pl['ngay_lap']?.toString();
              if (nl != null && nl.isNotEmpty) {
                ngayChuyenPhong = DateTime.tryParse(nl);
              }
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Lỗi kiểm tra phụ lục chuyển phòng: $e');
      }

      // 2. Tải chỉ số từ bảng chi_so_dien_nuoc thực tế trên Supabase!
      try {
        final chiSoList = await db
            .from('chi_so_dien_nuoc')
            .select()
            .eq('ma_hop_dong', cleanHd)
            .order('ngay_ghi_nhan', ascending: false);

        final list = (chiSoList as List);

        // Kiểm tra xem kỳ tháng này đã gửi đơn chưa (chỉ cho gửi 1 đơn/tháng)
        Map<String, dynamic>? recordKyNay;
        for (final item in list) {
          final maKyItem = item['ma_ky']?.toString() ?? '';
          final thangNamItem = item['thang_nam']?.toString() ?? '';
          final ngayGhiNhanStr = item['ngay_ghi_nhan']?.toString() ?? '';
          DateTime? ngayGhiNhan;
          if (ngayGhiNhanStr.isNotEmpty) {
            ngayGhiNhan = DateTime.tryParse(ngayGhiNhanStr);
          }

          // Nếu phòng này là phòng mới chuyển đến:
          // Bản ghi cũ của phòng trước (không chứa mã phòng mới trong ma_ky hoặc ghi trước ngày chuyển)
          // KHÔNG ĐƯỢC tính là đơn đã nộp của phòng mới!
          if (ngayChuyenPhong != null) {
            final bool isFromThisRoom = maKyItem == maKyPhong || maKyItem.contains(pPart);
            if (!isFromThisRoom) {
              continue; // Bỏ qua bản ghi của phòng trước!
            }
          }

          final bool matchKy = maKyItem == maKyPhong ||
              maKyItem == maKyHd ||
              thangNamItem == thangNam ||
              (ngayGhiNhan != null &&
                  ngayGhiNhan.month == now.month &&
                  ngayGhiNhan.year == now.year);
          if (matchKy) {
            recordKyNay = Map<String, dynamic>.from(item);
            break;
          }
        }

        if (recordKyNay != null) {
          // Đã nộp đơn trong kỳ này -> Điền sẵn thông tin & lưu trạng thái đã gửi
          _daGuiDonKyNay = recordKyNay;
          final dienMoi = recordKyNay['chi_so_dien_moi'];
          final nuocMoi = recordKyNay['chi_so_nuoc_moi'];
          if (dienMoi != null) {
            final dVal = double.tryParse(dienMoi.toString());
            _dienController.text = dVal != null ? (dVal % 1 == 0 ? dVal.toInt().toString() : dVal.toString()) : dienMoi.toString();
          }
          if (nuocMoi != null) {
            final nVal = double.tryParse(nuocMoi.toString());
            _nuocController.text = nVal != null ? (nVal % 1 == 0 ? nVal.toInt().toString() : nVal.toString()) : nuocMoi.toString();
          }

          _chiSoDienTruoc = double.tryParse(recordKyNay['chi_so_dien_cu']?.toString() ?? '210') ?? 210.0;
          _chiSoNuocTruoc = double.tryParse(recordKyNay['chi_so_nuoc_cu']?.toString() ?? '36') ?? 36.0;

          _urlAnhDienDaGui = recordKyNay['anh_dien']?.toString();
          _urlAnhNuocDaGui = recordKyNay['anh_nuoc']?.toString();
        } else if (ngayChuyenPhong != null) {
          // Phòng mới chuyển đến chưa có dữ liệu chốt số -> khởi tạo mốc chỉ số đầu kỳ = 0
          _daGuiDonKyNay = null;
          _chiSoDienTruoc = 0.0;
          _chiSoNuocTruoc = 0.0;
          _dienController.clear();
          _nuocController.clear();
        } else if (list.isNotEmpty) {
          final latest = list.first;
          final dienMoiCu = double.tryParse(latest['chi_so_dien_moi']?.toString() ?? '');
          final nuocMoiCu = double.tryParse(latest['chi_so_nuoc_moi']?.toString() ?? '');

          // Chỉ số cũ tháng này = chỉ số mới đã chốt của tháng trước
          _chiSoDienTruoc = dienMoiCu ?? double.tryParse(latest['chi_so_dien_cu']?.toString() ?? '210') ?? 210.0;
          _chiSoNuocTruoc = nuocMoiCu ?? double.tryParse(latest['chi_so_nuoc_cu']?.toString() ?? '36') ?? 36.0;
        } else {
          // Lấy bản ghi mới nhất trong hệ thống làm mốc
          final allLatest = await db
              .from('chi_so_dien_nuoc')
              .select()
              .order('ngay_ghi_nhan', ascending: false)
              .limit(1);
          if ((allLatest as List).isNotEmpty) {
            final latest = allLatest.first;
            _chiSoDienTruoc = double.tryParse(latest['chi_so_dien_moi']?.toString() ?? '210') ?? 210.0;
            _chiSoNuocTruoc = double.tryParse(latest['chi_so_nuoc_moi']?.toString() ?? '36') ?? 36.0;
          }
        }
      } catch (e) {
        debugPrint('Lỗi tải bảng chi_so_dien_nuoc: $e');
        _chiSoDienTruoc = ngayChuyenPhong != null ? 0.0 : 210.0;
        _chiSoNuocTruoc = ngayChuyenPhong != null ? 0.0 : 36.0;
      }

      _maCongTo = '#CTO-${widget.maPhong}';
      _maDongHo = '#DHN-${widget.maPhong}';

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tổng thể _loadFromSupabase: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────
  double get _dienMoi =>
      double.tryParse(_dienController.text.replaceAll(',', '.')) ?? 0;
  double get _nuocMoi =>
      double.tryParse(_nuocController.text.replaceAll(',', '.')) ?? 0;



  ChiSoDienNuocModel get _model => ChiSoDienNuocModel(
    maPhong: widget.maPhong,
    tenPhong: widget.tenPhong,
    kyThang: widget.kyThang,
    ngayChot: DateTime.now(),
    maCongToDien: _maCongTo,
    chiSoDienTruoc: _chiSoDienTruoc,
    chiSoDienMoi: _dienMoi,
    donGiaDien: _donGiaDien,
    maDongHoNuoc: _maDongHo,
    chiSoNuocTruoc: _chiSoNuocTruoc,
    chiSoNuocMoi: _nuocMoi,
    donGiaNuoc: _donGiaNuoc,
  );

  String _formatCurrency(double v) {
    return '${v.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}đ';
  }

  // ── Ràng buộc thực tế ────────────────────────────────────
  bool get _dienOk =>
      _dienController.text.trim().isNotEmpty && _dienMoi >= _chiSoDienTruoc;
  bool get _nuocOk =>
      _nuocController.text.trim().isNotEmpty && _nuocMoi >= _chiSoNuocTruoc;

  bool get _canProceed {
    // 1. Phải nhập đủ cả 2 chỉ số
    if (_dienController.text.trim().isEmpty || _nuocController.text.trim().isEmpty) {
      return false;
    }
    // 2. Ràng buộc thực tế: Chỉ số mới phải lớn hơn hoặc bằng chỉ số cũ!
    if (!_dienOk || !_nuocOk) {
      return false;
    }
    // 3. Ràng buộc minh chứng: Phải có ảnh chụp công tơ cả điện và nước để đối soát
    if (_bytesDien == null || _bytesNuoc == null) {
      return false;
    }
    return true;
  }

  void _thongBaoDaGuiDon() {
    final now = DateTime.now();
    final int nextThang = now.month == 12 ? 1 : now.month + 1;
    final int nextNam = now.month == 12 ? now.year + 1 : now.year;

    String ngayGui = 'Kỳ này';
    if (_daGuiDonKyNay != null && _daGuiDonKyNay!['ngay_ghi_nhan'] != null) {
      final dt = DateTime.tryParse(_daGuiDonKyNay!['ngay_ghi_nhan'].toString());
      if (dt != null) {
        ngayGui =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} lúc ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    final trangThai = _daGuiDonKyNay?['trang_thai_duyet']?.toString() ?? 'Chờ duyệt';
    final isDaDuyet = trangThai == 'Đã duyệt';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Đã Gửi Chỉ Số Kỳ Này',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isDaDuyet ? Icons.check_circle_rounded : Icons.hourglass_top_rounded,
                    color: isDaDuyet ? const Color(0xFF16A34A) : const Color(0xFFD97706),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bạn đã gửi thành công chỉ số điện nước kỳ Tháng ${now.month}/${now.year}.\nTrạng thái: $trangThai',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: isDaDuyet ? const Color(0xFF166534) : const Color(0xFF92400E),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '• Thời gian gửi: $ngayGui\n'
              '• Số điện nộp: ${_daGuiDonKyNay?['chi_so_dien_moi'] ?? _dienController.text} kWh\n'
              '• Số nước nộp: ${_daGuiDonKyNay?['chi_so_nuoc_moi'] ?? _nuocController.text} m³\n\n'
              '⚠️ Quy định: Mỗi tháng hệ thống mở cổng từ ngày 28 và chỉ nhận 01 đơn chốt chỉ số duy nhất để Ban Quản Lý đối soát và lập hóa đơn.\n\n'
              '📅 Đợt chốt chỉ số tiếp theo sẽ mở vào ngày 28/$nextThang/$nextNam.',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.45),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF09638E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Đã hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _goToConfirm() {
    // 0. Nếu đã gửi đơn kỳ này rồi: Khóa gửi đơn tiếp
    if (_daGuiDonKyNay != null) {
      _thongBaoDaGuiDon();
      return;
    }

    final now = DateTime.now();
    // 1. RÀNG BUỘC: Qua ngày 28 mỗi tháng mới được mở cổng gửi chỉ số
    if (now.day < 28) {
      final daysLeft = 28 - now.day;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(Icons.calendar_month_rounded, color: Color(0xFFD97706), size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chốt Chỉ Số Ngày 28 Hàng Tháng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Hệ thống chốt chỉ số vào ngày 28 hàng tháng!',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Hôm nay là ngày ${now.day}/${now.month}/${now.year} (còn $daysLeft ngày nữa mới đến ngày 28).\n\nTheo quy định của Ban Quản Lý Kiêu Giang, chỉ số điện nước chốt số vào ngày 28 hàng tháng để đối soát lập hóa đơn. Vui lòng quay lại gửi chỉ số từ ngày 28 bạn nhé!',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.45),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Đã hiểu', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Khi đã đến ngày 28: Kiểm tra đầy đủ ảnh minh chứng và chỉ số
    if (!_canProceed) {
      _showError();
      return;
    }

    setState(() => _step = 1);
    _slideController.reset();
    _slideController.forward();
  }

  void _showError() {
    String msg = '';
    if (_bytesDien == null || _bytesNuoc == null) {
      msg = 'Vui lòng chụp ảnh minh chứng cả Công tơ Điện và Đồng hồ Nước để đối soát.';
    } else if (_dienController.text.isEmpty || _nuocController.text.isEmpty) {
      msg = 'Vui lòng nhập hoặc chụp ảnh để quét đủ chỉ số điện và nước.';
    } else if (_dienMoi < _chiSoDienTruoc) {
      msg = 'Chỉ số điện mới ($_dienMoi kWh) phải ≥ chỉ số cũ ($_chiSoDienTruoc kWh).';
    } else if (_nuocMoi < _chiSoNuocTruoc) {
      msg = 'Chỉ số nước mới ($_nuocMoi m³) phải ≥ chỉ số cũ ($_chiSoNuocTruoc m³).';
    }
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Kiểm tra chỉ số',
      noiDung: msg,
      type: ThongBaoType.canhBao,
    );
  }

  // ── LƯU THỰC TẾ VÀO SUPABASE BẢNG chi_so_dien_nuoc ─────────
  Future<void> _submitReading() async {
    final now = DateTime.now();
    _thoiGianGui =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    try {
      final db = Supabase.instance.client;
      final thang = now.month.toString().padLeft(2, '0');
      final nam = now.year.toString();
      final thangNam = '$thang/$nam';

      final cleanHd = (widget.maHopDong.trim().isEmpty ? 'HD001' : widget.maHopDong)
          .replaceAll(' ', '');
      final cleanPhong = widget.maPhong.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final pPart = cleanPhong.length > 5
          ? cleanPhong.substring(cleanPhong.length - 5)
          : cleanPhong;
      // Bảng chi_so_dien_nuoc có cột ma_ky là VARCHAR(10)
      // Định dạng ưu tiên theo phòng: KY + Tháng (2 số) + _ + mã phòng (ví dụ: KY10_P105, đúng 9 ký tự)
      String maKy = 'KY${thang}_$pPart';
      if (maKy.length > 10) {
        maKy = maKy.substring(0, 10);
      }

      // ── XỬ LÝ LƯU ẢNH MINH CHỨNG (STORAGE + BASE64 FALLBACK) ──
      String? urlAnhDien;
      String? urlAnhNuoc;

      if (_bytesDien != null) {
        try {
          final pathDien = 'meters/${maKy}_dien.jpg';
          await db.storage.from('contracts').uploadBinary(
            pathDien,
            _bytesDien!,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
          urlAnhDien = db.storage.from('contracts').getPublicUrl(pathDien);
          debugPrint('[METER] Upload ảnh điện vào Storage thành công: $urlAnhDien');
        } catch (e) {
          debugPrint('[METER] Storage upload điện notice: $e (Lưu fallback Base64)');
          urlAnhDien = 'data:image/jpeg;base64,${base64Encode(_bytesDien!)}';
        }
      }

      if (_bytesNuoc != null) {
        try {
          final pathNuoc = 'meters/${maKy}_nuoc.jpg';
          await db.storage.from('contracts').uploadBinary(
            pathNuoc,
            _bytesNuoc!,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
          urlAnhNuoc = db.storage.from('contracts').getPublicUrl(pathNuoc);
          debugPrint('[METER] Upload ảnh nước vào Storage thành công: $urlAnhNuoc');
        } catch (e) {
          debugPrint('[METER] Storage upload nước notice: $e (Lưu fallback Base64)');
          urlAnhNuoc = 'data:image/jpeg;base64,${base64Encode(_bytesNuoc!)}';
        }
      }

      // Ghi nhận trực tiếp vào bảng chi_so_dien_nuoc bao gồm cả ảnh chụp minh chứng
      final upsertData = {
        'ma_ky': maKy,
        'thang_nam': thangNam,
        'chi_so_dien_cu': _chiSoDienTruoc,
        'chi_so_dien_moi': _dienMoi,
        'chi_so_nuoc_cu': _chiSoNuocTruoc,
        'chi_so_nuoc_moi': _nuocMoi,
        'ngay_ghi_nhan': now.toIso8601String(),
        'trang_thai_duyet': 'Chờ duyệt',
        'ma_hop_dong': cleanHd,
        if (urlAnhDien != null) 'anh_dien': urlAnhDien,
        if (urlAnhNuoc != null) 'anh_nuoc': urlAnhNuoc,
      };

      await db.from('chi_so_dien_nuoc').upsert(upsertData);

      // Cập nhật trạng thái đã nộp đơn kỳ này để khóa màn hình lập tức
      _daGuiDonKyNay = Map<String, dynamic>.from(upsertData);
      _urlAnhDienDaGui = urlAnhDien;
      _urlAnhNuocDaGui = urlAnhNuoc;

      debugPrint('[METER] Đã lưu thành công vào chi_so_dien_nuoc trên Supabase kèm ảnh: $maKy');

      if (!mounted) return;
      setState(() => _step = 2);
      _slideController.reset();
      _slideController.forward();
      await Future.delayed(const Duration(milliseconds: 200));
      _successController.forward();
    } catch (e) {
      debugPrint('Lỗi lưu chi_so_dien_nuoc vào Supabase: $e');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi gửi chỉ số',
          noiDung: 'Lỗi gửi chỉ số điện nước: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  // ── CHỌN NGUỒN ẢNH VÀ QUÉT TỰ ĐỘNG BẰNG AI ────────────────
  void _chonNguonAnhVaQuet(bool isDien) {
    if (_daGuiDonKyNay != null) {
      _thongBaoDaGuiDon();
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                'Chụp ảnh ${isDien ? 'Công tơ Điện' : 'Đồng hồ Nước'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'AI sẽ tự động nhận diện và trích xuất chỉ số mới',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF0284C7)),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF0284C7)),
                title: const Text('Chụp ảnh trực tiếp bằng Camera'),
                subtitle: const Text('Chụp rõ màn hình số, tránh lóa sáng', style: TextStyle(fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _chupHoacChonAnh(ImageSource.camera, isDien);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF0284C7)),
                title: const Text('Chọn ảnh từ Thư viện (Bộ sưu tập)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _chupHoacChonAnh(ImageSource.gallery, isDien);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chupHoacChonAnh(ImageSource source, bool isDien) async {
    final picker = ImagePicker();
    try {
      final img = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (img == null || !mounted) return;

      final bytes = await img.readAsBytes();
      setState(() {
        if (isDien) {
          _bytesDien = bytes;
          _isScanningDien = true;
          _thongBaoQuetDien = null;
        } else {
          _bytesNuoc = bytes;
          _isScanningNuoc = true;
          _thongBaoQuetNuoc = null;
        }
      });

      // ── AI OCR TỰ ĐỘNG QUÉT CHỈ SỐ MỚI ──
      final ketQua = await DichVuQuetDongHo.quetChiSoDongHoBytes(
        bytes,
        isDien: isDien,
        chiSoCu: isDien ? _chiSoDienTruoc : _chiSoNuocTruoc,
      );

      if (!mounted) return;

      setState(() {
        if (isDien) {
          _isScanningDien = false;
        } else {
          _isScanningNuoc = false;
        }
      });

      if (ketQua.thanhCong && ketQua.chiSo != null) {
        // OCR thành công → điền số và hiện popup kết quả (KHÔNG hiện toast cảnh báo)
        final soQuet = ketQua.chiSo!;
        setState(() {
          final hienThiStr = (soQuet % 1 == 0 ? soQuet.toInt().toString() : soQuet.toStringAsFixed(1));
          if (isDien) {
            _dienController.text = hienThiStr;
            _thongBaoQuetDien = 'AI quét: $hienThiStr kWh (chạm để chỉnh)';
          } else {
            _nuocController.text = hienThiStr;
            _thongBaoQuetNuoc = 'AI quét: $hienThiStr m³ (chạm để chỉnh)';
          }
        });

        // Chỉ bật popup kết quả thành công
        _hienThiPopupQuetDongHoThanhCong(isDien, soQuet);
      } else {
        // OCR thất bại → mới hiện toast cảnh báo để người dùng biết cần chụp lại
        if (mounted) {
          ThongBaoHelper.hienToast(
            context,
            tieuDe: 'Chưa đọc rõ chỉ số',
            noiDung: ketQua.thongDiep ??
                'Chưa đọc rõ chỉ số trên ảnh. Vui lòng chụp lại gần hơn hoặc nhập tay nhé!',
            type: ThongBaoType.canhBao,
            duration: const Duration(seconds: 3),
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi chọn/chụp ảnh: $e');
      if (mounted) {
        setState(() {
          _isScanningDien = false;
          _isScanningNuoc = false;
        });
      }
    }
  }

  // ── POPUP DIALOG Ở GIỮA MÀN HÌNH KHI QUÉT XONG ─────────────
  void _hienThiPopupQuetDongHoThanhCong(bool isDien, double soQuet) {
    final chiSoCu = isDien ? _chiSoDienTruoc : _chiSoNuocTruoc;
    final donVi = isDien ? 'kWh' : 'm³';
    final donGia = isDien ? _donGiaDien : _donGiaNuoc;
    final tieuThu = (soQuet - chiSoCu).clamp(0, double.infinity);
    final thanhTien = tieuThu * donGia;

    final soQuetStr = (soQuet % 1 == 0 ? soQuet.toInt().toString() : soQuet.toStringAsFixed(1));
    final chiSoCuStr = (chiSoCu % 1 == 0 ? chiSoCu.toInt().toString() : chiSoCu.toStringAsFixed(1));
    final tieuThuStr = (tieuThu % 1 == 0 ? tieuThu.toInt().toString() : tieuThu.toStringAsFixed(1));

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: Colors.white,
        elevation: 8,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDien ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDien ? const Color(0xFFFCD34D) : const Color(0xFF93C5FD),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isDien ? Icons.bolt_rounded : Icons.water_drop_rounded,
                    color: isDien ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quét Chỉ Số ${isDien ? 'Điện' : 'Nước'} Thành Công!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'AI đã tự động nhận diện chỉ số mới và tính lượng tiêu thụ:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _modalRow('Chỉ số cũ:', '$chiSoCuStr $donVi'),
                      const SizedBox(height: 6),
                      _modalRow(
                        'Chỉ số mới (AI quét):',
                        '$soQuetStr $donVi',
                        isBold: true,
                        color: isDien ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),
                      _modalRow('Tiêu thụ kỳ này:', '$tieuThuStr $donVi'),
                      const SizedBox(height: 6),
                      _modalRow(
                        'Thành tiền tạm tính:',
                        _formatCurrency(thanhTien),
                        isBold: true,
                        color: const Color(0xFF16A34A),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFF64748B)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mẹo: Nếu bánh xe số đang quay dở giữa chừng, bạn có thể chạm vào ô số mới để chỉnh lại cho chuẩn xác.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09638E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Xác nhận & Điền chỉ số',
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

  Widget _modalRow(String label, String value, {bool isBold = false, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FB),
      body: SafeArea(
        child: _isLoading
            ? const LoadingMeoMeo(
                message: 'Đang tải chỉ số điện nước...',
                subMessage: 'Đợi mèo con kiểm tra công tơ xíu nha~ 🐾',
              )
            : SlideTransition(
                position: _slideAnimation,
                child: _buildCurrentStep(),
              ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _buildStep0Input();
      case 1:
        return _buildStep1Confirm();
      case 2:
        return _buildStep2Success();
      default:
        return _buildStep0Input();
    }
  }

  // ============================================================
  // BƯỚC 0: NHẬP CHỈ SỐ
  // ============================================================
  Widget _buildStep0Input() {
    return Column(
      children: [
        _buildAppBar('Chỉ số điện nước', step: 1, total: 3),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner thông tin kỳ chốt số
                _buildKyBanner(),
                const SizedBox(height: 16),

                // Công tơ điện
                _buildMeterCard(
                  isDien: true,
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFFD97706),
                  bgColor: const Color(0xFFFEF3C7),
                  title: 'Công tơ Điện',
                  maMay: _maCongTo,
                  chiSoTruoc: _chiSoDienTruoc,
                  donVi: 'kWh',
                  controller: _dienController,
                  imageBytes: _bytesDien,
                  urlAnhDaLuu: _urlAnhDienDaGui,
                  isScanning: _isScanningDien,
                  thongBaoQuet: _thongBaoQuetDien,
                ),
                const SizedBox(height: 16),

                // Đồng hồ nước
                _buildMeterCard(
                  isDien: false,
                  icon: Icons.water_drop_rounded,
                  color: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFDBEAFE),
                  title: 'Đồng hồ Nước',
                  maMay: _maDongHo,
                  chiSoTruoc: _chiSoNuocTruoc,
                  donVi: 'm³',
                  controller: _nuocController,
                  imageBytes: _bytesNuoc,
                  urlAnhDaLuu: _urlAnhNuocDaGui,
                  isScanning: _isScanningNuoc,
                  thongBaoQuet: _thongBaoQuetNuoc,
                ),
                const SizedBox(height: 16),

                // Tổng tạm tính
                _buildTotalCard(),
                const SizedBox(height: 16),

                // Lưu ý
                _buildNoteCard(),
                const SizedBox(height: 24),

                // Nút tiếp theo
                Builder(
                  builder: (context) {
                    final isSent = _daGuiDonKyNay != null;
                    final isAfter28 = DateTime.now().day >= 28;
                    final nextMonth = DateTime.now().month == 12 ? 1 : DateTime.now().month + 1;
                    final daysLeft = 28 - DateTime.now().day;

                    return _buildPrimaryButton(
                      label: isSent
                          ? 'Đã gửi chỉ số Tháng ${DateTime.now().month} (Mở lại 28/$nextMonth)'
                          : (isAfter28
                              ? 'Xác nhận & Gửi chỉ số cho Quản lý'
                              : 'Chốt số ngày 28 hàng tháng (còn $daysLeft ngày)'),
                      icon: isSent
                          ? Icons.check_circle_rounded
                          : (isAfter28 ? Icons.send_rounded : Icons.lock_clock_rounded),
                      gradientColors: isSent
                          ? const [Color(0xFF64748B), Color(0xFF475569)]
                          : (!isAfter28
                              ? const [Color(0xFFD97706), Color(0xFFB45309)]
                              : null),
                      onTap: _goToConfirm,
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildKyBanner() {
    final now = DateTime.now();
    final isSent = _daGuiDonKyNay != null;
    final isOpen = now.day >= 28;
    final int thang = now.month;
    final int nam = now.year;
    final int nextThang = thang == 12 ? 1 : thang + 1;
    final daysLeft = 28 - now.day;

    // Màu theo trạng thái
    final Color accentColor = isSent
        ? const Color(0xFF09638E)
        : (isOpen ? const Color(0xFF16A34A) : const Color(0xFFD97706));
    final Color bgColor = isSent
        ? const Color(0xFFF0F9FF)
        : (isOpen ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB));
    final Color borderColor = isSent
        ? const Color(0xFFBAE6FD)
        : (isOpen ? const Color(0xFFBBF7D0) : const Color(0xFFFDE68A));
    final IconData statusIcon = isSent
        ? Icons.task_alt_rounded
        : (isOpen ? Icons.bolt_rounded : Icons.schedule_rounded);

    final String kyLabel = 'Tháng $thang/$nam';
    final String subLabel = isSent
        ? 'Mở đợt kế tiếp ngày 28/$nextThang'
        : (isOpen
            ? 'Đang trong đợt chốt số'
            : 'Còn $daysLeft ngày nữa mở đợt');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          // Icon trạng thái
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, size: 18, color: accentColor),
          ),
          const SizedBox(width: 12),
          // Text trạng thái
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Text(
                      isSent ? 'Đã chốt chỉ số' : 'Chốt chỉ số',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        kyLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                    if (isSent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '✓ ĐÃ NỘP',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: accentColor.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Badge phòng
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 105),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                widget.tenPhong,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMeterImageWidget({
    Uint8List? imageBytes,
    String? imageUrlOrBase64,
    BoxFit fit = BoxFit.cover,
  }) {
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return Image.memory(
        imageBytes,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildBrokenImagePlaceholder(),
      );
    }

    if (imageUrlOrBase64 == null || imageUrlOrBase64.trim().isEmpty) {
      return _buildBrokenImagePlaceholder();
    }

    final clean = imageUrlOrBase64.trim();

    // 1. Chuỗi Data URI Base64 (ví dụ: data:image/jpeg;base64,...)
    if (clean.startsWith('data:image')) {
      try {
        final b64 = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (_, __, ___) => _buildBrokenImagePlaceholder(),
        );
      } catch (e) {
        debugPrint('Lỗi decode base64 data:image: $e');
        return _buildBrokenImagePlaceholder();
      }
    }

    // 2. Đường dẫn mạng HTTP / HTTPS
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return Image.network(
        clean,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: const Color(0xFFF1F5F9),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildBrokenImagePlaceholder(),
      );
    }

    // 3. Chuỗi Base64 thô (không có tiền tố data:image)
    try {
      final bytes = base64Decode(clean.replaceAll(RegExp(r'\s+'), ''));
      return Image.memory(
        bytes,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildBrokenImagePlaceholder(),
      );
    } catch (_) {
      return _buildBrokenImagePlaceholder();
    }
  }

  Widget _buildBrokenImagePlaceholder() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 28),
      ),
    );
  }

  void _showZoomImageDialog({
    required String title,
    Uint8List? imageBytes,
    String? imageUrlOrBase64,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                color: Colors.black,
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: _buildMeterImageWidget(
                    imageBytes: imageBytes,
                    imageUrlOrBase64: imageUrlOrBase64,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockedCardContent({
    required bool isDien,
    required String maMay,
    required Color color,
    required String donVi,
    required double chiSoTruoc,
    required double val,
    required double diff,
    required bool hasImage,
    required Uint8List? imageBytes,
    required String? urlAnhDaLuu,
  }) {
    final donGia = isDien ? _donGiaDien : _donGiaNuoc;
    final thanhTien = diff * donGia;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ảnh chụp công tơ đã chốt (nếu có)
        if (hasImage) ...[
          GestureDetector(
            onTap: () {
              _showZoomImageDialog(
                title: isDien ? 'Ảnh Công tơ Điện ($maMay)' : 'Ảnh Đồng hồ Nước ($maMay)',
                imageBytes: imageBytes,
                imageUrlOrBase64: urlAnhDaLuu,
              );
            },
            child: Container(
              width: double.infinity,
              height: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildMeterImageWidget(
                    imageBytes: imageBytes,
                    imageUrlOrBase64: urlAnhDaLuu,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.zoom_in_rounded, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Chạm xem ảnh lớn',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Bảng số liệu đối soát điện nước
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chỉ số cũ',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${chiSoTruoc.toStringAsFixed(chiSoTruoc % 1 == 0 ? 0 : 1)} $donVi',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          'Chỉ số mới (đã chốt)',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${val.toStringAsFixed(val % 1 == 0 ? 0 : 1)} $donVi',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Tiêu thụ',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '+${diff.toStringAsFixed(diff % 1 == 0 ? 0 : 1)} $donVi',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFE2E8F0)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đơn giá: ${_formatCurrency(donGia)}/$donVi',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  Row(
                    children: [
                      const Text(
                        'Thành tiền: ',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      Text(
                        _formatCurrency(thanhTien),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.lock_outline_rounded, size: 13, color: Color(0xFF94A3B8)),
            const SizedBox(width: 5),
            const Expanded(
              child: Text(
                'Đã nộp chỉ số kỳ này • Mở đợt chốt tiếp theo vào ngày 28 hàng tháng',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMeterCard({
    required bool isDien,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String title,
    required String maMay,
    required double chiSoTruoc,
    required String donVi,
    required TextEditingController controller,
    required Uint8List? imageBytes,
    String? urlAnhDaLuu,
    required bool isScanning,
    required String? thongBaoQuet,
  }) {
    final isDaGui = _daGuiDonKyNay != null;
    final hasImage = imageBytes != null || (urlAnhDaLuu != null && urlAnhDaLuu.isNotEmpty);
    final val = double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;
    final hasInput = controller.text.trim().isNotEmpty;
    final diff = val - chiSoTruoc;
    final isNegative = hasInput && diff < 0;
    final isAbnormal = hasInput && !isNegative && diff > (isDien ? 500 : 50);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isNegative
              ? const Color(0xFFFCA5A5)
              : (hasImage ? color.withValues(alpha: 0.3) : const Color(0xFFE2E8F0)),
          width: isNegative ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Mã công tơ: $maMay',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              if (thongBaoQuet != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.auto_awesome, color: Color(0xFF16A34A), size: 13),
                      SizedBox(width: 4),
                      Text(
                        'AI đã quét',
                        style: TextStyle(
                          color: Color(0xFF15803D),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (isDaGui)
            _buildLockedCardContent(
              isDien: isDien,
              maMay: maMay,
              color: color,
              donVi: donVi,
              chiSoTruoc: chiSoTruoc,
              val: val,
              diff: diff,
              hasImage: hasImage,
              imageBytes: imageBytes,
              urlAnhDaLuu: urlAnhDaLuu,
            )
          else ...[
            // Ảnh chụp công tơ & AI Scanner
            GestureDetector(
            onTap: () {
              if (hasImage) {
                _showZoomImageDialog(
                  title: isDien ? 'Ảnh Công tơ Điện ($maMay)' : 'Ảnh Đồng hồ Nước ($maMay)',
                  imageBytes: imageBytes,
                  imageUrlOrBase64: urlAnhDaLuu,
                );
              } else {
                _chonNguonAnhVaQuet(isDien);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: double.infinity,
              height: 125,
              decoration: BoxDecoration(
                color: hasImage ? Colors.black : bgColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isScanning
                      ? color
                      : (hasImage ? color.withValues(alpha: 0.6) : const Color(0xFFCBD5E1)),
                  width: isScanning ? 2 : 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    _buildMeterImageWidget(
                      imageBytes: imageBytes,
                      imageUrlOrBase64: urlAnhDaLuu,
                    )
                  else
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.15),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.camera_alt_rounded,
                            color: color,
                            size: 26,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Chụp trực tiếp để AI tự quét số',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Tự động nhận diện chỉ số mới & tính tiền',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                  // Overlay khi đang quét AI
                  if (isScanning)
                    Container(
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'AI đang quét số công tơ...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Đang trích xuất chỉ số $donVi',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Badge gợi ý chạm phóng to ảnh
                  if (hasImage && !isScanning)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white30, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.zoom_in_rounded, color: Colors.white, size: 13),
                            SizedBox(width: 4),
                            Text(
                              'Chạm xem ảnh lớn',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (hasImage && !isScanning) ...[
            const SizedBox(height: 6),
            if (isDaGui)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.lock_rounded, size: 14, color: Color(0xFF16A34A)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Đã nộp chỉ số kỳ này (Đã khóa, mở đợt mới ngày 28 tháng sau)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  if (thongBaoQuet != null)
                    Expanded(
                      child: Text(
                        thongBaoQuet,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _chonNguonAnhVaQuet(isDien),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 14, color: color),
                        const SizedBox(width: 4),
                        Text(
                          'Chụp lại ảnh khác',
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],

          const SizedBox(height: 14),

          // Hàng chỉ số cũ / mới
          Row(
            children: [
              // Chỉ số cũ (tháng trước)
              Expanded(
                child: Container(
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
                        'Số cũ tháng trước',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chiSoTruoc.toStringAsFixed(chiSoTruoc % 1 == 0 ? 0 : 1),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        donVi,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: color.withValues(alpha: 0.6),
                  size: 20,
                ),
              ),
              // Chỉ số mới (AI tự điền hoặc chỉnh tay)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isNegative
                        ? const Color(0xFFFEF2F2)
                        : bgColor.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isNegative
                          ? const Color(0xFFEF4444)
                          : (controller.text.isNotEmpty
                              ? color.withValues(alpha: 0.7)
                              : const Color(0xFFE2E8F0)),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Số mới kỳ này',
                            style: TextStyle(
                              fontSize: 11,
                              color: isNegative ? const Color(0xFFDC2626) : color.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        controller: controller,
                        readOnly: isDaGui,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '0',
                          hintStyle: TextStyle(
                            fontSize: 20,
                            color: color.withValues(alpha: 0.3),
                            fontWeight: FontWeight.bold,
                          ),
                          suffixIcon: isDaGui
                              ? const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.lock_rounded, size: 16, color: Color(0xFF64748B)),
                                )
                              : null,
                          suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          suffixText: donVi,
                          suffixStyle: TextStyle(
                            fontSize: 11,
                            color: color.withValues(alpha: 0.7),
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isNegative ? const Color(0xFFDC2626) : color,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── RÀNG BUỘC THỰC TẾ & BÁO LỖI / TIÊU THỤ ────────
          if (hasInput) ...[
            const SizedBox(height: 10),
            if (isNegative)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ràng buộc: Số mới ($val $donVi) không thể nhỏ hơn số cũ ($chiSoTruoc $donVi)!',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB91C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _buildConsumptionChip(
                isDien: isDien,
                color: color,
                bgColor: bgColor,
                donVi: donVi,
                tieu_thu: diff,
                thanh_tien: diff * (isDien ? _donGiaDien : _donGiaNuoc),
              ),
              if (isAbnormal)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Tiêu thụ tăng cao (${diff.toStringAsFixed(1)} $donVi). Hệ thống sẽ lưu kèm ảnh đối soát!',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],

          if (!hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: color.withValues(alpha: 0.8)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Cần chụp ảnh công tơ làm minh chứng đối soát hợp lệ.',
                      style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.9),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConsumptionChip({
    required bool isDien,
    required Color color,
    required Color bgColor,
    required String donVi,
    required double tieu_thu,
    required double thanh_tien,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tiêu thụ: ${tieu_thu.toStringAsFixed(tieu_thu % 1 == 0 ? 0 : 1)} $donVi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Text(
            '→ ${_formatCurrency(thanh_tien)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalCard() {
    final canShow =
        _dienController.text.isNotEmpty &&
        _nuocController.text.isNotEmpty &&
        _dienMoi >= _chiSoDienTruoc &&
        _nuocMoi >= _chiSoNuocTruoc;

    if (!canShow) return const SizedBox.shrink();

    final m = _model;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF07516E), Color(0xFF0A8FCA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF09638E).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.calculate_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                'TỔNG TIỀN ĐIỆN NƯỚC KỲ NÀY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              Spacer(),
              Text(
                'Tạm tính',
                style: TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatCurrency(m.tong_tien),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _totalItem(
                  icon: Icons.bolt_rounded,
                  label: '${m.tieu_thu_dien.toStringAsFixed(m.tieu_thu_dien % 1 == 0 ? 0 : 1)} kWh × ${_formatCurrency(_donGiaDien)}',
                  value: _formatCurrency(m.thanh_tien_dien),
                ),
              ),
              Container(
                height: 32,
                width: 1,
                color: Colors.white24,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              Expanded(
                child: _totalItem(
                  icon: Icons.water_drop_rounded,
                  label: '${m.tieu_thu_nuoc.toStringAsFixed(m.tieu_thu_nuoc % 1 == 0 ? 0 : 1)} m³ × ${_formatCurrency(_donGiaNuoc)}',
                  value: _formatCurrency(m.thanh_tien_nuoc),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 13),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFED7AA).withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Chỉ số bạn gửi sẽ được Ban Quản lý Kiêu Giang soát xét, đối chiếu và chốt hóa đơn chính thức. '
              'Dữ liệu lưu kèm ảnh chụp và thời gian gửi để minh bạch.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF92400E),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BƯỚC 1: XÁC NHẬN
  // ============================================================
  Widget _buildStep1Confirm() {
    final m = _model;
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        _buildAppBar('Xác nhận chỉ số', step: 2, total: 3),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.tenPhong,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                color: Colors.white70,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đã gửi lúc: $timeStr',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Xác Nhận Chỉ Số',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Kỳ thanh toán ${widget.kyThang}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Hai ảnh xem trước
                Row(
                  children: [
                    Expanded(
                      child: _buildImagePreviewCard(
                        isDien: true,
                        imageBytes: _bytesDien,
                        imageUrlOrBase64: _urlAnhDienDaGui,
                        chiSo: m.chiSoDienMoi,
                        chiSoTruoc: m.chiSoDienTruoc,
                        donVi: 'kWh',
                        icon: Icons.bolt_rounded,
                        color: const Color(0xFFD97706),
                        bgColor: const Color(0xFFFEF3C7),
                        dateStr: dateStr,
                        timeStr: timeStr,
                        ma: _maCongTo,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildImagePreviewCard(
                        isDien: false,
                        imageBytes: _bytesNuoc,
                        imageUrlOrBase64: _urlAnhNuocDaGui,
                        chiSo: m.chiSoNuocMoi,
                        chiSoTruoc: m.chiSoNuocTruoc,
                        donVi: 'm³',
                        icon: Icons.water_drop_rounded,
                        color: const Color(0xFF2563EB),
                        bgColor: const Color(0xFFDBEAFE),
                        dateStr: dateStr,
                        timeStr: timeStr,
                        ma: _maDongHo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Tóm tắt chỉ số
                _buildSummaryCard(m, dateStr, timeStr),
                const SizedBox(height: 16),

                // Quy trình xử lý tiếp theo
                _buildNextStepsCard(),
                const SizedBox(height: 16),

                // Nút gửi
                _buildPrimaryButton(
                  label: 'Gửi chỉ số BQL đối soát & chốt số',
                  icon: Icons.verified_rounded,
                  onTap: _submitReading,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    setState(() => _step = 0);
                    _slideController.reset();
                    _slideController.forward();
                  },
                  child: const Text(
                    'Quay lại chỉnh sửa',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreviewCard({
    required bool isDien,
    required Uint8List? imageBytes,
    String? imageUrlOrBase64,
    required double chiSo,
    required double chiSoTruoc,
    required String donVi,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required String dateStr,
    required String timeStr,
    required String ma,
  }) {
    final tieuThu = (chiSo - chiSoTruoc).clamp(0.0, double.infinity);
    final hasImg = imageBytes != null || (imageUrlOrBase64 != null && imageUrlOrBase64.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isDien ? 'Công tơ Điện' : 'Đồng hồ Nước',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Ảnh hoặc placeholder
          GestureDetector(
            onTap: () {
              if (hasImg) {
                _showZoomImageDialog(
                  title: isDien ? 'Ảnh Công tơ Điện ($ma)' : 'Ảnh Đồng hồ Nước ($ma)',
                  imageBytes: imageBytes,
                  imageUrlOrBase64: imageUrlOrBase64,
                );
              }
            },
            child: Container(
              height: 80,
              width: double.infinity,
              decoration: BoxDecoration(
                color: bgColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImg
                  ? _buildMeterImageWidget(
                      imageBytes: imageBytes,
                      imageUrlOrBase64: imageUrlOrBase64,
                      fit: BoxFit.cover,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_rounded,
                          color: color.withValues(alpha: 0.5),
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Chưa có ảnh',
                          style: TextStyle(
                            fontSize: 10,
                            color: color.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),

          // Timestamp
          Text(
            'Ảnh chụp lúc $timeStr',
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 6),

          // Chỉ số cũ → mới
          _confirmIndexRow(
            label: 'Số cũ',
            value:
                '${chiSoTruoc.toStringAsFixed(chiSoTruoc % 1 == 0 ? 0 : 1)} $donVi',
            color: const Color(0xFF64748B),
          ),
          const SizedBox(height: 3),
          _confirmIndexRow(
            label: 'Số mới',
            value: '${chiSo.toStringAsFixed(chiSo % 1 == 0 ? 0 : 1)} $donVi',
            color: color,
            bold: true,
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'Tiêu thụ: ${tieuThu.toStringAsFixed(0)} $donVi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Mã lô: $ma',
            style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E1)),
          ),
        ],
      ),
    );
  }

  Widget _confirmIndexRow({
    required String label,
    required String value,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    ChiSoDienNuocModel m,
    String dateStr,
    String timeStr,
  ) {
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF09638E),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tóm tắt chỉ số vừa gửi',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$dateStr +',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Điện
          _buildSummaryRow(
            icon: Icons.bolt_rounded,
            iconBg: const Color(0xFFFEF3C7),
            iconColor: const Color(0xFFD97706),
            ma: 'Công tơ Điện ($_maCongTo)',
            chiSo:
                '${m.chiSoDienMoi.toStringAsFixed(0)} kWh  ←  ${m.chiSoDienTruoc.toStringAsFixed(0)}',
            tieu_thu: '${m.tieu_thu_dien.toStringAsFixed(0)} kWh',
            thanh_tien: _formatCurrency(m.thanh_tien_dien),
            timeStr: timeStr,
            color: const Color(0xFFD97706),
          ),
          const SizedBox(height: 10),

          // Nước
          _buildSummaryRow(
            icon: Icons.water_drop_rounded,
            iconBg: const Color(0xFFDBEAFE),
            iconColor: const Color(0xFF2563EB),
            ma: 'Đồng hồ Nước ($_maDongHo)',
            chiSo:
                '${m.chiSoNuocMoi.toStringAsFixed(0)} m³  ←  ${m.chiSoNuocTruoc.toStringAsFixed(0)}',
            tieu_thu: '${m.tieu_thu_nuoc.toStringAsFixed(0)} m³',
            thanh_tien: _formatCurrency(m.thanh_tien_nuoc),
            timeStr: timeStr,
            color: const Color(0xFF2563EB),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String ma,
    required String chiSo,
    required String tieu_thu,
    required String thanh_tien,
    required String timeStr,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ma,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 11,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Ảnh chụp lúc $timeStr',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chỉ số',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            chiSo,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Thành tiền',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        Text(
                          thanh_tien,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
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

  Widget _buildNextStepsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: Color(0xFF09638E), size: 18),
              SizedBox(width: 8),
              Text(
                'Quy trình xử lý tiếp theo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStep(1, 'Khách gửi ảnh & chỉ số thực tế', true),
          _buildStep(
            2,
            'BQL – Kiêu Giang đối soát ảnh chụp\nBan Quản Lý kiểm tra tính chính xác và phê duyệt chỉ số',
            false,
          ),
          _buildStep(
            3,
            'Phát hành Hóa đơn T10\nHóa đơn sẽ tự động hiện trong mục Hóa đơn và gửi qua Zalo/App.',
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int num, String text, bool done) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done ? const Color(0xFF09638E) : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    )
                  : Text(
                      '$num',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: done ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BƯỚC 2: THÀNH CÔNG
  // ============================================================
  Widget _buildStep2Success() {
    final m = _model;
    final now = DateTime.now();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final timeStr = _thoiGianGui.isNotEmpty
        ? _thoiGianGui
        : '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Column(
      children: [
        _buildAppBar('Xác nhận chỉ số', step: 3, total: 3, showBack: false),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Success header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0EA5E9), Color(0xFF0369A1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.tenPhong,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time_rounded,
                                color: Colors.white70,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Đã gửi lúc: $timeStr',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Success icon animation
                      ScaleTransition(
                        scale: _successScale,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_circle_rounded,
                            color: Color(0xFF0EA5E9),
                            size: 38,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Đã Gửi Chỉ Số Thành Công!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Chỉ số điện & nước tháng ${widget.kyThang} của ${widget.tenPhong}\n'
                        'đã được gửi đến Ban Quản Lý Kiêu Giang.\n'
                        'Vui lòng chờ BQL đối soát và chốt hóa đơn chính thức.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.manage_search_rounded, size: 16),
                        label: const Text('Đang chờ BQL đối soát & chốt số'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(
                              color: Colors.white38,
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tóm tắt chỉ số
                _buildSummaryCard(m, dateStr, timeStr),
                const SizedBox(height: 16),

                // Quy trình (bước 1 done, bước 2 & 3 pending)
                _buildNextStepsCardSuccess(),
                const SizedBox(height: 16),

                // Hotline
                // Hotline
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.headset_mic_rounded,
                        color: Color(0xFF09638E),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Cần hỗ trợ? Hotline Quản lý: 0000 123 456',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Quay về trang chủ
                _buildPrimaryButton(
                  label: 'Quay Về Trang Chủ',
                  icon: Icons.home_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNextStepsCardSuccess() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded, color: Color(0xFF09638E), size: 18),
              SizedBox(width: 8),
              Text(
                'Quy trình xử lý tiếp theo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStepSuccess(1, 'Khách gửi ảnh & chỉ số thực tế', true),
          _buildStepSuccess(
            2,
            'BQL – Kiêu Giang đối soát ảnh chụp\nBan Quản Lý kiểm tra tính chính xác và phê duyệt chỉ số',
            false,
            pending: true,
          ),
          _buildStepSuccess(
            3,
            'Phát hành Hóa đơn T10\nHóa đơn sẽ tự động hiện trong mục Hóa đơn và gửi qua Zalo/App.',
            false,
            pending: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepSuccess(
    int num,
    String text,
    bool done, {
    bool pending = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: done
                  ? const Color(0xFF09638E)
                  : pending
                  ? const Color(0xFFF0F9FF)
                  : const Color(0xFFE2E8F0),
              shape: BoxShape.circle,
              border: pending
                  ? Border.all(color: const Color(0xFF0284C7), width: 1.5)
                  : null,
            ),
            child: Center(
              child: done
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 13,
                    )
                  : Text(
                      '$num',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: pending
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF64748B),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: done ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHARED WIDGETS
  // ============================================================

  Widget _buildAppBar(
    String title, {
    required int step,
    required int total,
    bool showBack = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBack)
            GestureDetector(
              onTap: () {
                if (_step == 0) {
                  Navigator.pop(context);
                } else {
                  setState(() => _step = _step - 1);
                  _slideController.reset();
                  _slideController.forward();
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: Color(0xFF475569),
                ),
              ),
            )
          else
            const SizedBox(width: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Bước $step / $total',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: step / total,
                        backgroundColor: const Color(0xFFE2E8F0),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF0284C7),
                        ),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Kiêu Giang label
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kiêu Giang',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF09638E),
                  ),
                ),
                Text(
                  widget.tenPhong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    List<Color>? gradientColors,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors ?? const [Color(0xFF07516E), Color(0xFF0A8FCA)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: (gradientColors?.first ?? const Color(0xFF09638E)).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

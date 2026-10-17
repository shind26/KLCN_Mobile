import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhBienBanThanhLy.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToan.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  int _currentStep = 0; // 0: Thông tin trả phòng, 1: Chốt điện nước & Đối soát hoàn cọc, 2: Hoàn tất & Biên bản
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Dữ liệu hợp đồng
  late HopDongModel _hd;
  String _tenNguoiThue = 'Cư Dân Kiêu Giang';
  double _tienDatCoc = 3800000;

  // Ràng buộc công nợ & Hóa đơn chưa thanh toán
  List<HoaDonModel> _danhSachHoaDonNo = [];
  double _tongTienNoHoaDon = 0;
  bool _canTruNoVaoTienCoc = true; // Mặc định: Cho phép cấn trừ nợ cũ vào tiền cọc khi thanh lý

  // Bước 1: Thông tin trả phòng
  late DateTime _ngayTraPhong;
  String _lyDoTraPhong = 'Hết hạn hợp đồng thuê';
  final List<String> _danhSachLyDo = [
    'Hết hạn hợp đồng thuê',
    'Chuyển địa điểm làm việc / Học tập',
    'Thay đổi kế hoạch cá nhân / Về quê',
    'Cần tìm phòng diện tích khác',
    'Lý do khác',
  ];
  final TextEditingController _lyDoChiTietController = TextEditingController();
  final TextEditingController _soTaiKhoanController = TextEditingController();
  String _nganHangDuocChon = 'MB Bank (Quân Đội)';
  final List<String> _danhSachNganHang = [
    'MB Bank (Quân Đội)',
    'Vietcombank (Ngoại Thương)',
    'Techcombank (Kỹ Thương)',
    'VPBank (Việt Nam Thịnh Vượng)',
    'ACB (Á Châu)',
    'BIDV (Đầu Tư & Phát Triển)',
    'VietinBank (Công Thương)',
    'TPBank (Tiên Phong)',
    'Sacombank (Sài Gòn Thương Tín)',
    'HDBank (Phát Triển TP.HCM)',
    'VIB (Quốc Tế)',
    'SHB (Sài Gòn - Hà Nội)',
    'OCB (Phương Đông)',
    'MSB (Hàng Hải)',
    'Agribank (Nông Nghiệp & PTNT)',
  ];
  final TextEditingController _chuTaiKhoanController = TextEditingController();

  // Bước 2: Chốt điện nước & Tài chính
  double _chiSoDienDau = 0.0;
  double _chiSoNuocDau = 0.0;
  double _donGiaDien = 3500;
  double _donGiaNuoc = 20000;

  final TextEditingController _chiSoDienCuoiController = TextEditingController();
  final TextEditingController _chiSoNuocCuoiController = TextEditingController();
  final TextEditingController _phiPhatSinhController = TextEditingController(text: '0');
  final TextEditingController _ghiChuController = TextEditingController();

  // Danh mục kiểm kê thiết bị bàn giao phòng
  List<Map<String, dynamic>> _danhSachThietBi = [
    {
      'ten': 'Máy lạnh Inverter Daikin',
      'icon': Icons.ac_unit_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
    {
      'ten': 'Tủ lạnh riêng Aqua 140L',
      'icon': Icons.kitchen_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
    {
      'ten': 'Bình nóng lạnh Ariston 20L',
      'icon': Icons.water_drop_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
    {
      'ten': 'Giường gỗ sồi & Nệm cao su',
      'icon': Icons.bed_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
    {
      'ten': 'Điều khiển (Remote) các loại',
      'icon': Icons.settings_remote_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
    {
      'ten': 'Cửa phòng & Khóa thẻ từ / Chìa',
      'icon': Icons.key_rounded,
      'isDatChuan': true,
      'chiPhi': 0.0,
      'ghiChu': '',
    },
  ];

  double get _tongTienBoiThuongThietBi {
    double sum = 0;
    for (final item in _danhSachThietBi) {
      if (item['isDatChuan'] == false) {
        sum += (item['chiPhi'] as num? ?? 0).toDouble();
      }
    }
    return sum;
  }

  int get _soThietBiHuHong => _danhSachThietBi.where((t) => t['isDatChuan'] == false).length;

  IconData _getIconChoThietBi(String ten) {
    final lower = ten.toLowerCase();
    if (lower.contains('máy lạnh') || lower.contains('điều hòa')) return Icons.ac_unit_rounded;
    if (lower.contains('tủ lạnh')) return Icons.kitchen_rounded;
    if (lower.contains('nóng') || lower.contains('nước')) return Icons.water_drop_rounded;
    if (lower.contains('giường') || lower.contains('nệm')) return Icons.bed_rounded;
    if (lower.contains('remote') || lower.contains('điều khiển')) return Icons.settings_remote_rounded;
    if (lower.contains('khóa') || lower.contains('thẻ') || lower.contains('chìa')) return Icons.key_rounded;
    if (lower.contains('bàn') || lower.contains('ghế') || lower.contains('tủ áo')) return Icons.chair_rounded;
    return Icons.devices_other_rounded;
  }

  // Kết quả quyết toán
  double _chiSoDienCuoi = 235;
  double _chiSoNuocCuoi = 40;
  double _tienDienCuoi = 0;
  double _tienNuocCuoi = 0;
  double _phiPhatSinh = 0;
  double _tongKhauTru = 0;
  double _tienCocHoanLai = 0;
  double _tienKhTraThem = 0;

  BienBanThanhLyModel? _bienBanDaTao;

  /// Tiền cọc chỉ được hoàn trả khi hết hạn hợp đồng thuê. Các lý do khác không được hoàn trả.
  bool get _isHetHanHopDong => _lyDoTraPhong == 'Hết hạn hợp đồng thuê';

  @override
  void initState() {
    super.initState();
    // Quy chế BQL: Mặc định báo trước 15 ngày
    _ngayTraPhong = DateTime.now().add(const Duration(days: 15));
    _taiThongTinHopDong();
  }

  @override
  void dispose() {
    _lyDoChiTietController.dispose();
    _soTaiKhoanController.dispose();
    _chuTaiKhoanController.dispose();
    _chiSoDienCuoiController.dispose();
    _chiSoNuocCuoiController.dispose();
    _phiPhatSinhController.dispose();
    _ghiChuController.dispose();
    super.dispose();
  }

  Future<void> _taiThongTinHopDong() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final maHD = widget.hopDong?.maHopDong ?? 'HD001';

      // 1. Tải hợp đồng nếu chưa có
      if (widget.hopDong != null) {
        _hd = widget.hopDong!;
      } else {
        final hdRow = await db.from('hop_dong').select().eq('ma_hop_dong', maHD).maybeSingle();
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

      _tienDatCoc = _hd.tienDatCoc.toDouble();

      // 2. Lấy tên người đại diện hợp đồng
      if (widget.tenKhachThue != null && widget.tenKhachThue!.isNotEmpty) {
        _tenNguoiThue = widget.tenKhachThue!;
      } else if (_hd.maKhachDaiDien.isNotEmpty) {
        final kt = await db.from('khach_thue').select('ho_ten_khach').eq('ma_khach', _hd.maKhachDaiDien).maybeSingle();
        if (kt != null && kt['ho_ten_khach'] != null) {
          _tenNguoiThue = kt['ho_ten_khach'].toString();
        }
      }
      // Chủ tài khoản nhận cọc để trống theo yêu cầu người dùng tự nhập

      // 3. Kiểm tra xem hợp đồng đã có Biên bản thanh lý hoặc yêu cầu trước đó chưa
      final bbRows = await db.from('bien_ban_thanh_ly').select().eq('ma_hop_dong', _hd.maHopDong).maybeSingle();
      if (bbRows != null) {
        _bienBanDaTao = BienBanThanhLyModel.fromJson(Map<String, dynamic>.from(bbRows));
        final isChoDuyet = _bienBanDaTao!.ghiChu.contains('Chờ BQL duyệt') || _hd.trangThai == 'Chờ thanh lý';
        _currentStep = isChoDuyet ? 1 : 2;
      } else if (_hd.trangThai == 'Chờ thanh lý') {
        _currentStep = 1;
      } else {
        _currentStep = 0;
      }
      
      if (_currentStep < 2) {
        // 4. RÀNG BUỘC THỰC TẾ: Quét kiểm tra toàn bộ công nợ hóa đơn chưa thanh toán
        try {
          final unpaidRows = await db
              .from('hoa_don')
              .select()
              .eq('ma_hop_dong', _hd.maHopDong)
              .neq('trang_thai', 'Đã thanh toán')
              .neq('trang_thai', 'Đã hủy')
              .order('ngay_lap', ascending: false);

          if (unpaidRows.isNotEmpty) {
            _danhSachHoaDonNo = unpaidRows
                .map((r) => HoaDonModel.fromJson(Map<String, dynamic>.from(r)))
                .toList();
            _tongTienNoHoaDon = _danhSachHoaDonNo.fold(
              0.0,
              (sum, item) => sum + item.tongTien.toDouble(),
            );
          }
        } catch (e) {
          debugPrint('Lỗi quét hóa đơn nợ: $e');
        }

        // 5. Tải đơn giá dịch vụ điện & nước thực tế từ bảng dich_vu
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

        // 6. Tải chỉ số điện nước đã chốt gần nhất từ bảng chi_so_dien_nuoc làm chỉ số đầu kỳ
        try {
          final chiSoList = await db
              .from('chi_so_dien_nuoc')
              .select()
              .eq('ma_hop_dong', _hd.maHopDong)
              .order('ngay_ghi_nhan', ascending: false);

          if ((chiSoList as List).isNotEmpty) {
            final latest = chiSoList.first;
            final dienMoi = double.tryParse(latest['chi_so_dien_moi']?.toString() ?? '');
            final nuocMoi = double.tryParse(latest['chi_so_nuoc_moi']?.toString() ?? '');
            _chiSoDienDau = dienMoi ?? double.tryParse(latest['chi_so_dien_cu']?.toString() ?? '210') ?? 210.0;
            _chiSoNuocDau = nuocMoi ?? double.tryParse(latest['chi_so_nuoc_cu']?.toString() ?? '36') ?? 36.0;
          } else {
            // Nếu hợp đồng chưa từng chốt, lấy chỉ số chung của phòng
            final phongRow = await db
                .from('phong')
                .select('chi_so_dien, chi_so_nuoc')
                .eq('ma_phong', widget.maPhong)
                .maybeSingle();
            if (phongRow != null) {
              _chiSoDienDau = double.tryParse(phongRow['chi_so_dien']?.toString() ?? '210') ?? 210.0;
              _chiSoNuocDau = double.tryParse(phongRow['chi_so_nuoc']?.toString() ?? '36') ?? 36.0;
            }
          }
        } catch (e) {
          debugPrint('Lỗi tải bảng chi_so_dien_nuoc: $e');
          _chiSoDienDau = 210.0;
          _chiSoNuocDau = 36.0;
        }

        if (_chiSoDienCuoiController.text.isEmpty) {
          _chiSoDienCuoiController.text = _chiSoDienDau.toInt().toString();
        }
        if (_chiSoNuocCuoiController.text.isEmpty) {
          _chiSoNuocCuoiController.text = _chiSoNuocDau.toInt().toString();
        }

        // 7. Tải danh mục thiết bị từ bảng tai_san phòng
        try {
          final tsRows = await db
              .from('tai_san')
              .select()
              .eq('ma_phong', widget.maPhong);
          if ((tsRows as List).isNotEmpty) {
            _danhSachThietBi = (tsRows).map((ts) {
              final ten = ts['ten_tai_san']?.toString() ?? ts['ten']?.toString() ?? 'Thiết bị';
              return {
                'ten': ten,
                'icon': _getIconChoThietBi(ten),
                'isDatChuan': true,
                'chiPhi': 0.0,
                'ghiChu': '',
              };
            }).toList();
          }
        } catch (e) {
          debugPrint('Lỗi tải bảng tai_san: $e');
        }
      }

      _tinhToanQuyetToan();
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu chấm dứt hợp đồng: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _tinhToanQuyetToan() {
    _chiSoDienCuoi = double.tryParse(_chiSoDienCuoiController.text.trim()) ?? _chiSoDienDau;
    _chiSoNuocCuoi = double.tryParse(_chiSoNuocCuoiController.text.trim()) ?? _chiSoNuocDau;
    _phiPhatSinh = double.tryParse(_phiPhatSinhController.text.trim()) ?? 0;

    final double tieuThuDien = (_chiSoDienCuoi >= _chiSoDienDau) ? (_chiSoDienCuoi - _chiSoDienDau) : 0;
    final double tieuThuNuoc = (_chiSoNuocCuoi >= _chiSoNuocDau) ? (_chiSoNuocCuoi - _chiSoNuocDau) : 0;

    _tienDienCuoi = tieuThuDien * _donGiaDien;
    _tienNuocCuoi = tieuThuNuoc * _donGiaNuoc;

    final double phiKhac = double.tryParse(_phiPhatSinhController.text.trim()) ?? 0;
    _phiPhatSinh = _tongTienBoiThuongThietBi + phiKhac;

    // Tổng khấu trừ = Điện cuối + Nước cuối + Bồi thường thiết bị hư + Phí khác + (Công nợ hóa đơn cũ nếu cấn trừ)
    final double tienNoCanTru = (_canTruNoVaoTienCoc && _tongTienNoHoaDon > 0) ? _tongTienNoHoaDon : 0.0;
    _tongKhauTru = _tienDienCuoi + _tienNuocCuoi + _phiPhatSinh + tienNoCanTru;

    if (_isHetHanHopDong) {
      // HẾT HẠN HỢP ĐỒNG: ĐỦ ĐIỀU KIỆN HOÀN CỌC
      if (_tienDatCoc >= _tongKhauTru) {
        _tienCocHoanLai = _tienDatCoc - _tongKhauTru;
        _tienKhTraThem = 0;
      } else {
        _tienCocHoanLai = 0;
        _tienKhTraThem = _tongKhauTru - _tienDatCoc;
      }
    } else {
      // NHỮNG LÝ DO KHÁC: CHẤM DỨT TRƯỚC HẠN -> KHÔNG HOÀN TRẢ TIỀN CỌC
      _tienCocHoanLai = 0;
      _tienKhTraThem = _tongKhauTru;
    }
  }

  Future<void> _xacNhanThanhLyHopDong() async {
    if (_isHetHanHopDong && _tienCocHoanLai > 0 && _soTaiKhoanController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập Số tài khoản ngân hàng để nhận hoàn tiền cọc!')),
      );
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final ngayTraStr = '${_ngayTraPhong.year}-${_ngayTraPhong.month.toString().padLeft(2, '0')}-${_ngayTraPhong.day.toString().padLeft(2, '0')}';
      final maTL = 'TL${_hd.maHopDong.replaceAll(RegExp(r'[^0-9]'), '')}_${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      String ghiChuNoiDung = 'Lý do: $_lyDoTraPhong (${_isHetHanHopDong ? "Hết hạn HĐ - Đủ điều kiện hoàn cọc" : "Chấm dứt trước hạn - Không hoàn cọc"})';
      final int soTbTot = _danhSachThietBi.length - _soThietBiHuHong;
      ghiChuNoiDung += ' | Thiết bị: $soTbTot/${_danhSachThietBi.length} đạt chuẩn';
      if (_soThietBiHuHong > 0) {
        ghiChuNoiDung += ' (Bồi thường hư hại $_soThietBiHuHong món: ${FormatUtils.currency(_tongTienBoiThuongThietBi)})';
      }
      if (_lyDoChiTietController.text.trim().isNotEmpty) {
        ghiChuNoiDung += ' - ${_lyDoChiTietController.text.trim()}';
      }
      if (_soTaiKhoanController.text.trim().isNotEmpty) {
        final chuTk = _chuTaiKhoanController.text.trim().isNotEmpty ? _chuTaiKhoanController.text.trim() : _tenNguoiThue;
        ghiChuNoiDung += ' | Nhận cọc: ${_soTaiKhoanController.text.trim()} ($_nganHangDuocChon) - $chuTk';
      }
      if (_ghiChuController.text.trim().isNotEmpty) {
        ghiChuNoiDung += ' | ${_ghiChuController.text.trim()}';
      }

      final bbData = <String, dynamic>{
        'ma_thanh_ly': maTL,
        'ma_hop_dong': _hd.maHopDong,
        'ngay_tra_phong': ngayTraStr,
        'chi_so_dien_cuoi': _chiSoDienCuoi,
        'chi_so_nuoc_cuoi': _chiSoNuocCuoi,
        'tien_kh_tra_them': _tienKhTraThem,
        'tien_coc_hoan_lai': _tienCocHoanLai,
        'ghi_chu': '[Trạng thái: Chờ BQL duyệt] $ghiChuNoiDung',
      };

      // 1. Lưu bản ghi vào bảng bien_ban_thanh_ly (tự động hỗ trợ cả khi có hoặc chưa có cột trang_thai)
      try {
        await db.from('bien_ban_thanh_ly').insert({
          ...bbData,
          'trang_thai': 'Chờ BQL duyệt',
        });
      } catch (_) {
        await db.from('bien_ban_thanh_ly').insert(bbData);
      }

      // 2. Cập nhật trạng thái hợp đồng (nếu database hỗ trợ trạng thái này)
      try {
        await db.from('hop_dong').update({
          'trang_thai': 'Chờ thanh lý',
        }).eq('ma_hop_dong', _hd.maHopDong);
      } catch (e) {
        debugPrint('Bỏ qua cập nhật trạng thái hợp đồng: $e');
      }

      // 3. Nếu chọn Cấn trừ nợ hóa đơn vào tiền cọc -> Cập nhật ghi chú hóa đơn
      if (_canTruNoVaoTienCoc && _danhSachHoaDonNo.isNotEmpty) {
        for (final item in _danhSachHoaDonNo) {
          try {
            await db.from('hoa_don').update({
              'trang_thai': 'Đã cấn trừ cọc',
            }).eq('ma_hoa_don', item.maHoaDon);
          } catch (e) {
            debugPrint('Lỗi cập nhật hóa đơn nợ ${item.maHoaDon}: $e');
          }
        }
      }

      // 4. Bắn thông báo hệ thống và thêm vào Cái Chuông
      SystemNotificationService.show(
        title: 'Đã gửi yêu cầu thanh lý hợp đồng',
        body: 'Yêu cầu trả phòng ${_hd.maHopDong} (${widget.tenPhong}) đã gửi đến BQL để chuẩn bị kiểm tra phòng.',
        tag: 'tl_${_hd.maHopDong}',
        loai: 'hop_dong',
      );

      setState(() {
        _bienBanDaTao = BienBanThanhLyModel.fromJson(bbData);
        _currentStep = 1; // Chuyển sang màn hình Đang chờ BQL nghiệm thu
        _isSubmitting = false;
      });

      if (mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Thanh Lý Hợp Đồng Thành Công',
          noiDung: 'Biên bản thanh lý hợp đồng ${_hd.maHopDong} đã được lưu vào hệ thống Kiêu Giang House.',
          type: ThongBaoType.thanhCong,
        );
      }
    } catch (e) {
      debugPrint('Lỗi thanh lý hợp đồng: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi thực hiện thanh lý: $e')),
        );
      }
    }
  }

  // ─── XUẤT FILE PDF BIÊN BẢN THANH LÝ HỢP ĐỒNG ───
  Future<void> _xuatPdfBienBan() async {
    final doc = pw.Document();
    pw.Font fontBold;
    pw.Font fontRegular;
    try {
      final fontRegularData = await rootBundle.load('assets/fonts/arial.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/arialbd.ttf');
      fontRegular = pw.Font.ttf(fontRegularData);
      fontBold = pw.Font.ttf(fontBoldData);
    } catch (_) {
      try {
        fontBold = await PdfGoogleFonts.robotoBold();
        fontRegular = await PdfGoogleFonts.robotoRegular();
      } catch (_) {
        fontBold = pw.Font.helveticaBold();
        fontRegular = pw.Font.helvetica();
      }
    }

    final bb = _bienBanDaTao;
    final maTL = bb?.maThanhLy ?? 'TL001';
    final ngayTra = bb?.ngayTraPhong ?? FormatUtils.formatDate(_ngayTraPhong.toIso8601String());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Quốc hiệu & Tiêu ngữ
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                      style: pw.TextStyle(font: fontBold, fontSize: 13),
                    ),
                    pw.Text(
                      'Độc lập - Tự do - Hạnh phúc',
                      style: pw.TextStyle(font: fontRegular, fontSize: 11),
                    ),
                    pw.Text('---------------------------', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Tiêu đề
              pw.Center(
                child: pw.Text(
                  'BIÊN BẢN THANH LÝ HỢP ĐỒNG THUÊ PHÒNG',
                  style: pw.TextStyle(font: fontBold, fontSize: 15, color: PdfColors.blue900),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Số: $maTL / BBTL-KG • Ngày trả phòng: $ngayTra',
                  style: pw.TextStyle(font: fontRegular, fontSize: 10, color: PdfColors.grey700),
                ),
              ),
              pw.SizedBox(height: 16),

              // Căn cứ
              pw.Text(
                'Căn cứ vào Hợp đồng thuê phòng số: ${_hd.maHopDong} ký ngày ${_hd.ngayKy};',
                style: pw.TextStyle(font: fontRegular, fontSize: 11),
              ),
              pw.Text(
                'Hôm nay, hai bên thống nhất tiến hành thanh lý hợp đồng thuê phòng với các nội dung sau:',
                style: pw.TextStyle(font: fontRegular, fontSize: 11),
              ),
              pw.SizedBox(height: 12),

              // Bên A & Bên B
              pw.Text('I. CÁC BÊN THAM GIA THANH LÝ', style: pw.TextStyle(font: fontBold, fontSize: 11)),
              pw.Text('1. BÊN CHO THUÊ (BÊN A): BAN QUẢN LÝ TÒA NHÀ KIÊU GIANG', style: pw.TextStyle(font: fontRegular, fontSize: 10.5)),
              pw.Text('   Địa chỉ: 124/6 Kiêu Giang, P. Phước Long B, TP. Thủ Đức, TP.HCM', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text('2. BÊN THUÊ (BÊN B): $_tenNguoiThue', style: pw.TextStyle(font: fontRegular, fontSize: 10.5)),
              pw.Text('   Thuê phòng: ${widget.tenPhong} (${widget.maPhong})', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.SizedBox(height: 12),

              // Nội dung thanh lý
              pw.Text('II. NỘI DUNG THANH LÝ VÀ BÀN GIAO PHÒNG', style: pw.TextStyle(font: fontBold, fontSize: 11)),
              pw.Text('1. Bên B đã tiến hành hoàn trả toàn bộ mặt bằng phòng ${widget.tenPhong} cùng trang thiết bị gắn liền cho Bên A.', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('2. Chỉ số công tơ điện nước chốt tại thời điểm bàn giao:', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('   • Chỉ số điện cuối: ${bb?.chiSoDienCuoi ?? _chiSoDienCuoi} kWh (Tiền điện kỳ cuối: ${FormatUtils.currency(_tienDienCuoi)})', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('   • Chỉ số nước cuối: ${bb?.chiSoNuocCuoi ?? _chiSoNuocCuoi} m³ (Tiền nước kỳ cuối: ${FormatUtils.currency(_tienNuocCuoi)})', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.SizedBox(height: 6),
              pw.Text('3. Kết quả kiểm kê thiết bị và nội thất phòng (${_danhSachThietBi.length - _soThietBiHuHong}/${_danhSachThietBi.length} đạt chuẩn):', style: pw.TextStyle(font: fontBold, fontSize: 10)),
              pw.Text('   • ${_danhSachThietBi.map((t) => "${t['ten']}: ${t['isDatChuan'] == true ? 'Đạt chuẩn' : 'Hư hỏng (-${FormatUtils.currency((t['chiPhi'] as num? ?? 0).toDouble())})'}").join(' | ')}', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
              pw.SizedBox(height: 12),

              // Quyết toán tài chính
              pw.Text('III. QUYẾT TOÁN TÀI CHÍNH VÀ TIỀN ĐẶT CỌC', style: pw.TextStyle(font: fontBold, fontSize: 11)),
              pw.Text('• Lý do trả phòng: $_lyDoTraPhong (${_isHetHanHopDong ? "Hết hạn hợp đồng - Đủ điều kiện hoàn cọc" : "Chấm dứt trước hạn - Không hoàn trả tiền đặt cọc"})', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('• Tiền đặt cọc ban đầu: ${FormatUtils.currency(_tienDatCoc)}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              if (_canTruNoVaoTienCoc && _tongTienNoHoaDon > 0)
                pw.Text('• Nợ hóa đơn cũ đã cấn trừ: ${FormatUtils.currency(_tongTienNoHoaDon)} (${_danhSachHoaDonNo.length} hóa đơn)', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text('• Tổng chi phí khấu trừ điện nước & dịch vụ cuối: ${FormatUtils.currency(_tongKhauTru)}', style: pw.TextStyle(font: fontRegular, fontSize: 10)),
              pw.Text(
                '• SỐ TIỀN CỌC HOÀN LẠI CHO BÊN B: ${_isHetHanHopDong ? FormatUtils.currency(bb?.tienCocHoanLai ?? _tienCocHoanLai) : "0 đ (Không hoàn cọc do trả phòng trước hạn)"}',
                style: pw.TextStyle(font: fontBold, fontSize: 11, color: _isHetHanHopDong ? PdfColors.green900 : PdfColors.red900),
              ),
              if ((bb?.tienKhTraThem ?? _tienKhTraThem) > 0)
                pw.Text(
                  '• SỐ TIỀN BÊN B CẦN NỘP THÊM: ${FormatUtils.currency(bb?.tienKhTraThem ?? _tienKhTraThem)}',
                  style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.red900),
                ),
              pw.SizedBox(height: 16),

              // Cam kết
              pw.Text(
                'Hai bên xác nhận không còn bất kỳ khiếu nại hay tranh chấp nào liên quan đến Hợp đồng thuê phòng này. Hợp đồng số ${_hd.maHopDong} chính thức hết hiệu lực kể từ ngày ký biên bản.',
                style: pw.TextStyle(font: fontRegular, fontSize: 9.5, fontStyle: pw.FontStyle.italic),
              ),
              pw.SizedBox(height: 24),

              // Chữ ký
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Text('ĐẠI DIỆN BÊN A', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      pw.Text('(Ký và ghi rõ họ tên)', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                      pw.SizedBox(height: 40),
                      pw.Text('BAN QUẢN LÝ KIÊU GIANG', style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('ĐẠI DIỆN BÊN B', style: pw.TextStyle(font: fontBold, fontSize: 11)),
                      pw.Text('(Ký và ghi rõ họ tên)', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                      pw.SizedBox(height: 40),
                      pw.Text(_tenNguoiThue.toUpperCase(), style: pw.TextStyle(font: fontBold, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'Bien_Ban_Thanh_Ly_${_hd.maHopDong}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgLight,
        body: Center(
          child: CircularProgressIndicator(color: _primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        title: const Text(
          'Chấm Dứt Hợp Đồng & Trả Phòng',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: _textDark),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: _textDark),
          onPressed: () {
            if (_currentStep == 1) {
              setState(() => _currentStep = 0);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: Column(
        children: [
          // ── STEP INDICATOR (Thanh tiến trình 3 bước) ──
          _buildStepHeader(),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                children: [
                  if (_currentStep == 0) _buildStep1Form(),
                  if (_currentStep == 1) _buildStep2Form(),
                  if (_currentStep == 2) _buildStep3Success(),
                ],
              ),
            ),
          ),

          // ── BOTTOM ACTION BAR ──
          if (_currentStep < 2) _buildBottomBar(),
        ],
      ),
    );
  }

  // ─── 1. STEP PROGRESS HEADER (Thanh tiến trình tối giản) ───
  Widget _buildStepHeader() {
    final titles = ['Gửi yêu cầu', 'Chờ BQL nghiệm thu', 'Biên bản thanh lý'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        children: [
          Row(
            children: List.generate(3, (i) {
              final isDone = _currentStep > i;
              final isCurrent = _currentStep == i;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: isDone || isCurrent ? _primary : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bước ${_currentStep + 1} / 3: ${titles[_currentStep]}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                _currentStep == 0
                    ? 'Chọn ngày & lý do trả phòng'
                    : _currentStep == 1
                        ? 'BQL kiểm tra thiết bị & phòng'
                        : 'Biên bản & Quyết toán cọc',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 2. BƯỚC 1: THÔNG TIN TRẢ PHÒNG & TÀI KHOẢN NHẬN CỌC ───
  Widget _buildStep1Form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thẻ thông tin phòng & hợp đồng
        _buildContractSummaryCard(),
        const SizedBox(height: 14),

        // 2. Thẻ kiểm tra hóa đơn chưa thanh toán (nếu có)
        _buildUnpaidBillsCard(),
        const SizedBox(height: 14),

        // 3. Kế hoạch dọn đi & Lý do
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
              const Row(
                children: [
                  Icon(Icons.event_note_rounded, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Kế hoạch trả phòng',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Chọn ngày trả phòng
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ngày dọn đi dự kiến', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Báo trước tối thiểu 15 ngày',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFD97706)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _ngayTraPhong,
                    firstDate: DateTime.now().add(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (picked != null) {
                    setState(() => _ngayTraPhong = picked);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_ngayTraPhong.day.toString().padLeft(2, '0')}/${_ngayTraPhong.month.toString().padLeft(2, '0')}/${_ngayTraPhong.year}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textDark),
                      ),
                      const Icon(Icons.calendar_month_outlined, size: 18, color: _primary),
                    ],
                  ),
                ),
              ),
              if (_ngayTraPhong.difference(DateTime.now()).inDays < 15) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bạn chọn ngày trả phòng trong vòng ${_ngayTraPhong.difference(DateTime.now()).inDays} ngày tới. Vui lòng liên hệ trực tiếp BQL để thống nhất lịch bàn giao.',
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Chọn lý do
              const Text('Lý do chấm dứt hợp đồng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textMuted)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _lyDoTraPhong,
                    isExpanded: true,
                    items: _danhSachLyDo
                        .map((lyDo) => DropdownMenuItem(value: lyDo, child: Text(lyDo, style: const TextStyle(fontSize: 13, color: _textDark))))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _lyDoTraPhong = val;
                          _tinhToanQuyetToan();
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Thẻ hiển thị quy định hoàn trả tiền cọc
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isHetHanHopDong ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isHetHanHopDong ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isHetHanHopDong ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                      size: 20,
                      color: _isHetHanHopDong ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isHetHanHopDong ? 'Đủ điều kiện hoàn trả tiền cọc' : 'Không hoàn trả tiền đặt cọc',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: _isHetHanHopDong ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _isHetHanHopDong
                                ? 'Trả phòng đúng thời điểm hết hạn hợp đồng. Tiền đặt cọc (${FormatUtils.currency(_tienDatCoc)}) sẽ được BQL hoàn trả lại sau khi đối soát điện nước và các nghĩa vụ thanh toán.'
                                : 'Theo quy chế hợp đồng thuê phòng, tiền đặt cọc chỉ được hoàn trả khi hết hạn hợp đồng. Trả phòng vì các lý do khác trước thời hạn sẽ KHÔNG ĐƯỢC HOÀN TRẢ tiền cọc.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: _isHetHanHopDong ? const Color(0xFF166534) : const Color(0xFF991B1B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Ghi chú thêm
              TextField(
                controller: _lyDoChiTietController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Ghi chú thêm về việc trả phòng (tùy chọn)...',
                  hintStyle: const TextStyle(fontSize: 12.5, color: _textMuted),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Tài khoản nhận hoàn cọc (Chỉ hiển thị khi đủ điều kiện hoàn cọc)
        if (!_isHetHanHopDong) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.money_off_rounded, size: 20, color: Color(0xFF64748B)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Không cần cung cấp tài khoản ngân hàng do trường hợp này không hoàn trả tiền cọc theo quy định hợp đồng.',
                    style: TextStyle(fontSize: 12, color: _textMuted, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
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
              const Row(
                children: [
                  Icon(Icons.account_balance_outlined, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Tài khoản nhận hoàn tiền cọc',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'BQL sẽ chuyển khoản hoàn cọc về tài khoản này sau khi chốt đối soát công nợ.',
                style: TextStyle(fontSize: 11.5, color: _textMuted),
              ),
              const SizedBox(height: 14),

              // 1. Chọn Ngân hàng
              const Text('Ngân hàng thụ hưởng *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _nganHangDuocChon,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _primary),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_balance_rounded, size: 18, color: _primary),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
                ),
                items: _danhSachNganHang.map((bank) => DropdownMenuItem(
                  value: bank,
                  child: Text(bank, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark)),
                )).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _nganHangDuocChon = val);
                  }
                },
              ),
              const SizedBox(height: 12),

              // 2. Số tài khoản
              const Text('Số tài khoản thụ hưởng *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
              const SizedBox(height: 6),
              TextField(
                controller: _soTaiKhoanController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                decoration: InputDecoration(
                  hintText: 'Nhập số tài khoản ngân hàng',
                  hintStyle: const TextStyle(fontSize: 12.5, color: _textMuted),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  prefixIcon: const Icon(Icons.credit_card_rounded, size: 18, color: _primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),

              // 3. Chủ tài khoản
              const Text('Tên chủ tài khoản *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
              const SizedBox(height: 6),
              TextField(
                controller: _chuTaiKhoanController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                decoration: InputDecoration(
                  hintText: 'Nhập họ tên chủ tài khoản (VD: NGUYEN VAN A)',
                  hintStyle: const TextStyle(fontSize: 12.5, color: _textMuted, fontWeight: FontWeight.normal),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: _primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        ],
        const SizedBox(height: 14),

        // 5. Thẻ danh mục thiết bị BQL sẽ kiểm tra bàn giao
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
              const Row(
                children: [
                  Icon(Icons.checklist_rtl_rounded, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Thiết bị BQL sẽ kiểm tra khi nhận phòng',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Vui lòng bảo quản nguyên vẹn để nhận lại 100% tiền cọc (nếu hết hạn HĐ):',
                style: TextStyle(fontSize: 11.5, color: _textMuted),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _danhSachThietBi.map((item) {
                  final ten = item['ten']?.toString() ?? 'Thiết bị';
                  final IconData icon = item['icon'] as IconData? ?? Icons.devices_other_rounded;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: _primary),
                        const SizedBox(width: 6),
                        Text(ten, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textDark)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 6. Hướng dẫn quy trình bàn giao 4 bước
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF0284C7)),
                  SizedBox(width: 8),
                  Text(
                    'Quy trình trả phòng & Hoàn cọc',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0369A1)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildStepGuideItem('1', 'Cư dân gửi đơn yêu cầu này lên hệ thống.'),
              _buildStepGuideItem('2', 'BQL tiếp nhận và liên hệ hẹn lịch kiểm tra phòng thực tế.'),
              _buildStepGuideItem('3', 'BQL trực tiếp đến phòng kiểm tra thiết bị & chốt số điện nước.'),
              _buildStepGuideItem('4', 'Hai bên ký Biên bản thanh lý & BQL hoàn cọc về tài khoản.'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepGuideItem(String step, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(color: Color(0xFF0284C7), shape: BoxShape.circle),
            child: Center(
              child: Text(step, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF0C4A6E), height: 1.35)),
          ),
        ],
      ),
    );
  }

  // ─── 3. BƯỚC 2: CHỜ BQL ĐẾN KIỂM TRA PHÒNG & NGHIỆM THU ───
  Widget _buildStep2Form() {
    final ngayTraStr = '${_ngayTraPhong.day.toString().padLeft(2, '0')}/${_ngayTraPhong.month.toString().padLeft(2, '0')}/${_ngayTraPhong.year}';
    final hasBank = _soTaiKhoanController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thẻ trạng thái lớn nổi bật: Đang chờ BQL nghiệm thu
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
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
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: Color(0xFFF59E0B),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(Icons.pending_actions_rounded, color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Yêu Cầu Đang Chờ BQL Nghiệm Thu',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
              ),
              const SizedBox(height: 6),
              Text(
                'BQL Kiêu Giang House đã tiếp nhận đơn yêu cầu trả phòng của bạn cho ${widget.tenPhong}. BQL sẽ trực tiếp đến phòng kiểm tra thiết bị & chốt số điện nước vào ngày hẹn.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309), height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Timeline Tiến trình bàn giao phòng
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.timeline_rounded, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Tiến trình xử lý bàn giao phòng',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Bước 1: Đã gửi đơn
              _buildTimelineStep(
                title: 'Đã gửi đơn yêu cầu trả phòng',
                subtitle: 'Ngày hẹn trả: $ngayTraStr',
                isCompleted: true,
                isCurrent: false,
              ),
              // Bước 2: BQL nghiệm thu phòng
              _buildTimelineStep(
                title: 'BQL đến kiểm tra phòng & chốt điện nước',
                subtitle: 'Chủ trọ / BQL kiểm kê thiết bị và chốt đồng hồ tại phòng',
                isCompleted: false,
                isCurrent: true,
              ),
              // Bước 3: Phát hành biên bản & hoàn cọc
              _buildTimelineStep(
                title: 'Lập Biên bản thanh lý & Hoàn cọc',
                subtitle: 'Đối soát công nợ cuối và hoàn trả tiền cọc về tài khoản',
                isCompleted: false,
                isCurrent: false,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 3. Thông tin chi tiết đơn đã nộp
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Chi tiết đơn đã gửi',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 10),

              _buildInfoRow('Phòng áp dụng', widget.tenPhong),
              _buildInfoRow('Ngày dự kiến trả', ngayTraStr),
              _buildInfoRow('Lý do trả phòng', _lyDoTraPhong),
              _buildInfoRow(
                'Điều kiện hoàn cọc',
                _isHetHanHopDong ? 'Đủ điều kiện hoàn cọc' : 'Không hoàn cọc (trước hạn)',
                valueColor: _isHetHanHopDong ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                isBold: true,
              ),
              if (hasBank && _isHetHanHopDong)
                _buildInfoRow('Tài khoản nhận cọc', '${_soTaiKhoanController.text} ($_nganHangDuocChon)'),
              if (_lyDoChiTietController.text.trim().isNotEmpty)
                _buildInfoRow('Ghi chú của bạn', _lyDoChiTietController.text.trim()),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Khối lưu ý chuẩn bị bàn giao phòng
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cleaning_services_rounded, size: 16, color: Color(0xFF475569)),
                  SizedBox(width: 8),
                  Text(
                    'Cần chuẩn bị trước khi BQL đến nghiệm thu:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('• Thu dọn sạch sẽ toàn bộ đồ đạc và tư trang cá nhân.', style: TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
              const SizedBox(height: 4),
              const Text('• Vệ sinh phòng cơ bản để tránh phát sinh phí vệ sinh dọn dẹp.', style: TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
              const SizedBox(height: 4),
              const Text('• Chuẩn bị sẵn đầy đủ remote máy lạnh, chìa khóa phòng, thẻ từ thang máy.', style: TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 5. Nút BQL nghiệm thu xong -> Chuyển sang xem Biên bản thanh lý
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: Column(
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_rounded, size: 18, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BQL đã nghiệm thu phòng xong?',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Khi BQL đã đến phòng kiểm tra thiết bị và chốt số điện nước, bạn có thể xem Biên bản thanh lý và số tiền cọc hoàn lại tại đây:',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF166534), height: 1.35),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _tinhToanQuyetToan();
                      _currentStep = 2; // Xem biên bản thanh lý chính thức
                    });
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text(
                    'Xem Biên Bản Thanh Lý Chính Thức',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isCurrent,
    bool isLast = false,
  }) {
    Color circleColor;
    IconData icon;
    if (isCompleted) {
      circleColor = const Color(0xFF16A34A);
      icon = Icons.check_rounded;
    } else if (isCurrent) {
      circleColor = const Color(0xFFF59E0B);
      icon = Icons.hourglass_top_rounded;
    } else {
      circleColor = const Color(0xFFCBD5E1);
      icon = Icons.circle_outlined;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
              child: Center(child: Icon(icon, color: Colors.white, size: 13)),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 38,
                color: isCompleted ? const Color(0xFF16A34A) : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isCurrent || isCompleted ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent ? const Color(0xFFB45309) : _textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: _textMuted),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 4. BƯỚC 3: MÀN HÌNH HOÀN TẤT & XEM BIÊN BẢN THANH LÝ ───
  Widget _buildStep3Success() {
    final bb = _bienBanDaTao;
    final maTL = bb?.maThanhLy ?? 'TL001';
    final ngayTra = bb?.ngayTraPhong ?? FormatUtils.formatDate(_ngayTraPhong.toIso8601String());

    return Column(
      children: [
        // Icon chúc mừng
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: Color(0xFFDCFCE7), shape: BoxShape.circle),
          child: const Center(
            child: Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 40),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Đã Lập Biên Bản Thanh Lý',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _textDark),
        ),
        const SizedBox(height: 4),
        Text(
          'Mã biên bản: $maTL • Hợp đồng ${_hd.maHopDong}',
          style: const TextStyle(fontSize: 13, color: _textMuted),
        ),
        const SizedBox(height: 20),

        // Thẻ biên bản thanh lý số hóa chính thức
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE2E8F0)),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('BIÊN BẢN SỐ HÓA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 0.5)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                    child: const Text('ĐÃ THANH LÝ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFF1F5F9)),

              _buildInfoRow('Phòng bàn giao', widget.tenPhong),
              _buildInfoRow('Người đại diện thuê', _tenNguoiThue),
              _buildInfoRow('Ngày trả phòng', ngayTra),
              _buildInfoRow('Chỉ số điện chốt cuối', '${bb?.chiSoDienCuoi.toInt() ?? _chiSoDienCuoi.toInt()} kWh'),
              _buildInfoRow('Chỉ số nước chốt cuối', '${bb?.chiSoNuocCuoi.toInt() ?? _chiSoNuocCuoi.toInt()} m³'),
              _buildInfoRow(
                'Kiểm kê thiết bị',
                '${_danhSachThietBi.length - _soThietBiHuHong}/${_danhSachThietBi.length} thiết bị đạt chuẩn',
                valueColor: _soThietBiHuHong == 0 ? const Color(0xFF15803D) : const Color(0xFFDC2626),
              ),
              if (_tongTienBoiThuongThietBi > 0)
                _buildInfoRow(
                  'Khấu trừ hư hỏng thiết bị',
                  FormatUtils.currency(_tongTienBoiThuongThietBi),
                  valueColor: const Color(0xFFDC2626),
                ),
              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              _buildInfoRow('Tiền cọc ban đầu', FormatUtils.currency(_tienDatCoc)),
              _buildInfoRow(
                'Tiền cọc hoàn lại',
                _isHetHanHopDong ? FormatUtils.currency(bb?.tienCocHoanLai ?? _tienCocHoanLai) : '0 đ (Không hoàn cọc)',
                valueColor: _isHetHanHopDong ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                isBold: true,
              ),
              if ((bb?.tienKhTraThem ?? _tienKhTraThem) > 0)
                _buildInfoRow(
                  'Tiền nộp thêm',
                  FormatUtils.currency(bb?.tienKhTraThem ?? _tienKhTraThem),
                  valueColor: const Color(0xFFB91C1C),
                  isBold: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Các nút hành động
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _xuatPdfBienBan,
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('Xem & In File PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2FE),
                    foregroundColor: _primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.home_rounded, size: 18),
                  label: const Text('Về Trang Chủ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
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
      ],
    );
  }

  // ─── BOTTOM ACTION BAR ───
  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep == 1) ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep = 0),
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Chỉnh sửa đơn', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textDark,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _tinhToanQuyetToan();
                      _currentStep = 2;
                    });
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('Xem Biên Bản', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            if (_isHetHanHopDong && _tienDatCoc > 0 && _soTaiKhoanController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Vui lòng nhập Số tài khoản ngân hàng để nhận hoàn tiền cọc!')),
                              );
                              return;
                            }
                            _showConfirmSendRequestDialog();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Gửi Đơn Yêu Cầu Trả Phòng Lên BQL',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showConfirmSendRequestDialog() {
    final ngayTraStr = '${_ngayTraPhong.day.toString().padLeft(2, '0')}/${_ngayTraPhong.month.toString().padLeft(2, '0')}/${_ngayTraPhong.year}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xác nhận gửi đơn yêu cầu?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn đang gửi yêu cầu trả phòng ${widget.tenPhong} vào ngày $ngayTraStr.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: _textDark),
            ),
            const SizedBox(height: 8),
            Text(
              'Lý do: $_lyDoTraPhong',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _primary),
            ),
            const SizedBox(height: 6),
            Text(
              _isHetHanHopDong
                  ? '✓ Đủ điều kiện hoàn cọc: BQL sẽ kiểm tra phòng và hoàn trả cọc về tài khoản của bạn.'
                  : '⚠️ Trả phòng trước hạn: Tiền cọc sẽ không được hoàn lại theo quy định hợp đồng.',
              style: TextStyle(
                fontSize: 11.5,
                color: _isHetHanHopDong ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'BQL sẽ liên hệ và trực tiếp đến phòng để chốt công tơ điện nước và kiểm kê thiết bị.',
              style: TextStyle(fontSize: 11.5, color: _textMuted, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Kiểm tra lại', style: TextStyle(color: _textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _xacNhanThanhLyHopDong();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xác nhận gửi', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildContractSummaryCard() {
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.meeting_room_outlined, color: _primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.tenPhong,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: _textDark),
                      ),
                      Text(
                        'Hợp đồng ${_hd.maHopDong}',
                        style: const TextStyle(fontSize: 11.5, color: _textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFDCFCE7)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(
                      _hd.trangThai,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Người đại diện hợp đồng', style: TextStyle(fontSize: 11.5, color: _textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    _tenNguoiThue,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _textDark),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Tiền cọc giữ chân', style: TextStyle(fontSize: 11.5, color: _textMuted)),
                  const SizedBox(height: 2),
                  Text(
                    FormatUtils.currency(_tienDatCoc),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _primary),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnpaidBillsCard() {
    if (_danhSachHoaDonNo.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCFCE7)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: Color(0xFF16A34A), size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hợp đồng không có hóa đơn nợ tồn đọng.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF15803D)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
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
          // Header cảnh báo nợ nhẹ nhàng
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, size: 17, color: Color(0xFFD97706)),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hóa đơn chưa trả (${_danhSachHoaDonNo.length})',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark),
                    ),
                  ],
                ),
                Text(
                  FormatUtils.currency(_tongTienNoHoaDon),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFFDC2626)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Danh sách từng hóa đơn nợ
          ..._danhSachHoaDonNo.map((hd) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${hd.maHoaDon} • Kỳ ${hd.thangNam}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textDark),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Hạn nộp: ${hd.hanDongTienFormatted}',
                            style: const TextStyle(fontSize: 11, color: _textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          FormatUtils.currency(hd.tongTien),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(height: 3),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PaymentScreen(
                                  hoaDon: hd,
                                  tenPhong: widget.tenPhong,
                                ),
                              ),
                            ).then((_) => _taiThongTinHopDong());
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Trả riêng',
                              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )),

          // Khối tùy chọn cấn trừ nợ vào tiền cọc
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cấn trừ nợ vào tiền cọc',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textDark),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _canTruNoVaoTienCoc
                            ? 'Bù trừ ${FormatUtils.currency(_tongTienNoHoaDon)} vào tiền hoàn cọc ở Bước 2'
                            : 'Cần thanh toán hóa đơn dứt điểm trước khi trả phòng',
                        style: TextStyle(
                          fontSize: 11,
                          color: _canTruNoVaoTienCoc ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _canTruNoVaoTienCoc,
                  activeTrackColor: _primary,
                  onChanged: (val) {
                    setState(() {
                      _canTruNoVaoTienCoc = val;
                      _tinhToanQuyetToan();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: _textMuted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? _textDark,
            ),
          ),
        ],
      ),
    );
  }
}

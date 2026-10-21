import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';

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

  // Phân loại 2 trường hợp người thuê trả phòng:
  // 1. Đúng hạn hợp đồng: Được HOÀN CỌC 100% sau khi khấu trừ tiền điện, nước và chi phí hư hại tài sản
  // 2. Trước hạn hợp đồng: MẤT 100% TIỀN CỌC theo điều khoản hợp đồng. Vẫn phải thanh toán tiền điện, nước thực tế
  bool _isDungHanHopDong = true;

  // Bước 1: Thông tin trả phòng
  late DateTime _ngayTraPhong;
  String _lyDoTraPhong = 'Hết hạn hợp đồng thuê';
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

  // Ảnh đồng hồ điện & nước để đối soát
  final ImagePicker _picker = ImagePicker();
  Uint8List? _anhDongHoDienBytes;
  Uint8List? _anhDongHoNuocBytes;

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

  /// Phân loại: Được hoàn cọc 100% khi đúng hạn hợp đồng. Mất 100% cọc khi trước hạn.
  bool get _isHetHanHopDong => _isDungHanHopDong;

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

      // Tự động kiểm tra thời hạn hợp đồng để gợi ý phân loại đúng hạn hay trước hạn
      if (_hd.ngayKt.isNotEmpty) {
        try {
          final ngayKetThuc = DateTime.parse(_hd.ngayKt);
          final daysLeft = ngayKetThuc.difference(DateTime.now()).inDays;
          _isDungHanHopDong = daysLeft <= 30;
          _lyDoTraPhong = _isDungHanHopDong ? 'Hết hạn hợp đồng thuê' : 'Chấm dứt trước hạn hợp đồng';
        } catch (_) {}
      }

      // 3. Kiểm tra xem hợp đồng đã có Biên bản thanh lý hoặc yêu cầu trước đó chưa
      final bbRows = await db.from('bien_ban_thanh_ly').select().eq('ma_hop_dong', _hd.maHopDong).maybeSingle();
      if (bbRows != null) {
        _bienBanDaTao = BienBanThanhLyModel.fromJson(Map<String, dynamic>.from(bbRows));
        _currentStep = 2; // Xem biên bản thanh lý chính thức
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

  Future<void> _pickAnhDongHo({required bool isDien}) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isDien ? 'Chụp ảnh đồng hồ điện' : 'Chụp ảnh đồng hồ nước',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ảnh chụp rõ mặt công tơ và dãy số để BQL đối soát chính xác.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: _textMuted),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final xfile = await _picker.pickImage(
                          source: ImageSource.camera,
                          maxWidth: 1200,
                          maxHeight: 1200,
                          imageQuality: 80,
                        );
                        if (xfile != null) {
                          final bytes = await xfile.readAsBytes();
                          setState(() {
                            if (isDien) {
                              _anhDongHoDienBytes = bytes;
                            } else {
                              _anhDongHoNuocBytes = bytes;
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.camera_alt_rounded, color: _primary),
                      label: const Text('Máy ảnh', style: TextStyle(color: _primary, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: _primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final xfile = await _picker.pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1200,
                          maxHeight: 1200,
                          imageQuality: 80,
                        );
                        if (xfile != null) {
                          final bytes = await xfile.readAsBytes();
                          setState(() {
                            if (isDien) {
                              _anhDongHoDienBytes = bytes;
                            } else {
                              _anhDongHoNuocBytes = bytes;
                            }
                          });
                        }
                      },
                      icon: const Icon(Icons.photo_library_rounded, color: Colors.white),
                      label: const Text('Thư viện', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: _primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _xacNhanThanhLyHopDong() async {
    final user = AuthService.currentUser;
    if (user != null) {
      final role = user.vaiTro.toLowerCase();
      if (role.contains('thanhvien') || role.contains('banocung') || role.contains('ocung')) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Không Có Quyền Thực Hiện',
          noiDung: 'Bạn đang đăng nhập với tư cách Thành viên phòng (Bạn cùng phòng). Thủ tục chấm dứt hợp đồng chỉ có Người đại diện (Trưởng phòng) mới có thẩm quyền thực hiện!',
          type: ThongBaoType.canhBao,
        );
        return;
      }
    }

    if (_isDungHanHopDong && _tienCocHoanLai > 0 && _soTaiKhoanController.text.trim().isEmpty) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Thiếu thông tin',
        noiDung: 'Vui lòng nhập Số tài khoản ngân hàng để nhận hoàn tiền cọc!',
        type: ThongBaoType.canhBao,
      );
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final ngayTraStr = '${_ngayTraPhong.year}-${_ngayTraPhong.month.toString().padLeft(2, '0')}-${_ngayTraPhong.day.toString().padLeft(2, '0')}';
      // Cột ma_thanh_ly trong Postgres có kiểu character varying(10) -> Đảm bảo độ dài chính xác 10 ký tự: 'TL' + 8 số
      final tsStr = DateTime.now().millisecondsSinceEpoch.toString();
      final maTL = 'TL${tsStr.substring(tsStr.length - 8)}';

      // 1. Tải ảnh đồng hồ điện lên Supabase Storage (hoặc base64)
      String? urlAnhDien;
      if (_anhDongHoDienBytes != null) {
        try {
          final storagePath = 'meters/${maTL}_dien.jpg';
          await db.storage.from('contracts').uploadBinary(
            storagePath,
            _anhDongHoDienBytes!,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
          urlAnhDien = db.storage.from('contracts').getPublicUrl(storagePath);
        } catch (_) {
          final b64 = base64Encode(_anhDongHoDienBytes!);
          urlAnhDien = 'data:image/jpeg;base64,$b64';
        }
      }

      // 2. Tải ảnh đồng hồ nước lên Supabase Storage (hoặc base64)
      String? urlAnhNuoc;
      if (_anhDongHoNuocBytes != null) {
        try {
          final storagePath = 'meters/${maTL}_nuoc.jpg';
          await db.storage.from('contracts').uploadBinary(
            storagePath,
            _anhDongHoNuocBytes!,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
          );
          urlAnhNuoc = db.storage.from('contracts').getPublicUrl(storagePath);
        } catch (_) {
          final b64 = base64Encode(_anhDongHoNuocBytes!);
          urlAnhNuoc = 'data:image/jpeg;base64,$b64';
        }
      }

      // 3. Xây dựng nội dung chi tiết biên bản
      String ghiChuNoiDung = 'Phân loại: ${_isDungHanHopDong ? "1. Đúng hạn hợp đồng (HOÀN CỌC 100%)" : "2. Trước hạn hợp đồng (MẤT 100% CỌC)"}';
      ghiChuNoiDung += ' | Điện chốt: ${_chiSoDienCuoi.toInt()} kWh (${FormatUtils.currency(_tienDienCuoi)})';
      ghiChuNoiDung += ' | Nước chốt: ${_chiSoNuocCuoi.toInt()} m³ (${FormatUtils.currency(_tienNuocCuoi)})';
      if (urlAnhDien != null) ghiChuNoiDung += ' | [Ảnh điện: $urlAnhDien]';
      if (urlAnhNuoc != null) ghiChuNoiDung += ' | [Ảnh nước: $urlAnhNuoc]';
      final int soTbTot = _danhSachThietBi.length - _soThietBiHuHong;
      ghiChuNoiDung += ' | Thiết bị: $soTbTot/${_danhSachThietBi.length} đạt chuẩn';
      if (_soThietBiHuHong > 0) {
        ghiChuNoiDung += ' (Bồi thường hư hại $_soThietBiHuHong món: ${FormatUtils.currency(_tongTienBoiThuongThietBi)})';
      }
      if (_lyDoChiTietController.text.trim().isNotEmpty) {
        ghiChuNoiDung += ' - Lý do: ${_lyDoChiTietController.text.trim()}';
      }
      if (_isDungHanHopDong && _soTaiKhoanController.text.trim().isNotEmpty) {
        final chuTk = _chuTaiKhoanController.text.trim().isNotEmpty ? _chuTaiKhoanController.text.trim() : _tenNguoiThue;
        ghiChuNoiDung += ' | Nhận hoàn cọc: ${_soTaiKhoanController.text.trim()} ($_nganHangDuocChon) - $chuTk';
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
        'trang_thai': 'Chờ duyệt',
        'ghi_chu': ghiChuNoiDung,
      };

      // Lưu bản ghi vào bảng bien_ban_thanh_ly với cột trang_thai riêng biệt
      try {
        await db.from('bien_ban_thanh_ly').insert(bbData);
      } catch (e) {
        debugPrint('Insert với trang_thai lỗi (fallback nếu bảng chưa có cột): $e');
        final fallbackData = Map<String, dynamic>.from(bbData)..remove('trang_thai');
        await db.from('bien_ban_thanh_ly').insert(fallbackData);
      }

      // Cập nhật trạng thái hợp đồng thành 'Chờ TL' (<= 10 ký tự)
      try {
        await db.from('hop_dong').update({
          'trang_thai': 'Chờ TL',
        }).eq('ma_hop_dong', _hd.maHopDong);
      } catch (e) {
        debugPrint('Bỏ qua cập nhật trạng thái hợp đồng: $e');
      }

      // Nếu cấn trừ nợ hóa đơn cũ vào cọc -> cập nhật hóa đơn
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

      // Bắn thông báo hệ thống và thêm vào trung tâm thông báo
      SystemNotificationService.show(
        title: 'Đã gửi biên bản bàn giao trả phòng',
        body: 'Biên bản trả phòng ${_hd.maHopDong} (${widget.tenPhong}) đã gửi đến BQL kèm số điện nước và ảnh đối soát.',
        tag: 'tl_${_hd.maHopDong}',
        loai: 'hop_dong',
      );

      setState(() {
        _bienBanDaTao = BienBanThanhLyModel.fromJson({
          ...bbData,
          'loai_tra_phong': _isDungHanHopDong ? 'Đúng hạn' : 'Trước hạn',
          'anh_dong_ho_dien': urlAnhDien,
          'anh_dong_ho_nuoc': urlAnhNuoc,
        });
        _currentStep = 2; // Chuyển sang màn hình xem Biên bản thanh lý chính thức
        _isSubmitting = false;
      });

      if (mounted) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Gửi Biên Bản Thành Công',
          noiDung: 'Biên bản bàn giao và số điện nước phòng ${widget.tenPhong} đã được lưu thành công vào hệ thống Kiêu Giang House.',
          type: ThongBaoType.thanhCong,
        );
      }
    } catch (e) {
      debugPrint('Lỗi thanh lý hợp đồng: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi thực hiện',
          noiDung: 'Lỗi thực hiện thanh lý: $e',
          type: ThongBaoType.thatBai,
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
        body: LoadingMeoMeo(
          message: 'Đang tải thông tin thanh lý...',
          subMessage: 'Mèo con đang kiểm tra biên bản bàn giao~ 🐾',
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
    final titles = ['Thông tin & Phân loại', 'Chốt điện nước & Bàn giao', 'Biên bản thanh lý'];
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
                'Bước ${_currentStep + 1} / 3',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _textMuted,
                ),
              ),
              Text(
                titles[_currentStep],
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                  letterSpacing: -0.2,
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

        // 3. Phân loại 2 trường hợp người thuê trả phòng
        _buildPhanLoaiTruongHopCard(),
        const SizedBox(height: 14),

        // 4. Kế hoạch dọn đi & Lý do
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

              // Ghi chú chi tiết lý do
              const Text('Chi tiết lý do dọn đi (tùy chọn)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _textMuted)),
              const SizedBox(height: 6),
              TextField(
                controller: _lyDoChiTietController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nhập thêm lý do hoặc nguyện vọng bàn giao (nếu có)...',
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

        // 5. Tài khoản nhận hoàn cọc (Áp dụng trường hợp Đúng hạn)
        if (!_isHetHanHopDong) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: Color(0xFFD97706)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Không áp dụng tài khoản nhận hoàn cọc',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF9A3412)),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Do trả phòng Trước hạn hợp đồng, bạn sẽ mất 100% tiền đặt cọc theo điều khoản hợp đồng. Bạn chỉ cần chốt và thanh toán tiền điện, nước thực tế đến ngày bàn giao.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFC2410C), height: 1.4),
                      ),
                    ],
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
                  'BQL sẽ chuyển khoản hoàn cọc 100% (sau khi khấu trừ điện nước) về tài khoản này:',
                  style: TextStyle(fontSize: 11.5, color: _textMuted),
                ),
                const SizedBox(height: 14),

                // Chọn Ngân hàng
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

                // Số tài khoản
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

                // Chủ tài khoản
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
              _buildStepGuideItem('1', 'Chọn trường hợp trả phòng & nhập tài khoản nhận cọc.'),
              _buildStepGuideItem('2', 'Chốt số đồng hồ điện nước & chụp ảnh công tơ đối soát.'),
              _buildStepGuideItem('3', 'Kiểm kê bàn giao thiết bị phòng cùng BQL.'),
              _buildStepGuideItem('4', 'Ký Biên bản thanh lý và nhận lại cọc (nếu đúng hạn).'),
            ],
          ),
        ),
      ],
    );
  }

  // ─── THẺ PHÂN LOẠI 2 TRƯỜNG HỢP NGƯỜI THUÊ TRẢ PHÒNG ───
  Widget _buildPhanLoaiTruongHopCard() {
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
            children: [
              const Icon(Icons.rule_folder_rounded, size: 18, color: _primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Phân loại trường hợp trả phòng',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Chọn 1 trong 2',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: _textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Quy định hoàn cọc và trách nhiệm thanh toán điện nước theo từng trường hợp:',
            style: TextStyle(fontSize: 11.5, color: _textMuted, height: 1.35),
          ),
          const SizedBox(height: 12),

          // Lựa chọn 1: Đúng hạn hợp đồng
          _buildOptionCard(
            isDungHan: true,
            title: '1. Đúng hạn hợp đồng',
            subTitle: 'Người thuê sắp hết hạn hợp đồng và báo trước theo quy định (≥ 15 ngày).',
            policyTitle: 'HOÀN CỌC 100%',
            policyDesc: 'Được HOÀN CỌC 100% sau khi khấu trừ tiền điện, nước tính đến ngày bàn giao và chi phí hư hại tài sản (nếu có).',
            isSelected: _isDungHanHopDong,
            activeColor: const Color(0xFF16A34A),
            activeBg: const Color(0xFFF0FDF4),
            activeBorder: const Color(0xFF86EFAC),
            icon: Icons.verified_user_rounded,
          ),
          const SizedBox(height: 10),

          // Lựa chọn 2: Trước hạn hợp đồng
          _buildOptionCard(
            isDungHan: false,
            title: '2. Trước hạn hợp đồng',
            subTitle: 'Người thuê xin dọn đi khi hợp đồng chưa hết hạn.',
            policyTitle: 'MẤT 100% TIỀN CỌC',
            policyDesc: 'MẤT 100% TIỀN CỌC theo điều khoản hợp đồng. Vẫn phải thanh toán tiền điện, nước thực tế đến ngày dọn đi.',
            isSelected: !_isDungHanHopDong,
            activeColor: const Color(0xFFDC2626),
            activeBg: const Color(0xFFFEF2F2),
            activeBorder: const Color(0xFFFCA5A5),
            icon: Icons.cancel_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required bool isDungHan,
    required String title,
    required String subTitle,
    required String policyTitle,
    required String policyDesc,
    required bool isSelected,
    required Color activeColor,
    required Color activeBg,
    required Color activeBorder,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () {
        setState(() {
          _isDungHanHopDong = isDungHan;
          if (isDungHan) {
            _lyDoTraPhong = 'Hết hạn hợp đồng thuê';
          } else {
            _lyDoTraPhong = 'Chấm dứt trước hạn hợp đồng';
          }
          _tinhToanQuyetToan();
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? activeColor : const Color(0xFF94A3B8),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? activeColor : _textDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    policyTitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: activeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subTitle,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? _textDark : _textMuted,
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? activeBorder : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 15, color: activeColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      policyDesc,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isSelected ? activeColor : _textMuted,
                        height: 1.35,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
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

  // ─── 3. BƯỚC 2: CHỐT ĐIỆN NƯỚC & BIÊN BẢN BÀN GIAO ───
  Widget _buildStep2Form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thẻ tiêu đề bước 2
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
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
                child: const Center(
                  child: Icon(Icons.fact_check_rounded, color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chốt Điện Nước & Bàn Giao Phòng',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Nhập chỉ số công tơ cuối kỳ và chụp ảnh đồng hồ để BQL đối soát khi thanh lý.',
                      style: TextStyle(fontSize: 11.5, color: Colors.green.shade800, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. Thẻ Chốt số điện & Ảnh đồng hồ điện
        _buildMeterSection(
          isDien: true,
          title: 'Đồng hồ Điện phòng ${widget.tenPhong}',
          icon: Icons.bolt_rounded,
          accentColor: const Color(0xFFF59E0B),
          unit: 'kWh',
          chiSoDau: _chiSoDienDau,
          controller: _chiSoDienCuoiController,
          donGia: _donGiaDien,
          tienDichVu: _tienDienCuoi,
          imageBytes: _anhDongHoDienBytes,
          onPickImage: () => _pickAnhDongHo(isDien: true),
        ),
        const SizedBox(height: 14),

        // 3. Thẻ Chốt số nước & Ảnh đồng hồ nước
        _buildMeterSection(
          isDien: false,
          title: 'Đồng hồ Nước phòng ${widget.tenPhong}',
          icon: Icons.water_drop_rounded,
          accentColor: const Color(0xFF0284C7),
          unit: 'm³',
          chiSoDau: _chiSoNuocDau,
          controller: _chiSoNuocCuoiController,
          donGia: _donGiaNuoc,
          tienDichVu: _tienNuocCuoi,
          imageBytes: _anhDongHoNuocBytes,
          onPickImage: () => _pickAnhDongHo(isDien: false),
        ),
        const SizedBox(height: 14),

        // 4. Kiểm kê thiết bị bàn giao phòng
        _buildDeviceChecklistSection(),
        const SizedBox(height: 14),

        // 5. Bảng tính quyết toán tài chính (Phân loại Đúng hạn vs Trước hạn)
        _buildFinancialSummaryCard(),
        const SizedBox(height: 14),

        // 6. Ghi chú thêm cho BQL
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
                  Icon(Icons.notes_rounded, size: 18, color: _primary),
                  SizedBox(width: 8),
                  Text(
                    'Ghi chú bổ sung cho BQL',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ghiChuController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nhập nội dung dặn dò thêm trước khi bàn giao chìa khóa...',
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
      ],
    );
  }

  Widget _buildMeterSection({
    required bool isDien,
    required String title,
    required IconData icon,
    required Color accentColor,
    required String unit,
    required double chiSoDau,
    required TextEditingController controller,
    required double donGia,
    required double tienDichVu,
    required Uint8List? imageBytes,
    required VoidCallback onPickImage,
  }) {
    final double chiSoCuoi = double.tryParse(controller.text.trim()) ?? chiSoDau;
    final double tieuThu = (chiSoCuoi >= chiSoDau) ? (chiSoCuoi - chiSoDau) : 0;

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
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${FormatUtils.currency(donGia)}/$unit',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Hai cột chỉ số: Đầu kỳ vs Cuối kỳ
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Chỉ số đầu kỳ', style: TextStyle(fontSize: 11, color: _textMuted)),
                      const SizedBox(height: 4),
                      Text(
                        '${chiSoDau.toInt()} $unit',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor, width: 1.4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chỉ số chốt cuối *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor)),
                      TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accentColor),
                        decoration: InputDecoration(
                          hintText: '${chiSoDau.toInt()}',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          suffixText: unit,
                          suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _textMuted),
                        ),
                        onChanged: (val) {
                          setState(() => _tinhToanQuyetToan());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Tạm tính tiêu thụ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tiêu thụ: ${tieuThu.toInt()} $unit',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark),
                ),
                Text(
                  'Thành tiền: ${FormatUtils.currency(tienDichVu)}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: accentColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // KHU VỰC CHỤP & TẢI ẢNH ĐỒNG HỒ ĐỐI SOÁT
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Ảnh chụp đồng hồ đối soát *',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark),
              ),
              if (imageBytes != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 12, color: Color(0xFF16A34A)),
                      SizedBox(width: 4),
                      Text('Đã có ảnh', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (imageBytes != null) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    imageBytes,
                    width: double.infinity,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: ElevatedButton.icon(
                    onPressed: onPickImage,
                    icon: const Icon(Icons.cached_rounded, size: 14),
                    label: const Text('Đổi ảnh', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            InkWell(
              onTap: onPickImage,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.camera_alt_rounded, size: 24, color: accentColor),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isDien ? 'Chụp ảnh công tơ điện' : 'Chụp ảnh đồng hồ nước',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: accentColor),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Chụp rõ mặt đồng hồ và dãy số để BQL nghiệm thu',
                      style: TextStyle(fontSize: 11, color: _textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceChecklistSection() {
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
            children: [
              const Icon(Icons.checklist_rtl_rounded, size: 18, color: _primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Kiểm kê thiết bị phòng',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${_danhSachThietBi.length - _soThietBiHuHong}/${_danhSachThietBi.length} đạt chuẩn',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: _soThietBiHuHong == 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          ...List.generate(_danhSachThietBi.length, (index) {
            final item = _danhSachThietBi[index];
            final ten = item['ten']?.toString() ?? 'Thiết bị';
            final IconData icon = item['icon'] as IconData? ?? Icons.devices_other_rounded;
            final bool isDat = item['isDatChuan'] as bool? ?? true;
            final double chiPhi = (item['chiPhi'] as num? ?? 0).toDouble();

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDat ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDat ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: isDat ? _primary : const Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ten,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _textDark),
                        ),
                        if (!isDat && chiPhi > 0)
                          Text(
                            'Khấu trừ bồi thường: ${FormatUtils.currency(chiPhi)}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        item['isDatChuan'] = !isDat;
                        if (item['isDatChuan'] == false && (item['chiPhi'] as num? ?? 0) == 0) {
                          item['chiPhi'] = 150000.0;
                        } else if (item['isDatChuan'] == true) {
                          item['chiPhi'] = 0.0;
                        }
                        _tinhToanQuyetToan();
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDat ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isDat ? 'Đạt chuẩn' : 'Báo hư hại',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDat ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFinancialSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDungHanHopDong ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
          width: 1.4,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, size: 18, color: _primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dự toán tài chính',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _textDark),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _isDungHanHopDong ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _isDungHanHopDong ? 'Đúng hạn (Hoàn 100%)' : 'Trước hạn (Mất cọc)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _isDungHanHopDong ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 8),

          if (_isDungHanHopDong) ...[
            // Trường hợp 1: Đúng hạn hợp đồng
            _buildInfoRow('Tiền đặt cọc ban đầu', FormatUtils.currency(_tienDatCoc), valueColor: const Color(0xFF16A34A), isBold: true),
            _buildInfoRow('Tiền điện chốt cuối', '- ${FormatUtils.currency(_tienDienCuoi)}', valueColor: const Color(0xFFDC2626)),
            _buildInfoRow('Tiền nước chốt cuối', '- ${FormatUtils.currency(_tienNuocCuoi)}', valueColor: const Color(0xFFDC2626)),
            if (_tongTienBoiThuongThietBi > 0)
              _buildInfoRow('Khấu trừ hư hại tài sản', '- ${FormatUtils.currency(_tongTienBoiThuongThietBi)}', valueColor: const Color(0xFFDC2626)),
            if (_canTruNoVaoTienCoc && _tongTienNoHoaDon > 0)
              _buildInfoRow('Khấu trừ hóa đơn nợ', '- ${FormatUtils.currency(_tongTienNoHoaDon)}', valueColor: const Color(0xFFDC2626)),
            const Divider(height: 16, color: Color(0xFFF1F5F9)),
            if (_tienCocHoanLai > 0)
              _buildInfoRow('DỰ KIẾN HOÀN TRẢ CỌC', FormatUtils.currency(_tienCocHoanLai), valueColor: const Color(0xFF16A34A), isBold: true)
            else
              _buildInfoRow('CẦN THANH TOÁN THÊM', FormatUtils.currency(_tienKhTraThem), valueColor: const Color(0xFFDC2626), isBold: true),
          ] else ...[
            // Trường hợp 2: Trước hạn hợp đồng
            _buildInfoRow('Tiền đặt cọc ban đầu', FormatUtils.currency(_tienDatCoc)),
            _buildInfoRow('Chính sách cọc', 'MẤT 100% TIỀN CỌC (0 đ)', valueColor: const Color(0xFFDC2626), isBold: true),
            _buildInfoRow('Tiền điện thực tế đến dọn đi', FormatUtils.currency(_tienDienCuoi), valueColor: const Color(0xFFDC2626)),
            _buildInfoRow('Tiền nước thực tế đến dọn đi', FormatUtils.currency(_tienNuocCuoi), valueColor: const Color(0xFFDC2626)),
            if (_tongTienBoiThuongThietBi > 0)
              _buildInfoRow('Bồi thường hư hại tài sản', FormatUtils.currency(_tongTienBoiThuongThietBi), valueColor: const Color(0xFFDC2626)),
            if (_tongTienNoHoaDon > 0)
              _buildInfoRow('Hóa đơn chưa thanh toán', FormatUtils.currency(_tongTienNoHoaDon), valueColor: const Color(0xFFDC2626)),
            const Divider(height: 16, color: Color(0xFFF1F5F9)),
            _buildInfoRow('TỔNG CƯ DÂN PHẢI THANH TOÁN', FormatUtils.currency(_tienKhTraThem), valueColor: const Color(0xFFDC2626), isBold: true),
          ],
        ],
      ),
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
                  const Text('BIÊN BẢN BÀN GIAO SỐ HÓA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 0.5)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (bb?.trangThai == 'Đã duyệt')
                          ? const Color(0xFFDCFCE7)
                          : (bb?.trangThai == 'Từ chối')
                              ? const Color(0xFFFEE2E2)
                              : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      (bb?.trangThai ?? 'Chờ duyệt').toUpperCase(),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: (bb?.trangThai == 'Đã duyệt')
                            ? const Color(0xFF16A34A)
                            : (bb?.trangThai == 'Từ chối')
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20, color: Color(0xFFF1F5F9)),

              // Phân loại trả phòng
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Phân loại trả phòng', style: TextStyle(fontSize: 12.5, color: _textMuted)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isDungHanHopDong ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _isDungHanHopDong ? 'Đúng hạn (Hoàn cọc 100%)' : 'Trước hạn (Mất cọc)',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: _isDungHanHopDong ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

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

              // Xem ảnh đồng hồ nếu có
              if (_anhDongHoDienBytes != null || _anhDongHoNuocBytes != null || bb?.anhDongHoDien != null || bb?.anhDongHoNuoc != null) ...[
                const SizedBox(height: 8),
                const Text('Ảnh chụp đồng hồ đối soát:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _textDark)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_anhDongHoDienBytes != null)
                      Expanded(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_anhDongHoDienBytes!, height: 80, width: double.infinity, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 4),
                            const Text('Đồng hồ điện', style: TextStyle(fontSize: 10.5, color: _textMuted)),
                          ],
                        ),
                      )
                    else if (bb?.anhDongHoDien != null && bb!.anhDongHoDien!.startsWith('http'))
                      Expanded(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(bb.anhDongHoDien!, height: 80, width: double.infinity, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 4),
                            const Text('Đồng hồ điện', style: TextStyle(fontSize: 10.5, color: _textMuted)),
                          ],
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (_anhDongHoNuocBytes != null)
                      Expanded(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(_anhDongHoNuocBytes!, height: 80, width: double.infinity, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 4),
                            const Text('Đồng hồ nước', style: TextStyle(fontSize: 10.5, color: _textMuted)),
                          ],
                        ),
                      )
                    else if (bb?.anhDongHoNuoc != null && bb!.anhDongHoNuoc!.startsWith('http'))
                      Expanded(
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(bb.anhDongHoNuoc!, height: 80, width: double.infinity, fit: BoxFit.cover),
                            ),
                            const SizedBox(height: 4),
                            const Text('Đồng hồ nước', style: TextStyle(fontSize: 10.5, color: _textMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],

              const Divider(height: 16, color: Color(0xFFF1F5F9)),

              _buildInfoRow('Tiền cọc ban đầu', FormatUtils.currency(_tienDatCoc)),
              _buildInfoRow(
                'Tiền cọc hoàn lại',
                _isHetHanHopDong ? FormatUtils.currency(bb?.tienCocHoanLai ?? _tienCocHoanLai) : '0 đ (Mất 100% cọc)',
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
            if (_currentStep == 0) ...[
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_isDungHanHopDong && _tienDatCoc > 0 && _soTaiKhoanController.text.trim().isEmpty) {
                        ThongBaoHelper.hienToast(
                          context,
                          tieuDe: 'Thiếu thông tin nhận cọc',
                          noiDung: 'Vui lòng nhập Số tài khoản ngân hàng để BQL chuyển hoàn tiền cọc!',
                          type: ThongBaoType.canhBao,
                        );
                        return;
                      }
                      setState(() {
                        _tinhToanQuyetToan();
                        _currentStep = 1;
                      });
                    },
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text(
                      'Tiếp Tục: Chốt Điện Nước & Bàn Giao',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ] else if (_currentStep == 1) ...[
              Expanded(
                flex: 1,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep = 0),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Quay lại', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () {
                          // 1. Kiểm tra chỉ số điện
                          final dienCuoi = double.tryParse(_chiSoDienCuoiController.text.trim());
                          if (dienCuoi == null || dienCuoi < _chiSoDienDau) {
                            ThongBaoHelper.hienToast(
                              context,
                              tieuDe: 'Chỉ số điện không hợp lệ',
                              noiDung: 'Số điện chốt cuối phải lớn hơn hoặc bằng ${_chiSoDienDau.toInt()} kWh!',
                              type: ThongBaoType.canhBao,
                            );
                            return;
                          }

                          // 2. Kiểm tra chỉ số nước
                          final nuocCuoi = double.tryParse(_chiSoNuocCuoiController.text.trim());
                          if (nuocCuoi == null || nuocCuoi < _chiSoNuocDau) {
                            ThongBaoHelper.hienToast(
                              context,
                              tieuDe: 'Chỉ số nước không hợp lệ',
                              noiDung: 'Số nước chốt cuối phải lớn hơn hoặc bằng ${_chiSoNuocDau.toInt()} m³!',
                              type: ThongBaoType.canhBao,
                            );
                            return;
                          }

                          // 3. Kiểm tra ảnh chụp đồng hồ đối soát
                          if (_anhDongHoDienBytes == null || _anhDongHoNuocBytes == null) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.camera_alt_outlined, color: Color(0xFFD97706)),
                                    SizedBox(width: 8),
                                    Text('Thiếu ảnh đồng hồ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: const Text(
                                  'Bạn chưa tải đủ ảnh đồng hồ điện và đồng hồ nước để đối soát. Bạn có muốn tiếp tục gửi biên bản không?',
                                  style: TextStyle(fontSize: 13, height: 1.4),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Chụp ảnh ngay', style: TextStyle(fontWeight: FontWeight.bold, color: _primary)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(ctx);
                                      _showConfirmSendRequestDialog();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD97706),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Vẫn gửi đơn'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }

                          _showConfirmSendRequestDialog();
                        },
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 16),
                  label: Text(
                    _isSubmitting ? 'Đang gửi...' : 'Gửi Biên Bản Bàn Giao',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size.fromHeight(48),
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
    final double dienCuoi = double.tryParse(_chiSoDienCuoiController.text.trim()) ?? _chiSoDienDau;
    final double nuocCuoi = double.tryParse(_chiSoNuocCuoiController.text.trim()) ?? _chiSoNuocDau;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xác nhận gửi biên bản bàn giao?', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Biên bản bàn giao ${widget.tenPhong} - Ngày dọn đi: $ngayTraStr',
              style: const TextStyle(fontSize: 13, height: 1.4, color: _textDark, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isDungHanHopDong ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _isDungHanHopDong ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isDungHanHopDong ? '1. Đúng hạn: HOÀN CỌC 100%' : '2. Trước hạn: MẤT 100% TIỀN CỌC',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: _isDungHanHopDong ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isDungHanHopDong
                        ? 'Dự kiến hoàn trả cọc: ${FormatUtils.currency(_tienCocHoanLai)}'
                        : 'Cư dân thanh toán tiền điện nước thực tế: ${FormatUtils.currency(_tienKhTraThem)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isDungHanHopDong ? const Color(0xFF166534) : const Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text('• Chỉ số điện chốt: ${dienCuoi.toInt()} kWh (${FormatUtils.currency(_tienDienCuoi)})', style: const TextStyle(fontSize: 12, color: _textDark)),
            const SizedBox(height: 3),
            Text('• Chỉ số nước chốt: ${nuocCuoi.toInt()} m³ (${FormatUtils.currency(_tienNuocCuoi)})', style: const TextStyle(fontSize: 12, color: _textDark)),
            const SizedBox(height: 3),
            Text(
              '• Ảnh chụp đối soát: ${_anhDongHoDienBytes != null ? "✓ Điện" : "✗ Thiếu điện"} | ${_anhDongHoNuocBytes != null ? "✓ Nước" : "✗ Thiếu nước"}',
              style: const TextStyle(fontSize: 12, color: _textDark),
            ),
            const SizedBox(height: 10),
            const Text(
              'Sau khi gửi, BQL sẽ nhận được biên bản đối soát và liên hệ hoàn tất thủ tục bàn giao.',
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
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: _textMuted),
            ),
          ),
          const SizedBox(width: 8),
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

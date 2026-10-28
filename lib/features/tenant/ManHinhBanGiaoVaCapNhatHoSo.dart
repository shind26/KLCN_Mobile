import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/DichVuQuetCccd.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhBanGiaoVaCapNhatHoSo extends StatefulWidget {
  final UserModel user;
  final String maKhach;
  final String maHopDong;
  final String maPhong;
  final Map<String, dynamic> khachThueData;
  final bool? isNguoiDaiDien;

  const ManHinhBanGiaoVaCapNhatHoSo({
    super.key,
    required this.user,
    required this.maKhach,
    required this.maHopDong,
    required this.maPhong,
    required this.khachThueData,
    this.isNguoiDaiDien,
  });

  @override
  State<ManHinhBanGiaoVaCapNhatHoSo> createState() =>
      _ManHinhBanGiaoVaCapNhatHoSoState();
}

class _ThongTinXe {
  String loaiXe;
  final TextEditingController bienSoController;
  final TextEditingController ghiChuController;

  _ThongTinXe({
    this.loaiXe = 'Xe tay ga',
    String bienSo = '',
    String ghiChu = '',
  }) : bienSoController = TextEditingController(text: bienSo),
       ghiChuController = TextEditingController(text: ghiChu);

  void dispose() {
    bienSoController.dispose();
    ghiChuController.dispose();
  }
}

class _ManHinhBanGiaoVaCapNhatHoSoState
    extends State<ManHinhBanGiaoVaCapNhatHoSo> {
  int _currentStep =
      0; // 0: CCCD & Cá nhân, 1: Phương tiện, 2: Biên bản bàn giao (nếu là đại diện)
  bool _isDaiDien = true;
  int get _totalSteps => _isDaiDien ? 3 : 2;

  // ── CONTROLLERS BƯỚC 1: CCCD & CÁ NHÂN ──
  late TextEditingController _hoTenController;
  late TextEditingController _soDtController;
  final _cccdController = TextEditingController();
  final _diaChiController = TextEditingController();
  final _nguoiLienHeController = TextEditingController();
  final _noiCapController = TextEditingController(
    text: 'Cục Cảnh sát QLHC về TTXH',
  );

  String _gioiTinh = 'Nam';
  DateTime? _ngaySinh;
  DateTime? _ngayCapCccd;

  // Ảnh CCCD
  final _picker = ImagePicker();
  Uint8List? _bytesMatTruoc;
  Uint8List? _bytesMatSau;
  String? _urlMatTruoc;
  String? _urlMatSau;
  bool _isScanningAi = false;

  // ── BƯỚC 2: PHƯƠNG TIỆN XE ──
  bool _coPhuongTien = true;
  final List<_ThongTinXe> _danhSachXe = [];

  // ── BƯỚC 3: BIÊN BẢN BÀN GIAO TÀI SẢN ──
  bool _isLoadingTaiSan = true;
  List<Map<String, dynamic>> _danhSachTaiSan = [];
  final _ghiChuBanGiaoController = TextEditingController();
  bool _camKetKiemTra = false;

  // Trạng thái lưu toàn bộ
  bool _isSubmitting = false;
  String? _submitProgressText;

  @override
  void initState() {
    super.initState();
    _isDaiDien = widget.isNguoiDaiDien ?? true;
    final kt = widget.khachThueData;
    _hoTenController = TextEditingController(
      text: kt['ho_ten_khach']?.toString() ?? widget.user.tenHienThi,
    );
    _soDtController = TextEditingController(
      text: kt['so_dt']?.toString() ?? widget.user.tenDangNhap,
    );
    _cccdController.text = kt['cccd']?.toString() ?? '';
    _diaChiController.text = kt['dia_chi_thuong_tru']?.toString() ?? '';
    _gioiTinh = (kt['gioi_tinh']?.toString() == 'Nữ') ? 'Nữ' : 'Nam';
    _nguoiLienHeController.text =
        kt['nguoi_lien_he_khan_cap']?.toString() ?? '';

    if (kt['ngay_sinh'] != null) {
      try {
        _ngaySinh = DateTime.parse(kt['ngay_sinh'].toString());
      } catch (_) {}
    }
    if (kt['ngay_cap_cccd'] != null) {
      try {
        _ngayCapCccd = DateTime.parse(kt['ngay_cap_cccd'].toString());
      } catch (_) {}
    }
    if (kt['noi_cap_cccd'] != null &&
        kt['noi_cap_cccd'].toString().trim().isNotEmpty) {
      _noiCapController.text = kt['noi_cap_cccd'].toString();
    }
    _urlMatTruoc = kt['anh_cccd_mat_truoc']?.toString();
    _urlMatSau = kt['anh_cccd_mat_sau']?.toString();

    // Mặc định khởi tạo 1 xe
    _danhSachXe.add(_ThongTinXe());

    if (_ghiChuBanGiaoController.text.trim().isEmpty) {
      _ghiChuBanGiaoController.text =
          'Đã kiểm tra và nhận đầy đủ thiết bị, tài sản phòng trong tình trạng hoạt động tốt theo danh mục bàn giao.';
    }

    // Tải danh sách tài sản phòng
    _loadTaiSanPhong();
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _soDtController.dispose();
    _cccdController.dispose();
    _diaChiController.dispose();
    _nguoiLienHeController.dispose();
    _noiCapController.dispose();
    _ghiChuBanGiaoController.dispose();
    for (var xe in _danhSachXe) {
      xe.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTaiSanPhong() async {
    setState(() => _isLoadingTaiSan = true);
    try {
      final db = Supabase.instance.client;
      try {
        final hd = await db
            .from('hop_dong')
            .select('da_xac_nhan_ban_giao, ma_khach_dai_dien')
            .eq('ma_hop_dong', widget.maHopDong)
            .maybeSingle();
        if (hd != null) {
          if (hd['da_xac_nhan_ban_giao'] == true) {
            _camKetKiemTra = true;
          }
          if (widget.isNguoiDaiDien == null) {
            final maDaiDien = hd['ma_khach_dai_dien']?.toString();
            if (maDaiDien != null && maDaiDien.isNotEmpty) {
              setState(() {
                _isDaiDien = (maDaiDien == widget.maKhach);
              });
            }
          }
        }
      } catch (_) {}

      if (widget.isNguoiDaiDien == null && !_isDaiDien) {
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
              setState(() => _isDaiDien = true);
            }
          }
        } catch (_) {}
      }

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

      // Nếu bảng tai_san chưa có dòng nào, lấy từ bảng phong (noi_that_san_co, tien_ich)
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
        _isLoadingTaiSan = false;
      });
    } catch (e) {
      debugPrint('Lỗi tải danh sách tài sản phòng: $e');
      setState(() => _isLoadingTaiSan = false);
    }
  }

  // ── XỬ LÝ CHỤP / CHỌN ẢNH CCCD & QUÉT AI OCR ──
  Future<void> _chonAnhCccd(ImageSource source, bool isMatTruoc) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      setState(() {
        if (isMatTruoc) {
          _bytesMatTruoc = bytes;
        } else {
          _bytesMatSau = bytes;
        }
      });

      // Nếu là mặt trước: Kích hoạt quét AI OCR tự động trích xuất thông tin
      if (isMatTruoc) {
        _thucHienQuetAiCccd(bytes);
      }
    } catch (e) {
      debugPrint('Lỗi chọn ảnh CCCD: $e');
    }
  }

  Future<void> _thucHienQuetAiCccd(Uint8List bytes) async {
    setState(() => _isScanningAi = true);

    try {
      final result = await DichVuQuetCccd.quetAnhCccdBytes(bytes);

      if (!mounted) return;
      setState(() => _isScanningAi = false);

      if (result != null && result.hopLe) {
        // Tự động điền thông tin trích xuất được
        if (result.soCccd.isNotEmpty) {
          _cccdController.text = result.soCccd;
        }
        if (result.hoTen.isNotEmpty) {
          _hoTenController.text = result.hoTen;
        }
        if (result.gioiTinh != null && result.gioiTinh!.isNotEmpty) {
          _gioiTinh = result.gioiTinh!;
        }
        if (result.diaChiThuongTru != null &&
            result.diaChiThuongTru!.isNotEmpty) {
          _diaChiController.text = result.diaChiThuongTru!;
        }
        if (result.ngaySinh != null && result.ngaySinh!.isNotEmpty) {
          try {
            // Định dạng dd/MM/yyyy
            final parts = result.ngaySinh!.split('/');
            if (parts.length == 3) {
              _ngaySinh = DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              );
            }
          } catch (_) {}
        }

        _showAiSuccessDialog(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể trích xuất tự động từ ảnh. Bạn vui lòng kiểm tra và điền thông tin bên dưới nhé!',
            ),
            backgroundColor: Color(0xFFD97706),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isScanningAi = false);
      debugPrint('Lỗi quét AI CCCD: $e');
    }
  }

  void _showAiSuccessDialog(KetQuaQuetCccd res) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF09638E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome, color: Color(0xFF09638E)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'AI Quét CCCD Thành Công',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Đã tự động trích xuất các thông tin sau từ ảnh CCCD:',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            _buildDialogRow(
              'Họ và tên:',
              res.hoTen.isNotEmpty ? res.hoTen : 'Chưa nhận diện',
            ),
            _buildDialogRow(
              'Số CCCD:',
              res.soCccd.isNotEmpty ? res.soCccd : 'Chưa nhận diện',
            ),
            if (res.gioiTinh != null)
              _buildDialogRow('Giới tính:', res.gioiTinh!),
            if (res.ngaySinh != null)
              _buildDialogRow('Ngày sinh:', res.ngaySinh!),
            if (res.diaChiThuongTru != null)
              _buildDialogRow('Thường trú:', res.diaChiThuongTru!),
            const SizedBox(height: 8),
            const Text(
              'Bạn có thể rà soát và chỉnh sửa lại các thông tin nếu cần.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Color(0xFF09638E),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF09638E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Đã hiểu & Tiếp tục'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF09638E),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _baoLoi(String msg) {
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Thông báo',
      noiDung: msg,
      type: ThongBaoType.canhBao,
    );
  }

  bool _kiemTraBuoc1({bool showError = true}) {
    final hoTen = _hoTenController.text.trim();
    final soDt = _soDtController.text.trim();
    final cccd = _cccdController.text.trim();
    final diaChi = _diaChiController.text.trim();
    final noiCap = _noiCapController.text.trim();
    final nguoiLienHe = _nguoiLienHeController.text.trim();
    final hasMatTruoc =
        _bytesMatTruoc != null ||
        (_urlMatTruoc != null && _urlMatTruoc!.isNotEmpty);
    final hasMatSau =
        _bytesMatSau != null || (_urlMatSau != null && _urlMatSau!.isNotEmpty);

    if (hoTen.isEmpty) {
      if (showError)
        _baoLoi('Vui lòng nhập Họ và tên khách thuê (không được bỏ trống)!');
      return false;
    }
    if (soDt.isEmpty) {
      if (showError)
        _baoLoi('Vui lòng nhập Số điện thoại liên hệ (không được bỏ trống)!');
      return false;
    }
    if (cccd.isEmpty) {
      if (showError)
        _baoLoi('Vui lòng nhập Số CCCD / Định danh (không được bỏ trống)!');
      return false;
    }
    if (cccd.length != 12 || !RegExp(r'^[0-9]{12}$').hasMatch(cccd)) {
      if (showError) _baoLoi('Số CCCD phải có đúng 12 chữ số hợp lệ!');
      return false;
    }
    if (_ngaySinh == null) {
      if (showError)
        _baoLoi('Vui lòng chọn Ngày sinh của bạn (không được bỏ trống)!');
      return false;
    }
    if (diaChi.isEmpty) {
      if (showError)
        _baoLoi(
          'Vui lòng nhập Địa chỉ thường trú theo CCCD (không được bỏ trống)!',
        );
      return false;
    }
    if (_ngayCapCccd == null) {
      if (showError)
        _baoLoi('Vui lòng chọn Ngày cấp CCCD (không được bỏ trống)!');
      return false;
    }
    if (noiCap.isEmpty) {
      if (showError)
        _baoLoi('Vui lòng nhập Nơi cấp CCCD (không được bỏ trống)!');
      return false;
    }
    if (nguoiLienHe.isEmpty) {
      if (showError)
        _baoLoi(
          'Vui lòng nhập Người & SĐT liên hệ khẩn cấp (không được bỏ trống)!',
        );
      return false;
    }
    if (!hasMatTruoc) {
      if (showError)
        _baoLoi('Vui lòng chụp hoặc tải lên ảnh Mặt trước CCCD (bắt buộc)!');
      return false;
    }
    if (!hasMatSau) {
      if (showError)
        _baoLoi('Vui lòng chụp hoặc tải lên ảnh Mặt sau CCCD (bắt buộc)!');
      return false;
    }
    return true;
  }

  bool _kiemTraBuoc2({bool showError = true}) {
    if (_coPhuongTien) {
      if (_danhSachXe.isEmpty) {
        if (showError)
          _baoLoi('Vui lòng thêm thông tin xe hoặc tắt tùy chọn gửi xe!');
        return false;
      }
      for (int i = 0; i < _danhSachXe.length; i++) {
        final xe = _danhSachXe[i];
        final bienSo = xe.bienSoController.text.trim();
        final ghiChu = xe.ghiChuController.text.trim();
        if (bienSo.isEmpty) {
          if (showError)
            _baoLoi(
              'Vui lòng nhập Biển số xe cho Phương tiện ${i + 1} (không được bỏ trống)!',
            );
          return false;
        }
        if (ghiChu.isEmpty) {
          if (showError)
            _baoLoi(
              'Vui lòng nhập Hãng xe / Màu sơn cho Phương tiện ${i + 1} (không được bỏ trống)!',
            );
          return false;
        }
      }
    }
    return true;
  }

  bool _kiemTraBuoc3({bool showError = true}) {
    if (!_isDaiDien) return true;
    if (_ghiChuBanGiaoController.text.trim().isEmpty) {
      if (showError)
        _baoLoi(
          'Vui lòng nhập Ghi chú / Nhận xét khi nhận bàn giao phòng (không được bỏ trống)!',
        );
      return false;
    }
    if (!_camKetKiemTra) {
      if (showError)
        _baoLoi(
          'Vui lòng tích cam kết đã kiểm tra và đồng ý nhận bàn giao tài sản!',
        );
      return false;
    }
    return true;
  }

  // ── HOÀN TẤT & LƯU TOÀN BỘ VÀO SUPABASE ──
  Future<void> _hoanTatXacNhan() async {
    // 1. Kiểm tra nghiêm ngặt toàn bộ các bước không được bỏ trống bất kỳ ô nào
    if (!_kiemTraBuoc1()) {
      setState(() => _currentStep = 0);
      return;
    }
    if (!_kiemTraBuoc2()) {
      setState(() => _currentStep = 1);
      return;
    }
    if (_isDaiDien && !_kiemTraBuoc3()) {
      setState(() => _currentStep = 2);
      return;
    }

    final hoTen = _hoTenController.text.trim();
    final soDt = _soDtController.text.trim();
    final cccd = _cccdController.text.trim();
    final diaChi = _diaChiController.text.trim();

    setState(() {
      _isSubmitting = true;
      _submitProgressText =
          'Đang tải ảnh CCCD và đồng bộ hồ sơ lên Supabase...';
    });

    try {
      final db = Supabase.instance.client;

      // ── BƯỚC A: TẢI ẢNH CCCD LÊN STORAGE HOẶC FALLBACK BASE64 (CHỈ KHI CÓ CHỌN MỚI) ──
      String? uploadedUrlMatTruoc;
      String? uploadedUrlMatSau;

      if (_bytesMatTruoc != null) {
        try {
          final path =
              'cccd/${widget.maKhach}_truoc_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await db.storage
              .from('contracts')
              .uploadBinary(
                path,
                _bytesMatTruoc!,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              )
              .timeout(const Duration(seconds: 8));
          uploadedUrlMatTruoc = db.storage.from('contracts').getPublicUrl(path);
        } catch (eStorage) {
          debugPrint(
            'Storage upload mặt trước lỗi: $eStorage -> Fallback Base64 an toàn',
          );
          uploadedUrlMatTruoc =
              'data:image/jpeg;base64,${base64Encode(_bytesMatTruoc!)}';
        }
      }

      if (_bytesMatSau != null) {
        try {
          final path =
              'cccd/${widget.maKhach}_sau_${DateTime.now().millisecondsSinceEpoch}.jpg';
          await db.storage
              .from('contracts')
              .uploadBinary(
                path,
                _bytesMatSau!,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              )
              .timeout(const Duration(seconds: 8));
          uploadedUrlMatSau = db.storage.from('contracts').getPublicUrl(path);
        } catch (eStorage) {
          debugPrint(
            'Storage upload mặt sau lỗi: $eStorage -> Fallback Base64 an toàn',
          );
          uploadedUrlMatSau =
              'data:image/jpeg;base64,${base64Encode(_bytesMatSau!)}';
        }
      }

      // ── BƯỚC B: CẬP NHẬT BẢNG khach_thue (LƯU LÊN SUPABASE) ──
      setState(() => _submitProgressText = 'Cập nhật hồ sơ khách thuê...');
      final Map<String, dynamic> updateKt = {
        'ho_ten_khach': hoTen,
        'so_dt': soDt,
        'cccd': cccd,
        'gioi_tinh': _gioiTinh,
        'dia_chi_thuong_tru': diaChi,
        'noi_cap_cccd': _noiCapController.text.trim(),
        'trang_thai_ekyc': 'DaXacThuc',
        'nguoi_lien_he_khan_cap': _nguoiLienHeController.text.trim(),
      };
      if (_ngaySinh != null) {
        updateKt['ngay_sinh'] = DateFormat('yyyy-MM-dd').format(_ngaySinh!);
      }
      if (_ngayCapCccd != null) {
        updateKt['ngay_cap_cccd'] = DateFormat(
          'yyyy-MM-dd',
        ).format(_ngayCapCccd!);
      }
      if (uploadedUrlMatTruoc != null) {
        updateKt['anh_cccd_mat_truoc'] = uploadedUrlMatTruoc;
      }
      if (uploadedUrlMatSau != null) {
        updateKt['anh_cccd_mat_sau'] = uploadedUrlMatSau;
      }

      // Xử lý chống xung đột UNIQUE CCCD (khach_thue_cccd_key)
      if (cccd.isNotEmpty) {
        try {
          final dupKt = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('cccd', cccd)
              .neq('ma_khach', widget.maKhach)
              .maybeSingle();

          if (dupKt != null && dupKt['ma_khach'] != null) {
            final oldMaKhach = dupKt['ma_khach'].toString();
            debugPrint(
              'Phát hiện trùng CCCD với hồ sơ cũ $oldMaKhach, đang giải phóng CCCD cũ để cập nhật hồ sơ mới...',
            );
            await db
                .from('khach_thue')
                .update({'cccd': null})
                .eq('ma_khach', oldMaKhach);
          }
        } catch (eDup) {
          debugPrint('Lỗi kiểm tra giải phóng trùng CCCD: $eDup');
        }
      }

      await db
          .from('khach_thue')
          .update(updateKt)
          .eq('ma_khach', widget.maKhach);

      // ── BƯỚC C: LƯU PHƯƠNG TIỆN XE (NẾU CÓ) ──
      if (_coPhuongTien && _danhSachXe.isNotEmpty) {
        setState(
          () => _submitProgressText = 'Đăng ký thông tin phương tiện xe...',
        );
        // Xóa phương tiện cũ của khách thuê này để tránh trùng lặp
        try {
          await db.from('phuong_tien').delete().eq('ma_khach', widget.maKhach);
        } catch (_) {}

        for (final xe in _danhSachXe) {
          final bienSo = xe.bienSoController.text.trim();
          final ghiChu = xe.ghiChuController.text.trim();
          if (bienSo.isNotEmpty) {
            final maPt = 'PT${Random().nextInt(900000) + 100000}';
            await db.from('phuong_tien').upsert({
              'ma_phuong_tien': maPt,
              'ma_khach': widget.maKhach,
              'ma_phong': widget.maPhong,
              'loai_xe': xe.loaiXe,
              'bien_so_xe': bienSo,
              'ghi_chu': ghiChu,
              'ma_the_xe': null,
              'trang_thai': 'Hoạt động',
              'ngay_dang_ky': DateTime.now().toIso8601String(),
            });
          }
        }
      }

      // ── BƯỚC D: XÁC NHẬN BÀN GIAO TÀI SẢN TRONG BẢNG hop_dong (CHỈ DÀNH CHO NGƯỜI ĐẠI DIỆN HỢP ĐỒNG) ──
      if (_isDaiDien) {
        setState(() => _submitProgressText = 'Ký biên bản bàn giao tài sản...');
        final nowStr = DateTime.now().toIso8601String();
        await db
            .from('hop_dong')
            .update({
              'da_xac_nhan_ban_giao': true,
              'ngay_xac_nhan_ban_giao': nowStr,
            })
            .eq('ma_hop_dong', widget.maHopDong);
      }

      // ── BƯỚC E: LẤY VAI TRÒ TỪ chi_tiet_hop_dong_khach_thue GÁN XUỐNG tai_khoan ──
      setState(() => _submitProgressText = 'Đồng bộ vai trò tài khoản...');
      String vaiTroGan = _isDaiDien ? 'Đại diện hợp đồng' : 'Thành viên ở cùng';
      try {
        final cthd = await db
            .from('chi_tiet_hop_dong_khach_thue')
            .select('vai_tro')
            .eq('ma_hop_dong', widget.maHopDong)
            .eq('ma_khach', widget.maKhach)
            .maybeSingle();

        if (cthd != null &&
            cthd['vai_tro'] != null &&
            cthd['vai_tro'].toString().trim().isNotEmpty) {
          vaiTroGan = cthd['vai_tro'].toString();
        } else {
          // Nếu là người ký đại diện trong hop_dong
          final hdCheck = await db
              .from('hop_dong')
              .select('ma_khach_dai_dien')
              .eq('ma_hop_dong', widget.maHopDong)
              .maybeSingle();
          if (hdCheck?['ma_khach_dai_dien']?.toString() == widget.maKhach) {
            vaiTroGan = 'Đại diện hợp đồng';
          } else {
            vaiTroGan = 'Thành viên ở cùng';
          }
        }
      } catch (e) {
        debugPrint('Lỗi truy vấn vai trò chi tiết hợp đồng: $e');
        vaiTroGan = _isDaiDien ? 'Đại diện hợp đồng' : 'Thành viên ở cùng';
      }

      // Cập nhật xuống bảng tai_khoan
      await db
          .from('tai_khoan')
          .update({'vai_tro': vaiTroGan, 'ho_ten': hoTen})
          .eq('ma_tai_khoan', widget.user.maTaiKhoan);

      // Cập nhật phiên đăng nhập cục bộ
      final updatedUser = widget.user.copyWith(vaiTro: vaiTroGan, hoTen: hoTen);
      await AuthService.updateCurrentUser(updatedUser);

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Hiển thị Popup hoàn tất và chuyển vào trang chủ cư dân
      _hienThiPopupThanhCong(updatedUser, vaiTroGan);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi hoàn tất hồ sơ',
          noiDung: 'Lỗi trong quá trình hoàn tất: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  void _hienThiPopupThanhCong(UserModel updatedUser, String vaiTro) {
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
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF09638E).withValues(alpha: 0.25),
                  blurRadius: 32,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.task_alt_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isDaiDien
                      ? 'Bàn Giao & Nhận Phòng Thành Công!'
                      : 'Hoàn Tất Hồ Sơ Cư Dân Thành Công!',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _isDaiDien
                      ? 'Chúc mừng ${updatedUser.tenHienThi} đã hoàn tất thủ tục cư dân và nhận bàn giao phòng ${widget.maPhong}.'
                      : 'Chúc mừng ${updatedUser.tenHienThi} đã hoàn tất khai báo thông tin cư dân phòng ${widget.maPhong}.',
                  style: const TextStyle(
                    fontSize: 14,
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
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.badge_rounded,
                        size: 18,
                        color: Color(0xFF0369A1),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Vai trò: $vaiTro',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0369A1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogCtx);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TenantHomeScreen(
                            tenantName: updatedUser.tenHienThi,
                          ),
                        ),
                        (route) => false,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09638E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Vào trang quản lý phòng của tôi →',
                      style: TextStyle(
                        fontSize: 15,
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
    if (widget.isNguoiDaiDien != null) {
      _isDaiDien = widget.isNguoiDaiDien!;
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF0F172A),
            size: 19,
          ),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          _isDaiDien ? 'Thủ Tục Cư Dân & Bàn Giao' : 'Thủ Tục Hồ Sơ Cư Dân',
          style: const TextStyle(
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
          Column(
            children: [
              // ── THANH TIẾN TRÌNH BƯỚC ──
              _buildStepperHeader(),

              // ── NỘI DUNG TỪNG BƯỚC ──
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  child: _buildStepContent(),
                ),
              ),
            ],
          ),

          // ── THANH ĐIỀU HƯỚNG DƯỚI CÙNG (BOTTOM ACTION BAR) ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomActionBar(),
          ),

          // ── OVERLAY LOADING KHI LƯU ──
          if (_isSubmitting)
            Container(
              color: Colors.black.withValues(alpha: 0.6),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF09638E)),
                      const SizedBox(height: 18),
                      Text(
                        _submitProgressText ?? 'Đang xử lý...',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── STEPPER HEADER HIỆN ĐẠI & TINH TẾ ──
  Widget _buildStepperHeader() {
    final stepNames = _isDaiDien
        ? ['Định danh eKYC', 'Phương tiện xe', 'Bàn giao tài sản']
        : ['Định danh eKYC', 'Phương tiện xe'];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          // Tiêu đề bước & Tiến độ
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF09638E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Bước ${_currentStep + 1}/$_totalSteps',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF09638E),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentStep < stepNames.length
                      ? stepNames[_currentStep]
                      : '',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Text(
                '${((_currentStep + 1) / _totalSteps * 100).toInt()}% hoàn thành',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Thẻ phân đoạn bước (Segmented Steps)
          Row(
            children: [
              _buildStepItem(0, '1. CCCD & eKYC', Icons.badge_rounded),
              const SizedBox(width: 8),
              _buildStepItem(1, '2. Phương tiện', Icons.two_wheeler_rounded),
              if (_isDaiDien) ...[
                const SizedBox(width: 8),
                _buildStepItem(
                  2,
                  '3. Bàn giao',
                  Icons.assignment_turned_in_rounded,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(int stepIndex, String title, IconData icon) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;

    Color bg;
    Color border;
    Color fg;

    if (isActive) {
      bg = const Color(0xFFE0F2FE);
      border = const Color(0xFF0284C7);
      fg = const Color(0xFF0284C7);
    } else if (isDone) {
      bg = const Color(0xFFECFDF5);
      border = const Color(0xFF10B981);
      fg = const Color(0xFF059669);
    } else {
      bg = const Color(0xFFF8FAFC);
      border = const Color(0xFFE2E8F0);
      fg = const Color(0xFF94A3B8);
    }

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (stepIndex == _currentStep) return;
          if (stepIndex < _currentStep) {
            setState(() => _currentStep = stepIndex);
            return;
          }
          if (stepIndex == 1) {
            if (!_kiemTraBuoc1()) return;
            setState(() => _currentStep = 1);
          } else if (stepIndex == 2 && _isDaiDien) {
            if (!_kiemTraBuoc1()) return;
            if (!_kiemTraBuoc2()) {
              setState(() => _currentStep = 1);
              return;
            }
            setState(() => _currentStep = 2);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: isActive ? 1.5 : 1.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDone ? Icons.check_circle_rounded : icon,
                color: fg,
                size: 15,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isActive || isDone
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: isActive
                        ? const Color(0xFF0F172A)
                        : (isDone
                              ? const Color(0xFF047857)
                              : const Color(0xFF64748B)),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Cccd();
      case 1:
        return _buildStep2PhuongTien();
      case 2:
        return _isDaiDien
            ? _buildStep3BanGiaoTaiSan()
            : const SizedBox.shrink();
      default:
        return const SizedBox.shrink();
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // BƯỚC 1: CẬP NHẬT THÔNG TIN CCCD & AI SCAN
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildStep1Cccd() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isDaiDien)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bạn là khách ở cùng phòng. Vui lòng hoàn tất thông tin cá nhân và phương tiện xe. Biên bản bàn giao tài sản phòng sẽ do người đại diện hợp đồng xác nhận.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF1E40AF),
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Banner hướng dẫn
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE0F2FE), Color(0xFFF0FDF4)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBAE6FD)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF09638E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quét AI CCCD tự động điền thông tin',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tải ảnh mặt trước CCCD để AI tự động trích xuất Họ tên, Số CCCD, Địa chỉ & Ngày sinh.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2 Khung chụp ảnh CCCD
        Row(
          children: [
            Expanded(
              child: _buildCccdBox(
                isMatTruoc: true,
                title: 'Mặt trước CCCD',
                subtitle: 'AI tự động quét',
                bytes: _bytesMatTruoc,
                url: _urlMatTruoc,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildCccdBox(
                isMatTruoc: false,
                title: 'Mặt sau CCCD',
                subtitle: 'Chụp rõ nét',
                bytes: _bytesMatSau,
                url: _urlMatSau,
              ),
            ),
          ],
        ),

        if (_isScanningAi) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF09638E),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AI đang đọc và bóc tách dữ liệu CCCD...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E40AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── FORM CẬP NHẬT CÁ NHÂN ──
        _buildSectionCard(
          title: 'Thông Tin Định Danh Khách Thuê',
          icon: Icons.person_pin_rounded,
          children: [
            _buildTextField(
              controller: _hoTenController,
              label: 'Họ và tên khách thuê *',
              hint: 'Ví dụ: NGUYỄN VĂN A',
              icon: Icons.person_rounded,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _soDtController,
              label: 'Số điện thoại liên hệ *',
              hint: 'Số điện thoại',
              icon: Icons.phone_android_rounded,
              readOnly: true,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _cccdController,
              label: 'Số CCCD / Định danh (12 số) *',
              hint: 'Ví dụ: 079201012345',
              icon: Icons.badge_rounded,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),

            // Giới tính
            const Text(
              'Giới tính *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildGenderChip('Nam', Icons.male_rounded),
                const SizedBox(width: 12),
                _buildGenderChip('Nữ', Icons.female_rounded),
              ],
            ),
            const SizedBox(height: 12),

            // Ngày sinh
            _buildDatePickerField(
              label: 'Ngày sinh (theo CCCD) *',
              currentDate: _ngaySinh,
              onSelected: (d) => setState(() => _ngaySinh = d),
              icon: Icons.cake_rounded,
            ),
            const SizedBox(height: 12),

            _buildTextField(
              controller: _diaChiController,
              label: 'Địa chỉ thường trú (theo CCCD) *',
              hint: 'Xã/Phường, Quận/Huyện, Tỉnh/TP',
              icon: Icons.home_rounded,
              maxLines: 2,
            ),
            const SizedBox(height: 12),

            // Ngày cấp & Nơi cấp
            Row(
              children: [
                Expanded(
                  child: _buildDatePickerField(
                    label: 'Ngày cấp CCCD *',
                    currentDate: _ngayCapCccd,
                    onSelected: (d) => setState(() => _ngayCapCccd = d),
                    icon: Icons.event_available_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTextField(
                    controller: _noiCapController,
                    label: 'Nơi cấp CCCD *',
                    hint: 'Cục Cảnh sát QLHC...',
                    icon: Icons.account_balance_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildTextField(
              controller: _nguoiLienHeController,
              label: 'Người & SĐT liên hệ khẩn cấp *',
              hint: 'Ví dụ: Bố Nguyễn Văn B - 0912345678',
              icon: Icons.emergency_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderChip(String gender, IconData icon) {
    final isSelected = _gioiTinh == gender;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _gioiTinh = gender),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF09638E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF09638E)
                  : const Color(0xFFCBD5E1),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Text(
                gender,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCccdBox({
    required bool isMatTruoc,
    required String title,
    required String subtitle,
    Uint8List? bytes,
    String? url,
  }) {
    final hasImage = bytes != null || (url != null && url.isNotEmpty);

    return InkWell(
      onTap: () => _hienThiModalChonAnh(isMatTruoc),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasImage ? const Color(0xFF09638E) : const Color(0xFFCBD5E1),
            width: hasImage ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (bytes != null)
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            else if (url != null && url.isNotEmpty)
              url.startsWith('data:image')
                  ? Image.memory(
                      base64Decode(
                        url.contains(',') ? url.split(',').last : url,
                      ),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(
                          Icons.broken_image_rounded,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: Color(0xFF09638E),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            if (hasImage)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF09638E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _hienThiModalChonAnh(bool isMatTruoc) {
    showModalBottomSheet(
      context: context,
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
                'Tải ảnh ${isMatTruoc ? 'Mặt trước' : 'Mặt sau'} CCCD',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: Color(0xFF09638E),
                ),
                title: const Text('Chụp ảnh trực tiếp từ Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _chonAnhCccd(ImageSource.camera, isMatTruoc);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF09638E),
                ),
                title: const Text('Chọn ảnh từ Thư viện'),
                onTap: () {
                  Navigator.pop(ctx);
                  _chonAnhCccd(ImageSource.gallery, isMatTruoc);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // BƯỚC 2: KHAI BÁO PHƯƠNG TIỆN XE
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildStep2PhuongTien() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Switch có xe / không có xe
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF09638E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.two_wheeler_rounded,
                  color: Color(0xFF09638E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tôi có phương tiện xe gửi tại trọ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Bật tùy chọn này để khai báo biển số xe và cấp thẻ gửi xe.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _coPhuongTien,
                onChanged: (val) {
                  setState(() {
                    _coPhuongTien = val;
                    if (val && _danhSachXe.isEmpty) {
                      _danhSachXe.add(_ThongTinXe());
                    }
                  });
                },
                activeColor: const Color(0xFF09638E),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        if (!_coPhuongTien)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(
                    Icons.directions_walk_rounded,
                    size: 40,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Bạn đã chọn không đăng ký phương tiện',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF475569),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Nếu sau này bạn có xe mới, bạn hoàn toàn có thể đăng ký bổ sung trong mục "Quản lý xe" bất cứ lúc nào.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else ...[
          // Danh sách các xe
          for (int i = 0; i < _danhSachXe.length; i++) ...[
            _buildCarCard(i),
            const SizedBox(height: 12),
          ],

          if (_danhSachXe.length < 3)
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _danhSachXe.add(_ThongTinXe()));
              },
              icon: const Icon(Icons.add_rounded),
              label: Text('Thêm phương tiện thứ ${_danhSachXe.length + 1}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF09638E),
                side: const BorderSide(color: Color(0xFF09638E), width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildCarCard(int index) {
    final xe = _danhSachXe[index];
    final loaiXeOptions = [
      'Xe tay ga',
      'Xe máy số',
      'Xe máy điện',
      'Xe đạp điện',
      'Ô tô',
      'Khác',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.moped_rounded,
                      color: Color(0xFF09638E),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Phương tiện ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (_danhSachXe.length > 1)
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      xe.dispose();
                      _danhSachXe.removeAt(index);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Chọn loại xe
          const Text(
            'Loại xe *',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: xe.loaiXe,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
            ),
            items: loaiXeOptions
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => xe.loaiXe = val);
            },
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: xe.bienSoController,
            label: 'Biển số xe *',
            hint: 'Ví dụ: 59-X1 234.56',
            icon: Icons.pin_rounded,
          ),
          const SizedBox(height: 12),

          _buildTextField(
            controller: xe.ghiChuController,
            label: 'Hãng xe / Màu sơn *',
            hint: 'Ví dụ: Honda Vision màu đỏ',
            icon: Icons.palette_rounded,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // BƯỚC 3: BIÊN BẢN BÀN GIAO TÀI SẢN PHÒNG
  // ══════════════════════════════════════════════════════════════════════
  Widget _buildStep3BanGiaoTaiSan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Biên bản header dạng trang trọng
        // Khung biên bản trang trọng
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF09638E).withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 1.8,
                      color: const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 0.6,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 1.8,
                      color: const Color(0xFFDC2626),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Độc lập - Tự do - Hạnh phúc',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  color: Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'BIÊN BẢN BÀN GIAO TRANG THIẾT BỊ & TÀI SẢN',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  color: Color(0xFF09638E),
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.meeting_room_rounded,
                        size: 14,
                        color: Color(0xFF09638E),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Phòng: ${widget.maPhong}  •  Hợp đồng: ${widget.maHopDong}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 22, color: Color(0xFFE2E8F0)),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.business_rounded,
                          size: 15,
                          color: Color(0xFF09638E),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Bên giao:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'BQL Nhà Trọ Kiêu Giang',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0F172A),
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
                          size: 15,
                          color: Color(0xFF09638E),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Bên nhận:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Color(0xFF334155),
                          ),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${_hoTenController.text.trim()} (${_soDtController.text.trim()})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
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

        const SizedBox(height: 16),

        // DANH SÁCH TÀI SẢN LẤY TỪ BẢNG tai_san (Đã fix hoàn toàn lỗi tràn 43px màn hình)
        Row(
          children: [
            const Icon(
              Icons.inventory_2_rounded,
              color: Color(0xFF09638E),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF09638E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_danhSachTaiSan.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF09638E),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

        if (_isLoadingTaiSan)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Color(0xFF09638E)),
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
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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
        _buildTextField(
          controller: _ghiChuBanGiaoController,
          label: 'Ghi chú / Nhận xét của cư dân khi nhận phòng *',
          hint: 'Ví dụ: Phòng sạch đẹp, thiết bị đầy đủ nguyên vẹn...',
          icon: Icons.notes_rounded,
          maxLines: 2,
        ),

        const SizedBox(height: 16),

        // Checkbox cam kết bàn giao
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0FDF4), Color(0xFFDCFCE7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF86EFAC), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
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
        ),
      ],
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
                      Flexible(
                        child: Container(
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
                              Flexible(
                                child: Text(
                                  thuongHieu,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1D4ED8),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
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

  // ── BOTTOM ACTION BAR ──
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        child: Row(
          children: [
            if (_currentStep > 0)
              OutlinedButton(
                onPressed: () {
                  setState(() => _currentStep--);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF475569),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                child: const Text('← Quay lại'),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  if (_currentStep == 0) {
                    if (!_kiemTraBuoc1()) return;
                    setState(() => _currentStep = 1);
                  } else if (_currentStep == 1) {
                    if (!_kiemTraBuoc2()) return;
                    if (_isDaiDien) {
                      setState(() => _currentStep = 2);
                    } else {
                      _hoanTatXacNhan();
                    }
                  } else {
                    _hoanTatXacNhan();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF09638E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isDaiDien
                        ? (_currentStep == 2
                              ? 'Ký & Xác Nhận Bàn Giao Phòng ✓'
                              : 'Tiếp tục sang ${_currentStep == 0 ? "Phương tiện xe" : "Biên bản bàn giao"} →')
                        : (_currentStep == 1
                              ? 'Hoàn Tất Hồ Sơ Cư Dân ✓'
                              : 'Tiếp tục sang Phương tiện xe →'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HELPER WIDGETS ──
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF09638E), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool readOnly = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 13,
            color: readOnly ? const Color(0xFF64748B) : const Color(0xFF0F172A),
            fontWeight: readOnly ? FontWeight.w500 : FontWeight.normal,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF09638E)),
            filled: readOnly,
            fillColor: readOnly ? const Color(0xFFF1F5F9) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF09638E),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerField({
    required String label,
    required DateTime? currentDate,
    required Function(DateTime) onSelected,
    required IconData icon,
  }) {
    final text = currentDate != null
        ? DateFormat('dd/MM/yyyy').format(currentDate)
        : 'Chọn ngày...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: currentDate ?? DateTime(2000, 1, 1),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (picked != null) onSelected(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF09638E)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      color: currentDate != null
                          ? const Color(0xFF0F172A)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nhatro_kieugiang/core/services/DichVuQuetCccd.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/data/models/KhachLuuTruModel.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuLuuTru.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhXacNhanDangKyKhach.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhDangKyKhachQuaDem extends StatefulWidget {
  final String tenPhong;
  final String toaNha;

  const ManHinhDangKyKhachQuaDem({
    super.key,
    this.tenPhong = 'Phòng 203',
    this.toaNha = 'Kiêu Giang 2',
  });

  @override
  State<ManHinhDangKyKhachQuaDem> createState() =>
      _ManHinhDangKyKhachQuaDemState();
}

class _ManHinhDangKyKhachQuaDemState extends State<ManHinhDangKyKhachQuaDem>
    with TickerProviderStateMixin {
  late AnimationController _laserController;
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  final _formKey = GlobalKey<FormState>();

  // 1. Ô NHẬP LIỆU
  final _tenController = TextEditingController();
  final _cccdController = TextEditingController();
  final _sdtController = TextEditingController();

  DateTime _ngayDen = DateTime.now();
  DateTime _ngayDi = DateTime.now().add(const Duration(days: 1));

  String _moiQuanHe = 'Người thân';
  bool _camKet = false;

  // 2. BIẾN LƯU ẢNH CCCD (TƯƠNG THÍCH CẢ WEB VÀ MOBILE)
  File? _anhCccdMatTruoc;
  File? _anhCccdMatSau;
  Uint8List? _bytesCccdMatTruoc;
  Uint8List? _bytesCccdMatSau;
  String? _pathCccdMatTruoc;
  String? _pathCccdMatSau;

  // 3. TRẠNG THÁI QUÉT AI OCR & SUBMIT
  bool _isScanningCccd = false;
  String? _thongBaoQuetThanhCong;
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();
  final List<String> _danhSachQuanHe = [
    'Người thân',
    'Bạn bè',
    'Đồng nghiệp',
    'Khác',
  ];

  int get _soDemLuuTru {
    final diff = _ngayDi.difference(_ngayDen).inDays;
    return diff > 0 ? diff : 1;
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  // Chọn ngày (Khóa tối đa dưới 30 ngày theo Luật Cư trú)
  Future<void> _chonNgay(BuildContext context, bool isNgayDen) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isNgayDen ? _ngayDen : _ngayDi,
      firstDate: isNgayDen
          ? DateTime.now().subtract(const Duration(days: 1))
          : _ngayDen.add(const Duration(days: 1)),
      lastDate: DateTime(2030, 12, 31), // Cho phép chọn thoải mái
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: const ColorScheme.light(primary: _primary)),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isNgayDen) {
          _ngayDen = picked;
          if (_ngayDi.isBefore(_ngayDen)) {
            _ngayDi = _ngayDen.add(const Duration(days: 1));
          }
        } else {
          if (picked.isAfter(_ngayDen)) {
            _ngayDi = picked;
          }
        }
      });
    }
  }

  // BottomSheet chọn Camera hoặc Thư viện ảnh
  void _chonNguonAnh(bool isMatTruoc) {
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
                'Tải lên ${isMatTruoc ? 'Mặt trước (Tự động quét thông tin)' : 'Mặt sau'} CCCD',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: _primary,
                ),
                title: const Text('Chọn ảnh từ Thư viện (Bộ sưu tập)'),
                subtitle: isMatTruoc
                    ? const Text(
                        'AI sẽ tự động đọc Họ tên & Số CCCD từ ảnh',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0284C7),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _chupHoacChonAnh(ImageSource.gallery, isMatTruoc);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: _primary),
                title: const Text('Chụp ảnh trực tiếp bằng Camera'),
                subtitle: isMatTruoc
                    ? const Text(
                        'Chụp rõ nét mặt trước để AI quét thông tin',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0284C7),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _chupHoacChonAnh(ImageSource.camera, isMatTruoc);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chupHoacChonAnh(ImageSource source, bool isMatTruoc) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          if (isMatTruoc) {
            _bytesCccdMatTruoc = bytes;
            _pathCccdMatTruoc = pickedFile.path;
            if (!kIsWeb) {
              _anhCccdMatTruoc = File(pickedFile.path);
            }
          } else {
            _bytesCccdMatSau = bytes;
            _pathCccdMatSau = pickedFile.path;
            if (!kIsWeb) {
              _anhCccdMatSau = File(pickedFile.path);
            }
          }
        });

        // NẾU LÀ MẶT TRƯỚC CCCD: TỰ ĐỘNG QUÉT AI OCR TRÍCH XUẤT HỌ TÊN VÀ SỐ CCCD!
        if (isMatTruoc) {
          _thucHienQuetCccd(bytes);
        }
      }
    } catch (e) {
      debugPrint('Lỗi chọn ảnh: $e');
    }
  }

  // TỰ ĐỘNG QUÉT CCCD BẰNG AI
  Future<void> _thucHienQuetCccd(Uint8List bytes) async {
    setState(() {
      _isScanningCccd = true;
      _thongBaoQuetThanhCong = null;
    });

    // Da chuyen thong bao dang quet hien thi o chinh giua man hinh (Stack modal)

    final ketQua = await DichVuQuetCccd.quetAnhCccdBytes(bytes);

    if (!mounted) return;

    setState(() {
      _isScanningCccd = false;
    });

    if (ketQua != null && ketQua.hopLe) {
      setState(() {
        if (ketQua.hoTen.isNotEmpty) {
          _tenController.text = ketQua.hoTen;
        }
        if (ketQua.soCccd.isNotEmpty) {
          _cccdController.text = ketQua.soCccd;
        }
        _thongBaoQuetThanhCong =
            'Đã quét thành công: ${ketQua.hoTen.isNotEmpty ? ketQua.hoTen : 'CCCD ${ketQua.soCccd}'}';
      });

      // HIỂN THỊ THÔNG BÁO Ở GIỮA MÀN HÌNH (POPUP DIALOG)
      _hienThiPopupQuetThanhCong(ketQua.hoTen, ketQua.soCccd);
    } else {
      // Trường hợp ảnh mờ hoặc không nhận diện được
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Ảnh chưa rõ nét',
        noiDung:
            'Ảnh chụp chưa rõ hoặc không tìm thấy CCCD. Bạn vui lòng chụp lại mặt trước CCCD rõ nét hơn để AI quét thông tin nhé!',
        type: ThongBaoType.canhBao,
        duration: const Duration(seconds: 3),
      );
    }
  }

  // DIALOG THÔNG BÁO Ở GIỮA MÀN HÌNH KHI QUÉT THÀNH CÔNG
  void _hienThiPopupQuetThanhCong(String hoTen, String soCccd) {
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
                    color: const Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF86EFAC),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF16A34A),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Quét CCCD Thành Công!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'AI đã trích xuất thông tin khách lưu trú từ ảnh CCCD:',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 17,
                            color: Color(0xFF09638E),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Họ tên:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hoTen.isNotEmpty ? hoTen : '(Chưa nhận diện)',
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
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Divider(height: 1, color: Color(0xFFE2E8F0)),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.badge_outlined,
                            size: 17,
                            color: Color(0xFF09638E),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Số CCCD:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              soCccd.isNotEmpty ? soCccd : '(Chưa nhận diện)',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF09638E),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                      'Xác nhận thông tin',
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

  // Tạo mã đăng ký tự tăng (DK_DEM_02, DK_DEM_03...) đảm bảo <= 10 ký tự chuẩn varchar(10)
  Future<String> _taoMaDangKyMoi() async {
    try {
      final db = Supabase.instance.client;
      final res = await db
          .from('dang_ky_khach_qua_dem')
          .select('ma_dang_ky')
          .order('ma_dang_ky', ascending: false)
          .limit(20);

      int maxIndex = 0;
      final regex = RegExp(r'DK_DEM_(\d+)');
      for (final row in res) {
        final id = row['ma_dang_ky']?.toString() ?? '';
        final match = regex.firstMatch(id);
        if (match != null) {
          final num = int.tryParse(match.group(1)!) ?? 0;
          if (num > maxIndex) maxIndex = num;
        }
      }

      final nextNum = maxIndex + 1;
      if (nextNum < 100) {
        return 'DK_DEM_${nextNum.toString().padLeft(2, '0')}'; // e.g. DK_DEM_02 (9 ký tự)
      } else {
        final ts = DateTime.now().millisecondsSinceEpoch.toString();
        return 'DKD${ts.substring(ts.length - 7)}'; // 3 + 7 = 10 ký tự
      }
    } catch (_) {
      final ts = DateTime.now().millisecondsSinceEpoch.toString();
      return 'DK${ts.substring(ts.length - 8)}'; // 2 + 8 = 10 ký tự
    }
  }

  // Xử lý xác nhận form và lưu vào Supabase
  Future<void> _xuLyXacNhan() async {
    // 0. KIỂM TRA RÀNG BUỘC LUẬT CƯ TRÚ (TỐI ĐA 29 NGÀY)
    if (_soDemLuuTru >= 30) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Text(
                'Vượt Quá Thời Hạn',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const Text(
            'Theo quy định Luật Cư trú, lưu trú từ 30 ngày trở lên bắt buộc phải ĐĂNG KÝ TẠM TRÚ hoặc thêm vào hợp đồng thuê phòng chính thức, không thể khai báo diện khách qua đêm.\n\nVui lòng chọn thời gian dưới 30 ngày hoặc liên hệ Ban Quản Lý.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }

    // 1. Kiểm tra validation text fields
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ─── 4. LƯU DỮ LIỆU VÀO SUPABASE BẢNG dang_ky_khach_qua_dem ───
    final String thoiGianStr =
        '${_formatDate(_ngayDen)} - ${_formatDate(_ngayDi)}';
    final int phi = _soDemLuuTru * 50000;
    final phiFormat =
        '${phi.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

    final maDangKy = await _taoMaDangKyMoi();

    // Xác định mã phòng & khách thuê
    String maPhong = 'P203';
    final matchP = RegExp(r'P\d+').firstMatch(widget.tenPhong);
    if (matchP != null) {
      maPhong = matchP.group(0)!;
    } else {
      final numM = RegExp(r'\d+').firstMatch(widget.tenPhong);
      if (numM != null) maPhong = 'P${numM.group(0)}';
    }

    String maKhach = 'KH_DUYEN';
    final user = AuthService.currentUser;
    if (user != null && user.maTaiKhoan.isNotEmpty) {
      try {
        final kt = await Supabase.instance.client
            .from('khach_thue')
            .select('ma_khach')
            .eq('ma_tai_khoan', user.maTaiKhoan)
            .maybeSingle();
        if (kt != null && kt['ma_khach'] != null) {
          maKhach = kt['ma_khach'].toString();
        }
      } catch (_) {}
    }

    try {
      final db = Supabase.instance.client;
      await db.from('dang_ky_khach_qua_dem').insert({
        'ma_dang_ky': maDangKy,
        'ho_ten_khach_ngoai': _tenController.text.trim(),
        'cccd_khach_ngoai': _cccdController.text.trim(),
        'tu_ngay': _ngayDen.toIso8601String().substring(0, 10),
        'den_ngay': _ngayDi.toIso8601String().substring(0, 10),
        'cam_ket_an_ninh': _camKet,
        'trang_thai': 'Chờ duyệt',
        'ma_phong': maPhong,
        'ma_khach_dang_ky': maKhach,
      });
      debugPrint(
        '[GUEST] Đã lưu thành công vào dang_ky_khach_qua_dem trên Supabase: $maDangKy',
      );
    } catch (e) {
      debugPrint('[GUEST] Lỗi lưu Supabase: $e');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi lưu thông tin',
          noiDung: 'Lỗi lưu Supabase: $e',
          type: ThongBaoType.thatBai,
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

    // ─── 5. TẠO VÀ LƯU PHIẾU VÀO DANH SÁCH DÙNG CHUNG ───
    final donMoi = KhachLuuTruModel(
      id: maDangKy,
      hoTen: _tenController.text.trim(),
      cccd: _cccdController.text.trim(),
      sdt: _sdtController.text.trim(),
      thoiGian: thoiGianStr,
      soDem: _soDemLuuTru,
      phiLuuTru: phiFormat,
      moiQuanHe: _moiQuanHe,
      trangThai: 'Chờ duyệt',
      anhMatTruoc: _anhCccdMatTruoc?.path,
      anhMatSau: _anhCccdMatSau?.path,
      ngayDangKy:
          '${_formatDate(DateTime.now())} • ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
    );

    // Chèn dữ liệu vừa tạo lên đầu danh sách lưu trữ
    KhachLuuTruModel.danhSachLuuTru.insert(0, donMoi);

    if (!mounted) return;

    // Điều hướng sang Màn hình xác nhận thành công
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManHinhXacNhanDangKyKhach(
          hoTen: donMoi.hoTen,
          cccd: donMoi.cccd,
          sdt: donMoi.sdt,
          thoiGian: donMoi.thoiGian,
          soDem: donMoi.soDem,
          moiQuanHe: donMoi.moiQuanHe,
          tenPhong: widget.tenPhong,
          toaNha: widget.toaNha,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _laserController.dispose();
    _tenController.dispose();
    _cccdController.dispose();
    _sdtController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBannerLuuY(),
                    const SizedBox(height: 14),

                    // 1. ĐƯA PHẦN TẢI CCCD LÊN ĐẦU ĐỂ QUÉT TỰ ĐỘNG
                    _buildCardHinhAnhCccd(),
                    const SizedBox(height: 14),

                    // 2. THÔNG TIN KHÁCH (TỰ ĐỘNG ĐIỀN TỪ CCCD)
                    _buildCardThongTinKhach(),
                    const SizedBox(height: 14),

                    // 3. THỜI GIAN LƯU TRÚ
                    _buildCardThoiGianLuuTru(),
                    const SizedBox(height: 16),

                    // 4. MỐI QUAN HỆ
                    _buildPhanMoiQuanHe(),
                    const SizedBox(height: 16),

                    // 5. CAM KẾT
                    _buildCheckboxCamKet(),
                    const SizedBox(height: 20),

                    // 6. NÚT XÁC NHẬN
                    _buildNutXacNhan(),
                  ],
                ),
              ),
            ),

            // THÔNG BÁO ĐANG QUÉT CCCD HIỂN THỊ CHÍNH GIỮA MÀN HÌNH (KHÔNG BỊ TRÀN)
            if (_isScanningCccd)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _laserController,
                          builder: (context, child) {
                            final scale =
                                1.0 +
                                0.08 *
                                    math.sin(
                                      _laserController.value * math.pi * 2,
                                    );
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFBAE6FD),
                                width: 2,
                              ),
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Color(0xFF09638E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Đang quét & nhận diện CCCD',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hệ thống AI đang phân tích và bóc tách thông tin thẻ CCCD, vui lòng đợi trong giây lát...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF64748B),
                            height: 1.4,
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
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: _primary,
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: Column(
        children: [
          const Text(
            'Đăng Ký Khách Qua Đêm',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${widget.tenPhong} • ${widget.toaNha}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManHinhLichSuLuuTru(
                    tenPhong: widget.tenPhong,
                    toaNha: widget.toaNha,
                    initialTabIndex: 0, // Mở tab Tất cả để luôn thấy đầy đủ khách đã duyệt & chờ duyệt
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.history_edu_rounded, size: 15, color: _primary),
                  SizedBox(width: 4),
                  Text(
                    'Lịch sử lưu trú',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBannerLuuY() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF0284C7),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Quy định lưu trú: ',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0369A1),
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'Đăng ký trước 22h00 đêm. Chỉ cần chụp ảnh mặt trước CCCD, hệ thống AI sẽ ',
                        style: TextStyle(fontWeight: FontWeight.normal),
                      ),
                      TextSpan(
                        text: 'tự động quét và điền Họ tên, CCCD',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const TextSpan(
                        text: ' cho bạn.',
                        style: TextStyle(fontWeight: FontWeight.normal),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ManHinhLichSuLuuTru(
                    tenPhong: widget.tenPhong,
                    toaNha: widget.toaNha,
                    initialTabIndex: 0, // Tab Tất cả (hiển thị cả đã duyệt và chờ duyệt)
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.history_edu_rounded,
                    size: 16,
                    color: Color(0xFF0284C7),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Xem lịch sử & danh sách khách lưu trú (đã duyệt & chờ duyệt) 👉',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // CARD HÌNH ẢNH CCCD (CÓ NÚT QUÉT AI)
  Widget _buildCardHinhAnhCccd() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isScanningCccd
              ? const Color(0xFF0284C7)
              : const Color(0xFFE2E8F0),
          width: _isScanningCccd ? 1.5 : 1,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: Color(0xFF0284C7),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'AI Tự động quét',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Chụp hoặc tải ảnh CCCD của khách *',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chụp mặt trước rõ nét để AI tự động trích xuất Họ tên & Số CCCD',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _buildCccdBox(
                  'Mặt trước CCCD',
                  isMatTruoc: true,
                  onTap: () => _chonNguonAnh(true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCccdBox(
                  'Mặt sau CCCD',
                  isMatTruoc: false,
                  onTap: () => _chonNguonAnh(false),
                ),
              ),
            ],
          ),

          if (_isScanningCccd) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đang phân tích và bóc tách thông tin thẻ CCCD...',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w500,
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

  Widget _buildCccdBox(
    String label, {
    required bool isMatTruoc,
    required VoidCallback onTap,
  }) {
    final Uint8List? bytes = isMatTruoc ? _bytesCccdMatTruoc : _bytesCccdMatSau;
    final File? file = isMatTruoc ? _anhCccdMatTruoc : _anhCccdMatSau;
    final String? path = isMatTruoc ? _pathCccdMatTruoc : _pathCccdMatSau;
    final bool hasImage =
        bytes != null || file != null || (path != null && path.isNotEmpty);

    Widget? imageWidget;
    if (bytes != null) {
      imageWidget = Image.memory(bytes, fit: BoxFit.cover);
    } else if (kIsWeb) {
      if (path != null && path.isNotEmpty) {
        imageWidget = Image.network(path, fit: BoxFit.cover);
      }
    } else if (file != null) {
      imageWidget = Image.file(file, fit: BoxFit.cover);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: hasImage ? Colors.white : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasImage
                ? const Color(0xFF16A34A)
                : (isMatTruoc
                      ? const Color(0xFF0284C7)
                      : const Color(0xFFCBD5E1)),
            width: hasImage ? 1.5 : (isMatTruoc ? 1.2 : 1),
          ),
        ),
        child: (hasImage && imageWidget != null)
            ? Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: imageWidget,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                  if (isMatTruoc && _isScanningCccd)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedBuilder(
                          animation: _laserController,
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _LaserScanPainter(
                                progress: _laserController.value,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(10),
                        ),
                      ),
                      child: Text(
                        isMatTruoc ? 'Đổi mặt trước' : 'Đổi mặt sau',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMatTruoc
                        ? Icons.document_scanner_rounded
                        : Icons.add_a_photo_outlined,
                    color: isMatTruoc ? _primary : const Color(0xFF64748B),
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isMatTruoc ? _primary : const Color(0xFF475569),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isMatTruoc) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Tự động điền AI',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF0284C7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  // CARD THÔNG TIN KHÁCH (CÓ BADGE ĐÃ TỰ ĐỘNG ĐIỀN)
  Widget _buildCardThongTinKhach() {
    return Container(
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Thông tin khách lưu trú *',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const Spacer(),
              if (_thongBaoQuetThanhCong != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 12,
                        color: Color(0xFF16A34A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Đã quét từ CCCD',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          _buildFieldLabel('Họ và tên khách * (Tự động điền từ CCCD)'),
          _buildInputField(
            controller: _tenController,
            hint: 'Tự động hiển thị khi quét mặt trước CCCD',
            readOnly: true,
            suffixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Vui lòng chụp/tải ảnh mặt trước CCCD để AI quét họ tên'
                : null,
          ),
          const SizedBox(height: 12),

          _buildFieldLabel('Số CCCD / Hộ chiếu * (Tự động điền từ CCCD)'),
          _buildInputField(
            controller: _cccdController,
            hint: 'Tự động hiển thị khi quét mặt trước CCCD',
            readOnly: true,
            keyboardType: TextInputType.number,
            suffixIcon: const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Vui lòng chụp/tải ảnh mặt trước CCCD để AI quét số CCCD';
              }
              if (v.trim().length < 9) return 'Số CCCD/Hộ chiếu không hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 12),

          _buildFieldLabel('Số điện thoại liên hệ *'),
          _buildInputField(
            controller: _sdtController,
            hint: 'Nhập số điện thoại của khách',
            keyboardType: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Vui lòng nhập số điện thoại';
              }
              if (v.trim().length < 10) return 'Số điện thoại phải từ 10 số';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool readOnly = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: readOnly ? const Color(0xFF334155) : _textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: Color(0xFF94A3B8),
          fontWeight: FontWeight.normal,
        ),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: readOnly ? const Color(0xFFCBD5E1) : _primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCardThoiGianLuuTru() {
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
          const Text(
            'Thời gian lưu trú',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Ngày đến'),
                    _buildDateSelector(
                      _formatDate(_ngayDen),
                      () => _chonNgay(context, true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Ngày đi'),
                    _buildDateSelector(
                      _formatDate(_ngayDi),
                      () => _chonNgay(context, false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Tổng thời gian
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tổng thời gian:',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF0369A1),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$_soDemLuuTru đêm lưu trú',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ],
            ),
          ),

          // CHỈ HIỆN KHI Ở TỪ 30 NGÀY TRỞ LÊN:
          if (_soDemLuuTru >= 30) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.gavel_rounded,
                        size: 18,
                        color: Color(0xFFD97706),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Thời gian lưu trú từ 30 ngày trở lên:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Theo Luật Cư trú, lưu trú từ 30 ngày trở lên bắt buộc phải đăng ký tạm trú dài hạn (thêm vào thành viên phòng). Không áp dụng diện khách qua đêm thông thường.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFB45309),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: ElevatedButton.icon(
                      onPressed: _hienThiHuongDanDangKyTamTru,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.group_add_rounded, size: 16),
                      label: const Text(
                        'Đăng ký Tạm trú dài hạn (Thêm người ở cùng)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
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

  void _hienThiHuongDanDangKyTamTru() {
    int soThangChon = 6; // Mặc định 6 tháng
    final ghiChuController = TextEditingController();
    bool isDangGui = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.badge_rounded,
                        color: Color(0xFF09638E),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Đăng Ký Tạm Trú Dài Hạn',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            'Thêm người ở cùng từ 30 ngày trở lên',
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
                const SizedBox(height: 14),

                // Thông tin người được đăng ký (lấy từ dữ liệu CCCD đã quét)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Người đăng ký:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            _tenController.text.isNotEmpty
                                ? _tenController.text
                                : 'Chưa quét CCCD',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Số CCCD:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          Text(
                            _cccdController.text.isNotEmpty
                                ? _cccdController.text
                                : 'Chưa có',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF09638E),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // LỰA CHỌN THỜI HẠN TẠM TRÚ (THÁNG)
                const Text(
                  'Chọn thời hạn đăng ký tạm trú: *',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [3, 6, 12].map((thang) {
                    final isSelected = soThangChon == thang;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => setModalState(() => soThangChon = thang),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF09638E)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF09638E)
                                    : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '$thang Tháng',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF334155),
                                  ),
                                ),
                                Text(
                                  '(${thang * 30} ngày)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isSelected
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Ghi chú thêm
                TextField(
                  controller: ghiChuController,
                  decoration: InputDecoration(
                    labelText:
                        'Ghi chú cho BQL (quan hệ thân nhân, công việc...)',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 16),

                // NÚT GỬI YÊU CẦU LÊN SUPABASE
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isDangGui
                        ? null
                        : () async {
                            if (_tenController.text.trim().isEmpty ||
                                _cccdController.text.trim().isEmpty) {
                              ThongBaoHelper.hienToast(
                                context,
                                tieuDe: 'Thiếu thông tin',
                                noiDung:
                                    'Vui lòng quét CCCD ở màn hình trước để có đủ Họ tên và CCCD!',
                                type: ThongBaoType.canhBao,
                              );
                              return;
                            }

                            setModalState(() => isDangGui = true);

                            final maDangKy =
                                'TT_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
                            final tuNgay = DateTime.now();
                            final denNgay = tuNgay.add(
                              Duration(days: soThangChon * 30),
                            );

                            String maPhong = 'P203';
                            final matchP = RegExp(
                              r'P\d+',
                            ).firstMatch(widget.tenPhong);
                            if (matchP != null) maPhong = matchP.group(0)!;

                            try {
                              // Đẩy trực tiếp vào bảng dang_ky_khach_qua_dem với thời hạn theo tháng
                              await Supabase.instance.client
                                  .from('dang_ky_khach_qua_dem')
                                  .insert({
                                    'ma_dang_ky': maDangKy,
                                    'ho_ten_khach_ngoai': _tenController.text
                                        .trim(),
                                    'cccd_khach_ngoai': _cccdController.text
                                        .trim(),
                                    'tu_ngay': tuNgay
                                        .toIso8601String()
                                        .substring(0, 10),
                                    'den_ngay': denNgay
                                        .toIso8601String()
                                        .substring(0, 10),
                                    'cam_ket_an_ninh': true,
                                    'trang_thai': 'Chờ duyệt',
                                    'ma_phong': maPhong,
                                    'ma_khach_dang_ky': 'KH_DUYEN',
                                  });

                              if (!mounted) return;
                              Navigator.pop(ctx);
                              ThongBaoHelper.hienToast(
                                context,
                                tieuDe: 'Gửi hồ sơ thành công',
                                noiDung:
                                    'Đã gửi hồ sơ tạm trú dài hạn ($soThangChon tháng) lên BQL thành công!',
                                type: ThongBaoType.thanhCong,
                              );
                            } catch (e) {
                              setModalState(() => isDangGui = false);
                              ThongBaoHelper.hienToast(
                                context,
                                tieuDe: 'Lỗi gửi hồ sơ',
                                noiDung: 'Lỗi gửi hồ sơ: $e',
                                type: ThongBaoType.thatBai,
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09638E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isDangGui
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Gửi Hồ Sơ Tạm Trú ($soThangChon Tháng) Lên BQL',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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

  Widget _buildDateSelector(String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textDark,
              ),
            ),
            const Icon(
              Icons.calendar_today_rounded,
              size: 15,
              color: Color(0xFF0284C7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhanMoiQuanHe() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mối quan hệ với chủ phòng',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _danhSachQuanHe.map((item) {
            final isSelected = _moiQuanHe == item;
            return ChoiceChip(
              label: Text(item),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
              selected: isSelected,
              selectedColor: _primary,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? _primary : const Color(0xFFCBD5E1),
                ),
              ),
              onSelected: (val) {
                if (val) setState(() => _moiQuanHe = item);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCheckboxCamKet() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: _camKet,
          activeColor: _primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          onChanged: (val) => setState(() => _camKet = val ?? false),
        ),
        const Expanded(
          child: Text(
            'Tôi cam kết chịu hoàn toàn trách nhiệm an ninh trật tự. *',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF334155),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNutXacNhan() {
    final bool isDaiHan = _soDemLuuTru >= 30;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isSubmitting
            ? null
            : (isDaiHan ? _hienThiHuongDanDangKyTamTru : _xuLyXacNhan),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDaiHan ? const Color(0xFFD97706) : _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isDaiHan
                        ? Icons.assignment_ind_rounded
                        : Icons.person_add_alt_1_rounded,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    isDaiHan
                        ? 'Chuyển sang Đăng ký Tạm trú dài hạn'
                        : 'Xác nhận & Khai báo lưu trú',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Hiệu ứng Laser quét thẻ CCCD bằng AI (Futuristic HUD Viewfinder)
class _LaserScanPainter extends CustomPainter {
  final double progress;

  _LaserScanPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ 4 góc định vị nhận diện thẻ (Camera HUD corner brackets)
    final bracketPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    const cornerLength = 16.0;

    // Top-Left
    canvas.drawLine(
      const Offset(4, 4),
      const Offset(4 + cornerLength, 4),
      bracketPaint,
    );
    canvas.drawLine(
      const Offset(4, 4),
      const Offset(4, 4 + cornerLength),
      bracketPaint,
    );

    // Top-Right
    canvas.drawLine(
      Offset(size.width - 4, 4),
      Offset(size.width - 4 - cornerLength, 4),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - 4, 4),
      Offset(size.width - 4, 4 + cornerLength),
      bracketPaint,
    );

    // Bottom-Left
    canvas.drawLine(
      Offset(4, size.height - 4),
      Offset(4 + cornerLength, size.height - 4),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(4, size.height - 4),
      Offset(4, size.height - 4 - cornerLength),
      bracketPaint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(size.width - 4, size.height - 4),
      Offset(size.width - 4 - cornerLength, size.height - 4),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(size.width - 4, size.height - 4),
      Offset(size.width - 4, size.height - 4 - cornerLength),
      bracketPaint,
    );

    // 2. Tia laser quét dọc chạy lên xuống
    final y = size.height * progress;

    // Gradient vệt sáng tỏa ra từ tia laser
    final auraPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00E5FF).withValues(alpha: 0.0),
          const Color(0xFF00E5FF).withValues(alpha: 0.28),
          const Color(0xFF00E5FF).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, y - 18, size.width, 36));
    canvas.drawRect(Rect.fromLTWH(0, y - 18, size.width, 36), auraPaint);

    // Tia sáng laser sắc nét chính giữa
    final beamPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), beamPaint);
  }

  @override
  bool shouldRepaint(covariant _LaserScanPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

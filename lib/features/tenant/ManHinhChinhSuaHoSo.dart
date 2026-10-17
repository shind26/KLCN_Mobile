import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nhatro_kieugiang/core/services/DichVuQuetCccd.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhuongTien.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhChinhSuaHoSo extends StatefulWidget {
  final Map<String, dynamic>? khachThueData;
  final String tenPhong;
  final String maHopDong;
  final String vaiTro;

  const ManHinhChinhSuaHoSo({
    super.key,
    this.khachThueData,
    this.tenPhong = 'P303',
    this.maHopDong = 'HD001',
    this.vaiTro = 'Trưởng phòng',
  });

  @override
  State<ManHinhChinhSuaHoSo> createState() => _ManHinhChinhSuaHoSoState();
}

class _ManHinhChinhSuaHoSoState extends State<ManHinhChinhSuaHoSo> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _hoTenController;
  late TextEditingController _soDtController;
  late TextEditingController _cccdController;
  late TextEditingController _ngaySinhController;
  late TextEditingController _diaChiController;
  late TextEditingController _emailController;
  String _gioiTinh = 'Nam';

  bool _isSaving = false;
  bool _isScanningCccd = false;
  late String _maKhach;
  late String _maPhong;

  // ── Danh sách phương tiện từ Supabase (bảng phuong_tien) ──
  List<PhuongTienModel> _danhSachPhuongTien = [];
  bool _isLoadingPhuongTien = true;

  @override
  void initState() {
    super.initState();
    final data = widget.khachThueData;
    _maKhach = data?['ma_khach']?.toString() ?? '';
    _maPhong = widget.tenPhong.replaceAll('P.', '').replaceAll('Phòng ', '').trim();

    final cccdVal = (data?['cccd'] ?? data?['so_cccd'])?.toString() ?? '';
    final hoTenVal = data?['ho_ten_khach']?.toString() ??
        AuthService.currentUser?.hoTen ??
        AuthService.currentUser?.tenHienThi ??
        '';
    final soDtVal = data?['so_dt']?.toString() ??
        AuthService.currentUser?.tenDangNhap ??
        '';
    final diaChiVal = (data?['dia_chi_thuong_tru'] ?? data?['dia_chi'])?.toString() ?? '';
    final ngaySinhVal = data?['ngay_sinh']?.toString() ?? '';
    final gioiTinhVal = data?['gioi_tinh']?.toString() ?? 'Nam';
    final emailVal = data?['email']?.toString() ?? '';

    _gioiTinh = (gioiTinhVal.toLowerCase().contains('nữ') || gioiTinhVal.toLowerCase().contains('female'))
        ? 'Nữ'
        : 'Nam';

    _hoTenController = TextEditingController(text: hoTenVal);
    _soDtController = TextEditingController(text: soDtVal);
    _cccdController = TextEditingController(text: cccdVal);
    _ngaySinhController = TextEditingController(text: ngaySinhVal);
    _diaChiController = TextEditingController(text: diaChiVal);
    _emailController = TextEditingController(text: emailVal);

    _taiDanhSachPhuongTien();
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _soDtController.dispose();
    _cccdController.dispose();
    _ngaySinhController.dispose();
    _diaChiController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// Tải danh sách phương tiện từ bảng `phuong_tien` trên Supabase
  Future<void> _taiDanhSachPhuongTien() async {
    try {
      final db = Supabase.instance.client;
      List<dynamic> rows = [];
      try {
        if (_maKhach.isNotEmpty) {
          rows = await db
              .from('phuong_tien')
              .select()
              .or('ma_khach.eq.$_maKhach,ma_phong.eq.$_maPhong')
              .order('ngay_dang_ky', ascending: false);
        } else {
          rows = await db
              .from('phuong_tien')
              .select()
              .eq('ma_phong', _maPhong)
              .order('ngay_dang_ky', ascending: false);
        }
      } catch (e) {
        debugPrint('[PHUONG_TIEN] Query fallback error: $e');
        // Thử query không order
        rows = await db.from('phuong_tien').select();
      }

      if (mounted) {
        setState(() {
          _danhSachPhuongTien = rows
              .map((e) => PhuongTienModel.fromJson(Map<String, dynamic>.from(e)))
              .where((pt) =>
                  (_maKhach.isNotEmpty && pt.maKhach == _maKhach) ||
                  pt.maPhong == _maPhong ||
                  pt.maPhong == widget.tenPhong)
              .toList();
          _isLoadingPhuongTien = false;
        });
      }
    } catch (e) {
      debugPrint('[PHUONG_TIEN] Lỗi tải phương tiện: $e');
      if (mounted) {
        setState(() => _isLoadingPhuongTien = false);
      }
    }
  }

  /// Mở camera hoặc thư viện để quét CCCD
  Future<void> _chonAnhVaQuetCccd() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.document_scanner_rounded, color: Color(0xFF0284C7), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quét Căn Cước Công Dân (CCCD)',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tự động nhận diện và trích xuất thông tin',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF16A34A)),
                ),
                title: const Text('Chụp ảnh mặt trước CCCD', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Dùng camera chụp rõ nét, đủ ánh sáng', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(ctx);
                  _thucHienQuet(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Color(0xFF2563EB)),
                ),
                title: const Text('Chọn ảnh từ Thư viện', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: const Text('Chọn ảnh thẻ CCCD đã chụp sẵn', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.pop(ctx);
                  _thucHienQuet(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _thucHienQuet(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;

      setState(() => _isScanningCccd = true);

      // Hiển thị dialog đang quét
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              content: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    CircularProgressIndicator(color: Color(0xFF09638E)),
                    SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Đang quét CCCD...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          SizedBox(height: 4),
                          Text('AI đang nhận diện họ tên, số định danh, quê quán...', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final result = await DichVuQuetCccd.quetAnhCccd(File(picked.path));

      // Đóng dialog loading
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _isScanningCccd = false);
      }

      if (result != null && result.hopLe) {
        HapticFeedback.mediumImpact();

        setState(() {
          if (result.hoTen.isNotEmpty) {
            _hoTenController.text = result.hoTen;
          }
          if (result.soCccd.isNotEmpty) {
            _cccdController.text = result.soCccd;
          }
          if (result.ngaySinh != null && result.ngaySinh!.isNotEmpty) {
            _ngaySinhController.text = result.ngaySinh!;
          }
          if (result.gioiTinh != null && result.gioiTinh!.isNotEmpty) {
            _gioiTinh = result.gioiTinh!;
          }
          if (result.diaChi != null && result.diaChi!.isNotEmpty) {
            _diaChiController.text = result.diaChi!;
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đã tự động điền thông tin từ CCCD (${result.nguon})!',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Không nhận diện được rõ thông tin. Vui lòng chụp thẳng và rõ nét hơn!'),
              backgroundColor: const Color(0xFFEA580C),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi quét CCCD: $e');
      if (mounted) {
        setState(() => _isScanningCccd = false);
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi quét ảnh: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Mở form Thêm / Sửa phương tiện đi lại
  void _hienThiModalThemPhuongTien({PhuongTienModel? phuongTienCu}) {
    final bool isEdit = phuongTienCu != null;
    String selectedLoaiXe = phuongTienCu?.loaiXe ?? 'Xe máy';
    final bienSoCtrl = TextEditingController(text: phuongTienCu?.bienSoXe ?? '');
    final theXeCtrl = TextEditingController(text: phuongTienCu?.maTheXe ?? '');
    String selectedTrangThai = phuongTienCu?.trangThai ?? 'Đang sử dụng';

    final List<String> danhSachLoaiXe = [
      'Xe máy',
      'Xe tay ga',
      'Xe số',
      'Xe đạp điện',
      'Ô tô 4-7 chỗ',
      'Xe đạp',
      'Khác',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFF0284C7), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isEdit ? 'Chỉnh Sửa Phương Tiện' : 'Đăng Ký Phương Tiện Mới',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(modalCtx),
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Loại xe Dropdown
              const Text('Loại phương tiện', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
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
                    value: danhSachLoaiXe.contains(selectedLoaiXe) ? selectedLoaiXe : danhSachLoaiXe.first,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF09638E)),
                    items: danhSachLoaiXe.map((lx) {
                      return DropdownMenuItem<String>(
                        value: lx,
                        child: Row(
                          children: [
                            Icon(_getIconForVehicle(lx), size: 18, color: const Color(0xFF0284C7)),
                            const SizedBox(width: 10),
                            Text(lx, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedLoaiXe = val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Biển số xe
              const Text('Biển số xe', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
              const SizedBox(height: 6),
              TextFormField(
                controller: bienSoCtrl,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Ví dụ: 59-X1 123.45',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal, letterSpacing: 0),
                  prefixIcon: const Icon(Icons.tag_rounded, size: 20, color: Color(0xFF09638E)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF09638E), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Mã thẻ xe (tùy chọn)
              const Text('Mã thẻ xe (BQL cấp)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
              const SizedBox(height: 6),
              TextFormField(
                controller: theXeCtrl,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'Để trống nếu chưa nhận thẻ xe',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
                  prefixIcon: const Icon(Icons.credit_card_rounded, size: 18, color: Color(0xFF09638E)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF09638E), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Nút bấm Lưu
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    final bienSo = bienSoCtrl.text.trim().toUpperCase();
                    if (bienSo.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập biển số xe')),
                      );
                      return;
                    }

                    Navigator.pop(modalCtx);
                    await _luuPhuongTienLenSupabase(
                      phuongTienCu: phuongTienCu,
                      loaiXe: selectedLoaiXe,
                      bienSoXe: bienSo,
                      maTheXe: theXeCtrl.text.trim().isEmpty ? null : theXeCtrl.text.trim(),
                      trangThai: selectedTrangThai,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09638E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    isEdit ? 'Cập Nhật Phương Tiện' : 'Lưu Phương Tiện',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Thực hiện insert / update lên bảng `phuong_tien` trên Supabase
  Future<void> _luuPhuongTienLenSupabase({
    PhuongTienModel? phuongTienCu,
    required String loaiXe,
    required String bienSoXe,
    String? maTheXe,
    required String trangThai,
  }) async {
    final db = Supabase.instance.client;
    final isEdit = phuongTienCu != null;
    final maPt = isEdit ? phuongTienCu.maPhuongTien : 'PT_${DateTime.now().millisecondsSinceEpoch}';

    final payload = {
      'ma_phuong_tien': maPt,
      'ma_khach': _maKhach.isNotEmpty ? _maKhach : (AuthService.currentUser?.maTaiKhoan ?? 'KH_MACDINH'),
      'ma_phong': _maPhong,
      'loai_xe': loaiXe,
      'bien_so_xe': bienSoXe,
      if (maTheXe != null && maTheXe.isNotEmpty) 'ma_the_xe': maTheXe,
      'trang_thai': trangThai,
      'ngay_dang_ky': isEdit && phuongTienCu.ngayDangKy != null
          ? phuongTienCu.ngayDangKy!.toIso8601String()
          : DateTime.now().toIso8601String(),
    };

    try {
      if (isEdit) {
        await db.from('phuong_tien').update(payload).eq('ma_phuong_tien', maPt);
      } else {
        await db.from('phuong_tien').insert(payload);
      }

      await _taiDanhSachPhuongTien();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEdit ? 'Đã cập nhật thông tin phương tiện!' : 'Đã đăng ký phương tiện $bienSoXe thành công!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      debugPrint('[PHUONG_TIEN] Lỗi lưu Supabase: $e');
      // Nếu dính RLS policy thì cập nhật local để cư dân vẫn thấy
      final fallbackModel = PhuongTienModel(
        maPhuongTien: maPt,
        maKhach: payload['ma_khach']!.toString(),
        maPhong: _maPhong,
        loaiXe: loaiXe,
        bienSoXe: bienSoXe,
        maTheXe: maTheXe,
        trangThai: trangThai,
        ngayDangKy: DateTime.now(),
      );

      setState(() {
        if (isEdit) {
          final idx = _danhSachPhuongTien.indexWhere((p) => p.maPhuongTien == maPt);
          if (idx != -1) _danhSachPhuongTien[idx] = fallbackModel;
        } else {
          _danhSachPhuongTien.insert(0, fallbackModel);
        }
      });

      if (mounted) {
        final errText = e.toString().contains('42501')
            ? 'Đã lưu tạm phương tiện vào máy (BQL cần cấu hình thêm quyền RLS trên Supabase để lưu vĩnh viễn).'
            : 'Đã lưu tạm phương tiện vào giao diện: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errText),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
      }
    }
  }

  /// Xóa phương tiện
  Future<void> _xacNhanXoaPhuongTien(PhuongTienModel pt) async {
    final xacNhan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa xe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('Bạn có chắc muốn xóa phương tiện biển số "${pt.bienSoXe}" khỏi danh sách?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), elevation: 0),
            child: const Text('Xóa', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (xacNhan == true) {
      try {
        final db = Supabase.instance.client;
        await db.from('phuong_tien').delete().eq('ma_phuong_tien', pt.maPhuongTien);
        await _taiDanhSachPhuongTien();
      } catch (e) {
        setState(() {
          _danhSachPhuongTien.removeWhere((p) => p.maPhuongTien == pt.maPhuongTien);
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gỡ phương tiện khỏi hồ sơ')),
        );
      }
    }
  }

  IconData _getIconForVehicle(String loaiXe) {
    final lower = loaiXe.toLowerCase();
    if (lower.contains('ô tô') || lower.contains('oto') || lower.contains('car')) {
      return Icons.directions_car_rounded;
    }
    if (lower.contains('đạp')) {
      return Icons.pedal_bike_rounded;
    }
    return Icons.two_wheeler_rounded;
  }

  Future<void> _luuThongTin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final db = Supabase.instance.client;
      final hoTen = _hoTenController.text.trim();
      final soDt = _soDtController.text.trim();
      final cccd = _cccdController.text.trim();
      final diaChi = _diaChiController.text.trim();
      final ngaySinh = _ngaySinhController.text.trim();
      final user = AuthService.currentUser;

      final updatePayload = {
        'ho_ten_khach': hoTen,
        'so_dt': soDt,
        'cccd': cccd,
        'dia_chi_thuong_tru': diaChi,
        if (ngaySinh.isNotEmpty) 'ngay_sinh': ngaySinh,
        'gioi_tinh': _gioiTinh,
      };

      // 1. Cập nhật bảng khach_thue
      if (_maKhach.isNotEmpty) {
        await db.from('khach_thue').update(updatePayload).eq('ma_khach', _maKhach);
      } else if (user != null && user.maTaiKhoan.isNotEmpty) {
        await db.from('khach_thue').update(updatePayload).eq('ma_tai_khoan', user.maTaiKhoan);
      }

      // 2. Cập nhật bảng tai_khoan nếu có
      if (user != null && user.maTaiKhoan.isNotEmpty) {
        try {
          await db.from('tai_khoan').update({
            'ho_ten': hoTen,
          }).eq('ma_tai_khoan', user.maTaiKhoan);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      await ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Cập Nhật Hồ Sơ Thành Công!',
        noiDung: 'Thông tin cá nhân, định danh CCCD và danh sách phương tiện đã được lưu an toàn.',
        type: ThongBaoType.thanhCong,
        nutText: 'Hoàn tất',
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Lỗi lưu hồ sơ: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể lưu thông tin: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Chỉnh Sửa Hồ Sơ',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Card Avatar & Thông tin phòng ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEF08A),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text('🐥', style: TextStyle(fontSize: 32)),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hoTenController.text.isNotEmpty ? _hoTenController.text : 'Cư Dân Kiêu Giang',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0F2FE),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.vaiTro,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0284C7),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.tenPhong,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Hợp đồng: ${widget.maHopDong}',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Banner AI Quét CCCD tiện lợi ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0284C7)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quét CCCD Tự Động Điền',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Chụp ảnh thẻ CCCD hoặc QR để tự động điền nhanh họ tên, ngày sinh, số CCCD',
                              style: TextStyle(
                                color: Color(0xFFE0F2FE),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isScanningCccd ? null : _chonAnhVaQuetCccd,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF09638E),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isScanningCccd
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF09638E)),
                              )
                            : const Text('Quét Ngay', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // ── Phần thông tin cá nhân ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'THÔNG TIN CÁ NHÂN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _chonAnhVaQuetCccd,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 15, color: Color(0xFF0284C7)),
                      label: const Text(
                        'Quét CCCD',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // Họ và tên
                      _buildTextField(
                        controller: _hoTenController,
                        label: 'Họ và tên',
                        hint: 'Nhập họ và tên đầy đủ',
                        icon: Icons.person_outline_rounded,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập họ và tên';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Số điện thoại
                      _buildTextField(
                        controller: _soDtController,
                        label: 'Số điện thoại',
                        hint: '09xx xxx xxx',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập số điện thoại';
                          }
                          if (v.trim().length < 10) {
                            return 'Số điện thoại tối thiểu 10 chữ số';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Số CCCD
                      _buildTextField(
                        controller: _cccdController,
                        label: 'Số CCCD / CMND',
                        hint: 'Nhập số CCCD (12 chữ số)',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.camera_alt_outlined, size: 18, color: Color(0xFF0284C7)),
                          tooltip: 'Quét từ ảnh thẻ CCCD',
                          onPressed: _chonAnhVaQuetCccd,
                        ),
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            if (v.trim().length != 9 && v.trim().length != 12) {
                              return 'Số CCCD phải gồm 12 số (hoặc CMND 9 số)';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Hàng Ngày sinh & Giới tính
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ngày sinh
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              controller: _ngaySinhController,
                              label: 'Ngày sinh',
                              hint: 'dd/mm/yyyy',
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Giới tính
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Giới tính',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 48,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _gioiTinh,
                                      isExpanded: true,
                                      icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF09638E)),
                                      items: const [
                                        DropdownMenuItem(value: 'Nam', child: Text('Nam', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                        DropdownMenuItem(value: 'Nữ', child: Text('Nữ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) setState(() => _gioiTinh = val);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Địa chỉ thường trú
                      _buildTextField(
                        controller: _diaChiController,
                        label: 'Địa chỉ thường trú / Quê quán',
                        hint: 'Xã/Phường, Quận/Huyện, Tỉnh/TP',
                        icon: Icons.home_outlined,
                      ),
                      const SizedBox(height: 14),

                      // Email
                      _buildTextField(
                        controller: _emailController,
                        label: 'Email (Tùy chọn)',
                        hint: 'example@gmail.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── PHƯƠNG TIỆN ĐI LẠI (Dựa trên bảng phuong_tien Supabase) ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'PHƯƠNG TIỆN ĐI LẠI (XE CỦA BẠN)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    InkWell(
                      onTap: () => _hienThiModalThemPhuongTien(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_rounded, size: 16, color: Color(0xFF0284C7)),
                            SizedBox(width: 4),
                            Text(
                              'Thêm xe',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _isLoadingPhuongTien
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(color: Color(0xFF09638E), strokeWidth: 2),
                          ),
                        )
                      : _danhSachPhuongTien.isEmpty
                          ? _buildEmptyVehicleView()
                          : Column(
                              children: [
                                for (int i = 0; i < _danhSachPhuongTien.length; i++) ...[
                                  _buildVehicleItemCard(_danhSachPhuongTien[i]),
                                  if (i < _danhSachPhuongTien.length - 1)
                                    const Divider(height: 16, color: Color(0xFFF1F5F9)),
                                ],
                              ],
                            ),
                ),
                const SizedBox(height: 24),

                // ── Nút Lưu Thay Đổi ──
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _luuThongTin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF09638E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'Lưu Thay Đổi',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Giao diện khi chưa có xe nào đăng ký
  Widget _buildEmptyVehicleView() {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.two_wheeler_outlined, size: 28, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 10),
        const Text(
          'Chưa đăng ký phương tiện đi lại',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Thêm biển số xe để Ban quản lý cấp thẻ giữ xe và đảm bảo an ninh bãi đỗ.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _hienThiModalThemPhuongTien(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Đăng ký biển số xe'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0284C7),
            side: const BorderSide(color: Color(0xFFBAE6FD)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  /// Giao diện thẻ từng xe
  Widget _buildVehicleItemCard(PhuongTienModel pt) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Icon loại xe
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDCFCE7)),
          ),
          child: Icon(_getIconForVehicle(pt.loaiXe), color: const Color(0xFF16A34A), size: 22),
        ),
        const SizedBox(width: 12),

        // Thông tin xe: Loại & Biển số
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    pt.loaiXe,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: pt.trangThai == 'Đang sử dụng'
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      pt.trangThai,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: pt.trangThai == 'Đang sử dụng'
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFD97706),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),

              // Thiết kế Biển số xe kiểu thẻ biển số
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  pt.bienSoXe,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),

              if (pt.maTheXe != null && pt.maTheXe!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Thẻ xe: ${pt.maTheXe}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ],
          ),
        ),

        // Actions: Sửa / Xóa
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF64748B)),
          tooltip: 'Chỉnh sửa',
          onPressed: () => _hienThiModalThemPhuongTien(phuongTienCu: pt),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
          tooltip: 'Xóa xe',
          onPressed: () => _xacNhanXoaPhuongTien(pt),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          onChanged: onChanged,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.normal),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF09638E)),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF09638E), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

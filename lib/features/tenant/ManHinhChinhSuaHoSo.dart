import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
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
  late TextEditingController _diaChiController;
  late TextEditingController _noiCapController;
  late TextEditingController _nguoiLienHeController;

  String _gioiTinh = 'Nam';
  DateTime? _ngaySinh;
  DateTime? _ngayCapCccd;

  // Ảnh CCCD
  final _picker = ImagePicker();
  Uint8List? _bytesMatTruoc;
  Uint8List? _bytesMatSau;
  String? _urlMatTruoc;
  String? _urlMatSau;

  bool _isSaving = false;
  late String _maKhach;
  List<Map<String, dynamic>> _danhSachPhuongTien = [];

  @override
  void initState() {
    super.initState();
    final data = widget.khachThueData;
    _maKhach = data?['ma_khach']?.toString() ?? '';
    _taiDanhSachPhuongTien();

    final cccdVal = (data?['cccd'] ?? data?['so_cccd'])?.toString() ?? '';
    final hoTenVal =
        data?['ho_ten_khach']?.toString() ??
        AuthService.currentUser?.hoTen ??
        AuthService.currentUser?.tenHienThi ??
        '';
    final soDtVal =
        data?['so_dt']?.toString() ??
        AuthService.currentUser?.tenDangNhap ??
        '';
    final diaChiVal =
        (data?['dia_chi_thuong_tru'] ?? data?['dia_chi'])?.toString() ?? '';
    final noiCapVal = data?['noi_cap_cccd']?.toString() ?? '';
    final nguoiLienHeVal = data?['nguoi_lien_he_khan_cap']?.toString() ?? '';

    _hoTenController = TextEditingController(text: hoTenVal);
    _soDtController = TextEditingController(text: soDtVal);
    _cccdController = TextEditingController(text: cccdVal);
    _diaChiController = TextEditingController(text: diaChiVal);
    _noiCapController = TextEditingController(text: noiCapVal);
    _nguoiLienHeController = TextEditingController(text: nguoiLienHeVal);

    _gioiTinh = (data?['gioi_tinh']?.toString() == 'Nữ') ? 'Nữ' : 'Nam';

    _urlMatTruoc = data?['anh_cccd_mat_truoc']?.toString();
    _urlMatSau = data?['anh_cccd_mat_sau']?.toString();

    if (data?['ngay_sinh'] != null) {
      try {
        _ngaySinh = DateTime.parse(data!['ngay_sinh'].toString());
      } catch (_) {}
    }
    if (data?['ngay_cap_cccd'] != null) {
      try {
        _ngayCapCccd = DateTime.parse(data!['ngay_cap_cccd'].toString());
      } catch (_) {}
    }
  }

  Future<void> _taiDanhSachPhuongTien() async {
    try {
      final db = Supabase.instance.client;
      final mk = _maKhach.isNotEmpty
          ? _maKhach
          : (AuthService.currentUser?.maTaiKhoan ?? '');
      if (mk.isNotEmpty) {
        final ptRows = await db.from('phuong_tien').select().eq('ma_khach', mk);
        if (mounted) {
          setState(() {
            _danhSachPhuongTien = List<Map<String, dynamic>>.from(
              ptRows as List,
            );
          });
        }
      }
    } catch (_) {}
  }

  void _showModalSuaPhuongTien(Map<String, dynamic>? phuongTienHienTai) {
    final isEditing = phuongTienHienTai != null;
    final maPt = phuongTienHienTai?['ma_phuong_tien']?.toString() ?? '';
    final bienSoCtrl = TextEditingController(
      text: phuongTienHienTai?['bien_so_xe']?.toString() ?? '',
    );
    String loaiXeSelected =
        phuongTienHienTai?['loai_xe']?.toString() ?? 'Xe máy';

    final dsLoaiXe = ['Xe máy', 'Xe tay ga', 'Xe số', 'Xe điện', 'Xe đạp điện'];
    if (!dsLoaiXe.contains(loaiXeSelected)) dsLoaiXe.add(loaiXeSelected);

    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: SingleChildScrollView(
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
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF09638E,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.two_wheeler_rounded,
                            color: Color(0xFF09638E),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEditing
                                    ? 'Chỉnh Sửa Phương Tiện'
                                    : 'Đăng Ký Phương Tiện Mới',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isEditing
                                    ? 'Cập nhật loại xe và biển số xe'
                                    : 'Đăng ký xe gửi tại nhà trọ',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF64748B),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),

                    const Text(
                      'Loại phương tiện *',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: dsLoaiXe.map((lx) {
                        final isSel = lx == loaiXeSelected;
                        return ChoiceChip(
                          label: Text(lx),
                          selected: isSel,
                          selectedColor: const Color(0xFF09638E),
                          labelStyle: TextStyle(
                            color: isSel
                                ? Colors.white
                                : const Color(0xFF334155),
                            fontWeight: isSel
                                ? FontWeight.bold
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide(
                            color: isSel
                                ? const Color(0xFF09638E)
                                : const Color(0xFFE2E8F0),
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => loaiXeSelected = lx);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Biển số xe *',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: bienSoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ví dụ: 59-X1 234.56',
                        prefixIcon: const Icon(
                          Icons.pin_rounded,
                          color: Color(0xFF09638E),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
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
                            color: Color(0xFF09638E),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        if (isEditing) ...[
                          IconButton(
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: ctx,
                                      builder: (c) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                        ),
                                        title: const Text(
                                          'Xóa Phương Tiện',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        content: Text(
                                          'Bạn có chắc muốn xóa phương tiện "${bienSoCtrl.text.trim()}" không?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c, false),
                                            child: const Text('Hủy'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(
                                                0xFFEF4444,
                                              ),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Xóa'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setModalState(() => isSubmitting = true);
                                      try {
                                        await Supabase.instance.client
                                            .from('phuong_tien')
                                            .delete()
                                            .eq('ma_phuong_tien', maPt);
                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          ThongBaoHelper.hienToast(
                                            context,
                                            tieuDe: 'Thành công',
                                            noiDung: 'Đã xóa phương tiện.',
                                            type: ThongBaoType.thanhCong,
                                          );
                                          _taiDanhSachPhuongTien();
                                        }
                                      } catch (err) {
                                        setModalState(
                                          () => isSubmitting = false,
                                        );
                                        ThongBaoHelper.hienToast(
                                          context,
                                          tieuDe: 'Lỗi',
                                          noiDung: '$err',
                                          type: ThongBaoType.thatBai,
                                        );
                                      }
                                    }
                                  },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFEF4444),
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFFFEE2E2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(12),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final bienSo = bienSoCtrl.text
                                          .trim()
                                          .toUpperCase();
                                      if (bienSo.isEmpty) {
                                        ThongBaoHelper.hienToast(
                                          context,
                                          tieuDe: 'Thiếu thông tin',
                                          noiDung: 'Vui lòng nhập biển số xe.',
                                          type: ThongBaoType.canhBao,
                                        );
                                        return;
                                      }
                                      setModalState(() => isSubmitting = true);
                                      try {
                                        final db = Supabase.instance.client;
                                        final mk = _maKhach.isNotEmpty
                                            ? _maKhach
                                            : (AuthService
                                                      .currentUser
                                                      ?.maTaiKhoan ??
                                                  '');
                                        if (isEditing) {
                                          await db
                                              .from('phuong_tien')
                                              .update({
                                                'loai_xe': loaiXeSelected,
                                                'bien_so_xe': bienSo,
                                              })
                                              .eq('ma_phuong_tien', maPt);
                                        } else {
                                          final newMaPt =
                                              'PT_${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';
                                          await db.from('phuong_tien').insert({
                                            'ma_phuong_tien': newMaPt,
                                            'ma_khach': mk,
                                            'ma_phong': widget.tenPhong,
                                            'loai_xe': loaiXeSelected,
                                            'bien_so_xe': bienSo,
                                            'trang_thai': 'Đang sử dụng',
                                            'ngay_dang_ky': DateTime.now()
                                                .toIso8601String(),
                                          });
                                        }
                                        if (mounted) {
                                          Navigator.pop(ctx);
                                          ThongBaoHelper.hienToast(
                                            context,
                                            tieuDe: 'Thành công',
                                            noiDung: isEditing
                                                ? 'Đã cập nhật phương tiện!'
                                                : 'Đã thêm phương tiện mới!',
                                            type: ThongBaoType.thanhCong,
                                          );
                                          _taiDanhSachPhuongTien();
                                        }
                                      } catch (err) {
                                        setModalState(
                                          () => isSubmitting = false,
                                        );
                                        ThongBaoHelper.hienToast(
                                          context,
                                          tieuDe: 'Lỗi',
                                          noiDung: '$err',
                                          type: ThongBaoType.thatBai,
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF09638E),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      isEditing
                                          ? 'Lưu Thay Đổi'
                                          : 'Xác Nhận Thêm',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
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
        },
      ),
    );
  }

  @override
  void dispose() {
    _hoTenController.dispose();
    _soDtController.dispose();
    _cccdController.dispose();
    _diaChiController.dispose();
    _noiCapController.dispose();
    _nguoiLienHeController.dispose();
    super.dispose();
  }

  void _baoLoi(String msg) {
    ThongBaoHelper.hienToast(
      context,
      tieuDe: 'Lỗi thông tin',
      noiDung: msg,
      type: ThongBaoType.thatBai,
    );
  }

  Future<void> _luuThongTin() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ngaySinh == null) {
      _baoLoi('Vui lòng chọn Ngày sinh theo CCCD (không được bỏ trống)!');
      return;
    }
    if (_ngayCapCccd == null) {
      _baoLoi('Vui lòng chọn Ngày cấp CCCD (không được bỏ trống)!');
      return;
    }
    if (_noiCapController.text.trim().isEmpty) {
      _baoLoi('Vui lòng nhập Nơi cấp CCCD (không được bỏ trống)!');
      return;
    }
    if (_nguoiLienHeController.text.trim().isEmpty) {
      _baoLoi(
        'Vui lòng nhập Người & SĐT liên hệ khẩn cấp (không được bỏ trống)!',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final db = Supabase.instance.client;
      final hoTen = _hoTenController.text.trim();
      final soDt = _soDtController.text.trim();
      final cccd = _cccdController.text.trim();
      final diaChi = _diaChiController.text.trim();
      final noiCap = _noiCapController.text.trim();
      final nguoiLienHe = _nguoiLienHeController.text.trim();
      final user = AuthService.currentUser;

      final Map<String, dynamic> updateData = {
        'ho_ten_khach': hoTen,
        'so_dt': soDt,
        'cccd': cccd,
        'gioi_tinh': _gioiTinh,
        'dia_chi_thuong_tru': diaChi,
        'noi_cap_cccd': noiCap,
        'nguoi_lien_he_khan_cap': nguoiLienHe,
        'ngay_sinh': DateFormat('yyyy-MM-dd').format(_ngaySinh!),
        'ngay_cap_cccd': DateFormat('yyyy-MM-dd').format(_ngayCapCccd!),
      };

      // Tải ảnh CCCD lên storage hoặc fallback Base64 CHỈ KHI người dùng chọn ảnh mới
      if (_bytesMatTruoc != null) {
        String uploadedUrlMatTruoc;
        try {
          final path =
              'cccd/${_maKhach.isNotEmpty ? _maKhach : "KH"}_truoc_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
          debugPrint('Storage upload mặt trước fallback base64: $eStorage');
          uploadedUrlMatTruoc =
              'data:image/jpeg;base64,${base64Encode(_bytesMatTruoc!)}';
        }
        updateData['anh_cccd_mat_truoc'] = uploadedUrlMatTruoc;
      }

      if (_bytesMatSau != null) {
        String uploadedUrlMatSau;
        try {
          final path =
              'cccd/${_maKhach.isNotEmpty ? _maKhach : "KH"}_sau_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
          debugPrint('Storage upload mặt sau fallback base64: $eStorage');
          uploadedUrlMatSau =
              'data:image/jpeg;base64,${base64Encode(_bytesMatSau!)}';
        }
        updateData['anh_cccd_mat_sau'] = uploadedUrlMatSau;
      }

      // Xử lý chống xung đột UNIQUE CCCD (khach_thue_cccd_key)
      final cccdVal = updateData['cccd']?.toString().trim() ?? '';
      if (cccdVal.isNotEmpty) {
        try {
          final dupKt = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('cccd', cccdVal)
              .neq('ma_khach', _maKhach)
              .maybeSingle();

          if (dupKt != null && dupKt['ma_khach'] != null) {
            final oldMaKhach = dupKt['ma_khach'].toString();
            debugPrint(
              'Phát hiện trùng CCCD với hồ sơ cũ $oldMaKhach, đang giải phóng CCCD cũ để cập nhật...',
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

      // 1. Cập nhật bảng khach_thue
      if (_maKhach.isNotEmpty) {
        await db.from('khach_thue').update(updateData).eq('ma_khach', _maKhach);
      } else if (user != null && user.maTaiKhoan.isNotEmpty) {
        await db
            .from('khach_thue')
            .update(updateData)
            .eq('ma_tai_khoan', user.maTaiKhoan);
      }

      // 2. Cập nhật bảng tai_khoan nếu có
      if (user != null && user.maTaiKhoan.isNotEmpty) {
        try {
          await db
              .from('tai_khoan')
              .update({'ho_ten': hoTen})
              .eq('ma_tai_khoan', user.maTaiKhoan);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _isSaving = false);

      await ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Cập Nhật Hồ Sơ Thành Công!',
        noiDung:
            'Thông tin cá nhân và định danh CCCD của bạn đã được lưu đầy đủ lên Supabase.',
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
      _baoLoi('Không thể lưu thông tin: $e');
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
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Color(0xFF0F172A),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Chỉnh Sửa Hồ Sơ Cá Nhân',
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
                      Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFEF08A),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('🐥', style: TextStyle(fontSize: 30)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hoTenController.text.isNotEmpty
                                  ? _hoTenController.text
                                  : 'Cư Dân Kiêu Giang',
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
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
                            const SizedBox(height: 4),
                            Text(
                              'Hợp đồng: ${widget.maHopDong}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Phần thông tin cá nhân bắt buộc ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'THÔNG TIN CÁ NHÂN & ĐỊNH DANH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF64748B),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Text(
                        '* Bắt buộc tất cả',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Họ và tên
                      _buildTextField(
                        controller: _hoTenController,
                        label: 'Họ và tên khách thuê *',
                        hint: 'Nhập họ và tên đầy đủ',
                        icon: Icons.person_outline_rounded,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập họ và tên (không được bỏ trống)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Số điện thoại
                      _buildTextField(
                        controller: _soDtController,
                        label: 'Số điện thoại liên hệ *',
                        hint: '09xx xxx xxx',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập số điện thoại (không được bỏ trống)';
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
                        label: 'Số CCCD / Định danh (12 số) *',
                        hint: 'Ví dụ: 079201012345',
                        icon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(12),
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập số CCCD (không được bỏ trống)';
                          }
                          if (v.trim().length != 12) {
                            return 'Số CCCD phải có đúng 12 chữ số';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // 2 KHUNG ẢNH CCCD MẶT TRƯỚC VÀ MẶT SAU
                      Row(
                        children: const [
                          Icon(
                            Icons.photo_camera_back_rounded,
                            size: 15,
                            color: Color(0xFF09638E),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Ảnh chụp CCCD 2 mặt (lưu trữ hồ sơ):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildCccdBox(
                              isMatTruoc: true,
                              title: 'Mặt trước CCCD',
                              bytes: _bytesMatTruoc,
                              url: _urlMatTruoc,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildCccdBox(
                              isMatTruoc: false,
                              title: 'Mặt sau CCCD',
                              bytes: _bytesMatSau,
                              url: _urlMatSau,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Giới tính
                      const Text(
                        'Giới tính *',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
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
                      const SizedBox(height: 14),

                      // Ngày sinh
                      _buildDatePickerField(
                        label: 'Ngày sinh (theo CCCD) *',
                        currentDate: _ngaySinh,
                        onSelected: (d) => setState(() => _ngaySinh = d),
                        icon: Icons.cake_rounded,
                      ),
                      const SizedBox(height: 14),

                      // Địa chỉ thường trú
                      _buildTextField(
                        controller: _diaChiController,
                        label: 'Địa chỉ thường trú (theo CCCD) *',
                        hint: 'Xã/Phường, Quận/Huyện, Tỉnh/TP',
                        icon: Icons.home_outlined,
                        maxLines: 2,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập địa chỉ thường trú (không được bỏ trống)';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Ngày cấp & Nơi cấp
                      Row(
                        children: [
                          Expanded(
                            child: _buildDatePickerField(
                              label: 'Ngày cấp CCCD *',
                              currentDate: _ngayCapCccd,
                              onSelected: (d) =>
                                  setState(() => _ngayCapCccd = d),
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
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Nhập nơi cấp';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Người & SĐT liên hệ khẩn cấp
                      _buildTextField(
                        controller: _nguoiLienHeController,
                        label: 'Người & SĐT liên hệ khẩn cấp *',
                        hint: 'Ví dụ: Bố Nguyễn Văn B - 0912345678',
                        icon: Icons.emergency_rounded,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Vui lòng nhập người liên hệ khẩn cấp (không được bỏ trống)';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Card Phương Tiện Xe Gửi Tại Trọ ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
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
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.two_wheeler_rounded,
                              color: Color(0xFFD97706),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'PHƯƠNG TIỆN XE ĐĂNG KÝ',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _showModalSuaPhuongTien(null),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF09638E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_rounded,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Thêm xe',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
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
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.directions_walk_rounded,
                                color: Color(0xFF94A3B8),
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Chưa có phương tiện xe nào được đăng ký.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _danhSachPhuongTien.length,
                          separatorBuilder: (_, __) => const Divider(
                            height: 14,
                            color: Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, idx) {
                            final xe = _danhSachPhuongTien[idx];
                            final bienSo =
                                xe['bien_so_xe']?.toString() ??
                                'Chưa có biển số';
                            final loaiXe =
                                xe['loai_xe']?.toString() ?? 'Xe máy';

                            return InkWell(
                              onTap: () => _showModalSuaPhuongTien(xe),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE0F2FE),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.moped_rounded,
                                        color: Color(0xFF09638E),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bienSo,
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            loaiXe,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Color(0xFF09638E),
                                      ),
                                      onPressed: () =>
                                          _showModalSuaPhuongTien(xe),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Sửa xe',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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
                            'Lưu Thay Đổi Lên Hệ Thống',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
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
            color: isSelected
                ? const Color(0xFF09638E)
                : const Color(0xFFF8FAFC),
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
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF334155),
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
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      fontWeight: currentDate != null
                          ? FontWeight.w600
                          : FontWeight.normal,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
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
          maxLines: maxLines,
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
            hintStyle: const TextStyle(
              fontSize: 13,
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.normal,
            ),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF09638E)),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF09638E),
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFDC2626),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

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
    } catch (e) {
      debugPrint('Lỗi chọn ảnh CCCD: $e');
    }
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

  Widget _buildCccdBox({
    required bool isMatTruoc,
    required String title,
    Uint8List? bytes,
    String? url,
  }) {
    final hasImage = bytes != null || (url != null && url.isNotEmpty);

    return InkWell(
      onTap: () => _hienThiModalChonAnh(isMatTruoc),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasImage ? const Color(0xFF09638E) : const Color(0xFFCBD5E1),
            width: hasImage ? 2 : 1,
          ),
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
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
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
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
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
                  const Icon(
                    Icons.add_a_photo_outlined,
                    color: Color(0xFF09638E),
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Chạm để chụp / chọn ảnh',
                    style: TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
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
}

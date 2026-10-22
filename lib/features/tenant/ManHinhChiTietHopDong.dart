import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/core/widgets/BangKyTay.dart';
import 'package:nhatro_kieugiang/core/widgets/ChuKyBenAMacDinh.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhDichVu.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChamDutHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhGiaHanHopDong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ContractDetailScreen extends StatefulWidget {
  final String maHopDong;

  const ContractDetailScreen({super.key, this.maHopDong = 'HD001'});

  @override
  State<ContractDetailScreen> createState() => _ContractDetailScreenState();
}

class _ContractDetailScreenState extends State<ContractDetailScreen> {
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  // Đường dẫn chữ ký số mặc định của Bên A (Chủ trọ / Ban Quản Lý)
  static const String _defaultChuKyBenAAsset =
      'assets/images/chuky_ben_a_mac_dinh.png';

  bool _isLoading = true;
  String? _errorMessage;

  HopDongModel? _hopDong;
  RoomModel? _phong;
  KhachThueModel? _khachDaiDien;
  List<KhachThueModel> _danhSachOCung = [];
  List<DichVuModel> _danhSachDichVu = [];
  List<PhuLucHopDongModel> _danhSachPhuLuc = [];

  // ─── Chữ ký tay ───
  // Bên A: Chữ ký số mặc định do BQL phê duyệt, Bên B không được ký
  // Bên B: Người thuê vẽ chữ ký tay xác nhận
  final ChuKyController _controlBenB = ChuKyController();
  final ScrollController _scrollController = ScrollController();
  String? _urlChuKyBenA; // URL ảnh chữ ký Bên A đã lưu trên Supabase (nếu có)
  String? _urlChuKyBenB; // URL ảnh chữ ký Bên B đã lưu trên Supabase
  bool _dangLuuKyBenB = false;

  /// Kiểm tra xem tài khoản đang đăng nhập có phải là Người đại diện hợp đồng hay không
  bool get _isNguoiDaiDien {
    final user = AuthService.currentUser;
    if (user == null) return true;

    // 0. Quản trị viên hoặc Chủ trọ luôn có toàn quyền
    final authRole = user.vaiTro.toLowerCase();
    if (authRole.contains('admin') ||
        authRole.contains('chutro') ||
        authRole.contains('quanly')) {
      return true;
    }

    // 1. So khớp với khách đại diện hợp đồng
    if (_khachDaiDien != null) {
      if (_khachDaiDien!.maTaiKhoan != null &&
          _khachDaiDien!.maTaiKhoan!.isNotEmpty &&
          user.maTaiKhoan.isNotEmpty) {
        if (_khachDaiDien!.maTaiKhoan == user.maTaiKhoan) return true;
      }
      if (_khachDaiDien!.soDt.isNotEmpty && user.tenDangNhap.isNotEmpty) {
        final dtKhach = _khachDaiDien!.soDt.replaceAll(RegExp(r'\D'), '');
        final dtUser = user.tenDangNhap.replaceAll(RegExp(r'\D'), '');
        if (dtKhach.isNotEmpty && dtKhach == dtUser) return true;
      }
      if (_khachDaiDien!.hoTenKhach.isNotEmpty && user.tenHienThi.isNotEmpty) {
        if (_khachDaiDien!.hoTenKhach.trim().toLowerCase() ==
            user.tenHienThi.trim().toLowerCase()) {
          return true;
        }
      }
    }

    // 2. Nếu người dùng trùng khớp với bất kỳ ai trong danh sách ở cùng -> chắc chắn không phải đại diện
    if (_danhSachOCung.isNotEmpty) {
      final isOCung = _danhSachOCung.any((oc) {
        if (oc.maTaiKhoan != null &&
            oc.maTaiKhoan!.isNotEmpty &&
            oc.maTaiKhoan == user.maTaiKhoan)
          return true;
        if (oc.soDt.isNotEmpty && user.tenDangNhap.isNotEmpty) {
          final dt1 = oc.soDt.replaceAll(RegExp(r'\D'), '');
          final dt2 = user.tenDangNhap.replaceAll(RegExp(r'\D'), '');
          if (dt1.isNotEmpty && dt1 == dt2) return true;
        }
        if (oc.hoTenKhach.trim().toLowerCase() ==
            user.tenHienThi.trim().toLowerCase())
          return true;
        return false;
      });
      if (isOCung) return false;
    }

    // 3. Vai trò từ bảng tài khoản
    if (authRole.contains('truongphong') || authRole.contains('daidien'))
      return true;
    if (authRole.contains('thanhvien') ||
        authRole.contains('banocung') ||
        authRole.contains('ocung'))
      return false;

    // 4. Nếu phòng chỉ có 1 người ở
    if (_danhSachOCung.isEmpty && _khachDaiDien != null) return true;

    return false;
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
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
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
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Color(0xFF09638E),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Theo quy định hợp đồng, thủ tục "$hanhDong" chỉ có Người đại diện (Trưởng phòng đứng tên trên hợp đồng) mới có thẩm quyền thực hiện.',
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
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.3,
              ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Đã hiểu',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchContractData();
  }

  @override
  void dispose() {
    _controlBenB.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchContractData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = Supabase.instance.client;

      // 1. Tải thông tin Hợp đồng
      final contractQuery = await db
          .from('hop_dong')
          .select()
          .eq('ma_hop_dong', widget.maHopDong)
          .maybeSingle();

      Map<String, dynamic>? contractData = contractQuery;

      // Fallback nếu không tìm thấy mã truyền vào, tìm mã HD001
      contractData ??= await db
          .from('hop_dong')
          .select()
          .eq('ma_hop_dong', 'HD001')
          .maybeSingle();

      if (contractData != null) {
        _hopDong = HopDongModel.fromJson(contractData);

        // 2. Tải thông tin Phòng tương ứng
        if (_hopDong!.maPhong.isNotEmpty) {
          final phongData = await db
              .from('phong')
              .select()
              .eq('ma_phong', _hopDong!.maPhong)
              .maybeSingle();
          if (phongData != null) {
            _phong = RoomModel.fromJson(phongData);
          }
        }

        // 3. Tải danh sách khách thuê thuộc hợp đồng
        final chiTietList = await db
            .from('chi_tiet_hop_dong_khach_thue')
            .select()
            .eq('ma_hop_dong', _hopDong!.maHopDong);

        final List<KhachThueModel> allKhach = [];
        for (final item in chiTietList) {
          final maKhach = item['ma_khach']?.toString() ?? '';
          if (maKhach.isNotEmpty) {
            final ktData = await db
                .from('khach_thue')
                .select()
                .eq('ma_khach', maKhach)
                .maybeSingle();
            if (ktData != null) {
              final kt = KhachThueModel.fromJson(ktData);
              kt.vaiTro = item['vai_tro']?.toString() ?? 'Thành viên ở cùng';
              kt.trangThaiLuuTru =
                  item['trang_thai_luu_tru']?.toString() ?? 'Đang ở';
              allKhach.add(kt);
            }
          }
        }

        // Phân loại khách đại diện và người ở cùng
        if (allKhach.any(
          (k) =>
              k.vaiTro == 'Đại diện hợp đồng' ||
              k.maKhach == _hopDong!.maKhachDaiDien,
        )) {
          _khachDaiDien = allKhach.firstWhere(
            (k) =>
                k.vaiTro == 'Đại diện hợp đồng' ||
                k.maKhach == _hopDong!.maKhachDaiDien,
          );
        } else if (allKhach.isNotEmpty) {
          _khachDaiDien = allKhach.first;
        } else if (_hopDong!.maKhachDaiDien.isNotEmpty) {
          final ktData = await db
              .from('khach_thue')
              .select()
              .eq('ma_khach', _hopDong!.maKhachDaiDien)
              .maybeSingle();
          if (ktData != null) {
            _khachDaiDien = KhachThueModel.fromJson(ktData);
          }
        }

        _danhSachOCung = allKhach
            .where((k) => k.maKhach != _khachDaiDien?.maKhach)
            .toList();
      }

      // 4. Tải danh mục Bảng giá Dịch vụ cam kết
      final dvData = await db.from('dich_vu').select();
      _danhSachDichVu = dvData.map((e) => DichVuModel.fromJson(e)).toList();
      // 5. Tải URL chữ ký đã lưu (nếu có)
      if (_hopDong != null) {
        _urlChuKyBenA = contractData?['chu_ky_ben_a'] as String?;
        _urlChuKyBenB = contractData?['chu_ky_ben_b'] as String?;

        // Tự động tải chữ ký Bên A lên Supabase nếu chưa có
        if (_urlChuKyBenA == null || _urlChuKyBenA!.isEmpty) {
          _khoiTaoChuKyBenATrenSupabase(db, _hopDong!.maHopDong);
        }

        // 6. Tải danh sách các Phụ Lục Hợp Đồng đã ký của hợp đồng này
        try {
          final plData = await db
              .from('phu_luc_hop_dong')
              .select()
              .eq('ma_hop_dong', _hopDong!.maHopDong)
              .order('ngay_lap', ascending: false);
          _danhSachPhuLuc = (plData as List)
              .map((e) => PhuLucHopDongModel.fromJson(e))
              .toList();
        } catch (errPl) {
          debugPrint('Lỗi tải phụ lục hợp đồng: $errPl');
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu hợp đồng: $e');
      _errorMessage = 'Không thể tải dữ liệu hợp đồng: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Tự động tải chữ ký Bên A lên Supabase và lưu vào bảng hop_dong
  Future<void> _khoiTaoChuKyBenATrenSupabase(
    SupabaseClient db,
    String maHd,
  ) async {
    try {
      final pngBytes = await ChuKyBenAMacDinhWidget.toPngBytes(
        width: 800,
        height: 320,
      );
      final fileName = 'chuky_${maHd}_ben_a.png';
      final storagePath = 'hop_dong/$fileName';

      String signatureData = '';
      try {
        await db.storage
            .from('contracts')
            .uploadBinary(
              storagePath,
              pngBytes,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: true,
              ),
            );
        signatureData = db.storage.from('contracts').getPublicUrl(storagePath);
      } catch (storageError) {
        debugPrint(
          'Storage bucket contracts chặn RLS, fallback lưu Base64 an toàn vào DB: $storageError',
        );
        final base64String = base64Encode(pngBytes);
        signatureData = 'data:image/png;base64,$base64String';
      }

      await db
          .from('hop_dong')
          .update({'chu_ky_ben_a': signatureData})
          .eq('ma_hop_dong', maHd);

      if (mounted) {
        setState(() {
          _urlChuKyBenA = signatureData;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tự động tải chữ ký Bên A lên Supabase: $e');
    }
  }

  // ─── Lưu chữ ký Bên B lên Supabase Storage & cập nhật hop_dong ───
  Future<void> _luuChuKy({required bool isBenA}) async {
    // Ràng buộc bảo mật: Bên B (người thuê) không được phép ký thay cho Bên A
    if (isBenA) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Chữ ký Bên A bảo mật',
        noiDung:
            'Chữ ký Bên A đã được Ban Quản Lý xác thực sẵn và khóa bảo mật!',
        type: ThongBaoType.thongTin,
      );
      return;
    }

    // Ràng buộc pháp lý: Chữ ký Bên B đã ký và lưu rồi thì không cho phép ký lại
    if (_urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Hợp đồng đã ký',
        noiDung:
            'Hợp đồng đã có chữ ký Bên B được xác thực và khóa bảo mật, không thể ký lại!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    final ctrl = _controlBenB;
    if (!ctrl.isFilled) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Chưa có chữ ký',
        noiDung: 'Vui lòng ký vào ô chữ ký trước khi xác nhận!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    setState(() {
      _dangLuuKyBenB = true;
    });

    try {
      // Export chữ ký thành PNG bytes trực tiếp từ Native Canvas
      final Uint8List? pngBytes = await ctrl.toPngBytes(
        width: 800,
        height: 320,
      );
      if (pngBytes == null) throw Exception('Không xuất được ảnh chữ ký');

      final db = Supabase.instance.client;
      final maHd = _hopDong?.maHopDong ?? 'HD001';
      final fileName = 'chuky_${maHd}_ben_b.png';
      final storagePath = 'hop_dong/$fileName';

      String signatureData = '';
      try {
        // 1. Thử upload lên Supabase Storage bucket "contracts"
        await db.storage
            .from('contracts')
            .uploadBinary(
              storagePath,
              pngBytes,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: true,
              ),
            );
        signatureData = db.storage.from('contracts').getPublicUrl(storagePath);
      } catch (storageError) {
        debugPrint(
          'Storage bucket contracts chặn RLS, fallback lưu Base64 an toàn vào DB: $storageError',
        );
        // 2. Fallback an toàn: Lưu Base64 Data URI trực tiếp vào cột chu_ky_ben_b
        final base64String = base64Encode(pngBytes);
        signatureData = 'data:image/png;base64,$base64String';
      }

      // Cập nhật chữ ký vào bảng hop_dong
      await db
          .from('hop_dong')
          .update({'chu_ky_ben_b': signatureData})
          .eq('ma_hop_dong', maHd);

      if (mounted) {
        setState(() {
          _urlChuKyBenB = signatureData;
        });
        _showSignatureSuccessDialog();
      }
    } catch (e) {
      debugPrint('Lỗi lưu chữ ký: $e');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi lưu chữ ký',
          noiDung: 'Lỗi lưu chữ ký: $e',
          type: ThongBaoType.thatBai,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _dangLuuKyBenB = false;
        });
      }
    }
  }

  /// Modal Card thông báo ở giữa màn hình khi Bên B ký thành công
  void _showSignatureSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final maHd = _hopDong?.maHopDong ?? 'HD001';
        final soPhong = _phong?.tenHienThi ?? 'Phòng';
        final tenKhach = _khachDaiDien?.hoTenKhach ?? 'Khách thuê';
        final now = DateTime.now();
        final nowStr =
            '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} • ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Banner với Icon thành công nổi bật
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF22C55E,
                                  ).withValues(alpha: 0.4),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 38,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'KÝ HỢP ĐỒNG THÀNH CÔNG',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hợp đồng điện tử số $maHd đã được xác thực',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Nội dung thông tin chi tiết
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              children: [
                                _buildSuccessInfoRow(
                                  'Mã hợp đồng',
                                  maHd,
                                  isBold: true,
                                ),
                                const Divider(
                                  height: 14,
                                  color: Color(0xFFE2E8F0),
                                ),
                                _buildSuccessInfoRow(
                                  'Phòng thuê',
                                  'Phòng $soPhong',
                                ),
                                const Divider(
                                  height: 14,
                                  color: Color(0xFFE2E8F0),
                                ),
                                _buildSuccessInfoRow(
                                  'Bên B (Người ký)',
                                  tenKhach,
                                ),
                                const Divider(
                                  height: 14,
                                  color: Color(0xFFE2E8F0),
                                ),
                                _buildSuccessInfoRow('Thời gian ký', nowStr),
                                const Divider(
                                  height: 14,
                                  color: Color(0xFFE2E8F0),
                                ),
                                _buildSuccessInfoRow(
                                  'Tình trạng',
                                  'Đã có đủ chữ ký A & B',
                                  valueColor: const Color(0xFF16A34A),
                                  isBold: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Icon(
                                Icons.verified_rounded,
                                size: 16,
                                color: Color(0xFF16A34A),
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Chữ ký đã được lưu trữ bảo mật trực tiếp vào hệ thống cơ sở dữ liệu.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Các nút tương tác
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    side: const BorderSide(
                                      color: Color(0xFFCBD5E1),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Xem lại hợp đồng',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _xuatPdfHopDong();
                                  },
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Tải file PDF',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
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
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Nạp font chữ tiếng Việt cho PDF ───
  Future<pw.ThemeData> _napPdfTheme() async {
    pw.Font fontRegular;
    pw.Font fontBold;
    pw.Font fontItalic;
    pw.Font fontBoldItalic;
    try {
      final fontRegularData = await rootBundle.load('assets/fonts/arial.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/arialbd.ttf');
      fontRegular = pw.Font.ttf(fontRegularData);
      fontBold = pw.Font.ttf(fontBoldData);
      fontItalic = fontRegular;
      fontBoldItalic = fontBold;
    } catch (e) {
      debugPrint('Không đọc được font từ assets, nạp từ Google Fonts: $e');
      try {
        fontRegular = await PdfGoogleFonts.robotoRegular();
        fontBold = await PdfGoogleFonts.robotoBold();
        fontItalic = await PdfGoogleFonts.robotoItalic();
        fontBoldItalic = await PdfGoogleFonts.robotoBoldItalic();
      } catch (e2) {
        debugPrint('Lỗi tải font từ Google Fonts: $e2');
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
        fontItalic = pw.Font.helveticaOblique();
        fontBoldItalic = pw.Font.helveticaBoldOblique();
      }
    }

    return pw.ThemeData.withFont(
      base: fontRegular,
      bold: fontBold,
      italic: fontItalic,
      boldItalic: fontBoldItalic,
    );
  }

  // ─── Tải ảnh chữ ký tay Bên A và Bên B ───
  Future<Map<String, pw.MemoryImage?>> _taiAnhChuKyHaiBen() async {
    pw.MemoryImage? imgChuKyA;
    pw.MemoryImage? imgChuKyB;

    if (_urlChuKyBenA != null && _urlChuKyBenA!.isNotEmpty) {
      try {
        if (_urlChuKyBenA!.startsWith('data:image')) {
          final base64Str = _urlChuKyBenA!.split(',').last;
          imgChuKyA = pw.MemoryImage(base64Decode(base64Str));
        } else {
          final res = await http.get(Uri.parse(_urlChuKyBenA!));
          if (res.statusCode == 200) {
            imgChuKyA = pw.MemoryImage(res.bodyBytes);
          }
        }
      } catch (e) {
        debugPrint('Lỗi tải ảnh chữ ký Bên A: $e');
      }
    }

    if (imgChuKyA == null) {
      try {
        final byteData = await rootBundle.load(_defaultChuKyBenAAsset);
        imgChuKyA = pw.MemoryImage(byteData.buffer.asUint8List());
      } catch (e) {
        debugPrint('Lỗi tải ảnh chữ ký mặc định Bên A từ asset: $e');
        try {
          final bytes = await ChuKyBenAMacDinhWidget.toPngBytes(
            width: 800,
            height: 320,
          );
          imgChuKyA = pw.MemoryImage(bytes);
        } catch (_) {}
      }
    }

    if (_urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty) {
      try {
        if (_urlChuKyBenB!.startsWith('data:image')) {
          final base64Str = _urlChuKyBenB!.split(',').last;
          imgChuKyB = pw.MemoryImage(base64Decode(base64Str));
        } else {
          final res = await http.get(Uri.parse(_urlChuKyBenB!));
          if (res.statusCode == 200) {
            imgChuKyB = pw.MemoryImage(res.bodyBytes);
          }
        }
      } catch (e) {
        debugPrint('Lỗi tải ảnh chữ ký Bên B: $e');
      }
    }

    return {'benA': imgChuKyA, 'benB': imgChuKyB};
  }

  // ─── 1. XUẤT PDF HỢP ĐỒNG THUÊ NHÀ Ở (12 ĐIỀU CHUẨN LUẬT KDBĐS 2023) ───
  Future<void> _xuatPdfHopDong() async {
    if (mounted) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Đang tạo PDF Hợp Đồng',
        noiDung: 'Đang xuất Hợp đồng thuê nhà ở 12 điều chuẩn pháp lý...',
        type: ThongBaoType.thongTin,
        duration: const Duration(seconds: 2),
      );
    }

    try {
      final theme = await _napPdfTheme();
      final pdf = pw.Document(theme: theme);
      final hd = _hopDong;
      final phong = _phong;
      final rep = _khachDaiDien;

      final chuKyMap = await _taiAnhChuKyHaiBen();
      final imgChuKyA = chuKyMap['benA'];
      final imgChuKyB = chuKyMap['benB'];

      final String tenPhong =
          phong?.tenHienThi ?? 'Phòng ${phong?.maPhong ?? 'P203'}';
      final String diaChiToaNha =
          phong?.toaNha ??
          'Kiêu Giang House, P. Hiệp Bình Chánh, TP. Thủ Đức, TP.HCM';
      final String dienTich = '${phong?.dienTich ?? 28} m²';
      final String giaThueText =
          '${FormatUtils.currency((hd?.giaThueThaoThuan ?? 3800000).toDouble())} đồng/tháng';
      final String tienCocText =
          '${FormatUtils.currency((hd?.tienDatCoc ?? 3800000).toDouble())} đồng';
      final String thoiHanThue = hd?.thoiHanHopDongText ?? '12 tháng';
      final String ngayBd = hd?.ngayBdFormatted ?? '01/01/2026';
      final String ngayKt = hd?.ngayKtFormatted ?? '31/12/2026';
      final noiThatStr = phong?.noiThatSanCo.isNotEmpty == true
          ? phong!.noiThatSanCo.join(', ')
          : 'Máy lạnh Inverter, Tủ lạnh riêng 130L, Nước nóng Ariston, Tủ áo, Bàn làm việc, Kệ bếp sinh hoạt, Khóa cổng vân tay AI';

      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          build: (pw.Context context) {
            return [
              // Quốc hiệu, tiêu ngữ
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    pw.Text(
                      'Độc lập - Tự do - Hạnh phúc',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'HỢP ĐỒNG THUÊ NHÀ Ở',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Số: ${hd?.maHopDong ?? 'HD001'} / HĐTN-KG',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              // Căn cứ pháp lý
              pw.Text(
                '• Căn cứ Bộ luật Dân sự ngày 24 tháng 11 năm 2015;\n'
                '• Căn cứ Luật Nhà ở ngày 27 tháng 11 năm 2023;\n'
                '• Căn cứ Luật Kinh doanh bất động sản ngày 28 tháng 11 năm 2023;\n'
                '• Căn cứ Nghị định số 96/2024/NĐ-CP của Chính phủ quy định chi tiết một số điều của Luật Kinh doanh bất động sản;\n'
                '• Căn cứ nhu cầu và sự thỏa thuận tự nguyện giữa hai bên.',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontStyle: pw.FontStyle.italic,
                  height: 1.3,
                ),
              ),
              pw.SizedBox(height: 10),

              pw.Text(
                'Hôm nay, ngày $ngayBd, tại Hệ thống Nhà trọ Kiêu Giang, hai bên chúng tôi gồm có:',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.SizedBox(height: 8),

              // BÊN A
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'I. BÊN CHO THUÊ NHÀ Ở (BÊN CHO THUÊ - BÊN A):',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Tên cơ sở: HỆ THỐNG NHÀ TRỌ KIÊU GIANG',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Người đại diện pháp lý / Quản lý: TRỊNH MỸ DUYÊN',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'CCCD/ĐKKD số: 079198004663  -  Cấp tại: Cục CS QLHC về TTXH',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Địa chỉ cơ sở: $diaChiToaNha',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Điện thoại hotline / BQL: 0328 004 663',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // BÊN B
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'II. BÊN THUÊ NHÀ Ở (BÊN THUÊ - BÊN B):',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Họ và tên: ${rep?.hoTenKhach ?? 'Khách thuê'}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Số CCCD/CMND: ${rep?.cccd ?? ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Địa chỉ thường trú: ${rep?.diaChiThuongTru ?? ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Điện thoại liên hệ: ${rep?.soDt ?? ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    if (_danhSachOCung.isNotEmpty)
                      pw.Text(
                        'Thành viên cùng ở (${_danhSachOCung.length} người): ${_danhSachOCung.map((e) => '${e.hoTenKhach} (${e.cccd})').join(', ')}',
                        style: const pw.TextStyle(fontSize: 8.5),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              pw.Text(
                'Hai bên cùng thống nhất ký kết Hợp đồng thuê nhà ở theo các điều khoản cụ thể sau đây:',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.SizedBox(height: 8),

              // 12 Điều khoản hợp đồng
              _buildPdfArticle(
                'Điều 1. Các thông tin về nhà ở cho thuê',
                '1.1. Bên A đồng ý cho Bên B thuê căn phòng: $tenPhong, tại địa chỉ: $diaChiToaNha.\n'
                    '1.2. Diện tích sử dụng thực tế: $dienTich.\n'
                    '1.3. Trang thiết bị gắn liền với nhà ở bàn giao: $noiThatStr.\n'
                    '1.4. Mục đích sử dụng: Chỉ sử dụng làm nơi ở sinh hoạt hợp pháp; số lượng người cư trú tối đa theo đăng ký (02 người).',
              ),
              _buildPdfArticle(
                'Điều 2. Giá thuê nhà ở và chi phí sử dụng dịch vụ',
                '2.1. Giá thuê nhà ở cố định: $giaThueText (Cam kết không tăng giá trong suốt thời hạn hợp đồng).\n'
                    '2.2. Chi phí sử dụng dịch vụ tiêu thụ hàng tháng:\n'
                    '   - Tiền điện: 3.500 đ/kWh (tính theo chỉ số công tơ điện tử riêng từng phòng).\n'
                    '   - Tiền nước máy thủy cục: 20.000 đ/m³ (tính theo đồng hồ đo nước riêng).\n'
                    '   - Dịch vụ chung (Wifi cáp quang tốc độ cao, vệ sinh hành lang, bảo trì): theo đơn giá niêm yết tòa nhà.\n'
                    '2.3. Tiền đặt cọc bảo đảm thực hiện hợp đồng: $tienCocText (tương đương 01 tháng tiền phòng). Bên A có trách nhiệm hoàn trả 100% tiền đặt cọc cho Bên B khi kết thúc hợp đồng theo đúng thỏa thuận.',
              ),
              _buildPdfArticle(
                'Điều 3. Phương thức và thời hạn thanh toán',
                '3.1. Phương thức thanh toán: Chuyển khoản ngân hàng (quét mã VietQR trên App Kiêu Giang) hoặc tiền mặt.\n'
                    '3.2. Thời hạn thanh toán: Định kỳ chu kỳ ${hd?.chuKyThuTien ?? 1} tháng/lần, từ ngày 01 đến ngày 05 của mỗi tháng thanh toán.',
              ),
              _buildPdfArticle(
                'Điều 4. Thời hạn thuê nhà ở và thời điểm bàn giao',
                '4.1. Thời hạn thuê nhà ở là: $thoiHanThue, bắt đầu từ ngày $ngayBd đến hết ngày $ngayKt.\n'
                    '4.2. Thời điểm bàn giao nhà ở: Bắt đầu từ ngày $ngayBd cùng toàn bộ trang thiết bị nội thất hoạt động bình thường.',
              ),
              _buildPdfArticle(
                'Điều 5. Quyền và nghĩa vụ của Bên cho thuê (Bên A)',
                '5.1. Quyền của Bên cho thuê:\n'
                    '   - Yêu cầu Bên thuê nhận nhà theo đúng thỏa thuận và sử dụng đúng mục đích cư trú.\n'
                    '   - Yêu cầu Bên thuê thanh toán đủ và đúng hạn tiền thuê nhà và các chi phí dịch vụ.\n'
                    '   - Yêu cầu Bên thuê giữ gìn vệ sinh, trật tự chung và bảo vệ tài sản, thiết bị bàn giao.\n'
                    '   - Đơn phương chấm dứt hợp đồng nếu Bên B có hành vi vi phạm nghiêm trọng (chậm nộp tiền phòng quá hạn, chứa hàng cấm, gây rối).\n'
                    '5.2. Nghĩa vụ của Bên cho thuê:\n'
                    '   - Bàn giao nhà ở và trang thiết bị cho Bên thuê đúng thời hạn cam kết.\n'
                    '   - Bảo đảm cung cấp ổn định nguồn điện, nước, internet, cổng khóa thông minh cho Bên B sử dụng 24/7.\n'
                    '   - Bảo đảm quyền sử dụng trọn vẹn, hợp pháp của Bên B đối với nhà ở trong suốt thời hạn thuê.\n'
                    '   - Hoàn trả lại 100% tiền đặt cọc cho Bên thuê khi thanh lý hợp đồng đúng quy định.',
              ),
              _buildPdfArticle(
                'Điều 6. Quyền và nghĩa vụ của Bên thuê (Bên B)',
                '6.1. Quyền của Bên thuê:\n'
                    '   - Nhận bàn giao nhà ở và trang thiết bị kèm theo đúng tình trạng cam kết.\n'
                    '   - Được toàn quyền sử dụng nhà ở theo mục đích cư trú hợp pháp; giờ giấc tự do ra vào 24/7.\n'
                    '   - Yêu cầu Bên cho thuê sửa chữa kịp thời các hư hỏng kết cấu chung không do lỗi của Bên thuê.\n'
                    '   - Được nhận lại đầy đủ 100% tiền đặt cọc khi chấm dứt hợp đồng đúng thỏa thuận.\n'
                    '6.2. Nghĩa vụ của Bên thuê:\n'
                    '   - Sử dụng nhà ở đúng mục đích; không được tự ý cải tạo, cơi nới, đục phá tường, kết cấu phòng.\n'
                    '   - Thanh toán đầy đủ, đúng hạn tiền thuê phòng và các khoản tiền điện, nước, dịch vụ phát sinh.\n'
                    '   - Bảo quản tài sản, thiết bị nội thất được bàn giao ban đầu (nếu làm hỏng phải sửa, làm mất phải bồi thường).\n'
                    '   - Tuân thủ tuyệt đối quy định an ninh, an toàn PCCC, không đun nấu bằng bếp gas mini không an toàn, tắt thiết bị điện khi ra ngoài.\n'
                    '   - Khách ở qua đêm phải khai báo tạm trú trên App Kiêu Giang trước 22h00; Bên B chịu trách nhiệm về khách của mình.',
              ),
              _buildPdfArticle(
                'Điều 7. Đơn phương chấm dứt thực hiện hợp đồng thuê nhà ở',
                '7.1. Một trong hai bên có quyền đơn phương chấm dứt hợp đồng và phải thông báo bằng văn bản (hoặc gửi đơn trên App Kiêu Giang) cho bên kia biết trước ít nhất 30 ngày.\n'
                    '7.2. Nếu Bên thuê tự ý đơn phương chấm dứt hợp đồng trước hạn mà không thuộc các trường hợp pháp luật cho phép hoặc không báo trước đủ 30 ngày thì sẽ không được hoàn trả tiền đặt cọc theo thỏa thuận.',
              ),
              _buildPdfArticle(
                'Điều 8. Các trường hợp chấm dứt hợp đồng và xử lý hậu quả',
                '8.1. Hợp đồng chấm dứt khi: Hết hạn hợp đồng mà hai bên không gia hạn; Hai bên thỏa thuận chấm dứt bằng văn bản; hoặc Nhà ở không còn bảo đảm an toàn kết cấu.\n'
                    '8.2. Xử lý hậu quả chấm dứt hợp đồng:\n'
                    '   - Hai bên cùng tiến hành chốt chỉ số công tơ điện nước và kiểm tra hiện trạng bàn giao tài sản, chìa khóa phòng.\n'
                    '   - Sau khi cấn trừ tiền điện nước tiêu thụ kỳ cuối và chi phí bồi hoàn hư hỏng (nếu có), Bên A có trách nhiệm hoàn trả lại toàn bộ số tiền đặt cọc còn lại cho Bên B trong vòng 03 ngày làm việc.',
              ),
              _buildPdfArticle(
                'Điều 9. Phạt vi phạm hợp đồng và bồi thường thiệt hại',
                '9.1. Bên nào vi phạm hợp đồng gây thiệt hại cho bên kia thì phải bồi thường toàn bộ thiệt hại thực tế phát sinh.\n'
                    '9.2. Nếu Bên B chậm thanh toán tiền thuê phòng quá 15 ngày kể từ ngày đến hạn mà không có lý do chính đáng được Bên A chấp thuận, Bên A có quyền tạm ngắt dịch vụ và đơn phương thu hồi phòng.',
              ),
              _buildPdfArticle(
                'Điều 10. Sự kiện bất khả kháng',
                'Các bên không bị coi là vi phạm hợp đồng và không phải chịu trách nhiệm bồi thường nếu việc không thực hiện nghĩa vụ là do các sự kiện bất khả kháng theo quy định pháp luật (thiên tai, dịch bệnh, hỏa hoạn khách quan hoặc quyết định của cơ quan Nhà nước có thẩm quyền).',
              ),
              _buildPdfArticle(
                'Điều 11. Giải quyết tranh chấp',
                'Mọi tranh chấp phát sinh từ hợp đồng này sẽ được các bên ưu tiên thương lượng giải quyết trên tinh thần dân chủ và hợp tác. Trường hợp không tự thỏa thuận được, tranh chấp sẽ được đưa ra Tòa án nhân dân có thẩm quyền để giải quyết theo quy định pháp luật.',
              ),
              _buildPdfArticle(
                'Điều 12. Hiệu lực của hợp đồng',
                '12.1. Hợp đồng này có hiệu lực kể từ ngày ký.\n'
                    '12.2. Hợp đồng gồm 12 điều, được lập thành 02 bản có giá trị pháp lý như nhau, mỗi bên giữ 01 bản để thực hiện. Các phụ lục hợp đồng kèm theo (nếu có) là bộ phận cấu thành không thể tách rời của Hợp đồng này.\n'
                    '12.3. Mọi sửa đổi, bổ sung nội dung hợp đồng phải được hai bên lập thành Phụ lục hợp đồng bằng văn bản hoặc xác nhận điện tử.',
              ),
              pw.SizedBox(height: 16),

              // Bảng ký tên hai bên
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Đại diện Bên B
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'ĐẠI DIỆN BÊN B (BÊN THUÊ)',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                        pw.Text(
                          '(Ký, ghi rõ họ tên)',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (imgChuKyB != null)
                          pw.Container(
                            height: 60,
                            alignment: pw.Alignment.center,
                            child: pw.Image(
                              imgChuKyB,
                              height: 55,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        else
                          pw.SizedBox(height: 60),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          rep?.hoTenKhach ?? 'Bên B đã ký',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                        if (_urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty)
                          pw.Text(
                            '(Đã ký số điện tử)',
                            style: const pw.TextStyle(
                              fontSize: 7.5,
                              color: PdfColors.green700,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Đại diện Bên A
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'ĐẠI DIỆN BÊN A (BÊN CHO THUÊ)',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                        pw.Text(
                          '(Ký, ghi rõ họ tên & đóng dấu)',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (imgChuKyA != null)
                          pw.Container(
                            height: 60,
                            alignment: pw.Alignment.center,
                            child: pw.Image(
                              imgChuKyA,
                              height: 55,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        else
                          pw.SizedBox(height: 60),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'TRỊNH MỸ DUYÊN',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                        pw.Text(
                          '(BQL Hệ Thống Kiêu Giang)',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.blue700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'HopDongThueNha_${hd?.maHopDong ?? 'HD001'}_${phong?.maPhong ?? 'P203'}.pdf',
      );
    } catch (e, stack) {
      debugPrint('Lỗi xuất PDF hợp đồng: $e\n$stack');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi xuất file',
          noiDung: 'Lỗi xuất file PDF hợp đồng: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  // ─── 2. XUẤT PDF PHỤ LỤC HỢP ĐỒNG THUÊ PHÒNG TRỌ (THEO MẪU DOCX) ───
  Future<void> _xuatPdfPhuLuc(PhuLucHopDongModel pl) async {
    if (mounted) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Đang tạo PDF Phụ Lục',
        noiDung: 'Đang chuẩn bị in Phụ lục hợp đồng: ${pl.maPhuLuc}...',
        type: ThongBaoType.thongTin,
        duration: const Duration(seconds: 2),
      );
    }

    try {
      final theme = await _napPdfTheme();
      final pdf = pw.Document(theme: theme);
      final hd = _hopDong;
      final phong = _phong;
      final rep = _khachDaiDien;

      final chuKyMap = await _taiAnhChuKyHaiBen();
      final imgChuKyA = chuKyMap['benA'];
      final imgChuKyB = chuKyMap['benB'];

      final String tenPhong = pl.maPhongMoi != null && pl.maPhongMoi!.isNotEmpty
          ? 'Phòng ${pl.maPhongMoi}'
          : (phong?.tenHienThi ?? 'Phòng ${phong?.maPhong ?? 'P203'}');
      final String diaChiToaNha =
          phong?.toaNha ??
          'Kiêu Giang House, Phường Hiệp Bình Chánh, TP. Thủ Đức, TP.HCM';
      final String giaThueText = pl.giaTheMoi > 0
          ? '${FormatUtils.currency(pl.giaTheMoi.toDouble())} đ/tháng'
          : '${FormatUtils.currency((hd?.giaThueThaoThuan ?? 3800000).toDouble())} đ/tháng';
      final String tienCocText =
          '${FormatUtils.currency((hd?.tienDatCoc ?? 3800000).toDouble())} đ (Bảo lưu chuyển tiếp)';
      final String ngayGiaHanDenText = pl.ngayGiaHanDen.isNotEmpty
          ? pl.ngayGiaHanDenFormatted
          : (hd?.ngayKtFormatted ?? '31/12/2026');

      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 28),
          build: (pw.Context context) {
            return [
              // Tiêu đề Quốc hiệu
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    pw.Text(
                      'Độc lập – Tự do – Hạnh phúc',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      'PHỤ LỤC HỢP ĐỒNG THUÊ PHÒNG TRỌ',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Mã phụ lục: ${pl.maPhuLuc} (Kèm theo Hợp đồng số: ${hd?.maHopDong ?? 'HD001'})',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Text(
                'Hôm nay ngày ${pl.ngayLapFormatted}; tại Hệ thống Nhà trọ Kiêu Giang ($diaChiToaNha)',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.Text(
                'Chúng tôi gồm có:',
                style: const pw.TextStyle(fontSize: 9.5),
              ),
              pw.SizedBox(height: 8),

              // Đại diện Bên A
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '1. Đại diện bên cho thuê phòng trọ (Bên A):',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Ông/Bà: TRỊNH MỸ DUYÊN',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Nơi đăng ký HK: P. Hiệp Bình Chánh, TP. Thủ Đức, TP.HCM',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'CCCD số: 079198004663  -  Điện thoại: 0328 004 663',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 6),

              // Đại diện Bên B
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '2. Đại diện bên thuê phòng trọ (Bên B):',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 9.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Ông/Bà: ${rep?.hoTenKhach ?? 'Khách thuê'}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Nơi đăng ký HK thường trú: ${rep?.diaChiThuongTru ?? 'Theo CCCD'}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                    pw.Text(
                      'Số CCCD: ${rep?.cccd ?? ''}  -  Số điện thoại: ${rep?.soDt ?? ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 10),

              pw.Text(
                'Sau khi bàn bạc trên tinh thần dân chủ, hai bên cùng có lợi, cùng thống nhất ký kết Phụ lục hợp đồng thuê phòng trọ với các nội dung sau:',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
              pw.SizedBox(height: 8),

              // Nội dung phụ lục
              _buildPdfArticle(
                'NỘI DUNG THỎA THUẬN PHỤ LỤC',
                '• Căn phòng thuê: $tenPhong tại địa chỉ: $diaChiToaNha.\n'
                    '• Nội dung điều chỉnh: ${pl.noiDungDieuChinh.isNotEmpty ? pl.noiDungDieuChinh : 'Gia hạn thời hạn hợp đồng thuê phòng'}.\n'
                    '• Giá thuê: $giaThueText.\n'
                    '• Hình thức thanh toán: Chuyển khoản VietQR trên App Kiêu Giang định kỳ hàng tháng.\n'
                    '• Tiền điện: 3.500 đ/kWh tính theo chỉ số công tơ, thanh toán vào cuối các tháng.\n'
                    '• Tiền nước: 20.000 đ/m³ (hoặc theo thỏa thuận) thanh toán vào đầu các tháng.\n'
                    '• Tiền đặt cọc: $tienCocText.\n'
                    '• Phụ lục có giá trị hiệu lực: Kể từ ngày ${pl.ngayLapFormatted} đến hết ngày $ngayGiaHanDenText.',
              ),
              _buildPdfArticle(
                'TRÁCH NHIỆM CỦA CÁC BÊN',
                '* Trách nhiệm của Bên A:\n'
                    '- Tạo mọi điều kiện thuận lợi để Bên B thực hiện theo hợp đồng và phụ lục.\n'
                    '- Cung cấp nguồn điện, nước, wifi ổn định cho Bên B sử dụng.\n\n'
                    '* Trách nhiệm của Bên B:\n'
                    '- Thanh toán đầy đủ các khoản tiền theo đúng thỏa thuận.\n'
                    '- Bảo quản các trang thiết bị và cơ sở vật chất của Bên A trang bị cho ban đầu (làm hỏng phải sửa, mất phải đền).\n'
                    '- Không được tự ý sửa chữa, cải tạo cơ sở vật chất khi chưa được sự đồng ý của Bên A.\n'
                    '- Giữ gìn vệ sinh trong và ngoài khuôn viên của phòng trọ.\n'
                    '- Bên B phải chấp hành mọi quy định của pháp luật Nhà nước và quy định của địa phương.\n'
                    '- Nếu Bên B cho khách ở qua đêm thì phải báo và được sự đồng ý của chủ nhà qua App Kiêu Giang, đồng thời phải chịu trách nhiệm về các hành vi vi phạm pháp luật của khách trong thời gian ở lại.',
              ),
              _buildPdfArticle(
                'TRÁCH NHIỆM CHUNG',
                '- Hai bên phải tạo điều kiện cho nhau thực hiện hợp đồng.\n'
                    '- Trong thời gian hợp đồng và phụ lục còn hiệu lực nếu bên nào vi phạm các điều khoản đã thỏa thuận thì bên còn lại có quyền đơn phương chấm dứt hợp đồng; nếu sự vi phạm hợp đồng đó gây tổn thất cho bên bị vi phạm thì bên vi phạm hợp đồng phải bồi thường thiệt hại.\n'
                    '- Một trong hai bên muốn chấm dứt hợp đồng trước thời hạn thì phải báo trước cho bên kia ít nhất 30 ngày và hai bên phải có sự thống nhất.\n'
                    '- Bên A phải trả lại tiền đặt cọc cho Bên B khi kết thúc hợp đồng đúng quy định.\n'
                    '- Bên nào vi phạm điều khoản chung thì phải chịu trách nhiệm trước pháp luật.\n'
                    '- Phụ lục được lập thành 02 bản có giá trị pháp lý như nhau và là bộ phận không thể tách rời của Hợp đồng số ${hd?.maHopDong ?? 'HD001'}, mỗi bên giữ một bản.',
              ),
              pw.SizedBox(height: 16),

              // Bảng ký tên hai bên
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'ĐẠI DIỆN BÊN B',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                        pw.Text(
                          '(Ký, ghi rõ họ tên)',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (imgChuKyB != null)
                          pw.Container(
                            height: 60,
                            alignment: pw.Alignment.center,
                            child: pw.Image(
                              imgChuKyB,
                              height: 55,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        else
                          pw.SizedBox(height: 60),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          rep?.hoTenKhach ?? 'Bên B đã ký',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                        if (_urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty)
                          pw.Text(
                            '(Đã ký số điện tử)',
                            style: const pw.TextStyle(
                              fontSize: 7.5,
                              color: PdfColors.green700,
                            ),
                          ),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text(
                          'ĐẠI DIỆN BÊN A',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9.5,
                          ),
                        ),
                        pw.Text(
                          '(Ký, ghi rõ họ tên & đóng dấu)',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontStyle: pw.FontStyle.italic,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 6),
                        if (imgChuKyA != null)
                          pw.Container(
                            height: 60,
                            alignment: pw.Alignment.center,
                            child: pw.Image(
                              imgChuKyA,
                              height: 55,
                              fit: pw.BoxFit.contain,
                            ),
                          )
                        else
                          pw.SizedBox(height: 60),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'TRỊNH MỸ DUYÊN',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                        pw.Text(
                          '(BQL Hệ Thống Kiêu Giang)',
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.blue700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'PhuLucHopDong_${pl.maPhuLuc}_${phong?.maPhong ?? 'P203'}.pdf',
      );
    } catch (e, stack) {
      debugPrint('Lỗi xuất PDF phụ lục: $e\n$stack');
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi xuất file',
          noiDung: 'Lỗi xuất file PDF phụ lục: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  // ─── Modal xem chi tiết Phụ lục hợp đồng & Tải PDF ───
  void _xemChiTietPhuLucModal(PhuLucHopDongModel pl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(ctx).padding.bottom + 20,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phụ Lục Hợp Đồng ${pl.maPhuLuc}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _textDark,
                          ),
                        ),
                        Text(
                          'Ngày lập: ${pl.ngayLapFormatted}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildModalPhuLucRow(
                      'Nội dung điều chỉnh',
                      pl.noiDungDieuChinh.isNotEmpty
                          ? pl.noiDungDieuChinh
                          : 'Gia hạn thời hạn hợp đồng',
                    ),
                    if (pl.giaTheMoi > 0) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildModalPhuLucRow(
                        'Giá thuê mới',
                        '${FormatUtils.currency(pl.giaTheMoi.toDouble())} đ/tháng',
                      ),
                    ],
                    if (pl.ngayGiaHanDen.isNotEmpty) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildModalPhuLucRow(
                        'Gia hạn đến ngày',
                        pl.ngayGiaHanDenFormatted,
                      ),
                    ],
                    if (pl.maPhongMoi != null && pl.maPhongMoi!.isNotEmpty) ...[
                      const Divider(height: 16, color: Color(0xFFE2E8F0)),
                      _buildModalPhuLucRow(
                        'Phòng chuyển đến',
                        'Phòng ${pl.maPhongMoi}',
                      ),
                    ],
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalPhuLucRow(
                      'Tiền điện niêm yết',
                      '3.500 đ/kWh (công tơ riêng)',
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalPhuLucRow(
                      'Tiền nước niêm yết',
                      '20.000 đ/m³ (đồng hồ riêng)',
                    ),
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    _buildModalPhuLucRow(
                      'Quy định báo trước',
                      'Tối thiểu 30 ngày (hoàn 100% cọc)',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      child: const Text(
                        'Đóng',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _xuatPdfPhuLuc(pl);
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('In / Tải PDF'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
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
        );
      },
    );
  }

  Widget _buildModalPhuLucRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfArticle(String title, String content) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            content,
            style: const pw.TextStyle(fontSize: 8.5, height: 1.3),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _buildTopAppBar(),
        body: const LoadingMeoMeo(
          message: 'Đang tải hợp đồng...',
          subMessage: 'Đợi mèo con kiểm tra hồ sơ xíu nha~ 🐾',
        ),
      );
    }

    if (_errorMessage != null && _hopDong == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: _buildTopAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: _textDark),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _fetchContractData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Thử lại'),
                  style: ElevatedButton.styleFrom(backgroundColor: _primary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildTopAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchContractData,
          color: _primary,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderTitleRow(),
                const SizedBox(height: 14),
                // Thông báo khi khách chưa ký hợp đồng (nếu đã ký thì ẩn)
                if (_urlChuKyBenB == null || _urlChuKyBenB!.isEmpty) ...[
                  _buildThongBaoChuaKyHopDongBanner(),
                ],
                _buildCardHopDongDienTu(),
                const SizedBox(height: 12),
                _buildGiaVaTienCocRow(),
                const SizedBox(height: 14),
                _buildCardThongTinPhong(),
                const SizedBox(height: 14),
                _buildCardChuTheHopDong(),
                const SizedBox(height: 14),
                _buildCardBangGiaDichVu(),
                const SizedBox(height: 14),
                _buildCardDieuKhoanThucTe(),
                const SizedBox(height: 14),
                _buildCardDanhSachPhuLucHopDong(),
                const SizedBox(height: 14),
                _buildCardChuKyTay(),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // ─── 1. TOP APP BAR ───
  PreferredSizeWidget _buildTopAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Kiêu Giang',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _primary,
            ),
          ),
          Text(
            'Quản lý hợp đồng cư dân',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Color(0xFF334155)),
          tooltip: 'Tải lại dữ liệu',
          onPressed: _fetchContractData,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ─── 2. HÀNG TIÊU ĐỀ: HỢP ĐỒNG THUÊ ───
  Widget _buildHeaderTitleRow() {
    final tenPhong = _phong?.tenHienThi ?? 'Phòng 203 • Gác lửng';
    final toaNha = _phong?.toaNha ?? 'Tòa A';

    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
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
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hợp Đồng Thuê Điện Tử',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$tenPhong • $toaNha',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // Nút tải PDF
        IconButton(
          icon: const Icon(
            Icons.file_download_outlined,
            color: _primary,
            size: 24,
          ),
          tooltip: 'Tải hợp đồng PDF',
          onPressed: _xuatPdfHopDong,
        ),
      ],
    );
  }

  /// Banner thông báo nổi bật khi Bên B (khách thuê) chưa hoàn tất ký hợp đồng
  Widget _buildThongBaoChuaKyHopDongBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Amber-50
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFCD34D),
          width: 1.2,
        ), // Amber-300
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.08),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_document,
                  size: 20,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hợp đồng chưa được ký kết!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    Text(
                      'Quý khách chưa ký xác nhận Bên B',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'CHƯA KÝ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Bên A (Ban Quản Lý) đã ký xác thực sẵn. Quý khách vui lòng vẽ chữ ký tay tại ô "Chữ ký Bên B" bên dưới và bấm "Xác nhận ký Bên B" để hợp đồng chính thức có hiệu lực pháp lý.',
            style: TextStyle(
              fontSize: 11.5,
              color: Color(0xFF78350F),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeInOutCubic,
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.draw_rounded, size: 14, color: Color(0xFFB45309)),
                  SizedBox(width: 6),
                  Text(
                    'Kéo xuống ký tên ngay',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 13,
                    color: Color(0xFFB45309),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 3. CARD HỢP ĐỒNG ĐIỆN TỬ (TIẾN ĐỘ THỜI HẠN) ───
  Widget _buildCardHopDongDienTu() {
    final hd = _hopDong;
    final maHd = hd?.maHopDong ?? 'HD001';
    final trangThai = hd?.trangThai ?? 'Còn hạn';
    final ngayBd = hd?.ngayBdFormatted ?? '01/01/2026';
    final ngayKt = hd?.ngayKtFormatted ?? '31/12/2026';
    final ngayKy = hd?.ngayKyFormatted ?? '01/01/2026';

    // Tính tiến độ phần trăm thực tế giữa ngayBd và ngayKt
    double progress = 0.5;
    int remainingDays = 0;
    try {
      final start = DateTime.parse(hd!.ngayBd);
      final end = DateTime.parse(hd.ngayKt);
      final now = DateTime.now();
      final totalDays = end.difference(start).inDays;
      final passedDays = now.difference(start).inDays;
      remainingDays = end.difference(now).inDays;
      if (totalDays > 0) {
        progress = (passedDays / totalDays).clamp(0.0, 1.0);
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.verified_outlined,
                          size: 14,
                          color: Color(0xFF0284C7),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'HỢP ĐỒNG CHÍNH THỨC',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0284C7),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      maHd,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                          ? 'Ngày ký: $ngayKy • Đã xác thực điện tử'
                          : 'Ngày ký: $ngayKy • Chờ Bên B ký tên',
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                            ? const Color(0xFF64748B)
                            : const Color(0xFFD97706),
                        fontWeight:
                            _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color:
                            _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                            ? const Color(0xFFBBF7D0)
                            : const Color(0xFFFDE68A),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color:
                              _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD97706),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _urlChuKyBenB != null && _urlChuKyBenB!.isNotEmpty
                              ? trangThai
                              : 'Chờ Bên B ký',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color:
                                _urlChuKyBenB != null &&
                                    _urlChuKyBenB!.isNotEmpty
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    remainingDays > 0
                        ? 'Còn lại $remainingDays ngày'
                        : 'Đã đến hạn',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Thanh tiến độ thời hạn
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      ngayBd,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF475569),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          'Thời hạn ${hd?.thoiHanHopDongText ?? "12 tháng"}',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      ngayKt,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(_primary),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_rounded,
                      size: 13,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        'Kỳ đóng tiền: Chu kỳ ${hd?.chuKyThuTien ?? 1} tháng/lần (Ngày 05)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Text(
                      'Đúng hạn',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
                      ),
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

  // ─── 4. GIÁ THUÊ & TIỀN CỌC PHÒNG ───
  Widget _buildGiaVaTienCocRow() {
    final giaThue = _hopDong?.giaThueThaoThuan ?? 3800000;
    final tienCoc = _hopDong?.tienDatCoc ?? 3800000;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Giá thuê cố định',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    FormatUtils.currency(giaThue.toDouble()),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: _primary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cam kết không đổi ${_hopDong?.tongSoThang ?? 12}T',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tiền cọc giữ chỗ',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    FormatUtils.currency(tienCoc.toDouble()),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF16A34A),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Đã ký quỹ bảo đảm',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 5. CARD THÔNG TIN PHÒNG TỪ SUPABASE ───
  Widget _buildCardThongTinPhong() {
    final p = _phong;
    final tenPhong = (p?.tenHienThi != null && p!.tenHienThi.isNotEmpty)
        ? p.tenHienThi
        : (_hopDong?.maPhong.isNotEmpty == true ? _hopDong!.maPhong : '');
    final toaNha = p?.toaNha ?? '';
    final dienTich = p?.dienTich ?? 0;
    final tang = p?.tang ?? 0;
    final hinhAnh = p?.hinhAnh ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: hinhAnh.isNotEmpty
                ? Image.network(
                    hinhAnh,
                    width: 82,
                    height: 82,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 82,
                      height: 82,
                      color: const Color(0xFFF1F5F9),
                      child: const Icon(
                        Icons.apartment_rounded,
                        color: _primary,
                        size: 36,
                      ),
                    ),
                  )
                : Container(
                    width: 82,
                    height: 82,
                    color: const Color(0xFFF1F5F9),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: _primary,
                      size: 36,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Tầng $tang • $toaNha',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$dienTich m²',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tenPhong,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hệ thống Nhà trọ Kiêu Giang • Khép kín',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.groups_rounded,
                      size: 13,
                      color: Color(0xFF0284C7),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tối đa: 02 - 03 người (${1 + _danhSachOCung.length} người đang ở)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w600,
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
        ],
      ),
    );
  }

  // ─── 6. CHỦ THỂ HỢP ĐỒNG (BÊN A & BÊN B TỪ SUPABASE) ───
  Widget _buildCardChuTheHopDong() {
    final rep = _khachDaiDien;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.handshake_rounded, color: _primary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chủ Thể Hợp Đồng',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              Text(
                'Đã đối soát CCCD',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0284C7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bên A: Chủ nhà / Quản lý
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'BÊN A',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Hệ thống Nhà trọ Kiêu Giang',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRowTwoCol('Đại diện chủ trọ:', 'TRỊNH MỸ DUYÊN'),
                const SizedBox(height: 4),
                _buildRowTwoCol(
                  'Hotline quản lý:',
                  '0328 004 663 (24/7)',
                  valColor: const Color(0xFF0284C7),
                ),
                const SizedBox(height: 4),
                _buildRowTwoCol(
                  'Địa chỉ cơ sở:',
                  'Kiêu Giang House, P. Hiệp Bình Chánh, TP. Thủ Đức, TP.HCM',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Bên B: Khách đại diện
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'BÊN B',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        rep?.hoTenKhach ?? 'Hồ Thị Mỹ Duyên',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Đại diện hợp đồng',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildRowTwoCol(
                  'Số CCCD gắn chip:',
                  rep?.cccd ?? '079201012345',
                ),
                const SizedBox(height: 4),
                _buildRowTwoCol('Số điện thoại:', rep?.soDt ?? '0865109632'),
                const SizedBox(height: 4),
                _buildRowTwoCol(
                  'Địa chỉ thường trú:',
                  rep?.diaChiThuongTru ?? 'Tân Phú, TP.HCM',
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Tình trạng cư trú:',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                    Row(
                      children: [
                        Icon(Icons.circle, size: 6, color: Color(0xFF16A34A)),
                        SizedBox(width: 4),
                        Text(
                          'Đã đăng ký tạm trú',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF16A34A),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Danh sách thành viên ở cùng thực tế từ Supabase
                if (_danhSachOCung.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Thành viên ở cùng (${_danhSachOCung.length} người)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._danhSachOCung.map((member) {
                    final initials = member.hoTenKhach.trim().isNotEmpty
                        ? member.hoTenKhach
                              .trim()
                              .split(' ')
                              .last
                              .substring(0, 1)
                              .toUpperCase()
                        : 'M';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 13,
                            backgroundColor: const Color(0xFFE0F2FE),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.hoTenKhach,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _textDark,
                                  ),
                                ),
                                Text(
                                  'CCCD: ${member.cccd} • SĐT: ${member.soDt}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Đang ở',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7. BẢNG GIÁ DỊCH VỤ CAM KẾT TỪ SUPABASE ───
  Widget _buildCardBangGiaDichVu() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF0284C7),
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bảng Giá Dịch Vụ Cam Kết',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              Text(
                'Minh bạch niêm yết',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF0284C7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Render danh sách từ bảng `dich_vu`
          if (_danhSachDichVu.isNotEmpty)
            ..._danhSachDichVu.map((dv) {
              IconData icon = Icons.electrical_services_rounded;
              if (dv.maDichVu.contains('DIEN')) icon = Icons.bolt_rounded;
              if (dv.maDichVu.contains('NUOC')) icon = Icons.water_drop_rounded;
              if (dv.maDichVu.contains('WIFI')) icon = Icons.wifi_rounded;
              if (dv.maDichVu.contains('RAC'))
                icon = Icons.delete_outline_rounded;
              if (dv.maDichVu.contains('XE')) icon = Icons.two_wheeler_rounded;

              final isFree = dv.donGia == 0;
              final priceText = isFree
                  ? 'Miễn phí'
                  : '${FormatUtils.currency(dv.donGia.toDouble())} đ';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDichVuTile(
                  icon,
                  dv.tenDichVu,
                  dv.ghiChu,
                  priceText,
                  '/ ${dv.donViTinh}',
                  isFree: isFree,
                ),
              );
            })
          else ...[
            _buildDichVuTile(
              Icons.bolt_rounded,
              'Điện sinh hoạt',
              'Công tơ điện tử riêng phòng',
              '3.500 đ',
              '/ kWh',
            ),
            const SizedBox(height: 8),
            _buildDichVuTile(
              Icons.water_drop_rounded,
              'Nước máy thủy cục',
              'Đồng hồ nước thủy cục riêng',
              '20.000 đ',
              '/ m³',
            ),
            const SizedBox(height: 8),
            _buildDichVuTile(
              Icons.wifi_rounded,
              'Wifi cáp quang tốc độ cao',
              'Băng thông 300Mbps',
              '50.000 đ',
              '/ phòng / tháng',
            ),
            const SizedBox(height: 8),
            _buildDichVuTile(
              Icons.delete_outline_rounded,
              'Rác & vệ sinh hành lang',
              'Lau dọn tuần 3 lần',
              '50.000 đ',
              '/ người / tháng',
            ),
            const SizedBox(height: 8),
            _buildDichVuTile(
              Icons.two_wheeler_rounded,
              'Phí gửi xe máy',
              'Free 02 xe - Hầm có bảo vệ 24/24',
              'Miễn phí',
              'Bao gồm',
              isFree: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDichVuTile(
    IconData icon,
    String title,
    String sub,
    String price,
    String unit, {
    bool isFree = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF0284C7), size: 16),
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
                    color: _textDark,
                  ),
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isFree ? const Color(0xFF16A34A) : _textDark,
                ),
              ),
              Text(
                unit,
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 8. ĐIỀU KHOẢN HỢP ĐỒNG THUÊ NHÀ Ở (12 ĐIỀU CHUẨN LUẬT KDBĐS 2023) ───
  Widget _buildCardDieuKhoanThucTe() => _buildCardDieuKhoanHopDong();

  Widget _buildCardDieuKhoanHopDong() {
    final noiThatList = _phong?.noiThatSanCo.isNotEmpty == true
        ? _phong!.noiThatSanCo
        : [
            'Máy lạnh Inverter',
            'Tủ lạnh riêng 130L',
            'Nước nóng Ariston',
            'Tủ áo & bàn làm việc',
            'Kệ bếp bồn rửa đôi',
            'Máy giặt & sân phơi',
            'Cổng vân tay AI & thẻ từ',
            'Camera an ninh 24/7',
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.gavel_rounded, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '12 Điều Khoản Hợp Đồng Thuê Nhà Ở',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              Text(
                'Luật KDBĐS 2023',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF0284C7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          _buildDieuKhoanItem(
            'Điều 1 & 2: Thông tin nhà ở & Đơn giá dịch vụ:',
            'Phòng ${_phong?.tenHienThi ?? 'P203'} (${_phong?.dienTich ?? 28}m²), cư trú tối đa 02 người. Tiền phòng: ${FormatUtils.currency((_hopDong?.giaThueThaoThuan ?? 3800000).toDouble())}đ/tháng (cố định suốt hợp đồng). Tiền điện 3.500 đ/kWh (công tơ riêng), nước 20.000 đ/m³ (đồng hồ riêng).',
          ),
          const SizedBox(height: 8),

          _buildDieuKhoanItem(
            'Điều 3 & 4: Thanh toán & Thời hạn bàn giao:',
            'Thanh toán định kỳ hàng tháng từ ngày 01 đến ngày 05 qua chuyển khoản VietQR trên App Kiêu Giang. Thời hạn thuê từ ${_hopDong?.ngayBdFormatted ?? '01/01/2026'} đến ${_hopDong?.ngayKtFormatted ?? '31/12/2026'}. Bàn giao nguyên trạng đầy đủ tiện nghi.',
          ),
          const SizedBox(height: 8),

          _buildDieuKhoanItem(
            'Điều 5 & 6: Quyền và nghĩa vụ Bên A & Bên B:',
            'Bên A đảm bảo cung cấp điện, nước, internet ổn định và cổng kiểm soát AI 24/7. Bên B sử dụng phòng đúng mục đích cư trú hợp pháp, không tự ý sửa chữa kết cấu, giữ gìn tài sản bàn giao, không gây ồn ào sau 22h00 và khai báo tạm trú trên app.',
          ),
          const SizedBox(height: 8),

          _buildDieuKhoanItem(
            'Điều 7 & 8: Đơn phương chấm dứt & Hoàn 100% cọc 30 ngày:',
            'Khi hết hạn hoặc muốn chấm dứt hợp đồng, mỗi bên phải thông báo trước tối thiểu 30 ngày trên App Kiêu Giang. Bên A nghiệm thu tài sản và hoàn trả 100% tiền đặt cọc (${FormatUtils.currency((_hopDong?.tienDatCoc ?? 3800000).toDouble())}đ) trong vòng 03 ngày làm việc.',
          ),
          const SizedBox(height: 8),

          _buildDieuKhoanItem(
            'Điều 9 - 12: Vi phạm hợp đồng & Hiệu lực thi hành:',
            'Bên nào vi phạm gây tổn thất phải bồi thường. Chậm đóng tiền quá 15 ngày Bên A có quyền đơn phương thu hồi phòng. Tranh chấp giải quyết theo Tòa án nhân dân có thẩm quyền. Hợp đồng có giá trị pháp lý tương đương cho 02 bản.',
          ),
          const SizedBox(height: 14),

          // Danh mục bàn giao nội thất
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chair_rounded,
                  size: 15,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nội thất bàn giao (${noiThatList.length} thiết bị)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 11,
                      color: Color(0xFF16A34A),
                    ),
                    SizedBox(width: 3),
                    Text(
                      'Nguyên trạng 100%',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF16A34A),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Wrap chips nội thất
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: noiThatList.map((item) {
              final tt = _layThongTinNoiThat(item);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: tt.bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tt.icon, size: 13, color: tt.color),
                    const SizedBox(width: 5),
                    Text(
                      item,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF334155),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDieuKhoanItem(String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0F2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              height: 1.38,
            ),
          ),
        ],
      ),
    );
  }

  /// Trợ lý ánh xạ Icon và Màu sắc sinh động cho từng loại thiết bị nội thất
  _ThongTinNoiThat _layThongTinNoiThat(String ten) {
    final lower = ten.toLowerCase();
    if (lower.contains('máy lạnh') || lower.contains('điều hòa')) {
      return const _ThongTinNoiThat(
        Icons.ac_unit_rounded,
        Color(0xFF0284C7),
        Color(0xFFE0F2FE),
      );
    }
    if (lower.contains('tủ lạnh')) {
      return const _ThongTinNoiThat(
        Icons.kitchen_rounded,
        Color(0xFF0D9488),
        Color(0xFFCCFBF1),
      );
    }
    if (lower.contains('nước nóng') ||
        lower.contains('bình nóng') ||
        lower.contains('ariston')) {
      return const _ThongTinNoiThat(
        Icons.hot_tub_rounded,
        Color(0xFFEA580C),
        Color(0xFFFFEDD5),
      );
    }
    if (lower.contains('tủ áo') ||
        lower.contains('bàn') ||
        lower.contains('giường') ||
        lower.contains('nệm')) {
      return const _ThongTinNoiThat(
        Icons.chair_rounded,
        Color(0xFF7C3AED),
        Color(0xFFEDE9FE),
      );
    }
    if (lower.contains('bếp') ||
        lower.contains('bồn rửa') ||
        lower.contains('chậu')) {
      return const _ThongTinNoiThat(
        Icons.soup_kitchen_rounded,
        Color(0xFFD97706),
        Color(0xFFFEF3C7),
      );
    }
    if (lower.contains('máy giặt') ||
        lower.contains('sân phơi') ||
        lower.contains('phơi')) {
      return const _ThongTinNoiThat(
        Icons.local_laundry_service_rounded,
        Color(0xFF2563EB),
        Color(0xFFDBEAFE),
      );
    }
    if (lower.contains('vân tay') ||
        lower.contains('thẻ từ') ||
        lower.contains('cổng') ||
        lower.contains('khóa')) {
      return const _ThongTinNoiThat(
        Icons.fingerprint_rounded,
        Color(0xFF059669),
        Color(0xFFD1FAE5),
      );
    }
    if (lower.contains('camera') || lower.contains('an ninh')) {
      return const _ThongTinNoiThat(
        Icons.videocam_rounded,
        Color(0xFFE11D48),
        Color(0xFFFFE4E6),
      );
    }
    if (lower.contains('wifi') ||
        lower.contains('mạng') ||
        lower.contains('internet')) {
      return const _ThongTinNoiThat(
        Icons.wifi_rounded,
        Color(0xFF0284C7),
        Color(0xFFE0F2FE),
      );
    }
    if (lower.contains('tivi') || lower.contains('tv')) {
      return const _ThongTinNoiThat(
        Icons.tv_rounded,
        Color(0xFF4F46E5),
        Color(0xFFEEF2FF),
      );
    }
    if (lower.contains('quạt')) {
      return const _ThongTinNoiThat(
        Icons.mode_fan_off_rounded,
        Color(0xFF0891B2),
        Color(0xFFCFFAFE),
      );
    }
    return const _ThongTinNoiThat(
      Icons.inventory_2_outlined,
      Color(0xFF475569),
      Color(0xFFF1F5F9),
    );
  }

  /// Trợ lý dựng hình chữ ký hợp lệ (hỗ trợ cả Base64 Data URI, HTTP URL hoặc Widget mặc định)
  Widget _buildChuKyImageOrPlaceholder(
    String? urlChuKy, {
    double height = 38,
    bool isBenA = false,
  }) {
    if (urlChuKy == null || urlChuKy.trim().isEmpty) {
      if (isBenA) {
        return ChuKyBenAMacDinhWidget(height: height);
      }
      return SizedBox(height: height);
    }
    final clean = urlChuKy.trim();
    if (clean.startsWith('data:image')) {
      try {
        final b64 = clean.contains(',') ? clean.split(',').last : clean;
        final bytes = base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
        return SizedBox(
          height: height,
          child: Image.memory(bytes, fit: BoxFit.contain),
        );
      } catch (e) {
        debugPrint('Lỗi decode base64 chữ ký: $e');
        return isBenA
            ? ChuKyBenAMacDinhWidget(height: height)
            : SizedBox(height: height);
      }
    }
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return SizedBox(
        height: height,
        child: Image.network(
          clean,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => isBenA
              ? ChuKyBenAMacDinhWidget(height: height)
              : SizedBox(height: height),
        ),
      );
    }
    try {
      final bytes = base64Decode(clean.replaceAll(RegExp(r'\s+'), ''));
      return SizedBox(
        height: height,
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    } catch (_) {
      return isBenA
          ? ChuKyBenAMacDinhWidget(height: height)
          : SizedBox(height: height);
    }
  }

  // ─── MODAL TOÀN VĂN CHI TIẾT PHỤ LỤC HỢP ĐỒNG ĐIỆN TỬ ───
  void _showChiTietPhuLucModal(PhuLucHopDongModel pl) {
    final isChuyenPhong =
        pl.maPhuLuc.startsWith('PLCP') ||
        (pl.maPhongMoi != null && pl.maPhongMoi!.isNotEmpty);
    final effectiveHd = _hopDong?.maHopDong ?? pl.maHopDong;
    final tenNguoiThue = _khachDaiDien?.hoTenKhach ?? 'Khách thuê';
    const tenChuTro = 'TRỊNH MỸ DUYÊN';
    const sdtChuTro = '0328 004 663';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Thanh kéo handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isChuyenPhong
                            ? const Color(0xFFE0F2FE)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isChuyenPhong
                            ? Icons.swap_horiz_rounded
                            : Icons.history_edu_rounded,
                        color: isChuyenPhong
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF16A34A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isChuyenPhong
                                ? 'Phụ Lục Chuyển Phòng'
                                : 'Phụ Lục Gia Hạn Hợp Đồng',
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          Text(
                            'Mã số: ${pl.maPhuLuc} • HĐ: $effectiveHd',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Text(
                        'ĐÃ DUYỆT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF64748B),
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),

              // Nội dung chi tiết cuộn
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CĂN CỨ PHÁP LÝ
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(
                                  Icons.gavel_rounded,
                                  size: 15,
                                  color: _primary,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'CĂN CỨ PHÁP LÝ HỢP ĐỒNG',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: _primary,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildPhuLucRow('Căn cứ Hợp đồng số:', effectiveHd),
                            const SizedBox(height: 5),
                            _buildPhuLucRow(
                              'Cơ sở lưu trú:',
                              'Kiều Giang House, P. Hiệp Bình Chánh, Thủ Đức',
                            ),
                            const SizedBox(height: 5),
                            _buildPhuLucRow(
                              'Bên A (Chủ trọ):',
                              '$tenChuTro (ĐT: $sdtChuTro)',
                            ),
                            const SizedBox(height: 5),
                            _buildPhuLucRow(
                              'Bên B (Người thuê):',
                              tenNguoiThue,
                            ),
                            const SizedBox(height: 5),
                            _buildPhuLucRow(
                              'Ngày lập phụ lục:',
                              pl.ngayLapFormatted,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // NỘI DUNG ĐIỀU CHỈNH
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
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
                                Icon(
                                  isChuyenPhong
                                      ? Icons.meeting_room_outlined
                                      : Icons.calendar_month_outlined,
                                  size: 16,
                                  color: isChuyenPhong
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  isChuyenPhong
                                      ? 'THÔNG TIN CHUYỂN ĐỔI PHÒNG'
                                      : 'THÔNG TIN GIA HẠN HỢP ĐỒNG',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isChuyenPhong
                                        ? const Color(0xFF0284C7)
                                        : const Color(0xFF16A34A),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (isChuyenPhong) ...[
                              if (pl.maPhongMoi != null &&
                                  pl.maPhongMoi!.isNotEmpty) ...[
                                _buildPhuLucRow(
                                  'Phòng chuyển đến:',
                                  pl.maPhongMoi!,
                                  highlight: true,
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (pl.giaTheMoi > 0) ...[
                                _buildPhuLucRow(
                                  'Giá thuê phòng mới:',
                                  '${FormatUtils.currency(pl.giaTheMoi.toDouble())}/tháng',
                                  highlight: true,
                                ),
                                const SizedBox(height: 6),
                              ],
                              _buildPhuLucRow(
                                'Tiền cọc bảo lưu:',
                                pl.chenhLechTienCoc == 0
                                    ? 'Bảo lưu nguyên vẹn 100% tiền cọc'
                                    : 'Chênh lệch: ${FormatUtils.currency(pl.chenhLechTienCoc.toDouble())}',
                              ),
                            ] else ...[
                              if (pl.ngayGiaHanDen.isNotEmpty) ...[
                                _buildPhuLucRow(
                                  'Gia hạn hiệu lực đến:',
                                  pl.ngayGiaHanDenFormatted,
                                  highlight: true,
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (pl.giaTheMoi > 0) ...[
                                _buildPhuLucRow(
                                  'Giá thuê áp dụng mới:',
                                  '${FormatUtils.currency(pl.giaTheMoi.toDouble())}/tháng',
                                  highlight: true,
                                ),
                                const SizedBox(height: 6),
                              ],
                            ],
                            const SizedBox(height: 12),
                            const Text(
                              'Nội dung điều chỉnh cụ thể:',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Text(
                                pl.noiDungDieuChinh,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF334155),
                                  height: 1.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ĐIỀU KHOẢN THI HÀNH
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 15,
                              color: Color(0xFFD97706),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Phụ lục này có giá trị pháp lý gắn liền và không tách rời Hợp đồng số $effectiveHd. Mọi quyền lợi và nghĩa vụ khác của hai Bên tiếp tục thực hiện theo Hợp đồng thuê đã ký.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF92400E),
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // CHỮ KÝ XÁC NHẬN HAI BÊN
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'ĐẠI DIỆN BÊN A',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '(Ký và ghi rõ họ tên)',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildChuKyImageOrPlaceholder(
                                    _urlChuKyBenA,
                                    height: 38,
                                    isBenA: true,
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    tenChuTro,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _textDark,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'ĐẠI DIỆN BÊN B',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    '(Ký và ghi rõ họ tên)',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontStyle: FontStyle.italic,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildChuKyImageOrPlaceholder(
                                    _urlChuKyBenB,
                                    height: 38,
                                    isBenA: false,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    tenNguoiThue,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: _textDark,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Nút Đóng
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Đóng văn bản',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
      },
    );
  }

  Widget _buildPhuLucRow(String label, String value, {bool highlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 135,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
              color: highlight
                  ? const Color(0xFF09638E)
                  : const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    );
  }

  // ─── 8.2 DANH SÁCH PHỤ LỤC HỢP ĐỒNG ĐÃ KÝ (GIA HẠN / CHUYỂN PHÒNG) ───
  Widget _buildCardDanhSachPhuLucHopDong() {
    if (_danhSachPhuLuc.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_edu_rounded,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Phụ Lục Hợp Đồng Đã Ký',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (sheetCtx) => DraggableScrollableSheet(
                      initialChildSize: 0.6,
                      minChildSize: 0.4,
                      maxChildSize: 0.92,
                      builder: (_, scrollCtrl) => Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Handle bar
                            Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            // Header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0F2FE),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.history_edu_rounded,
                                      color: Color(0xFF0284C7),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Danh Sách Phụ Lục Hợp Đồng',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          '${_danhSachPhuLuc.length} phụ lục đã ký',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            // Danh sách phụ lục
                            Expanded(
                              child: ListView.separated(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.all(16),
                                itemCount: _danhSachPhuLuc.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, i) {
                                  final pl = _danhSachPhuLuc[i];
                                  final isChuyenPhong =
                                      pl.maPhuLuc.startsWith('PLCP') ||
                                      (pl.maPhongMoi != null &&
                                          pl.maPhongMoi!.isNotEmpty);
                                  return InkWell(
                                    onTap: () {
                                      Navigator.pop(sheetCtx);
                                      _showChiTietPhuLucModal(pl);
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isChuyenPhong
                                                      ? const Color(0xFF0EA5E9)
                                                      : const Color(0xFF09638E),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  pl.maPhuLuc,
                                                  style: const TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  isChuyenPhong
                                                      ? 'Phụ lục chuyển phòng'
                                                      : 'Phụ lục gia hạn',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF0F172A),
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFDCFCE7,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: const Text(
                                                  'ĐÃ DUYỆT',
                                                  style: TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF16A34A),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Nội dung điều chỉnh
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Text(
                                              pl.noiDungDieuChinh,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: Color(0xFF334155),
                                                height: 1.5,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons
                                                        .calendar_today_rounded,
                                                    size: 13,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Ngày lập: ',
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      color: Color(0xFF64748B),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (pl.giaTheMoi > 0)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.payments_outlined,
                                                      size: 13,
                                                      color: Color(0xFF09638E),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '/tháng',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF09638E,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              if (isChuyenPhong &&
                                                  pl.maPhongMoi != null)
                                                Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .meeting_room_outlined,
                                                      size: 13,
                                                      color: Color(0xFF0EA5E9),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '→ ',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Color(
                                                          0xFF0EA5E9,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              Text(
                                                'Xem chi tiết văn bản →',
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF09638E),
                                                ),
                                              ),
                                            ],
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
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_danhSachPhuLuc.length} Phụ lục',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 10,
                        color: Color(0xFF16A34A),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._danhSachPhuLuc.map((pl) {
            final isChuyenPhong =
                pl.maPhuLuc.startsWith('PLCP') ||
                (pl.maPhongMoi != null && pl.maPhongMoi!.isNotEmpty);
            final title = isChuyenPhong
                ? 'Phụ lục chuyển sang phòng ${pl.maPhongMoi ?? ""}'
                : 'Phụ lục gia hạn thời hạn hợp đồng';

            return InkWell(
              onTap: () => _showChiTietPhuLucModal(pl),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF09638E),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pl.maPhuLuc,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ĐÃ DUYỆT',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pl.noiDungDieuChinh,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF475569),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_rounded,
                              size: 12,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ngày lập: ',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                        if (pl.giaTheMoi > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.payments_outlined,
                                size: 12,
                                color: Color(0xFF09638E),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Giá: /tháng',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF09638E),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Xem chi tiết văn bản →',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF09638E),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 9. CHỮ KÝ TAY THẬT (2 BÊN) ───
  Widget _buildCardChuKyTay() {
    final rep = _khachDaiDien;
    final ngayKy = _hopDong?.ngayKyFormatted ?? '01/01/2026';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.draw_rounded,
                  color: _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chữ Ký Hợp Đồng',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Vẽ chữ ký trực tiếp bằng ngón tay',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── BÊN A (Đại diện Bên Cho Thuê - Đã ký sẵn và khóa bảo mật) ──
          _buildKhuVucChuKyBenA(
            tenNguoi: 'TRỊNH MỸ DUYÊN',
            chucVu: 'Chủ Trọ / Ban Quản Lý Nhà Trọ Kiêu Giang',
            ngayKy: ngayKy,
            urlChuKy: _urlChuKyBenA,
          ),
          const SizedBox(height: 14),

          // Đường phân cách
          Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Text(
                  'và',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            ],
          ),
          const SizedBox(height: 14),

          // ── BÊN B (Đại diện Bên Thuê - Người thuê trực tiếp ký) ──
          _buildKhuVucChuKyBenB(
            tenNguoi: rep?.hoTenKhach.toUpperCase() ?? 'HỒ THỊ MỸ DUYÊN',
            chucVu:
                'CCCD: ${rep?.cccd ?? '079201012345'} • SĐT: ${rep?.soDt ?? '0865109632'}',
            ngayKy: ngayKy,
            urlChuKy: _urlChuKyBenB,
            control: _controlBenB,
            dangLuu: _dangLuuKyBenB,
            onLuu: () => _luuChuKy(isBenA: false),
            onXoa: () => setState(() {
              _controlBenB.clear();
            }),
          ),
          const SizedBox(height: 12),

          // Ghi chú pháp lý
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: Color(0xFFD97706),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chữ ký được lưu trữ bảo mật trên hệ thống. Hợp đồng có hiệu lực pháp lý khi cả 2 bên hoàn tất ký tên.',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Khu vực chữ ký Bên A: Mặc định sẵn chữ ký số của Ban Quản Lý, khóa đối với Bên B
  Widget _buildKhuVucChuKyBenA({
    required String tenNguoi,
    required String chucVu,
    required String ngayKy,
    required String? urlChuKy,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bên A
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'BÊN A',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenNguoi,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        chucVu,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified_rounded,
                        size: 12,
                        color: Color(0xFF15803D),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Đã ký xác nhận',
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Vùng hiển thị chữ ký Bên A (cố định, đã ký sẵn, không cho phép Bên B sửa/ký)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        right: 12,
                        bottom: 8,
                        child: Opacity(
                          opacity: 0.08,
                          child: Icon(
                            Icons.verified_user_rounded,
                            size: 80,
                            color: _primary,
                          ),
                        ),
                      ),
                      if (urlChuKy != null && urlChuKy.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: urlChuKy.startsWith('data:image')
                              ? Image.memory(
                                  base64Decode(urlChuKy.split(',').last),
                                  height: 110,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                )
                              : Image.network(
                                  urlChuKy,
                                  height: 110,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const ChuKyBenAMacDinhWidget(height: 110),
                                ),
                        )
                      else
                        const ChuKyBenAMacDinhWidget(height: 110),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Thông tin xác nhận ký số
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 13,
                      color: Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Ký xác nhận ngày $ngayKy • Ban Quản Lý Nhà Trọ Kiều Giang',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Ràng buộc bảo mật đối với Bên B
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: Color(0xFF64748B),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Khóa bảo mật: Chữ ký Bên A do Ban Quản Lý xác thực sẵn. Bên B không thể can thiệp hoặc ký thay.',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Khu vực chữ ký Bên B: Người thuê (Bên B) trực tiếp ký tay và xác nhận
  Widget _buildKhuVucChuKyBenB({
    required String tenNguoi,
    required String chucVu,
    required String ngayKy,
    required String? urlChuKy,
    required ChuKyController control,
    required bool dangLuu,
    required VoidCallback onLuu,
    required VoidCallback onXoa,
  }) {
    final daKy = urlChuKy != null && urlChuKy.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bên B
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15803D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'BÊN B',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenNguoi,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        chucVu,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (daKy)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16A34A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 11, color: Colors.white),
                        SizedBox(width: 3),
                        Text(
                          'Đã ký',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Bên B chưa ký',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Vùng chữ ký Bên B
          if (daKy) ...[
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: urlChuKy.startsWith('data:image')
                          ? Image.memory(
                              base64Decode(urlChuKy.split(',').last),
                              height: 110,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            )
                          : Image.network(
                              urlChuKy,
                              height: 110,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    height: 110,
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '(Không tải được ảnh chữ ký)',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF94A3B8),
                                      ),
                                    ),
                                  ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bên B ký ngày $ngayKy',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 12,
                          color: Color(0xFF16A34A),
                        ),
                        SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Khóa bảo mật: Chữ ký đã được xác nhận và có hiệu lực pháp lý (không thể ký lại)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.touch_app_rounded,
                        size: 13,
                        color: Color(0xFF15803D),
                      ),
                      SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Người thuê vui lòng vẽ chữ ký tay vào ô bên dưới',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF15803D),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Khung pad ký tay
                  Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF86EFAC),
                        width: 1.5,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 32,
                            left: 20,
                            right: 20,
                            child: Container(
                              height: 1,
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          Positioned(
                            bottom: 18,
                            left: 20,
                            child: Text(
                              'Chữ ký Bên B (Người thuê)',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Colors.grey.shade400,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                          BangKyTay(
                            controller: control,
                            mauNet: Colors.black87,
                            doDayNet: 2.8,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => control.clear(),
                          icon: const Icon(Icons.clear_rounded, size: 15),
                          label: const Text(
                            'Xóa',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF64748B),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: dangLuu ? null : onLuu,
                          icon: dangLuu
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 16),
                          label: Text(
                            dangLuu ? 'Đang lưu...' : 'Xác nhận ký Bên B',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF15803D),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 10. ACTION BUTTONS ───
  Widget _buildActionButtons() {
    final bool isTerminated = _hopDong?.trangThai == 'Đã thanh lý';

    // Bạn ở cùng phòng không hiển thị các chức năng gia hạn hay chấm dứt/thanh lý
    if (!_isNguoiDaiDien) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _xuatPdfHopDong,
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text(
            'Tải File PDF Hợp Đồng',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE0F2FE),
            foregroundColor: _primary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _xuatPdfHopDong,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Tải File PDF',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE0F2FE),
                    foregroundColor: _primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (!_isNguoiDaiDien) {
                      _thongBaoKhongCoQuyen(hanhDong: 'Gia hạn hợp đồng');
                      return;
                    }
                    int daysLeft = 999;
                    if (_hopDong?.ngayKt != null &&
                        _hopDong!.ngayKt.isNotEmpty) {
                      try {
                        final dt = DateTime.parse(_hopDong!.ngayKt);
                        daysLeft = dt.difference(DateTime.now()).inDays;
                      } catch (_) {}
                    }
                    if (daysLeft > 30) {
                      ThongBaoHelper.hienToast(
                        context,
                        tieuDe: 'Chưa Đến Hạn Gia Hạn',
                        noiDung:
                            'Hợp đồng còn $daysLeft ngày. Theo quy định, chỉ được gửi đơn gia hạn khi hợp đồng sắp hết hạn (trong vòng 30 ngày cuối / còn 1 tháng)!',
                        type: ThongBaoType.canhBao,
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManHinhGiaHanHopDong(
                          hopDong: _hopDong,
                          tenPhong: _phong?.tenHienThi ?? 'Phòng 203',
                          maPhong: _phong?.maPhong ?? 'P203',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Gia Hạn Hợp Đồng',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () async {
              if (!isTerminated && !_isNguoiDaiDien) {
                _thongBaoKhongCoQuyen(
                  hanhDong: 'Chấm dứt hợp đồng & Trả phòng',
                );
                return;
              }
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManHinhChamDutHopDong(
                    hopDong: _hopDong,
                    tenPhong: _phong?.tenHienThi ?? 'Phòng 303',
                    maPhong: _phong?.maPhong ?? 'P303',
                    tenKhachThue: _khachDaiDien?.hoTenKhach,
                  ),
                ),
              );
              if (result == true) {
                _fetchContractData();
              }
            },
            icon: Icon(
              isTerminated ? Icons.verified_rounded : Icons.logout_rounded,
              size: 18,
              color: isTerminated
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
            ),
            label: Text(
              isTerminated
                  ? 'Xem Biên Bản Thanh Lý Hợp Đồng'
                  : 'Chấm Dứt Hợp Đồng & Trả Phòng',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isTerminated
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: isTerminated
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF2F2),
              side: BorderSide(
                color: isTerminated
                    ? const Color(0xFFBBF7D0)
                    : const Color(0xFFFECACA),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── BOTTOM NAVIGATION BAR ───
  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      currentIndex: 1,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: _primary,
      unselectedItemColor: const Color(0xFF94A3B8),
      selectedFontSize: 11,
      unselectedFontSize: 11,
      onTap: (index) {
        if (index != 1) Navigator.pop(context);
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          label: 'Trang chủ',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.key_rounded), label: 'Phòng'),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Hóa đơn',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.build_outlined),
          label: 'Yêu cầu',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Cá nhân',
        ),
      ],
    );
  }

  Widget _buildRowTwoCol(String label, String value, {Color? valColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: valColor ?? _textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _ThongTinNoiThat {
  final IconData icon;
  final Color color;
  final Color bgColor;
  const _ThongTinNoiThat(this.icon, this.color, this.bgColor);
}

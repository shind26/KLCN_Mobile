import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/data/models/KhachLuuTruModel.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhDangKyKhachQuaDem.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManHinhLichSuLuuTru extends StatefulWidget {
  final String tenPhong;
  final String toaNha;
  final int initialTabIndex;
  final String? maKhach;
  final String? maPhong;

  const ManHinhLichSuLuuTru({
    super.key,
    this.tenPhong = 'Phòng 203',
    this.toaNha = 'Kiêu Giang 2',
    this.initialTabIndex = 0,
    this.maKhach,
    this.maPhong,
  });

  @override
  State<ManHinhLichSuLuuTru> createState() => _ManHinhLichSuLuuTruState();
}

class _ManHinhLichSuLuuTruState extends State<ManHinhLichSuLuuTru> {
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  // 0: Tất cả, 1: Chờ duyệt, 2: Đã duyệt, 3: Từ chối
  late int _selectedTabIndex;
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
    _taiDanhSachTuSupabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _taiDanhSachTuSupabase() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      final user = AuthService.currentUser;

      String maKhach = widget.maKhach ?? '';
      if (maKhach.isEmpty && user != null && user.maTaiKhoan.isNotEmpty) {
        try {
          final kt = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('ma_tai_khoan', user.maTaiKhoan)
              .maybeSingle();
          if (kt != null && kt['ma_khach'] != null) {
            maKhach = kt['ma_khach'].toString();
          }
        } catch (_) {}
      }

      final pDigits =
          (widget.maPhong ?? widget.tenPhong).replaceAll(RegExp(r'[^0-9]'), '');

      List<dynamic> res = [];
      try {
        if (maKhach.isNotEmpty && pDigits.isNotEmpty) {
          res = await db
              .from('dang_ky_khach_qua_dem')
              .select()
              .or('ma_khach_dang_ky.eq.$maKhach,ma_phong.eq.P$pDigits,ma_phong.eq.$pDigits')
              .order('tu_ngay', ascending: false);
        } else if (maKhach.isNotEmpty) {
          res = await db
              .from('dang_ky_khach_qua_dem')
              .select()
              .eq('ma_khach_dang_ky', maKhach)
              .order('tu_ngay', ascending: false);
        } else if (pDigits.isNotEmpty) {
          res = await db
              .from('dang_ky_khach_qua_dem')
              .select()
              .or('ma_phong.eq.P$pDigits,ma_phong.eq.$pDigits,ma_phong.eq.${widget.tenPhong}')
              .order('tu_ngay', ascending: false);
        } else {
          res = await db
              .from('dang_ky_khach_qua_dem')
              .select()
              .order('tu_ngay', ascending: false);
        }
      } catch (err) {
        debugPrint('[LICH_SU] Lỗi query lọc, tải toàn bộ: $err');
        res = await db
            .from('dang_ky_khach_qua_dem')
            .select()
            .order('tu_ngay', ascending: false);
      }

      // Nếu lọc xong mà không có bản ghi nào nhưng bảng có dữ liệu của khách, fallback tải toàn bộ
      if (res.isEmpty) {
        try {
          final fallbackRes = await db
              .from('dang_ky_khach_qua_dem')
              .select()
              .order('tu_ngay', ascending: false);
          if (fallbackRes.isNotEmpty) {
            res = fallbackRes;
          }
        } catch (_) {}
      }

      final listMoi = res
          .map((m) => KhachLuuTruModel.fromSupabase(m as Map<String, dynamic>))
          .toList();
      setState(() {
        KhachLuuTruModel.danhSachLuuTru.clear();
        KhachLuuTruModel.danhSachLuuTru.addAll(listMoi);
      });
    } catch (e) {
      debugPrint('[LICH_SU] Lỗi load Supabase: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hủy đăng ký phiếu đang chờ duyệt
  Future<void> _huyDangKy(String maDangKy) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận hủy đăng ký'),
        content: const Text(
          'Bạn có chắc chắn muốn hủy phiếu đăng ký khách qua đêm này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text(
              'Hủy phiếu',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = Supabase.instance.client;
      await db
          .from('dang_ky_khach_qua_dem')
          .delete()
          .eq('ma_dang_ky', maDangKy);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy phiếu đăng ký thành công!'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _taiDanhSachTuSupabase();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi hủy: $e')));
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'K';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  // Lọc danh sách theo tab và tìm kiếm
  List<KhachLuuTruModel> get _danhSachLoc {
    var list = KhachLuuTruModel.danhSachLuuTru;

    // Lọc theo Tab
    if (_selectedTabIndex == 1) {
      // Chờ duyệt / Chờ xác nhận
      list = list.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('chờ') || st.contains('đang');
      }).toList();
    } else if (_selectedTabIndex == 2) {
      // Đã duyệt / Xác nhận / Hoàn tất
      list = list.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('duyệt') ||
            st.contains('xác nhận') ||
            st.contains('hoàn tất') ||
            st.contains('đồng ý') ||
            st.contains('chấp nhận') ||
            st.contains('hợp lệ');
      }).toList();
    } else if (_selectedTabIndex == 3) {
      // Từ chối / Hủy
      list = list.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('từ chối') ||
            st.contains('hủy') ||
            st.contains('không');
      }).toList();
    }

    // Lọc theo từ khóa tìm kiếm
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((x) {
        return x.hoTen.toLowerCase().contains(q) ||
            x.cccd.toLowerCase().contains(q) ||
            x.id.toLowerCase().contains(q);
      }).toList();
    }

    return list;
  }

  int get _countChoDuyet => KhachLuuTruModel.danhSachLuuTru.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('chờ') || st.contains('đang');
      }).length;

  int get _countDaDuyet => KhachLuuTruModel.danhSachLuuTru.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('duyệt') ||
            st.contains('xác nhận') ||
            st.contains('hoàn tất') ||
            st.contains('đồng ý') ||
            st.contains('chấp nhận') ||
            st.contains('hợp lệ');
      }).length;

  int get _countTuChoi => KhachLuuTruModel.danhSachLuuTru.where((x) {
        final st = x.trangThai.toLowerCase();
        return st.contains('từ chối') ||
            st.contains('hủy') ||
            st.contains('không');
      }).length;

  // Bảng chi tiết khách lưu trú
  void _xemChiTiet(KhachLuuTruModel item) {
    final bool isChoDuyet = item.trangThai.toLowerCase().contains('chờ');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chi tiết phiếu #${item.id}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF94A3B8),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFF1F5F9)),
              const SizedBox(height: 8),
              _buildModalRow('Khách lưu trú:', item.hoTen, isBold: true),
              _buildModalRow('Số CCCD / Định danh:', item.cccd),
              _buildModalRow('Số điện thoại:', item.sdt),
              _buildModalRow('Mối quan hệ:', item.moiQuanHe),
              _buildModalRow('Phòng lưu trú:', item.maPhong ?? widget.tenPhong),
              _buildModalRow(
                'Thời gian lưu trú:',
                '${item.thoiGian} (${item.soDem} đêm)',
              ),
              _buildModalRow(
                'Phí dịch vụ lưu trú:',
                item.phiLuuTru,
                valueColor: _primary,
              ),
              _buildModalRow(
                'Trạng thái phê duyệt:',
                item.trangThai,
                valueColor: isChoDuyet
                    ? const Color(0xFFD97706)
                    : (item.trangThai.toLowerCase().contains('duyệt') ||
                            item.trangThai.toLowerCase().contains('xác nhận') ||
                            item.trangThai.toLowerCase().contains('hoàn tất')
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626)),
              ),
              _buildModalRow('Ngày đăng ký:', item.ngayDangKy),
              const SizedBox(height: 14),
              const Text(
                'Hình ảnh CCCD đã tải lên:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildAnhPreview('Mặt trước', item.anhMatTruoc),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _buildAnhPreview('Mặt sau', item.anhMatSau)),
                ],
              ),
              const SizedBox(height: 18),

              // Nút thao tác nhanh
              // Nút thao tác dành cho Cư dân (Chỉ có quyền Hủy khi chưa được BQL duyệt)
              if (isChoDuyet) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _huyDangKy(item.id);
                    },
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                    label: const Text(
                      'Hủy yêu cầu đăng ký',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? _textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnhPreview(String label, String? path) {
    Widget? imageWidget;
    if (path != null && path.isNotEmpty) {
      if (path.startsWith('http') || path.startsWith('blob:')) {
        imageWidget = Image.network(path, fit: BoxFit.cover);
      } else if (!kIsWeb) {
        final file = File(path);
        if (file.existsSync()) {
          imageWidget = Image.file(file, fit: BoxFit.cover);
        }
      }
    }

    return Container(
      height: 95,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: imageWidget != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageWidget,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: Color(0xFF94A3B8),
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danhSachHienThi = _danhSachLoc;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _taiDanhSachTuSupabase,
          color: _primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Ô tìm kiếm
                _buildSearchBar(),
                const SizedBox(height: 12),

                // 2. Thẻ thống kê nhanh
                _buildThongKeGrid(),
                const SizedBox(height: 14),

                // 3. Tab trạng thái (Tất cả, Chờ duyệt, Đã duyệt, Từ chối)
                _buildFilterTabs(),
                const SizedBox(height: 16),

                // 4. Nút đăng ký khách mới
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ManHinhDangKyKhachQuaDem(
                            tenPhong: widget.tenPhong,
                            toaNha: widget.toaNha,
                          ),
                        ),
                      ).then((_) => _taiDanhSachTuSupabase());
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text(
                      'Đăng ký khách qua đêm mới',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 5. Tiêu đề danh sách
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Danh sách khách (${danhSachHienThi.length})',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      InkWell(
                        onTap: _taiDanhSachTuSupabase,
                        child: const Row(
                          children: [
                            Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: _primary,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Làm mới',
                              style: TextStyle(
                                fontSize: 12,
                                color: _primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // 6. Danh sách thẻ khách
                if (_isLoading && KhachLuuTruModel.danhSachLuuTru.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: CircularProgressIndicator(color: _primary),
                    ),
                  )
                else if (danhSachHienThi.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 44,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Không có khách lưu trú nào trong mục này',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: danhSachHienThi.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = danhSachHienThi[index];
                      return _buildTheKhachLuuTru(item);
                    },
                  ),

                const SizedBox(height: 16),
                _buildCardQuyDinh(),
              ],
            ),
          ),
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
            'Khách Lưu Trú Qua Đêm',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${widget.tenPhong} • ${widget.toaNha}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: _primary),
          tooltip: 'Tải lại',
          onPressed: _taiDanhSachTuSupabase,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'Tìm theo họ tên, CCCD hoặc mã phiếu...',
          hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF64748B),
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 12,
            horizontal: 14,
          ),
        ),
      ),
    );
  }

  // 2 Thẻ thống kê tóm tắt
  Widget _buildThongKeGrid() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Chờ duyệt',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                    Icon(
                      Icons.schedule_rounded,
                      color: Color(0xFFD97706),
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _countChoDuyet.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFB45309),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Đang đợi BQL xử lý',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF92400E)),
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
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Đã duyệt',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A),
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _countDaDuyet.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF15803D),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Hợp lệ lưu trú',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF166534)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(
            index: 0,
            label: 'Tất cả (${KhachLuuTruModel.danhSachLuuTru.length})',
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            index: 1,
            label: 'Chờ duyệt ($_countChoDuyet)',
            dotColor: const Color(0xFFD97706),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            index: 2,
            label: 'Đã duyệt ($_countDaDuyet)',
            dotColor: const Color(0xFF16A34A),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            index: 3,
            label: 'Từ chối ($_countTuChoi)',
            dotColor: const Color(0xFFDC2626),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required int index,
    required String label,
    Color? dotColor,
  }) {
    final bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _primary : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTheKhachLuuTru(KhachLuuTruModel item) {
    final String st = item.trangThai.toLowerCase();
    final bool isChoDuyet = st.contains('chờ') || st.contains('đang');
    final bool isDaDuyet = st.contains('duyệt') ||
        st.contains('xác nhận') ||
        st.contains('hoàn tất') ||
        st.contains('đồng ý') ||
        st.contains('chấp nhận') ||
        st.contains('hợp lệ');

    final Color badgeBg = isChoDuyet
        ? const Color(0xFFFFFBEB)
        : (isDaDuyet ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2));
    final Color badgeBorder = isChoDuyet
        ? const Color(0xFFFDE68A)
        : (isDaDuyet ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA));
    final Color badgeText = isChoDuyet
        ? const Color(0xFFB45309)
        : (isDaDuyet ? const Color(0xFF15803D) : const Color(0xFFDC2626));
    final IconData badgeIcon = isChoDuyet
        ? Icons.schedule_rounded
        : (isDaDuyet ? Icons.check_circle_rounded : Icons.cancel_rounded);

    return InkWell(
      onTap: () => _xemChiTiet(item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFFE0F2FE),
                  child: Text(
                    _getInitials(item.hoTen),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _primary,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.hoTen,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '#${item.id} • ${item.maPhong ?? widget.tenPhong}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 12, color: badgeText),
                      const SizedBox(width: 4),
                      Text(
                        item.trangThai,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 14,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Flexible(
                  flex: 5,
                  child: Text(
                    'CCCD: ${item.cccd}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '|',
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                  ),
                ),
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: Color(0xFF0284C7),
                ),
                const SizedBox(width: 4),
                Flexible(
                  flex: 6,
                  child: Text(
                    item.thoiGian,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardQuyDinh() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: Color(0xFF2563EB)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Lưu ý: Tất cả khách lưu trú qua đêm cần được đăng ký trước 22h00 và có xác nhận duyệt từ Ban Quản Lý tòa nhà theo quy định an ninh.',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFF1E40AF),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

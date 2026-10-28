import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhGiaHanHopDong.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

/// Màn hình: Lịch Sử Gia Hạn Hợp Đồng (Contract Renewal History)
/// Quản lý và theo dõi toàn bộ các đơn yêu cầu gia hạn và các phụ lục hợp đồng gia hạn.
class ManHinhLichSuGiaHanHopDong extends StatefulWidget {
  final String? maHopDong;
  final String? tenPhong;
  final HopDongModel? hopDong;

  const ManHinhLichSuGiaHanHopDong({
    super.key,
    this.maHopDong,
    this.tenPhong,
    this.hopDong,
  });

  @override
  State<ManHinhLichSuGiaHanHopDong> createState() =>
      _ManHinhLichSuGiaHanHopDongState();
}

class _ManHinhLichSuGiaHanHopDongState
    extends State<ManHinhLichSuGiaHanHopDong> {
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  int _selectedFilterIndex =
      0; // 0: Tất cả, 1: Chờ duyệt, 2: Đã duyệt, 3: Từ chối
  bool _isLoading = true;
  bool _isDaiDien = true;
  List<Map<String, dynamic>> _danhSachPhuLuc = [];
  RealtimeChannel? _rtChannel;

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
    _fetchLichSuGiaHan();
    _initRealtime();
  }

  @override
  void dispose() {
    _rtChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtime() {
    try {
      final db = Supabase.instance.client;
      _rtChannel = db.channel('public:pl_history_$_contractCode')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'phu_luc_hop_dong',
          callback: (_) {
            _fetchLichSuGiaHan(isSilent: true);
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  String get _contractCode {
    if (widget.maHopDong != null && widget.maHopDong!.isNotEmpty) {
      return widget.maHopDong!;
    }
    if (widget.hopDong?.maHopDong != null &&
        widget.hopDong!.maHopDong.isNotEmpty) {
      return widget.hopDong!.maHopDong;
    }
    return 'HD001';
  }

  String get _roomName {
    if (widget.tenPhong != null && widget.tenPhong!.isNotEmpty) {
      return widget.tenPhong!;
    }
    if (widget.hopDong?.maPhong != null && widget.hopDong!.maPhong.isNotEmpty) {
      return 'Phòng ${widget.hopDong!.maPhong}';
    }
    return 'Phòng 203';
  }

  Future<void> _fetchLichSuGiaHan({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);

    try {
      final db = Supabase.instance.client;
      String cCode = _contractCode;

      final user = AuthService.currentUser;
      bool userIsDaiDien = true;
      if (user != null) {
        final authRole = user.vaiTro.toLowerCase();
        if (authRole.contains('admin') ||
            authRole.contains('chutro') ||
            authRole.contains('quanly')) {
          userIsDaiDien = true;
        } else if (authRole.contains('thanhvien') ||
            authRole.contains('banocung') ||
            authRole.contains('ocung')) {
          userIsDaiDien = false;
        } else if (user.maTaiKhoan.isNotEmpty) {
          final kt = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('ma_tai_khoan', user.maTaiKhoan)
              .maybeSingle();
          if (kt != null) {
            final maKhach = kt['ma_khach']?.toString() ?? '';
            final cthd = await db
                .from('chi_tiet_hop_dong_khach_thue')
                .select('ma_hop_dong, vai_tro')
                .eq('ma_khach', maKhach)
                .maybeSingle();
            if (cthd != null) {
              cCode = cthd['ma_hop_dong']?.toString() ?? cCode;
              final vt = (cthd['vai_tro']?.toString() ?? '').toLowerCase();
              if (vt.contains('ở cùng') ||
                  vt.contains('thành viên') ||
                  vt.contains('ocung')) {
                userIsDaiDien = false;
              } else if (vt.contains('đại diện') ||
                  vt.contains('trưởng phòng')) {
                userIsDaiDien = true;
              }
            }
          }
        }
      }

      // Nếu mã mặc định, thử lấy mã thực từ tài khoản đang đăng nhập
      if (cCode == 'HD001' && user != null && user.maTaiKhoan.isNotEmpty) {
        final kt = await db
            .from('khach_thue')
            .select('ma_khach')
            .eq('ma_tai_khoan', user.maTaiKhoan)
            .maybeSingle();
        if (kt != null) {
          final cthd = await db
              .from('chi_tiet_hop_dong_khach_thue')
              .select('ma_hop_dong')
              .eq('ma_khach', kt['ma_khach'])
              .limit(1)
              .maybeSingle();
          if (cthd != null) {
            cCode = cthd['ma_hop_dong']?.toString() ?? cCode;
          }
        }
      }

      final res = await db
          .from('phu_luc_hop_dong')
          .select()
          .eq('ma_hop_dong', cCode)
          .order('ngay_lap', ascending: false);

      if (mounted) {
        // Lọc chỉ giữ các phụ lục gia hạn (loại bỏ phụ lục chuyển phòng có mã PLCP hoặc ma_phong_moi)
        final giaHanList = (res as List)
            .where((item) {
              final pMoi = item['ma_phong_moi']?.toString() ?? '';
              final code = item['ma_phu_luc']?.toString() ?? '';
              final loai = item['loai_phu_luc']?.toString().toLowerCase() ?? '';
              if (pMoi.isNotEmpty ||
                  code.startsWith('PLCP') ||
                  loai.contains('chuyển phòng')) {
                return false;
              }
              return true;
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        setState(() {
          _isDaiDien = userIsDaiDien;
          _danhSachPhuLuc = giaHanList;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[LICH_SU_GIA_HAN] Lỗi tải dữ liệu: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_selectedFilterIndex == 0) return _danhSachPhuLuc;
    if (_selectedFilterIndex == 1) {
      return _danhSachPhuLuc
          .where((i) => (i['trang_thai']?.toString() ?? '') == 'Chờ duyệt')
          .toList();
    }
    if (_selectedFilterIndex == 2) {
      return _danhSachPhuLuc
          .where((i) => (i['trang_thai']?.toString() ?? '') == 'Đã duyệt')
          .toList();
    }
    if (_selectedFilterIndex == 3) {
      return _danhSachPhuLuc
          .where((i) => (i['trang_thai']?.toString() ?? '') == 'Từ chối')
          .toList();
    }
    return _danhSachPhuLuc;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _fetchLichSuGiaHan(),
          color: _primary,
          child: Column(
            children: [
              _buildSummaryHeader(),
              _buildFilterChips(),
              Expanded(
                child: _isLoading
                    ? const LoadingMeoMeo(
                        message: 'Đang tải lịch sử gia hạn...',
                        subMessage: 'Mèo con đang kiểm tra các đơn gia hạn~ 🐾',
                      )
                    : _filteredList.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                        itemCount: _filteredList.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (context, index) {
                          final item = _filteredList[index];
                          return _buildPhuLucCard(item);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: _isDaiDien
          ? FloatingActionButton.extended(
              onPressed: () async {
                if (!_isDaiDien) {
                  _thongBaoKhongCoQuyen(hanhDong: 'Gia hạn hợp đồng');
                  return;
                }
                int daysLeft = 999;
                if (widget.hopDong?.ngayKt != null &&
                    widget.hopDong!.ngayKt.isNotEmpty) {
                  try {
                    final dt = DateTime.parse(widget.hopDong!.ngayKt);
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
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ManHinhGiaHanHopDong(
                      hopDong: widget.hopDong,
                      tenPhong: _roomName,
                      maPhong: widget.hopDong?.maPhong ?? 'P203',
                    ),
                  ),
                );
                _fetchLichSuGiaHan(isSilent: true);
              },
              backgroundColor: _primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                'Tạo Đơn Gia Hạn',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 19,
          color: _textDark,
        ),
        onPressed: () => Navigator.pop(context),
      ),
      centerTitle: true,
      title: Column(
        children: [
          const Text(
            'Lịch Sử Gia Hạn Hợp Đồng',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$_roomName • HĐ: $_contractCode',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    final tong = _danhSachPhuLuc.length;
    final choDuyet = _danhSachPhuLuc
        .where((i) => i['trang_thai'] == 'Chờ duyệt')
        .length;
    final daDuyet = _danhSachPhuLuc
        .where((i) => i['trang_thai'] == 'Đã duyệt')
        .length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCol('Tổng số đơn', '$tong', const Color(0xFF0F172A)),
          Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
          _buildStatCol('Chờ duyệt', '$choDuyet', const Color(0xFFD97706)),
          Container(width: 1, height: 32, color: const Color(0xFFE2E8F0)),
          _buildStatCol('Đã duyệt', '$daDuyet', const Color(0xFF16A34A)),
        ],
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Tất cả', 'Chờ duyệt', 'Đã duyệt', 'Từ chối'];
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return ChoiceChip(
            label: Text(filters[index]),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedFilterIndex = index),
            backgroundColor: Colors.white,
            selectedColor: _primary,
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isSelected ? _primary : const Color(0xFFE2E8F0),
              ),
            ),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _buildPhuLucCard(Map<String, dynamic> item) {
    final maPl = item['ma_phu_luc']?.toString() ?? 'PL_GIA_HAN';
    final st = item['trang_thai']?.toString() ?? 'Chờ duyệt';
    final ngayLap = item['ngay_lap']?.toString() ?? '';
    final ngayDen = item['ngay_gia_han_den']?.toString() ?? '';
    final noiDung =
        item['noi_dung_dieu_chinh']?.toString() ?? 'Gia hạn thời hạn hợp đồng';
    final giaMoi = num.tryParse(item['gia_thue_moi']?.toString() ?? '0') ?? 0;

    Color badgeColor;
    Color badgeTextColor;
    String badgeText;
    IconData badgeIcon;

    if (st == 'Đã duyệt') {
      badgeColor = const Color(0xFFDCFCE7);
      badgeTextColor = const Color(0xFF15803D);
      badgeText = 'ĐÃ DUYỆT';
      badgeIcon = Icons.check_circle_rounded;
    } else if (st == 'Từ chối') {
      badgeColor = const Color(0xFFFEE2E2);
      badgeTextColor = const Color(0xFFB91C1C);
      badgeText = 'TỪ CHỐI';
      badgeIcon = Icons.cancel_rounded;
    } else {
      badgeColor = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFB45309);
      badgeText = 'CHỜ DUYỆT';
      badgeIcon = Icons.hourglass_top_rounded;
    }

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
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Mã phụ lục & Trạng thái
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history_edu_rounded,
                      size: 14,
                      color: _primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      maPl,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 13, color: badgeTextColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Nội dung điều chỉnh
          Text(
            noiDung,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _textDark,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Thông tin thời gian & Tiền cọc
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoMini('Ngày nộp đơn', _formatDate(ngayLap)),
              if (ngayDen.isNotEmpty)
                _buildInfoMini(
                  'Gia hạn đến',
                  _formatDate(ngayDen),
                  isHighlight: true,
                ),
              if (giaMoi > 0)
                _buildInfoMini(
                  'Giá thuê',
                  '${FormatUtils.currency(giaMoi.toDouble())}/tháng',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Nút xem chi tiết phụ lục
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: () => _hienThiChiTietPhuLucModal(item),
              icon: const Icon(
                Icons.visibility_outlined,
                size: 16,
                color: _primary,
              ),
              label: const Text(
                'Xem Chi Tiết Phụ Lục Ký Kết',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFBAE6FD)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoMini(
    String label,
    String value, {
    bool isHighlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFF0284C7) : _textDark,
          ),
        ),
      ],
    );
  }

  String _formatDate(String raw) {
    if (raw.trim().isEmpty) return '---';
    try {
      final d = DateTime.parse(raw);
      final dd = d.day.toString().padLeft(2, '0');
      final mm = d.month.toString().padLeft(2, '0');
      final yyyy = d.year.toString();
      return '$dd/$mm/$yyyy';
    } catch (_) {
      return raw;
    }
  }

  void _hienThiChiTietPhuLucModal(Map<String, dynamic> item) {
    final maPl = item['ma_phu_luc']?.toString() ?? 'PL_GIA_HAN';
    final st = item['trang_thai']?.toString() ?? 'Chờ duyệt';
    final ngayLap = item['ngay_lap']?.toString() ?? '';
    final ngayDen = item['ngay_gia_han_den']?.toString() ?? '';
    final noiDung = item['noi_dung_dieu_chinh']?.toString() ?? '';
    final giaMoi = num.tryParse(item['gia_thue_moi']?.toString() ?? '0') ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_rounded,
                      color: _primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Phụ Lục Gia Hạn #$maPl',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _textDark,
                          ),
                        ),
                        Text(
                          'Căn cứ Hợp đồng số: $_contractCode',
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
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              const SizedBox(height: 14),

              _buildModalRow('Trạng thái phê duyệt:', st),
              _buildModalRow('Ngày lập văn bản:', _formatDate(ngayLap)),
              _buildModalRow('Phòng áp dụng:', _roomName),
              if (ngayDen.isNotEmpty)
                _buildModalRow('Thời hạn thuê mới đến:', _formatDate(ngayDen)),
              if (giaMoi > 0)
                _buildModalRow(
                  'Giá thuê thỏa thuận:',
                  '${FormatUtils.currency(giaMoi.toDouble())}/tháng',
                ),
              _buildModalRow(
                'Tiền đặt cọc bảo lưu:',
                '100% bảo lưu tiền cọc gốc',
              ),

              const SizedBox(height: 14),
              const Text(
                'Điều khoản điều chỉnh:',
                style: TextStyle(
                  fontSize: 12.5,
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
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  noiDung.isNotEmpty
                      ? noiDung
                      : 'Gia hạn thời hạn hợp đồng thuê nhà theo thỏa thuận.',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: Color(0xFF16A34A),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Phụ lục này là bộ phận không tách rời của Hợp đồng thuê nhà ban đầu và có giá trị pháp lý đầy đủ.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF15803D),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Đóng',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFE0F2FE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_edu_rounded,
                size: 36,
                color: _primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa Có Đơn Gia Hạn Nào',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Các yêu cầu gia hạn hợp đồng và phụ lục đã ký của bạn sẽ được hiển thị và theo dõi tại đây.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
            if (_isDaiDien) ...[
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () async {
                  if (!_isDaiDien) {
                    _thongBaoKhongCoQuyen(hanhDong: 'Gia hạn hợp đồng');
                    return;
                  }
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManHinhGiaHanHopDong(
                        hopDong: widget.hopDong,
                        tenPhong: _roomName,
                        maPhong: widget.hopDong?.maPhong ?? 'P203',
                      ),
                    ),
                  );
                  _fetchLichSuGiaHan(isSilent: true);
                },
                icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                label: const Text('Tạo Yêu Cầu Gia Hạn Ngay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

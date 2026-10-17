import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChuyenPhongThanhCong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTimKiemChuyenPhong.dart';

/// Màn hình: Lịch Sử Chuyển Phòng (Room Transfer History)
/// Theo dõi toàn bộ danh sách đơn yêu cầu chuyển phòng, tiến độ phê duyệt,
/// biên bản nghiệm thu hiện trạng và lịch dọn phòng.
class RoomTransferHistoryScreen extends StatefulWidget {
  final String? currentRoomNumber;
  final String? maHopDong;
  final HopDongModel? hopDong;

  const RoomTransferHistoryScreen({
    super.key,
    this.currentRoomNumber,
    this.maHopDong,
    this.hopDong,
  });

  @override
  State<RoomTransferHistoryScreen> createState() =>
      _RoomTransferHistoryScreenState();
}

class _RoomTransferHistoryScreenState extends State<RoomTransferHistoryScreen> {
  // ── Theme Navy Sang Trọng Đồng Bộ Hệ Thống ──
  static const _navyDark = Color(0xFF0F2042);
  static const _navyAccent = Color(0xFF1E3A8A);
  static const _navyBlue = Color(0xFF09638E);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  int _selectedFilterIndex = 0; // 0: Tất cả, 1: Đang xử lý, 2: Đã duyệt, 3: Đã hủy/Từ chối
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _danhSachYccp = [];
  RealtimeChannel? _rtChannel;

  @override
  void initState() {
    super.initState();
    _fetchTransferRequests();
    _initRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _rtChannel?.unsubscribe();
    super.dispose();
  }

  void _initRealtime() {
    try {
      final db = Supabase.instance.client;
      _rtChannel = db.channel('public:yccp_history_${DateTime.now().millisecondsSinceEpoch}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'yeu_cau_chuyen_phong',
          callback: (_) {
            _fetchTransferRequests(isSilent: true);
          },
        )
        ..subscribe();
    } catch (_) {}
  }

  Future<void> _fetchTransferRequests({bool isSilent = false}) async {
    if (!isSilent) setState(() => _isLoading = true);

    try {
      final db = Supabase.instance.client;
      String? contractCode = widget.maHopDong ?? widget.hopDong?.maHopDong;
      final curRoom = widget.currentRoomNumber ?? widget.hopDong?.maPhong ?? 'P203';

      if (contractCode == null || contractCode.isEmpty) {
        final user = AuthService.currentUser;
        if (user != null && user.maTaiKhoan.isNotEmpty) {
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
              contractCode = cthd['ma_hop_dong']?.toString();
            }
          }
        }
      }

      var query = db.from('yeu_cau_chuyen_phong').select();

      if (contractCode != null && contractCode.isNotEmpty) {
        query = query.or('ma_hop_dong_ht.eq.$contractCode,ma_phong_cu.eq.$curRoom');
      }

      final rows = await query.order('ngay_tao', ascending: false);

      if (mounted) {
        setState(() {
          _danhSachYccp = List<Map<String, dynamic>>.from(rows as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[YCCP_HISTORY] Lỗi tải lịch sử chuyển phòng: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Đếm số lượng theo trạng thái ──
  int get _countInProgress => _danhSachYccp.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Chờ duyệt' ||
            st == 'Đang xử lý' ||
            st == 'Đã kiểm tra' ||
            st == 'Chờ khách xác nhận' ||
            st == 'Khách đã xác nhận' ||
            st == 'Chờ chủ duyệt';
      }).length;

  int get _countCompleted => _danhSachYccp.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Đã duyệt' || st == 'Hoàn tất';
      }).length;

  int get _countCancelled => _danhSachYccp.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Từ chối' || st == 'Đã hủy';
      }).length;

  List<Map<String, dynamic>> get _filteredList {
    var list = _danhSachYccp;

    // Lọc theo Tab
    if (_selectedFilterIndex == 1) {
      list = list.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Chờ duyệt' ||
            st == 'Đang xử lý' ||
            st == 'Đã kiểm tra' ||
            st == 'Chờ khách xác nhận' ||
            st == 'Khách đã xác nhận' ||
            st == 'Chờ chủ duyệt';
      }).toList();
    } else if (_selectedFilterIndex == 2) {
      list = list.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Đã duyệt' || st == 'Hoàn tất';
      }).toList();
    } else if (_selectedFilterIndex == 3) {
      list = list.where((r) {
        final st = r['trang_thai_tien_do']?.toString() ?? '';
        return st == 'Từ chối' || st == 'Đã hủy';
      }).toList();
    }

    // Lọc theo từ khóa tìm kiếm
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((r) {
        final maYC = (r['ma_yeu_cau'] ?? '').toString().toLowerCase();
        final phongCu = (r['ma_phong_cu'] ?? '').toString().toLowerCase();
        final phongMoi = (r['ma_phong_moi'] ?? '').toString().toLowerCase();
        final lyDo = (r['ly_do_chuyen'] ?? '').toString().toLowerCase();
        return maYC.contains(q) ||
            phongCu.contains(q) ||
            phongMoi.contains(q) ||
            lyDo.contains(q);
      }).toList();
    }

    return list;
  }

  // ── Mở màn hình biên bản nghiệm thu / chi tiết ──
  Future<void> _moManHinhNghiemThu(Map<String, dynamic> r) async {
    final maYC = r['ma_yeu_cau']?.toString() ?? '';
    final maPhongCu = r['ma_phong_cu']?.toString() ?? widget.currentRoomNumber ?? 'P203';
    final maPhongMoi = r['ma_phong_moi']?.toString() ?? 'P201';

    Map<String, dynamic>? phongMoiData;
    try {
      final res = await Supabase.instance.client
          .from('phong')
          .select()
          .eq('ma_phong', maPhongMoi)
          .maybeSingle();
      if (res != null) {
        phongMoiData = res;
      }
    } catch (_) {}

    final giaThueMoi = (phongMoiData?['gia_thue'] as num?) ?? 3500000;
    final tienCocMoi = (phongMoiData?['tien_dat_coc'] as num?) ?? giaThueMoi;
    final tangMoi = (phongMoiData?['tang'] as num?)?.toInt() ?? 2;
    final dienTichMoi = (phongMoiData?['dien_tich'] as num?)?.toInt() ?? 26;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomTransferSuccessScreen(
          ticketCode: maYC,
          targetRoom: {
            'maPhong': maPhongMoi,
            'toaNha': phongMoiData?['toa_nha']?.toString() ?? 'Kiêu Giang',
            'tang': tangMoi,
            'dienTich': dienTichMoi,
            'giaThue': giaThueMoi,
            'tienDatCoc': tienCocMoi,
          },
          currentRoomNumber: maPhongCu,
          currentPrice: (r['tien_coc_bao_luu'] as num?) ?? widget.hopDong?.giaThueThaoThuan ?? 3800000,
          moveInDateFormatted: r['thoi_gian_hen']?.toString() ?? '',
          reason: r['ly_do_chuyen']?.toString() ?? 'Chuyển phòng theo yêu cầu',
          note: '',
        ),
      ),
    ).then((_) => _fetchTransferRequests(isSilent: true));
  }

  // ── Xử lý Hủy đơn chuyển phòng ──
  Future<void> _xacNhanHuyDon(Map<String, dynamic> r) async {
    final maYC = r['ma_yeu_cau']?.toString() ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Hủy yêu cầu chuyển phòng?'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn hủy đơn yêu cầu chuyển sang phòng ${r['ma_phong_moi']} (#$maYC) không?\n\nSau khi hủy, bạn có thể tạo lại yêu cầu mới bất kỳ lúc nào.',
          style: const TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Giữ lại đơn', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Xác nhận hủy'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final db = Supabase.instance.client;
        await db.from('yeu_cau_chuyen_phong').update({
          'trang_thai_tien_do': 'Đã hủy',
        }).eq('ma_yeu_cau', maYC);

        if (!mounted) return;
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Đã Hủy Yêu Cầu Thành Công',
          noiDung: 'Yêu cầu chuyển phòng #$maYC đã được hủy thành công.',
          type: ThongBaoType.thanhCong,
        );
        _fetchTransferRequests();
      } catch (e) {
        if (!mounted) return;
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Lỗi Hủy Yêu Cầu',
          noiDung: 'Không thể hủy đơn: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _navyDark),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchTransferRequests,
                      color: _navyDark,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSubHeader(),
                            const SizedBox(height: 12),
                            _buildSearchBar(),
                            const SizedBox(height: 12),
                            _buildFilterTabs(),
                            const SizedBox(height: 14),
                            _buildSummaryBanner(),
                            const SizedBox(height: 16),
                            _buildRequestsList(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final curRoom = widget.currentRoomNumber ?? widget.hopDong?.maPhong ?? 'P203';
          final curPrice = widget.hopDong?.giaThueThaoThuan ?? 2800000;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RoomTransferSearchScreen(
                currentRoomNumber: curRoom,
                currentPrice: curPrice,
                maHopDong: widget.maHopDong ?? widget.hopDong?.maHopDong,
                hopDong: widget.hopDong,
              ),
            ),
          ).then((_) => _fetchTransferRequests(isSilent: true));
        },
        backgroundColor: _navyDark,
        elevation: 4,
        label: const Text(
          'Đổi phòng mới',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  // ─── 1. TOP APP BAR ───
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _navyDark,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Lịch Sử Chuyển Phòng',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: _navyDark,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  widget.currentRoomNumber != null
                      ? 'Cư dân phòng ${widget.currentRoomNumber} • Kiêu Giang House'
                      : 'Theo dõi tiến trình & biên bản nghiệm thu',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE6EDF5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: _navyDark,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2. SUB HEADER ───
  Widget _buildSubHeader() {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: _navyBlue, size: 16),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Quy trình: Gửi đơn → BQL kiểm tra → Khách ký nghiệm thu → Đổi phòng',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF475569),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ─── 3. SEARCH BAR ───
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(fontSize: 13, color: _textDark),
        decoration: InputDecoration(
          hintText: 'Tìm theo mã đơn (#YCCP), phòng cũ, phòng mới...',
          hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 18),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }

  // ─── 4. FILTER TABS ───
  Widget _buildFilterTabs() {
    final tabs = [
      'Tất cả (${_danhSachYccp.length})',
      'Đang xử lý ($_countInProgress)',
      'Đã duyệt ($_countCompleted)',
      'Từ chối/Hủy ($_countCancelled)',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedFilterIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedFilterIndex = index),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [_navyDark, _navyAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: isSelected ? null : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? _navyDark : const Color(0xFFCBD5E1),
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: _navyDark.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF334155),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── 5. SUMMARY BANNER ───
  Widget _buildSummaryBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F2042), Color(0xFF09638E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navyDark.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quy chế đổi phòng Kiêu Giang',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tiền cọc cũ được bảo lưu 100% sang phòng mới. Giãn cách mỗi lần đổi phòng là 60 ngày.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. REQUESTS LIST ───
  Widget _buildRequestsList() {
    final list = _filteredList;

    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            const Icon(Icons.find_in_page_outlined, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'Không tìm thấy yêu cầu chuyển phòng nào',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bạn chưa gửi đơn chuyển phòng nào hoặc không khớp từ khóa tìm kiếm.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                final curRoom = widget.currentRoomNumber ?? widget.hopDong?.maPhong ?? 'P203';
                final curPrice = widget.hopDong?.giaThueThaoThuan ?? 2800000;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RoomTransferSearchScreen(
                      currentRoomNumber: curRoom,
                      currentPrice: curPrice,
                      maHopDong: widget.maHopDong ?? widget.hopDong?.maHopDong,
                      hopDong: widget.hopDong,
                    ),
                  ),
                ).then((_) => _fetchTransferRequests(isSilent: true));
              },
              icon: const Icon(Icons.add_home_rounded, size: 16),
              label: const Text('Tìm phòng mới để chuyển'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: list.map((r) => _buildTransferCard(r)).toList(),
    );
  }

  // ─── 7. CARD TỪNG ĐƠN CHUYỂN PHÒNG ───
  Widget _buildTransferCard(Map<String, dynamic> r) {
    final maYC = r['ma_yeu_cau']?.toString() ?? 'YCCP';
    final maPhongCu = r['ma_phong_cu']?.toString() ?? 'P.203';
    final maPhongMoi = r['ma_phong_moi']?.toString() ?? 'P.302';
    final status = r['trang_thai_tien_do']?.toString() ?? 'Chờ duyệt';
    final ngayTao = r['ngay_tao']?.toString() ?? '';
    final thoiGianHen = r['thoi_gian_hen']?.toString() ?? '';
    final lyDo = r['ly_do_chuyen']?.toString() ?? 'Chuyển phòng theo nhu cầu';
    final ghiChu = r['ghi_chu_hu_hai']?.toString() ?? '';
    final lyDoTuChoi = r['ly_do_tu_choi']?.toString() ?? '';
    final tienPhatSinh = num.tryParse(r['tien_phat_sinh']?.toString() ?? '0') ?? 0;
    final dienNuocCu = num.tryParse(r['tien_dien_nuoc_cu']?.toString() ?? '0') ?? 0;
    final huHaiCu = num.tryParse(r['tien_hu_hai_cu']?.toString() ?? '0') ?? 0;

    // Phân loại trạng thái
    final isAwaitingInspection = status == 'Chờ khách xác nhận' || status == 'Đã kiểm tra';
    final isApproved = status == 'Đã duyệt' || status == 'Hoàn tất';
    final isRejected = status == 'Từ chối';
    final isCancelled = status == 'Đã hủy';
    final isProcessing = status == 'Chờ duyệt' || status == 'Đang xử lý';
    final isAwaitingLandlord = status == 'Khách đã xác nhận' || status == 'Chờ chủ duyệt';

    Color statusColor;
    Color statusBg;
    IconData statusIcon;

    if (isApproved) {
      statusColor = const Color(0xFF16A34A);
      statusBg = const Color(0xFFDCFCE7);
      statusIcon = Icons.check_circle_rounded;
    } else if (isAwaitingInspection) {
      statusColor = const Color(0xFF0284C7);
      statusBg = const Color(0xFFE0F2FE);
      statusIcon = Icons.assignment_turned_in_rounded;
    } else if (isAwaitingLandlord) {
      statusColor = const Color(0xFF9333EA);
      statusBg = const Color(0xFFF3E8FF);
      statusIcon = Icons.hourglass_top_rounded;
    } else if (isRejected) {
      statusColor = const Color(0xFFDC2626);
      statusBg = const Color(0xFFFEE2E2);
      statusIcon = Icons.cancel_rounded;
    } else if (isCancelled) {
      statusColor = const Color(0xFF64748B);
      statusBg = const Color(0xFFF1F5F9);
      statusIcon = Icons.remove_circle_outline_rounded;
    } else {
      statusColor = const Color(0xFFD97706);
      statusBg = const Color(0xFFFEF3C7);
      statusIcon = Icons.pending_actions_rounded;
    }

    String ngayTaoFormatted = ngayTao;
    if (ngayTao.isNotEmpty) {
      try {
        final dt = DateTime.parse(ngayTao);
        ngayTaoFormatted =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    String thoiGianHenFormatted = thoiGianHen;
    if (thoiGianHen.isNotEmpty) {
      try {
        final dt = DateTime.parse(thoiGianHen);
        thoiGianHenFormatted =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAwaitingInspection
              ? const Color(0xFF0284C7)
              : (isApproved ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
          width: isAwaitingInspection ? 1.5 : 1.0,
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
          // 1. Mã đơn & Status Badge
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.confirmation_number_outlined,
                          size: 14, color: _navyDark),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '#$maYC',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _navyDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Chuyển đổi trực quan: Phòng cũ -> Phòng mới
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                // Phòng cũ
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phòng đang ở',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.meeting_room_outlined,
                              size: 15, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              maPhongCu,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
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

                // Icon Mũi tên chuyển hướng
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _navyBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: _navyBlue,
                    size: 18,
                  ),
                ),

                // Phòng mới
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Phòng chuyển đến',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF0369A1)),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              maPhongMoi,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: _navyBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.hotel_rounded,
                              size: 16, color: _navyBlue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Thông tin chi tiết: Thời gian & Chi phí phát sinh
          if (thoiGianHenFormatted.isNotEmpty)
            _buildDetailRow(
              Icons.event_available_rounded,
              'Ngày hẹn dọn:',
              thoiGianHenFormatted,
              valueColor: _navyDark,
              isBold: true,
            ),
          _buildDetailRow(
            Icons.access_time_rounded,
            'Thời gian gửi đơn:',
            ngayTaoFormatted,
          ),
          _buildDetailRow(
            Icons.comment_outlined,
            'Lý do chuyển:',
            lyDo,
          ),

          if (tienPhatSinh != 0)
            _buildDetailRow(
              Icons.account_balance_wallet_outlined,
              'Chênh lệch cọc/phí:',
              FormatUtils.currency(tienPhatSinh),
              valueColor: tienPhatSinh > 0 ? const Color(0xFFD97706) : const Color(0xFF16A34A),
              isBold: true,
            ),

          if (dienNuocCu > 0 || huHaiCu > 0)
            _buildDetailRow(
              Icons.handyman_outlined,
              'Điện nước & Khấu trừ:',
              FormatUtils.currency(dienNuocCu + huHaiCu),
              valueColor: const Color(0xFFDC2626),
              isBold: true,
            ),

          if (isRejected && lyDoTuChoi.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Lý do từ chối: $lyDoTuChoi',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (ghiChu.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Ghi chú BQL: $ghiChu',
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFF64748B),
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 10),

          // 4. Các nút hành động tương tác thông minh
          Row(
            children: [
              if (isAwaitingInspection) ...[
                // Banner nhắc nhở cần ký
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _moManHinhNghiemThu(r),
                    icon: const Icon(Icons.draw_rounded, size: 16),
                    label: const Text(
                      'Xem Biên Bản & Ký Xác Nhận',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ] else if (isProcessing) ...[
                OutlinedButton.icon(
                  onPressed: () => _xacNhanHuyDon(r),
                  icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                  label: const Text(
                    'Hủy yêu cầu',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _moManHinhNghiemThu(r),
                  icon: const Icon(Icons.remove_red_eye_rounded, size: 14),
                  label: const Text(
                    'Xem tiến độ',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyDark,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ] else if (isApproved) ...[
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ContractDetailScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.description_rounded, size: 14),
                  label: const Text(
                    'Xem Hợp Đồng & Phụ Lục Mới',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ] else ...[
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => _moManHinhNghiemThu(r),
                  icon: const Icon(Icons.info_outline_rounded, size: 14),
                  label: const Text(
                    'Chi tiết đơn',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navyDark,
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13.5, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: valueColor ?? _textDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhChiTietPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietChuyenPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChuyenPhongThanhCong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Màn hình 2: Chọn Phòng Trống cho Chức năng Chuyển Phòng Khách Thuê
/// Tìm kiếm, lọc theo giá, đối chiếu chênh lệch và chọn phòng để làm thủ tục chuyển.
class RoomTransferSearchScreen extends StatefulWidget {
  final String currentRoomNumber;
  final num currentPrice;
  final String? maHopDong;
  final HopDongModel? hopDong;

  const RoomTransferSearchScreen({
    super.key,
    this.currentRoomNumber = 'P.302',
    this.currentPrice = 3200000,
    this.maHopDong,
    this.hopDong,
  });

  @override
  State<RoomTransferSearchScreen> createState() =>
      _RoomTransferSearchScreenState();
}

class _RoomTransferSearchScreenState extends State<RoomTransferSearchScreen> {
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  final TextEditingController _searchController = TextEditingController();
  int _selectedTab = 0; // 0: Tất cả, 1: Cùng tòa
  int _selectedPriceFilter = 0; // 0: Tất cả, 1: Dưới 3.5tr, 2: 3.5tr - 4.5tr, 3: Có gác
  bool _isLoading = true;
  Map<String, dynamic>? _pendingTransfer;

  // Danh sách phòng thực tế tải từ Supabase
  List<Map<String, dynamic>> _rooms = [];

  // Danh sách phòng dự phòng khi offline hoặc cơ sở dữ liệu chưa có phòng trống
  final List<Map<String, dynamic>> _defaultRooms = [
    {
      'maPhong': 'P205',
      'toaNha': 'Kiêu Giang 2',
      'isSameBuilding': true,
      'tang': 2,
      'dienTich': 22,
      'giaThue': 3200000,
      'dacDiem': '22m² • Hướng Đông mát',
      'highlight': 'Đồng giá phòng cũ • Không bù tiền phòng',
      'tagTang': 'Tầng 2 - Tiện đi lại',
      'hinhAnh':
          'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=600',
      'tienIch': [
        'Máy lạnh inverter',
        'Nước nóng NLMT',
        'Kệ bếp riêng sạch',
        'Tủ lạnh riêng 150L',
      ],
      'diffAmount': 0,
      'diffText': '0đ (Đồng giá)',
    },
    {
      'maPhong': 'P402',
      'toaNha': 'Kiêu Giang 2',
      'isSameBuilding': true,
      'tang': 4,
      'dienTich': 25,
      'giaThue': 3500000,
      'dacDiem': '25m² • Ban công kính',
      'highlight': 'Chênh lệch: +300.000đ/tháng',
      'tagTang': 'Tầng 4 • Có ban công riêng • View thoáng',
      'hinhAnh':
          'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=600',
      'tienIch': [
        'Ban công phơi riêng',
        'Ánh sáng tự nhiên tốt',
        'Hẻm lộ xe cao cấp',
        'Vệ sinh khép kín mới',
      ],
      'diffAmount': 300000,
      'diffText': '+300.000đ/tháng',
    },
    {
      'maPhong': 'P103',
      'toaNha': 'Kiêu Giang 2',
      'isSameBuilding': true,
      'tang': 1,
      'dienTich': 20,
      'giaThue': 3100000,
      'dacDiem': '20m² • Cửa rộng thoáng',
      'highlight': 'Tiết kiệm: 100.000đ/tháng',
      'tagTang': 'Tầng 1 • Đi lại thuận tiện • Hợp xe to',
      'hinhAnh':
          'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=600',
      'tienIch': [
        'Gần bãi đỗ xe máy',
        'Cửa sổ thoáng khí',
        'Không cần leo cầu thang',
      ],
      'diffAmount': -100000,
      'diffText': 'Rẻ hơn 100.000đ/tháng',
    },
    {
      'maPhong': 'P305',
      'toaNha': 'Kiêu Giang 1',
      'isSameBuilding': false,
      'tang': 3,
      'dienTich': 28,
      'giaThue': 3800000,
      'dacDiem': '28m² • Full nội thất cao cấp',
      'highlight': 'Cơ sở Kiêu Giang 1 • Cách 500m',
      'tagTang': 'Hỗ trợ chuyển xe ba gác miễn phí sang Kiêu Giang 1',
      'hinhAnh':
          'https://images.unsplash.com/photo-1493809842364-78817add7ffb?w=600',
      'tienIch': [
        'Máy giặt riêng trong phòng',
        'Smart TV 43 inch',
        'Gác lửng đúc bê tông',
      ],
      'diffAmount': 600000,
      'diffText': '+600.000đ/tháng',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchEmptyRoomsFromSupabase();
  }

  /// Tải danh sách phòng trống thực tế trực tiếp từ Supabase giống khách vãng lai
  Future<void> _fetchEmptyRoomsFromSupabase() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final res = await Supabase.instance.client
          .from('phong')
          .select()
          .eq('trang_thai', 'Trống');

      final List<RoomModel> models = (res as List)
          .map((e) => RoomModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((r) => r.trangThai.trim().toLowerCase() == 'trống')
          .toList();

      final curClean = widget.currentRoomNumber
          .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
          .toLowerCase();

      // Loại bỏ chính phòng hiện tại mà khách đang thuê
      final filteredModels = models.where((r) {
        final rClean = r.maPhong
            .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
            .toLowerCase();
        return rClean != curClean;
      }).toList();

      final mapped = filteredModels.map((r) => _convertModelToRoomMap(r)).toList();

      // Kiểm tra xem cư dân có đơn nào đang chờ duyệt hay không
      try {
        final maHD = widget.maHopDong ?? 'HD001';
        final curRoom = widget.currentRoomNumber;
        final pendingRes = await Supabase.instance.client
            .from('yeu_cau_chuyen_phong')
            .select()
            .or('ma_hop_dong_ht.eq.$maHD,ma_phong_cu.eq.$curRoom')
            .inFilter('trang_thai_tien_do', [
              'Chờ duyệt',
              'Đang xử lý',
              'Chờ khách xác nhận',
              'Đã kiểm tra',
              'Khách đã xác nhận',
              'Chờ chủ duyệt',
            ])
            .order('ngay_tao', ascending: false)
            .limit(1);

        if (pendingRes.isNotEmpty && mounted) {
          _pendingTransfer = Map<String, dynamic>.from(pendingRes.first);
        } else if (mounted) {
          _pendingTransfer = null;
        }
      } catch (errCheck) {
        debugPrint('Lỗi kiểm tra đơn chờ duyệt: $errCheck');
      }

      if (mounted) {
        setState(() {
          if (mapped.isNotEmpty) {
            _rooms = mapped;
          } else {
            // Nếu database chưa có phòng trống nào, dùng tập dữ liệu mẫu loại trừ phòng hiện tại
            _rooms = _defaultRooms.where((r) {
              final rClean = r['maPhong']
                  .toString()
                  .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
                  .toLowerCase();
              return rClean != curClean;
            }).toList();
          }
          _isLoading = false;
        });
      }
      return;
    } catch (e) {
      debugPrint('Lỗi tải phòng trống Supabase cho chuyển phòng: $e');
    }

    if (mounted) {
      final curClean = widget.currentRoomNumber
          .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
          .toLowerCase();
      setState(() {
        _rooms = _defaultRooms.where((r) {
          final rClean = r['maPhong']
              .toString()
              .replaceAll(RegExp(r'[^0-9a-zA-Z]'), '')
              .toLowerCase();
          return rClean != curClean;
        }).toList();
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _convertModelToRoomMap(RoomModel room) {
    final diff = room.giaThue - widget.currentPrice;
    final absDiff = diff.abs().toDouble();
    final String diffText = diff == 0
        ? '0đ (Đồng giá)'
        : (diff > 0
            ? '+${FormatUtils.currency(absDiff)}/tháng'
            : 'Rẻ hơn ${FormatUtils.currency(absDiff)}/tháng');
    final String highlight = diff == 0
        ? 'Đồng giá phòng cũ • Không bù tiền phòng'
        : (diff > 0
            ? 'Chênh lệch: +${FormatUtils.currency(absDiff)}/tháng so với ${widget.currentRoomNumber}'
            : 'Tiết kiệm: ${FormatUtils.currency(absDiff)}/tháng so với ${widget.currentRoomNumber}');
    final isSame = room.toaNha.toLowerCase().contains('2') ||
        room.toaNha.toLowerCase().contains('kiêu giang 2');

    return {
      'maPhong': room.maPhong,
      'toaNha': room.toaNha,
      'isSameBuilding': isSame,
      'tang': room.tang,
      'dienTich': room.dienTich,
      'giaThue': room.giaThue,
      'tienDatCoc': room.tienDatCoc > 0 ? room.tienDatCoc : room.giaThue,
      'dacDiem': '${room.dienTich}m² • ${room.moTaNgan.isNotEmpty ? room.moTaNgan : (room.tang > 0 ? "Tầng ${room.tang}" : "Phòng tiêu chuẩn")}',
      'highlight': highlight,
      'tagTang': 'Tầng ${room.tang} • ${room.toaNha}',
      'hinhAnh': room.hinhAnh.isNotEmpty
          ? room.hinhAnh
          : 'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=600',
      'tienIch': room.tienIch.isNotEmpty
          ? room.tienIch
          : [
              'Máy lạnh inverter',
              'Nước nóng NLMT',
              'Kệ bếp riêng sạch',
              'Tủ lạnh riêng',
            ],
      'diffAmount': diff,
      'diffText': diffText,
      'roomModel': room,
    };
  }

  List<Map<String, dynamic>> get _filteredRooms {
    return _rooms.where((room) {
      // Filter tab: Cùng tòa
      if (_selectedTab == 1 && room['isSameBuilding'] != true) {
        return false;
      }
      // Price filter
      final price = room['giaThue'] as num;
      if (_selectedPriceFilter == 1 && price >= 3500000) return false;
      if (_selectedPriceFilter == 2 && (price < 3500000 || price > 4500000)) {
        return false;
      }
      if (_selectedPriceFilter == 3) {
        final desc = room['dacDiem'].toString().toLowerCase();
        final tienIchList = (room['tienIch'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
        final hasGac = desc.contains('gác') || tienIchList.any((t) => t.contains('gác'));
        if (!hasGac) return false;
      }
      // Search
      final query = _searchController.text.trim().toLowerCase();
      if (query.isNotEmpty) {
        final ma = room['maPhong'].toString().toLowerCase();
        final toa = room['toaNha'].toString().toLowerCase();
        final desc = room['dacDiem'].toString().toLowerCase();
        final tienIchList = (room['tienIch'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
        final tienIchMatch = tienIchList.any((t) => t.contains(query));
        return ma.contains(query) ||
            toa.contains(query) ||
            desc.contains(query) ||
            tienIchMatch;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Mở màn hình Chi Tiết Phòng giống khách vãng lai
  void _openRoomDetail(Map<String, dynamic> roomMap) {
    final RoomModel model = (roomMap['roomModel'] as RoomModel?) ??
        RoomModel(
        maPhong: roomMap['maPhong']?.toString() ?? '',
        maLoaiPhong: '',
        tenHienThi: 'Phòng ${roomMap["maPhong"]}',
        toaNha: roomMap['toaNha']?.toString() ?? 'Kiêu Giang 2',
        tang: (roomMap['tang'] is num) ? (roomMap['tang'] as num).toInt() : 1,
        dienTich: (roomMap['dienTich'] is num) ? (roomMap['dienTich'] as num) : 20,
        giaThue: (roomMap['giaThue'] is num) ? (roomMap['giaThue'] as num) : 3200000,
        tienDatCoc: (roomMap['tienDatCoc'] is num) ? (roomMap['tienDatCoc'] as num) : 3200000,
        trangThai: 'Trống',
        hinhAnh: roomMap['hinhAnh']?.toString() ?? '',
        danhGia: 5.0,
        soDanhGia: 0,
        moTaNgan: roomMap['dacDiem']?.toString() ?? '',
        tienIch: (roomMap['tienIch'] as List?)?.map((e) => e.toString()).toList() ?? [],
        noiThatSanCo: [],
      );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomDetailScreen(
          room: model,
          isTransferMode: true,
          currentRoomNumber: widget.currentRoomNumber,
          currentPrice: widget.currentPrice,
          onSelectTransfer: () {
            Navigator.pop(context);
            _navigateToTransfer(roomMap);
          },
        ),
      ),
    );
  }

  /// Điều hướng sang màn hình xác nhận thủ tục chuyển phòng
  void _navigateToTransfer(Map<String, dynamic> room) {
    if (_pendingTransfer != null) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Không Thể Gửi Thêm Đơn',
        noiDung: 'Bạn đang có yêu cầu chuyển sang phòng ${_pendingTransfer!["ma_phong_moi"]} (#${_pendingTransfer!["ma_yeu_cau"]}) đang chờ Ban Quản Lý duyệt. Không thể chọn thêm phòng mới!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    if (widget.hopDong != null && !widget.hopDong!.duDieuKienThoiGianChuyenPhong) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Chưa Đủ Điều Kiện',
        noiDung: 'Theo quy định, cư dân cần ở tối thiểu 30 ngày (1 tháng) tại phòng hiện tại trước khi chuyển phòng. Bạn mới ở được ${widget.hopDong!.soNgayDaO} ngày (thiếu ${widget.hopDong!.soNgayConThieuChuyenPhong} ngày)!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomTransferDetailScreen(
          targetRoom: room,
          currentRoomNumber: widget.currentRoomNumber,
          currentPrice: widget.currentPrice,
          maHopDong: widget.maHopDong,
          hopDong: widget.hopDong,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRooms;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: RefreshIndicator(
                color: _primary,
                onRefresh: _fetchEmptyRoomsFromSupabase,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 12),
                      _buildFilterTabs(),
                      const SizedBox(height: 10),
                      _buildTagFilters(),
                      const SizedBox(height: 14),
                      if (_pendingTransfer != null) ...[
                        _buildPendingTransferBanner(),
                        const SizedBox(height: 14),
                      ],
                      _buildCurrentRoomBanner(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Flexible(
                            child: Text(
                              'Phòng sẵn sàng vào ở',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isLoading ? 'Đang đồng bộ...' : 'Tìm thấy ${filtered.length} phòng',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_isLoading) ...[
                        const SizedBox(height: 40),
                        const Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(
                                color: _primary,
                                strokeWidth: 2.5,
                              ),
                              SizedBox(height: 14),
                              Text(
                                'Đang tải dữ liệu...',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                      ] else if (filtered.isEmpty) ...[
                        _buildEmptyState(),
                      ] else ...[
                        ...filtered.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildRoomCard(r),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      _buildHelpContactCard(),
                    ],
                  ),
                ),
              ),
            ),
            _buildBottomNavBar(),
          ],
        ),
      ),
    );
  }

  // ─── 1. TOP BAR ───
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _primary,
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
                  'Chọn Phòng Trống',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Đang ở: ${widget.currentRoomNumber} • Kiêu Giang 2',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tune_rounded, color: _primary, size: 18),
          ),
        ],
      ),
    );
  }

  // ─── 2. SEARCH BAR ───
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
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Tìm số phòng (vd: 205, 402), loại phòng, tòa...',
          hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF94A3B8),
            size: 20,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  // ─── 3. TABS (TẤT CẢ / CÙNG TÒA) ───
  Widget _buildFilterTabs() {
    return Row(
      children: [
        _buildTabBtn(0, 'Tất cả phòng trống (${_rooms.length})'),
        const SizedBox(width: 8),
        _buildTabBtn(
          1,
          'Cùng tòa Kiêu Giang 2 (${_rooms.where((r) => r["isSameBuilding"] == true).length})',
        ),
      ],
    );
  }

  Widget _buildTabBtn(int index, String title) {
    final isSel = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? _primaryDark : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSel ? _primaryDark : const Color(0xFFE2E8F0),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
              color: isSel ? Colors.white : const Color(0xFF475569),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ─── 4. TAG FILTERS ───
  Widget _buildTagFilters() {
    final tags = ['Tất cả giá', 'Dưới 3.5tr', '3.5tr - 4.5tr', 'Có gác lửng'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          const Text(
            'Lọc: ',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 4),
          ...List.generate(tags.length, (i) {
            final isSel = _selectedPriceFilter == i;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => setState(() => _selectedPriceFilter = i),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isSel ? const Color(0xFFE0F2FE) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSel
                          ? const Color(0xFF38BDF8)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    tags[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel ? _primary : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 4.5 PENDING TRANSFER BANNER ───
  Widget _buildPendingTransferBanner() {
    final don = _pendingTransfer;
    if (don == null) return const SizedBox.shrink();

    final maYC = don['ma_yeu_cau'] ?? '';
    final targetRoom = don['ma_phong_moi'] ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.08),
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
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_clock_rounded,
                  color: Color(0xFFD97706),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ĐANG CÓ YÊU CẦU CHỜ DUYỆT (#$maYC)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF92400E),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Bạn đang xin chuyển sang phòng $targetRoom. Hệ thống khóa quyền tạo đơn thứ 2 để BQL thẩm định.',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF78350F), height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Hủy yêu cầu?'),
                        content: Text('Bạn có chắc muốn hủy yêu cầu chuyển sang phòng $targetRoom (#$maYC)?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Không')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
                            child: const Text('Hủy đơn'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await Supabase.instance.client
                          .from('yeu_cau_chuyen_phong')
                          .update({'trang_thai_tien_do': 'Đã hủy'})
                          .eq('ma_yeu_cau', maYC);
                      if (mounted) {
                        setState(() => _pendingTransfer = null);
                        ThongBaoHelper.hienThongBao(
                          context,
                          tieuDe: 'Đã Hủy Yêu Cầu',
                          noiDung: 'Bây giờ bạn có thể chọn phòng mới!',
                          type: ThongBaoType.thanhCong,
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Hủy đơn cũ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Map<String, dynamic>? phongMoiData;
                    try {
                      final res = await Supabase.instance.client
                          .from('phong')
                          .select()
                          .eq('ma_phong', targetRoom)
                          .maybeSingle();
                      if (res != null) phongMoiData = res;
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
                            'maPhong': targetRoom,
                            'toaNha': phongMoiData?['toa_nha']?.toString() ?? 'Kiêu Giang',
                            'tang': tangMoi,
                            'dienTich': dienTichMoi,
                            'giaThue': giaThueMoi,
                            'tienDatCoc': tienCocMoi,
                          },
                          currentRoomNumber: widget.currentRoomNumber,
                          currentPrice: widget.currentPrice,
                          moveInDateFormatted: 'Đang hẹn',
                          reason: 'Chuyển phòng theo yêu cầu',
                          note: '',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09638E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Xem tiến độ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 5. CURRENT ROOM BANNER ───
  Widget _buildCurrentRoomBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.sync_alt_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Phòng hiện tại: ${widget.currentRoomNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '• 20m²',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Giá gốc: 3.200.000đ/tháng. Miễn 100% phí chuyển dọn nội bộ.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. ROOM CARD ───
  // ─── 6. ROOM CARD (ĐÃ FIX LỖI NGOẶC VÀ CHỐNG TRÀN) ───
  Widget _buildRoomCard(Map<String, dynamic> r) {
    final isSame = r['isSameBuilding'] == true;
    final diffAmount = r['diffAmount'] as num;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          // Room Image with badges
          InkWell(
            onTap: () => _openRoomDetail(r),
            child: Stack(
              children: [
                ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 145,
                  child: Image.network(
                    r['hinhAnh'],
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, error, stackTrace) => Container(
                      color: const Color(0xFFF1F5F9),
                      child: const Center(
                        child: Icon(
                          Icons.apartment_rounded,
                          size: 40,
                          color: _primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Top tag: Cùng tòa / Khác tòa
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSame
                            ? Icons.home_work_rounded
                            : Icons.location_on_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSame
                            ? 'Cùng tòa ${r["toaNha"]}'
                            : 'Cơ sở ${r["toaNha"]}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Bottom right tag: Tầng (Đã chống tràn)
              Positioned(
                bottom: 8,
                right: 10,
                left: 10,
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _primaryDark.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      r['tagTang'],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hàng tên phòng + Giá tiền (Đã bọc Expanded chống tràn)
                InkWell(
                  onTap: () => _openRoomDetail(r),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(
                              'Phòng ${r["maPhong"]}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _textDark,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                r['dacDiem'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        FormatUtils.currency((r['giaThue'] as num).toDouble()),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                        ),
                      ),
                      const Text(
                        'đ/th',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Highlight chip (Đồng giá / Tiết kiệm / Chênh lệch)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: diffAmount == 0
                        ? const Color(0xFFDCFCE7)
                        : (diffAmount < 0
                              ? const Color(0xFFE0F2FE)
                              : const Color(0xFFFEF3C7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        diffAmount == 0
                            ? Icons.check_circle_rounded
                            : (diffAmount < 0
                                  ? Icons.savings_rounded
                                  : Icons.trending_up_rounded),
                        color: diffAmount == 0
                            ? const Color(0xFF16A34A)
                            : (diffAmount < 0
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFFD97706)),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          r['highlight'],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: diffAmount == 0
                                ? const Color(0xFF16A34A)
                                : (diffAmount < 0
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFFB45309)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Amenities mini row
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: (r['tienIch'] as List<String>).map((item) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 13,
                          color: _primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Action buttons: "Xem chi tiết" & "Chọn chuyển phòng"
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        onPressed: () => _openRoomDetail(r),
                        icon: const Icon(
                          Icons.visibility_outlined,
                          size: 15,
                          color: _primary,
                        ),
                        label: const Text(
                          'Xem chi tiết',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: const Color(0xFFF0F7FB),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 5,
                      child: ElevatedButton.icon(
                        onPressed: () => _navigateToTransfer(r),
                        icon: const Icon(
                          Icons.sync_alt_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Chuyển sang ${r["maPhong"]}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryDark,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
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
    );
  }

  // ─── 6.5 EMPTY STATE ───
  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.meeting_room_outlined,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Không tìm thấy phòng trống phù hợp',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hiện tại không có phòng nào khớp với bộ lọc bạn đã chọn hoặc toàn bộ phòng đang được thuê.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _searchController.clear();
                _selectedTab = 0;
                _selectedPriceFilter = 0;
              });
              _fetchEmptyRoomsFromSupabase();
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Tải lại tất cả phòng'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7. HELP CONTACT CARD ───
  Widget _buildHelpContactCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: _primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cần xem phòng thực tế?',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Quản lý sẵn sàng mở cửa cho bạn xem phòng thực tế bất kỳ lúc nào.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 8. BOTTOM NAVIGATION BAR ───
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: 1, // Phòng active
        onTap: (index) {
          if (index != 1) Navigator.pop(context);
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _primary,
        unselectedItemColor: const Color(0xFF94A3B8),
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.key_outlined),
            activeIcon: Icon(Icons.key_rounded),
            label: 'Phòng',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            activeIcon: Icon(Icons.receipt_long_rounded),
            label: 'Hóa đơn',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            activeIcon: Icon(Icons.build_rounded),
            label: 'Yêu cầu',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

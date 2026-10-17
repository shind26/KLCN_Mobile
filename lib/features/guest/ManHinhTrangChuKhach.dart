import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuLuuDatPhong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhNguoiDung.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/auth/ManHinhDangNhap.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhChiTietPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhDatPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhLichSuDatPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({super.key});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> {
  List<RoomModel> _allRooms = [];
  List<RoomModel> _filteredRooms = [];
  bool _isLoading = true;
  String _selectedCategory = 'Tất cả';
  bool _sortAscending = true;
  int _currentBottomIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  RealtimeChannel? _homeBookingRealtimeChannel;
  bool _hasConfirmedNotice = false;
  int _currentPage = 1;
  static const int _itemsPerPage = 2;

  @override
  void initState() {
    super.initState();
    _fetchRoomsFromSupabase();
    _initBookingRealtimeTracking();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_homeBookingRealtimeChannel != null) {
      Supabase.instance.client.removeChannel(_homeBookingRealtimeChannel!);
    }
    super.dispose();
  }

  /// Lắng nghe và kiểm tra xem có lịch hẹn nào của khách vừa được duyệt không
  Future<void> _initBookingRealtimeTracking() async {
    final phone = await BookingStorageService.getLastPhone();
    if (phone == null || phone.isEmpty) return;

    // 1. Kiểm tra ban đầu xem có lịch hẹn đã xác nhận chưa được thông báo không
    _checkUnnotifiedBookings(phone);

    // 2. Thiết lập Supabase Realtime lắng nghe thay đổi
    try {
      _homeBookingRealtimeChannel = Supabase.instance.client
          .channel('public:dat_lich_xem_phong_home_$phone')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'dat_lich_xem_phong',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'so_dien_thoai',
              value: phone,
            ),
            callback: (payload) {
              debugPrint(
                'Realtime GuestHomeScreen phát hiện thay đổi lịch hẹn: ${payload.newRecord}',
              );
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty) {
                final status = newRecord['trang_thai'];
                final maLichHen = newRecord['ma_lich_hen']?.toString() ?? '';
                if (status == 'Đã xác nhận') {
                  if (mounted) {
                    setState(() => _hasConfirmedNotice = true);
                    _handleConfirmedBooking(newRecord);
                  }
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Lỗi đăng ký Realtime trên GuestHomeScreen: $e');
    }
  }

  Future<void> _checkUnnotifiedBookings(String phone) async {
    try {
      final response = await Supabase.instance.client
          .from('dat_lich_xem_phong')
          .select()
          .eq('so_dien_thoai', phone)
          .eq('trang_thai', 'Đã xác nhận')
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final booking = Map<String, dynamic>.from(response.first as Map);
        final maLichHen = booking['ma_lich_hen']?.toString() ?? '';
        final isNotified = await BookingStorageService.isAlreadyNotified(
          maLichHen,
        );
        if (!isNotified && mounted) {
          setState(() => _hasConfirmedNotice = true);
          // Đợi màn hình build xong mới hiện popup
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleConfirmedBooking(booking);
          });
        }
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra lịch hẹn chưa thông báo: $e');
    }
  }

  Future<void> _handleConfirmedBooking(Map<String, dynamic> booking) async {
    final maLichHen = booking['ma_lich_hen']?.toString() ?? '';
    await BookingStorageService.markAsNotified(maLichHen);
    if (!mounted) return;
    _showBookingConfirmedDialog(booking);
  }

  void _showBookingConfirmedDialog(Map<String, dynamic> booking) {
    final code = booking['ma_lich_hen']?.toString() ?? '';
    final roomCode = booking['ma_phong']?.toString() ?? '';
    final date = booking['ngay_hen']?.toString() ?? '';
    final time = booking['khung_gio']?.toString() ?? '';

    // Tìm tên phòng
    final room = _allRooms.firstWhere(
      (r) => r.maPhong == roomCode,
      orElse: () => RoomModel(
        maPhong: roomCode,
        maLoaiPhong: '',
        tenHienThi: 'Phòng $roomCode',
        toaNha: 'Tòa A',
        tang: 1,
        dienTich: 25,
        giaThue: 0,
        tienDatCoc: 0,
        trangThai: 'Trống',
        hinhAnh: '',
        danhGia: 5.0,
        soDanhGia: 0,
        moTaNgan: '',
        tienIch: [],
        noiThatSanCo: [],
      ),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon chúc mừng nổi bật
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Color(0xFF16A34A),
                  size: 36,
                ),
              ),
              const SizedBox(height: 14),

              const Text(
                'Lịch Hẹn Đã Được Xác Nhận!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Chủ nhà Kiêu Giang House đã duyệt lịch hẹn xem phòng của bạn. Bạn hãy đến đúng giờ để được đón tiếp chu đáo nhé!',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Thông tin tóm tắt
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    _buildPopupRow(
                      Icons.confirmation_number_outlined,
                      'Mã phiếu:',
                      code,
                    ),
                    const Divider(height: 14, thickness: 0.5),
                    _buildPopupRow(
                      Icons.meeting_room_outlined,
                      'Phòng hẹn:',
                      room.tenHienThi,
                    ),
                    const Divider(height: 14, thickness: 0.5),
                    _buildPopupRow(
                      Icons.calendar_today_outlined,
                      'Ngày xem:',
                      date,
                    ),
                    const Divider(height: 14, thickness: 0.5),
                    _buildPopupRow(Icons.schedule_rounded, 'Khung giờ:', time),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Nút xem chi tiết và đóng
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingHistoryScreen(
                          initialPhone: booking['so_dien_thoai'],
                        ),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.receipt_long_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Xem Chi Tiết Lịch Hẹn',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09638E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Đã hiểu',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF09638E)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  // Tải dữ liệu phòng trực tiếp từ bảng phong trên Supabase (chỉ lấy phòng có trạng thái 'Trống')
  Future<void> _fetchRoomsFromSupabase() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final client = Supabase.instance.client;
      final response = await client
          .from('phong')
          .select()
          .eq('trang_thai', 'Trống');
      debugPrint('Kết quả Supabase phong trống: $response');
      final List<RoomModel> loaded = response
          .map(
            (data) =>
                RoomModel.fromJson(Map<String, dynamic>.from(data as Map)),
          )
          .where((room) => room.trangThai.trim().toLowerCase() == 'trống')
          .toList();
      if (mounted) {
        setState(() {
          _allRooms = loaded;
          _isLoading = false;
        });
        _applyFilter();
      }
      return;
    } catch (e, stack) {
      debugPrint('Lỗi chi tiết khi tải phòng Supabase: $e\n$stack');
    }
    if (mounted) {
      setState(() {
        _allRooms = [];
        _isLoading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    List<RoomModel> list = List.from(_allRooms);

    // Lọc theo từ khóa tìm kiếm (tiện ích dịch vụ, sức chứa / số người, mô tả, loại phòng...)
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((r) {
        final nameMatch = r.tenHienThi.toLowerCase().contains(q);
        final amenityMatch = r.tienIch.any((t) => t.toLowerCase().contains(q));
        final descMatch = r.moTaNgan.toLowerCase().contains(q);
        final buildingMatch = r.toaNha.toLowerCase().contains(q);
        return nameMatch || amenityMatch || descMatch || buildingMatch;
      }).toList();
    }

    if (_selectedCategory == 'Gác lửng') {
      list = list
          .where(
            (r) =>
                r.tenHienThi.contains('Gác lửng') || r.maLoaiPhong == 'LP_GAC',
          )
          .toList();
    } else if (_selectedCategory == 'Ban công') {
      list = list
          .where(
            (r) =>
                r.tenHienThi.contains('Ban công') || r.maLoaiPhong == 'LP_BC',
          )
          .toList();
    } else if (_selectedCategory == 'Studio') {
      list = list
          .where(
            (r) => r.tenHienThi.contains('Studio') || r.maLoaiPhong == 'LP_STD',
          )
          .toList();
    } else if (_selectedCategory == 'Tiết kiệm') {
      list = list
          .where((r) => r.giaThue <= 3000000 || r.maLoaiPhong == 'LP_TIET')
          .toList();
    }

    list.sort(
      (a, b) => _sortAscending
          ? a.giaThue.compareTo(b.giaThue)
          : b.giaThue.compareTo(a.giaThue),
    );

    setState(() {
      _filteredRooms = list;
      _currentPage = 1;
    });
  }

  String _formatCurrency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return '${str.replaceAllMapped(reg, (Match m) => '${m[1]}.')}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      body: SafeArea(
        child: _currentBottomIndex == 1
            ? BookingScreen(
                availableRooms: _allRooms,
                isTabMode: true,
                onBookingSuccess: () {
                  setState(() {
                    _currentBottomIndex = 0;
                  });
                },
              )
            : Column(
                children: [
                  // 1. TOP APP BAR
                  _buildTopAppBar(),

                  // 2. NỘI DUNG CUỘN CHÍNH (TAB KHÁM PHÁ)
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF09638E),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchRoomsFromSupabase,
                            color: const Color(0xFF09638E),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),

                                  // HERO BANNER CARD
                                  _buildHeroBanner(),

                                  const SizedBox(height: 14),

                                  // THANH TÌM KIẾM PHÒNG TRỌ
                                  _buildSearchBar(),

                                  const SizedBox(height: 16),

                                  // BỘ LỌC CATEGORY CHIPS
                                  _buildCategoryChips(),

                                  const SizedBox(height: 14),

                                  // THANH THÔNG BÁO SỐ PHÒNG TRỐNG & SẮP XẾP GIÁ
                                  _buildInfoAndSortRow(),

                                  const SizedBox(height: 14),

                                  // DANH SÁCH THẺ PHÒNG TRỌ (DYNAMIC ROOM CARDS) HOẶC RỖNG
                                  if (_filteredRooms.isEmpty)
                                    _buildEmptySearchResults()
                                  else ...[
                                    ..._getPaginatedRooms().map(
                                      (room) => _buildRoomCard(room),
                                    ),
                                    if (_getTotalPages() > 1) ...[
                                      const SizedBox(height: 16),
                                      _buildPaginationSection(),
                                    ],
                                  ],

                                  const SizedBox(height: 24),

                                  // ĐẶC QUYỀN CƯ DÂN (TIỆN ÍCH MIỄN PHÍ)
                                  _buildAmenitiesSection(),

                                  const SizedBox(height: 20),

                                  // HOTLINE & TƯ VẤN CHỦ NHÀ
                                  _buildHotlineBanner(),

                                  const SizedBox(height: 28),
                                ],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
      ),

      // 3. BOTTOM NAVIGATION BAR
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  int _getTotalPages() {
    if (_filteredRooms.isEmpty) return 1;
    return (_filteredRooms.length / _itemsPerPage).ceil();
  }

  List<RoomModel> _getPaginatedRooms() {
    if (_filteredRooms.isEmpty) return [];
    final total = _getTotalPages();
    final validPage = _currentPage.clamp(1, total);
    final start = (validPage - 1) * _itemsPerPage;
    final end = (start + _itemsPerPage > _filteredRooms.length)
        ? _filteredRooms.length
        : start + _itemsPerPage;
    return _filteredRooms.sublist(start, end);
  }

  // BỘ ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION)
  // BỘ ĐIỀU HƯỚNG PHÂN TRANG (PAGINATION)
  Widget _buildPaginationSection() {
    final totalPages = _getTotalPages();
    final paginatedCount = _getPaginatedRooms().length;

    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 32,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF09638E).withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nút Previous (<)
                  _buildPageArrowButton(
                    icon: Icons.chevron_left_rounded,
                    enabled: _currentPage > 1,
                    onTap: () {
                      if (_currentPage > 1) {
                        setState(() => _currentPage--);
                      }
                    },
                  ),
                  const SizedBox(width: 4),

                  // Danh sách số trang (1, 2, 3...)
                  ...List.generate(totalPages, (index) {
                    final pageNum = index + 1;
                    final isActive = pageNum == _currentPage;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: InkWell(
                        onTap: () {
                          setState(() => _currentPage = pageNum);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? const Color(0xFF09638E)
                                : const Color(0xFFEBF5FA),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$pageNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isActive
                                  ? Colors.white
                                  : const Color(0xFF09638E),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(width: 4),

                  // Nút Next (>)
                  _buildPageArrowButton(
                    icon: Icons.chevron_right_rounded,
                    enabled: _currentPage < totalPages,
                    onTap: () {
                      if (_currentPage < totalPages) {
                        setState(() => _currentPage++);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Trang $_currentPage / $totalPages • Hiển thị $paginatedCount trong ${_filteredRooms.length} phòng trống',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageArrowButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? const Color(0xFFEBF5FA) : const Color(0xFFF1F5F9),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 20,
          color: enabled ? const Color(0xFF09638E) : const Color(0xFFCBD5E1),
        ),
      ),
    );
  }

  // TOP HEADER BAR
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(
        children: [
          // Logo & Title
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEBF5FA),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.home_work_rounded,
                color: Color(0xFF09638E),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KIÊU GIANG HOUSE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Color(0xFF09638E),
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Khám Phá',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Button Tra cứu lịch hẹn
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Lịch sử đặt lịch',
            onPressed: () {
              setState(() => _hasConfirmedNotice = false);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookingHistoryScreen()),
              );
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBF5FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF09638E).withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: Color(0xFF09638E),
                    size: 20,
                  ),
                ),
                if (_hasConfirmedNotice)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF16A34A),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // User Profile Pill or Login Button
          ValueListenableBuilder<UserModel?>(
            valueListenable: AuthService.currentUserNotifier,
            builder: (context, currentUser, _) {
              if (currentUser != null) {
                return GestureDetector(
                  onTap: () => _showAccountBottomSheet(currentUser),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: currentUser.isAdmin
                            ? [const Color(0xFFB45309), const Color(0xFFF59E0B)]
                            : [
                                const Color(0xFF07516E),
                                const Color(0xFF0A8FCA),
                              ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white,
                          child: Icon(
                            currentUser.isAdmin
                                ? Icons.admin_panel_settings_rounded
                                : Icons.person_rounded,
                            size: 15,
                            color: currentUser.isAdmin
                                ? const Color(0xFFB45309)
                                : const Color(0xFF09638E),
                          ),
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80),
                          child: Text(
                            currentUser.tenDangNhap.split('@').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_drop_down_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Chưa đăng nhập -> Nút Đăng nhập
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF07516E), Color(0xFF0A8FCA)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.login_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Đăng nhập',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // MODAL XEM THÔNG TIN TÀI KHOẢN & ĐĂNG XUẤT
  void _showAccountBottomSheet(UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thanh gạt
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header Profile
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF09638E), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.tenDangNhap,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Khách thuê',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              user.coSoVanHanh.isNotEmpty
                                  ? user.coSoVanHanh
                                  : 'Kiêu Giang House',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
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
            const SizedBox(height: 18),
            const Divider(color: Color(0xFFF1F5F9), thickness: 1.2),
            const SizedBox(height: 8),

            // Quick Actions
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.home_work_rounded,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
              ),
              title: const Text(
                'Phòng đã thuê của tôi (Phòng 302)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF09638E),
                ),
              ),
              subtitle: const Text(
                'Xem hóa đơn, sự cố, hợp đồng & thành viên',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF09638E),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TenantHomeScreen(
                      tenantName: user.tenDangNhap.contains('@')
                          ? user.tenDangNhap.split('@').first
                          : user.tenDangNhap,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),

            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
              ),
              title: const Text(
                'Lịch hẹn xem phòng của tôi',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Kiểm tra trạng thái xác nhận từ Chủ trọ',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BookingHistoryScreen(),
                  ),
                );
              },
            ),

            const SizedBox(height: 4),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_in_talk_rounded,
                  color: Color(0xFF16A34A),
                  size: 20,
                ),
              ),
              title: const Text(
                'Hotline Ban Quản Lý',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                '0987.654.321 (Hỗ trợ 24/7)',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hotline BQL: 0987.654.321 (Zalo & Phone)'),
                    backgroundColor: Color(0xFF09638E),
                  ),
                );
              },
            ),

            const SizedBox(height: 12),
            const Divider(color: Color(0xFFF1F5F9), thickness: 1.2),
            const SizedBox(height: 8),

            // Nút Đăng xuất
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showConfirmLogoutDialog();
                },
                icon: const Icon(
                  Icons.logout_rounded,
                  color: Color(0xFFE11D48),
                  size: 18,
                ),
                label: const Text(
                  'Đăng xuất tài khoản',
                  style: TextStyle(
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFECDD3)),
                  backgroundColor: const Color(0xFFFFF1F2),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // DIALOG XÁC NHẬN ĐĂNG XUẤT
  void _showConfirmLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Xác nhận đăng xuất',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản không?',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Hủy',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService.logout();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã đăng xuất thành công.'),
                    backgroundColor: Color(0xFF09638E),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Đăng xuất',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // HERO BANNER CARD
  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF15648F), Color(0xFF267BA7), Color(0xFF3892BF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15648F).withValues(alpha: 0.25),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.verified_user_outlined,
                  size: 13,
                  color: Colors.white,
                ),
                SizedBox(width: 5),
                Text(
                  'Ưu đãi chào tân cư dân',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Tìm phòng trọ ưng ý tại Nhà trọ\nKiêu Giang',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Không gian sống xanh mát, an ninh 24/7, đầy đủ tiện nghi với bảng giá thuê luôn minh bạch.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Promo Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.local_offer_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Giảm ngay 10% tháng đầu',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 1),
                      Text(
                        'Khi tạo tài khoản & đặt phòng',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
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

  // THANH TÌM KIẾM PHÒNG TRỌ (THEO SỨC CHỨA & TIỆN ÍCH DỊCH VỤ)
  Widget _buildSearchBar() {
    final quickTags = [
      'Máy lạnh',
      '2 - 3 người',
      'Ban công',
      'Tủ lạnh',
      'Bếp riêng',
      'Khóa vân tay',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
              _applyFilter();
            },
            decoration: InputDecoration(
              hintText:
                  'Tìm theo tiện ích, số người... (VD: Máy lạnh, 2 người)',
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Color(0xFF09638E),
                size: 22,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.cancel_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                        _applyFilter();
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // GỢI Ý TÌM NHANH THEO TIỆN ÍCH / SỨC CHỨA
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, right: 6),
                child: Text(
                  'Gợi ý:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
              ...quickTags.map((tag) {
                final isSelected =
                    _searchQuery.toLowerCase() == tag.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      if (isSelected) {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      } else {
                        _searchController.text = tag;
                        setState(() {
                          _searchQuery = tag;
                        });
                      }
                      _applyFilter();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE0F2FE)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF0284C7)
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isSelected
                              ? const Color(0xFF0369A1)
                              : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // THÔNG BÁO KHÔNG CÓ DỮ LIỆU HOẶC KHÔNG TÌM THẤY PHÒNG KHI SEARCH
  Widget _buildEmptySearchResults() {
    final bool isNoDataAtAll = _allRooms.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
            child: Icon(
              isNoDataAtAll
                  ? Icons.meeting_room_outlined
                  : Icons.search_off_rounded,
              size: 40,
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isNoDataAtAll
                ? 'Chưa có dữ liệu phòng'
                : 'Không tìm thấy phòng phù hợp',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isNoDataAtAll
                ? 'Hiện chưa có phòng trọ nào trong hệ thống.'
                : 'Rất tiếc, không có phòng nào phù hợp với từ khóa hoặc bộ lọc hiện tại của bạn.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              if (isNoDataAtAll) {
                _fetchRoomsFromSupabase();
              } else {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategory = 'Tất cả';
                });
                _applyFilter();
              }
            },
            icon: Icon(
              isNoDataAtAll
                  ? Icons.refresh_rounded
                  : Icons.cleaning_services_rounded,
              size: 16,
              color: Colors.white,
            ),
            label: Text(
              isNoDataAtAll ? 'Tải lại dữ liệu' : 'Xóa bộ lọc & Tìm lại',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF09638E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // CATEGORY CHIPS ROW
  Widget _buildCategoryChips() {
    final categories = [
      {
        'name': 'Tất cả',
        'label': 'Tất cả phòng (${_allRooms.length})',
        'icon': Icons.grid_view_rounded,
      },
      {
        'name': 'Gác lửng',
        'label': 'Có gác lửng',
        'icon': Icons.format_list_bulleted_rounded,
      },
      {'name': 'Ban công', 'label': 'Ban công', 'icon': Icons.balcony_rounded},
      {'name': 'Studio', 'label': 'VIP Studio', 'icon': Icons.star_rounded},
      {
        'name': 'Tiết kiệm',
        'label': 'Tiết kiệm',
        'icon': Icons.savings_rounded,
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedCategory == cat['name'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              avatar: Icon(
                cat['icon'] as IconData,
                size: 15,
                color: isSelected ? Colors.white : const Color(0xFF09638E),
              ),
              label: Text(
                cat['label'] as String,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF334155),
                ),
              ),
              selected: isSelected,
              selectedColor: const Color(0xFF09638E),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFF09638E)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = cat['name'] as String;
                  });
                  _applyFilter();
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // INFO & SORT ROW
  Widget _buildInfoAndSortRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF5FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF38BDF8),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Còn ${_filteredRooms.length} phòng trống ngay hôm nay',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
          ),

          // Dropdown sort button
          InkWell(
            onTap: () {
              setState(() {
                _sortAscending = !_sortAscending;
              });
              _applyFilter();
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.swap_vert_rounded,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _sortAscending ? 'Giá: Thấp → Cao' : 'Giá: Cao → Thấp',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
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

  Widget _buildRoomImagePlaceholder(RoomModel room) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -15,
            bottom: -20,
            child: Icon(
              Icons.apartment_rounded,
              size: 130,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.meeting_room_rounded,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                room.tenHienThi,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Kiêu Giang House • ${room.toaNha} • ${room.dienTich}m²',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // SINGLE ROOM CARD (Vẽ theo thiết kế cực đẹp từ mẫu)
  Widget _buildRoomCard(RoomModel room) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // IMAGE HEADER WITH OVERLAY BADGES
            Stack(
              children: [
                if (room.hinhAnh.trim().isNotEmpty)
                  Image.network(
                    room.hinhAnh,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildRoomImagePlaceholder(room),
                  )
                else
                  _buildRoomImagePlaceholder(room),

                // Top Left Overlay Badge (Tòa & Tầng)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.apartment_rounded,
                          size: 13,
                          color: Color(0xFF09638E),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${room.toaNha} • Tầng ${room.tang}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Top Right Overlay Badge (Đánh giá Star)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 14,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${room.danhGia} (${room.soDanhGia})',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Right Status Badge (Sẵn sàng dọn vào)
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          room.trangThai == 'Trống'
                              ? 'Sẵn sàng dọn vào'
                              : 'Trống từ 01/11',
                          style: const TextStyle(
                            fontSize: 11,
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

            // CARD CONTENT BODY
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Price Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          room.tenHienThi,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatCurrency(room.giaThue),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF09638E),
                            ),
                          ),
                          const Text(
                            '/tháng',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Room Specifications (Diện tích & Mô tả ngắn)
                  Row(
                    children: [
                      const Icon(
                        Icons.straighten_rounded,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${room.dienTich} m²',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '•',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      ),
                      const Icon(
                        Icons.people_outline_rounded,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          room.moTaNgan.isNotEmpty
                              ? room.moTaNgan
                              : 'Đầy đủ tiện nghi',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // List of Amenities (Tiện ích Tags)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: room.tienIch.map((amenity) {
                      IconData icon = Icons.check_circle_outline_rounded;
                      if (amenity.contains('lạnh'))
                        icon = Icons.ac_unit_rounded;
                      if (amenity.contains('lạnh riêng'))
                        icon = Icons.kitchen_rounded;
                      if (amenity.contains('nóng')) icon = Icons.shower_rounded;
                      if (amenity.contains('Bếp'))
                        icon = Icons.soup_kitchen_rounded;
                      if (amenity.contains('Ban công'))
                        icon = Icons.balcony_rounded;
                      if (amenity.contains('vân tay'))
                        icon = Icons.fingerprint_rounded;
                      if (amenity.contains('Camera'))
                        icon = Icons.videocam_outlined;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 12,
                              color: const Color(0xFF09638E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              amenity,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF334155),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),

                  // Action Buttons Row (Xem chi tiết & Đặt lịch xem)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RoomDetailScreen(room: room),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.remove_red_eye_outlined,
                            size: 15,
                            color: Color(0xFF09638E),
                          ),
                          label: const Text(
                            'Xem chi tiết',
                            style: TextStyle(
                              color: Color(0xFF09638E),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFFF0F7FB),
                            side: const BorderSide(color: Color(0xFFBAE6FD)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingScreen(room: room),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Đặt lịch xem',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF09638E),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }

  // ĐẶC QUYỀN CƯ DÂN SECTION
  Widget _buildAmenitiesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ĐẶC QUYỀN CƯ DÂN',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
            color: Color(0xFF0284C7),
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Tiện ích miễn phí tại Kiêu Giang',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 12),

        // 2x2 Grid of Feature Items
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.wifi_rounded,
                title: 'Wifi tốc độ cao',
                desc:
                    'Hạ tầng cáp quang riêng từng tầng, lướt web & làm việc ổn định 24/7.',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.shield_outlined,
                title: 'Khóa vân tay AI',
                desc:
                    'Kiểm soát ra vào tự động bằng vân tay, camera giám sát toàn khu an toàn tuyệt đối.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.ev_station_rounded,
                title: 'Trạm sạc xe điện',
                desc:
                    'Bãi đỗ xe trong nhà siêu rộng rãi, trang bị sẵn ổ cắm sạc xe máy điện an toàn PCCC.',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildFeatureCard(
                icon: Icons.build_outlined,
                title: 'Xử lý sự cố 30p',
                desc:
                    'Đội ngũ kỹ thuật túc trực tại tòa nhà, sửa chữa điện nước nhanh chóng miễn phí.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF09638E), size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // HOTLINE BANNER
  Widget _buildHotlineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEBF5FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF09638E),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'TRỰC TIẾP CHỦ NHÀ • KHÔNG MÔI GIỚI',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: Color(0xFF0284C7),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Hotline tư vấn & Xem phòng',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hỗ trợ dẫn xem trực tiếp 24/7 hoàn toàn miễn phí',
            style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 12),

          // Phone pill badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.phone_in_talk_rounded,
                  size: 16,
                  color: Color(0xFF09638E),
                ),
                const SizedBox(width: 6),
                const Text(
                  '0987.654.321',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Chủ trọ Kiêu Giang',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action Buttons: Gọi ngay & Chat Zalo
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.call_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Gọi ngay',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF09638E),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Chat Zalo',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F7CA7),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // BOTTOM NAVIGATION BAR
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentBottomIndex,
        onTap: (index) {
          setState(() {
            _currentBottomIndex = index;
          });
        },
        selectedItemColor: const Color(0xFF09638E),
        unselectedItemColor: const Color(0xFF64748B),
        selectedFontSize: 12,
        unselectedFontSize: 12,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: 'Khám phá',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month_rounded),
            label: 'Đặt lịch hẹn',
          ),
        ],
      ),
    );
  }
}

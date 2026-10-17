import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhChiTietPhong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuLuuDatPhong.dart';

class BookingHistoryScreen extends StatefulWidget {
  final String? initialPhone;

  const BookingHistoryScreen({super.key, this.initialPhone});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _bookings = [];
  Map<String, RoomModel> _roomsMap = {};
  bool _isLoading = false;
  bool _hasSearched = false;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _initDataAndRealtime();
  }

  Future<void> _initDataAndRealtime() async {
    String? phone = widget.initialPhone;
    if (phone == null || phone.isEmpty) {
      phone = await BookingStorageService.getLastPhone();
    }

    if (phone != null && phone.isNotEmpty) {
      _searchController.text = phone;
      _searchBookings(phone);
    } else {
      _fetchAllRecentBookings();
    }

    _subscribeToRealtime();
  }

  void _subscribeToRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('public:dat_lich_xem_phong_history')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'dat_lich_xem_phong',
            callback: (payload) {
              debugPrint('Realtime update phát hiện trong bảng dat_lich_xem_phong');
              if (!mounted) return;
              if (_hasSearched && _searchController.text.trim().isNotEmpty) {
                _searchBookings(_searchController.text.trim());
              } else {
                _fetchAllRecentBookings();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Lỗi Realtime channel: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (_realtimeChannel != null) {
      Supabase.instance.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  // Tải danh sách phòng để lấy tên & ảnh phòng theo mã
  Future<void> _fetchRoomsInfo() async {
    try {
      final resp = await Supabase.instance.client.from('phong').select();
      if (resp is List) {
        final Map<String, RoomModel> map = {};
        for (var item in resp) {
          final room = RoomModel.fromJson(Map<String, dynamic>.from(item as Map));
          map[room.maPhong] = room;
        }
        _roomsMap = map;
      }
    } catch (_) {}
  }

  // Bảo vệ thông tin cá nhân: Không tải danh sách lịch hẹn chung của người khác
  Future<void> _fetchAllRecentBookings() async {
    await _fetchRoomsInfo();
    if (mounted) {
      setState(() {
        _bookings = [];
        _isLoading = false;
        _hasSearched = false;
      });
    }
  }

  // Tra cứu theo số điện thoại hoặc mã phiếu
  Future<void> _searchBookings(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      _fetchAllRecentBookings();
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      await _fetchRoomsInfo();
      final client = Supabase.instance.client;
      
      // Tra cứu theo số điện thoại hoặc mã lịch hẹn
      final response = await client
          .from('dat_lich_xem_phong')
          .select()
          .or('so_dien_thoai.ilike.%$cleanQuery%,ma_lich_hen.ilike.%$cleanQuery%')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(response as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tra cứu lịch hẹn: $e');
      if (mounted) {
        setState(() {
          _bookings = [];
          _isLoading = false;
        });
      }
    }
  }

  // Hủy lịch hẹn
  Future<void> _cancelBooking(String maLichHen) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận hủy lịch hẹn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('Bạn có chắc chắn muốn hủy lịch hẹn xem phòng này không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Không', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Hủy lịch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('dat_lich_xem_phong')
          .update({'trang_thai': 'Đã hủy'})
          .eq('ma_lich_hen', maLichHen);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã hủy lịch hẹn thành công.'),
            backgroundColor: Color(0xFF09638E),
          ),
        );
        if (_hasSearched) {
          _searchBookings(_searchController.text);
        } else {
          _fetchAllRecentBookings();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi hủy lịch hẹn: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Đã xác nhận':
        return const Color(0xFF16A34A);
      case 'Đã xem':
      case 'Đã xem phòng':
        return const Color(0xFF2563EB);
      case 'Đã hủy':
        return const Color(0xFFDC2626);
      case 'Chờ xác nhận':
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status) {
      case 'Đã xác nhận':
        return const Color(0xFFDCFCE7);
      case 'Đã xem':
      case 'Đã xem phòng':
        return const Color(0xFFDBEAFE);
      case 'Đã hủy':
        return const Color(0xFFFEE2E2);
      case 'Chờ xác nhận':
      default:
        return const Color(0xFFFEF3C7);
    }
  }

  String _formatCurrency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.') + 'đ';
  }

  String _formatDate(String rawDate) {
    try {
      final dt = DateTime.parse(rawDate);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF0F172A),
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Padding(
            padding: EdgeInsets.all(10),
            child: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
        ),
        title: const Text(
          'Lịch Sử Đặt Hẹn Xem Phòng',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF09638E)),
            onPressed: () => _searchBookings(_searchController.text),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ====== SEARCH BAR ======
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: TextField(
                  controller: _searchController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (val) => _searchBookings(val),
                  decoration: InputDecoration(
                    hintText: 'Nhập số điện thoại hoặc mã phiếu (VD: 0912...)',
                    hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF09638E), size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              _searchController.clear();
                              _fetchAllRecentBookings();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ),

            // ====== LIST OR EMPTY STATE ======
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF09638E)),
                    )
                  : _bookings.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: () => _searchBookings(_searchController.text),
                          color: const Color(0xFF09638E),
                          child: ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.all(14),
                            itemCount: _bookings.length,
                            itemBuilder: (context, index) {
                              final booking = _bookings[index];
                              return _buildBookingCard(booking);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFEBF5FA),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 48,
                color: Color(0xFF09638E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _hasSearched ? 'Không tìm thấy lịch hẹn nào' : 'Chưa có lịch hẹn xem phòng nào',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _hasSearched
                  ? 'Vui lòng kiểm tra lại số điện thoại hoặc mã lịch hẹn của bạn.'
                  : 'Hãy chọn một phòng trọ ưng ý và đặt lịch hẹn để được dẫn xem trực tiếp!',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF64748B),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final maLichHen = booking['ma_lich_hen']?.toString() ?? 'N/A';
    final maPhong = booking['ma_phong']?.toString() ?? '';
    final tenKhach = booking['ten_khach_hang']?.toString() ?? '';
    final sdt = booking['so_dien_thoai']?.toString() ?? '';
    final ngayHen = booking['ngay_hen']?.toString() ?? '';
    final khungGio = booking['khung_gio']?.toString() ?? '';
    final soNguoi = booking['so_nguoi'] ?? 1;
    final ghiChu = booking['ghi_chu']?.toString() ?? '';
    final trangThai = booking['trang_thai']?.toString() ?? 'Chờ xác nhận';

    final room = _roomsMap[maPhong];
    final roomName = room?.tenHienThi ?? 'Phòng $maPhong';
    final roomPrice = room != null ? _formatCurrency(room.giaThue) : '';

    final statusColor = _getStatusColor(trangThai);
    final statusBgColor = _getStatusBgColor(trangThai);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card: Mã phiếu & Trạng thái
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined, size: 16, color: Color(0xFF09638E)),
                    const SizedBox(width: 6),
                    Text(
                      '#$maLichHen',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF09638E),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    trangThai,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Body: Thông tin phòng & thời gian hẹn
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: room?.hinhAnh != null && room!.hinhAnh.isNotEmpty
                      ? Image.network(
                          room.hinhAnh,
                          width: 74,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 74,
                            height: 68,
                            color: const Color(0xFFE2E8F0),
                            child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF94A3B8)),
                          ),
                        )
                      : Container(
                          width: 74,
                          height: 68,
                          color: const Color(0xFFE2E8F0),
                          child: const Icon(Icons.meeting_room_rounded, color: Color(0xFF94A3B8)),
                        ),
                ),
                const SizedBox(width: 12),

                // Info details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (roomPrice.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$roomPrice /tháng',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF09638E),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${_formatDate(ngayHen)} ($khungGio)',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline, size: 12, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '$tenKhach • $sdt ($soNguoi người)',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (ghiChu.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Ghi chú: $ghiChu',
                          style: const TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer actions (Hủy lịch / Xem phòng / Hotline)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (room != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => RoomDetailScreen(room: room)),
                      );
                    },
                    icon: const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF09638E)),
                    label: const Text('Xem phòng', style: TextStyle(fontSize: 12, color: Color(0xFF09638E), fontWeight: FontWeight.w600)),
                  ),
                if (trangThai == 'Chờ xác nhận') ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _cancelBooking(maLichHen),
                    icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                    label: const Text('Hủy lịch', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhChiTietPhong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuLuuDatPhong.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhThanhToanTheChan.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhGiuCho.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

class BookingHistoryScreen extends StatefulWidget {
  final String? initialPhone;
  final bool isTabMode;

  const BookingHistoryScreen({
    super.key,
    this.initialPhone,
    this.isTabMode = false,
  });

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
          .channel('public:giu_cho_history')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'giu_cho',
            callback: (payload) {
              debugPrint('Realtime update phát hiện trong bảng giu_cho');
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
      final Map<String, RoomModel> map = {};
      for (var item in resp) {
        final room = RoomModel.fromJson(Map<String, dynamic>.from(item as Map));
        map[room.maPhong] = room;
      }
      _roomsMap = map;
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
      
      // 1. Tìm các mã khách theo số điện thoại hoặc tên
      final khachRes = await client
          .from('khach_thue')
          .select('ma_khach, ho_ten_khach, so_dt')
          .or('so_dt.ilike.%$cleanQuery%,ho_ten_khach.ilike.%$cleanQuery%');

      final Map<String, Map<String, dynamic>> khachMap = {};
      final List<String> maKhachList = [];
      for (final k in (khachRes as List)) {
        final mk = k['ma_khach']?.toString() ?? '';
        if (mk.isNotEmpty) {
          khachMap[mk] = Map<String, dynamic>.from(k as Map);
          maKhachList.add(mk);
        }
      }

      // 2. Tra cứu trực tiếp từ bảng giu_cho
      List<dynamic> response;
      if (maKhachList.isNotEmpty) {
        response = await client
            .from('giu_cho')
            .select()
            .or('ma_giu_cho.ilike.%$cleanQuery%,ma_khach.in.(${maKhachList.join(",")})')
            .order('thoi_gian_giu_cho', ascending: false);
      } else {
        response = await client
            .from('giu_cho')
            .select()
            .or('ma_giu_cho.ilike.%$cleanQuery%,ma_phong.ilike.%$cleanQuery%')
            .order('thoi_gian_giu_cho', ascending: false);
      }

      // Lấy bù thông tin khách thuê cho các phiếu còn thiếu
      final missingKhach = response
          .map((e) => e['ma_khach']?.toString() ?? '')
          .where((mk) => mk.isNotEmpty && !khachMap.containsKey(mk))
          .toSet();
      if (missingKhach.isNotEmpty) {
        try {
          final extraKhach = await client
              .from('khach_thue')
              .select('ma_khach, ho_ten_khach, so_dt')
              .inFilter('ma_khach', missingKhach.toList());
          for (final k in (extraKhach as List)) {
            final mk = k['ma_khach']?.toString() ?? '';
            if (mk.isNotEmpty) khachMap[mk] = Map<String, dynamic>.from(k as Map);
          }
        } catch (_) {}
      }

      final List<Map<String, dynamic>> list = [];
      for (final item in response) {
        final gc = Map<String, dynamic>.from(item as Map);
        final mk = gc['ma_khach']?.toString() ?? '';
        final kh = khachMap[mk];
        final rawSt = gc['trang_thai']?.toString() ?? '';
        String displaySt = rawSt;
        if (rawSt == 'ChoThanhToan') displaySt = 'Chờ thanh toán';
        if (rawSt == 'DaHuy') displaySt = 'Đã hủy';
        if (rawSt == 'HetHan') displaySt = 'Hết hạn';

        list.add({
          'ma_lich_hen': gc['ma_giu_cho'],
          'ma_phong': gc['ma_phong'],
          'ten_khach_hang': kh?['ho_ten_khach'] ?? 'Khách thuê',
          'so_dien_thoai': kh?['so_dt'] ?? '',
          'ngay_hen': gc['ngay_du_kien_o'] ?? (gc['thoi_gian_giu_cho']?.toString().substring(0, 10) ?? ''),
          'khung_gio': gc['ghi_chu'] ?? 'Khung giờ thỏa thuận',
          'so_nguoi': gc['so_nguoi_o'] ?? 1,
          'ghi_chu': gc['ghi_chu'] ?? '',
          'trang_thai': displaySt,
          'da_coc_the_chan': rawSt == 'Đã thanh toán',
          'so_tien_the_chan': gc['so_tien_the_chan'],
          'created_at': gc['thoi_gian_giu_cho'],
        });
      }

      if (mounted) {
        setState(() {
          _bookings = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tra cứu giữ chỗ: $e');
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
          .from('giu_cho')
          .update({'trang_thai': 'DaHuy', 'expires_at': null})
          .eq('ma_giu_cho', maLichHen);

      // Trả lại trạng thái phòng về Trống
      final bIndex = _bookings.indexWhere((b) => b['ma_lich_hen'] == maLichHen);
      if (bIndex != -1) {
        final maPhong = _bookings[bIndex]['ma_phong']?.toString();
        if (maPhong != null && maPhong.isNotEmpty) {
          await Supabase.instance.client
              .from('phong')
              .update({'trang_thai': 'Trống'})
              .eq('ma_phong', maPhong);
        }
      }

      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Hủy giữ chỗ',
          noiDung: 'Đã hủy giữ chỗ thành công.',
          type: ThongBaoType.thanhCong,
        );
        if (_hasSearched) {
          _searchBookings(_searchController.text);
        } else {
          _fetchAllRecentBookings();
        }
      }
    } catch (e) {
      if (mounted) {
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi hủy lịch hẹn',
          noiDung: 'Lỗi khi hủy lịch hẹn: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Đã duyệt':
      case 'Đã xác nhận':
      case 'Đã thanh toán thế chân':
      case 'Đã cọc':
        return const Color(0xFF16A34A);
      case 'Đã xem':
      case 'Đã xem phòng':
        return const Color(0xFF2563EB);
      case 'Đã hủy':
        return const Color(0xFFDC2626);
      case 'Chờ duyệt':
        return const Color(0xFFD97706);
      case 'Chờ xác nhận':
      case 'Chờ thanh toán thế chân':
      default:
        return const Color(0xFFD97706);
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status) {
      case 'Đã duyệt':
      case 'Đã xác nhận':
      case 'Đã thanh toán thế chân':
      case 'Đã cọc':
        return const Color(0xFFDCFCE7);
      case 'Đã xem':
      case 'Đã xem phòng':
        return const Color(0xFFDBEAFE);
      case 'Đã hủy':
        return const Color(0xFFFEE2E2);
      case 'Chờ duyệt':
        return const Color(0xFFFEF3C7);
      case 'Chờ xác nhận':
      case 'Chờ thanh toán thế chân':
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
        automaticallyImplyLeading: !widget.isTabMode,
        leading: widget.isTabMode
            ? null
            : GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
              ),
        title: Text(
          widget.isTabMode ? 'Lịch Hẹn Của Tôi' : 'Lịch Sử Giữ Chỗ & Đặt Phòng',
          style: const TextStyle(
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
                    hintText: 'Nhập số điện thoại hoặc mã phiếu (VD: 0912... hoặc GC...)',
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
                  ? const LoadingMeoMeo(
                      message: 'Đang tải lịch hẹn...',
                      subMessage: 'Mèo con đang tìm danh sách cuộc hẹn của bạn~ 🐾',
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
    final depositAmount = (booking['so_tien_the_chan'] as num?) ??
        (room != null ? (room.giaThue * 0.1).round() : 300000);
    final depositStr = _formatCurrency(depositAmount);

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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.confirmation_number_outlined, size: 15, color: Color(0xFF09638E)),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '#$maLichHen',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF09638E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (booking['da_coc_the_chan'] == true) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF16A34A).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.shield_rounded, size: 11, color: Color(0xFF16A34A)),
                              SizedBox(width: 3),
                              Text(
                                'Đã cọc thế chân',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF16A34A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

          // Banner trạng thái chi tiết
          if (trangThai == 'Chờ duyệt')
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đã thanh toán thế chân $depositStr (10% giá thuê) thành công. Đang ở trạng thái Chờ duyệt, Chủ trọ sẽ liên hệ và phê duyệt lịch hẹn.',
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          if (trangThai == 'Đã duyệt' || trangThai == 'Đã xác nhận')
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.35)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF16A34A)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chủ trọ đã duyệt lịch hẹn! Quy trình đặt lịch đã hoàn tất thành công.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF15803D), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          // Footer actions (Hủy lịch / Xem phòng / Thanh toán thế chân / Chủ trọ duyệt)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
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
                  if (trangThai == 'Chờ thanh toán thế chân') ...[
                    ElevatedButton.icon(
                      onPressed: () => _openPaymentScreen(booking),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.payment_rounded, size: 14, color: Colors.white),
                      label: const Text(
                        'Thanh toán thế chân',
                        style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  if (trangThai == 'Chờ xác nhận' || trangThai == 'Chờ thanh toán thế chân' || trangThai == 'Chờ duyệt') ...[
                    TextButton.icon(
                      onPressed: () => _cancelBooking(maLichHen),
                      icon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626)),
                      label: const Text('Hủy lịch', style: TextStyle(fontSize: 12, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentScreen(Map<String, dynamic> booking) async {
    final maPhong = booking['ma_phong']?.toString() ?? '';
    final room = _roomsMap[maPhong];
    if (room == null) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Không tìm thấy phòng',
        noiDung: 'Không tìm thấy thông tin phòng đã chọn!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    final phone = (booking['so_dien_thoai'] ?? '').toString().trim();
    final hasAcc = await DepositService.hasExistingAccount(phone);
    if (hasAcc) {
      if (!mounted) return;
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Không Thể Giữ Chỗ',
        noiDung:
            'Số điện thoại $phone đã có tài khoản trên hệ thống. Theo quy định, số điện thoại đã đăng ký tài khoản không thể đặt giữ chỗ. Vui lòng sử dụng số điện thoại khác!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    try {
      final client = Supabase.instance.client;
      final holdRow = await client
          .from('giu_cho')
          .select()
          .eq('ma_phong', maPhong)
          .order('thoi_gian_giu_cho', ascending: false)
          .limit(1)
          .maybeSingle();

      GiuChoModel giuCho;
      if (holdRow != null &&
          holdRow['trang_thai'] != 'HetHan' &&
          holdRow['trang_thai'] != 'DaHuy') {
        giuCho = GiuChoModel.fromJson(Map<String, dynamic>.from(holdRow as Map));
      } else {
        final rawDate = booking['ngay_hen']?.toString() ?? '';
        final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now().add(const Duration(days: 2));
        final guestCount = int.tryParse(booking['so_nguoi']?.toString() ?? '1') ?? 1;

        giuCho = await DepositService.tienHanhDatCoc(
          room: room,
          hoTen: booking['ten_khach_hang'] ?? 'Khách thuê',
          soDt: booking['so_dien_thoai'] ?? '',
          ngayDuKienO: parsedDate,
          soNguoiO: guestCount,
          ghiChu: booking['ghi_chu']?.toString(),
        );
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ManHinhThanhToanTheChan(
            giuCho: giuCho,
            room: room,
            customerName: booking['ten_khach_hang'] ?? '',
            customerPhone: booking['so_dien_thoai'] ?? '',
            appointmentCode: booking['ma_lich_hen']?.toString(),
            appointmentDate: booking['ngay_hen']?.toString(),
            timeSlot: booking['khung_gio']?.toString(),
            guestCount: int.tryParse(booking['so_nguoi']?.toString() ?? '1') ?? 1,
            note: booking['ghi_chu']?.toString(),
          ),
        ),
      );

      if (mounted) {
        _searchBookings(_searchController.text);
      }
    } catch (e) {
      if (mounted) {
        final err = e.toString().replaceAll('Exception: ', '').trim();
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Thông báo',
          noiDung: err,
          type: ThongBaoType.thatBai,
        );
      }
    }
  }
}

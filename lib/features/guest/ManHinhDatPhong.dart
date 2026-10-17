import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhLichSuDatPhong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuLuuDatPhong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhThanhToanTheChan.dart';

class BookingScreen extends StatefulWidget {
  final RoomModel? room;
  final List<RoomModel>? availableRooms;
  final bool isTabMode;
  final bool isDepositMode;
  final VoidCallback? onBookingSuccess;

  const BookingScreen({
    super.key,
    this.room,
    this.availableRooms,
    this.isTabMode = false,
    this.isDepositMode = false,
    this.onBookingSuccess,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late int _selectedDayIndex;
  late List<DateTime> _displayDays;
  String? _selectedTimeSlot;
  int _guestCount = 2;
  RoomModel? _selectedRoom;
  List<RoomModel> _rooms = [];
  bool _isSubmitting = false;
  late bool _isDepositTab;

  final _nameController   = TextEditingController();
  final _phoneController  = TextEditingController();
  final _noteController   = TextEditingController();

  // ===== SLOT DEFINITIONS: [label, startHour, startMinute] =====
  static const List<Map<String, dynamic>> _allSlots = [
    // Sáng
    {'label': '08:30 - 09:30', 'startH': 8,  'startM': 30,  'session': 'morning'},
    {'label': '09:30 - 10:30', 'startH': 9,  'startM': 30,  'session': 'morning'},
    {'label': '10:30 - 11:30', 'startH': 10, 'startM': 30,  'session': 'morning'},
    // Chiều
    {'label': '14:00 - 15:00', 'startH': 14, 'startM': 0,   'session': 'afternoon'},
    {'label': '15:30 - 16:30', 'startH': 15, 'startM': 30,  'session': 'afternoon'},
    // Tối
    {'label': '17:30 - 18:30', 'startH': 17, 'startM': 30,  'session': 'evening'},
    {'label': '19:00 - 20:00', 'startH': 19, 'startM': 0,   'session': 'evening'},
  ];

  String? _slotStatus(DateTime day, Map<String, dynamic> slot) {
    if (day.weekday == DateTime.sunday) return 'sunday';

    final now = DateTime.now();
    final slotDateTime = DateTime(
      day.year, day.month, day.day,
      slot['startH'] as int, slot['startM'] as int,
    );

    final isToday = day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
    if (!isToday) return null;

    final diffMinutes = slotDateTime.difference(now).inMinutes;
    if (diffMinutes < 0) return 'passed';
    if (diffMinutes < 120) return 'soon';
    return null;
  }

  bool _isSlotAvailable(DateTime day, Map<String, dynamic> slot) =>
      _slotStatus(day, slot) == null;

  String? _firstAvailableSlot(DateTime day) {
    for (final slot in _allSlots) {
      if (_isSlotAvailable(day, slot)) return slot['label'] as String;
    }
    return null;
  }

  bool _dayHasAnySlot(DateTime day) => _firstAvailableSlot(day) != null;

  void _onDaySelected(int index) {
    final day = _displayDays[index];
    setState(() {
      _selectedDayIndex = index;
      if (!_isDepositTab) {
        if (_selectedTimeSlot != null) {
          final currentSlot = _allSlots.firstWhere(
            (s) => s['label'] == _selectedTimeSlot,
            orElse: () => _allSlots.first,
          );
          if (!_isSlotAvailable(day, currentSlot)) {
            _selectedTimeSlot = _firstAvailableSlot(day);
          }
        } else {
          _selectedTimeSlot = _firstAvailableSlot(day);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _isDepositTab = widget.isDepositMode;
    final now = DateTime.now();
    // Ràng buộc tối đa 5 ngày và không chọn quá khứ (Hôm nay đến +5 ngày)
    _displayDays = List.generate(6, (i) => now.add(Duration(days: i)));

    int firstValidIndex = 0;
    for (int i = 0; i < _displayDays.length; i++) {
      if (_isDepositTab || _dayHasAnySlot(_displayDays[i])) {
        firstValidIndex = i;
        break;
      }
    }
    _selectedDayIndex = firstValidIndex;
    _selectedTimeSlot = _isDepositTab ? null : _firstAvailableSlot(_displayDays[firstValidIndex]);

    _rooms = widget.availableRooms ?? (widget.room != null ? [widget.room!] : []);
    _selectedRoom = widget.room ?? (_rooms.isNotEmpty ? _rooms.first : null);
    if (_selectedRoom == null && _rooms.isEmpty) {
      _fetchRooms();
    }
  }

  Future<void> _fetchRooms() async {
    try {
      final resp = await Supabase.instance.client
          .from('phong')
          .select()
          .eq('trang_thai', 'Trống');
      if (resp is List && resp.isNotEmpty) {
        final list = resp
            .map((e) => RoomModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((r) => r.trangThai.trim().toLowerCase() == 'trống')
            .toList();
        if (mounted) {
          setState(() {
            _rooms = list;
            _selectedRoom ??= list.isNotEmpty ? list.first : null;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatCurrency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.') + 'đ';
  }

  String _getVietnameseDayName(DateTime date) {
    const names = ['Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7', 'CN'];
    return names[(date.weekday - 1).clamp(0, 6)];
  }

  String _daySubLabel(DateTime date) {
    if (date.weekday == DateTime.sunday) return 'Nghỉ';
    if (date.weekday == DateTime.saturday) return 'Cuối tuần';
    return 'Trong tuần';
  }

  Future<void> _confirmBooking() async {
    if (_selectedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn phòng trọ bạn muốn đặt lịch xem!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập họ và tên của bạn!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final phoneClean = phone.replaceAll(RegExp(r'\s+'), '');
    final phoneRegExp = RegExp(r'^(0[3|5|7|8|9])+([0-9]{8})$');
    if (phoneClean.isEmpty || !phoneRegExp.hasMatch(phoneClean)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số điện thoại Việt Nam hợp lệ (10 chữ số)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_selectedTimeSlot == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn khung giờ hẹn xem!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final selDay = _displayDays[_selectedDayIndex];
    final selSlotDef = _allSlots.firstWhere(
      (s) => s['label'] == _selectedTimeSlot,
      orElse: () => <String, dynamic>{},
    );
    if (selSlotDef.isNotEmpty && !_isSlotAvailable(selDay, selSlotDef)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Khung giờ đã không còn khả dụng, vui lòng chọn giờ khác!'),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final tsStr = DateTime.now().millisecondsSinceEpoch.toString();
    final appointmentCode = 'KG${tsStr.substring(tsStr.length - 7)}';
    final dateStr = '${_getVietnameseDayName(selDay)}, ${selDay.day.toString().padLeft(2, '0')}/${selDay.month.toString().padLeft(2, '0')}/${selDay.year}';

    try {
      // 1. Tiến hành đặt cọc giữ chỗ và lấy phiếu cọc thế chân 100k
      final giuCho = await DepositService.tienHanhDatCoc(
        room: _selectedRoom!,
        hoTen: name,
        soDt: phoneClean,
        ngayDuKienO: selDay,
        soNguoiO: _guestCount,
        ghiChu: 'Hẹn xem $_selectedTimeSlot ngày $dateStr. ${_noteController.text.trim()}'.trim(),
      );

      // 2. Lưu lịch hẹn vào bảng dat_lich_xem_phong với trạng thái Chờ thanh toán thế chân
      await Supabase.instance.client.from('dat_lich_xem_phong').insert({
        'ma_lich_hen': appointmentCode,
        'ma_phong': _selectedRoom!.maPhong,
        'ten_khach_hang': name,
        'so_dien_thoai': phoneClean,
        'ngay_hen': selDay.toIso8601String().substring(0, 10),
        'khung_gio': _selectedTimeSlot,
        'so_nguoi': _guestCount,
        'ghi_chu': _noteController.text.trim(),
        'trang_thai': 'Chờ thanh toán thế chân',
      });
      await BookingStorageService.saveLastBooking(
        phone: phoneClean,
        appointmentCode: appointmentCode,
      );
      debugPrint('Lưu lịch hẹn thành công vào bảng dat_lich_xem_phong');

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // 3. MỞ MÀN HÌNH CÓ MÃ QR ĐỂ THANH TOÁN TIỀN THẾ TRƯỚC KHI XÁC NHẬN ĐẶT LỊCH
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ManHinhThanhToanTheChan(
            giuCho: giuCho,
            room: _selectedRoom!,
            customerName: name,
            customerPhone: phoneClean,
            appointmentCode: appointmentCode,
            appointmentDate: dateStr,
            timeSlot: _selectedTimeSlot,
            guestCount: _guestCount,
            note: _noteController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Lỗi đặt lịch hẹn hoặc tạo cọc thế chân: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Không Thể Đặt Lịch',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(errorMsg, style: const TextStyle(fontSize: 13.5, height: 1.4)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF09638E)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đã hiểu', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }
  }

  /// TIẾN HÀNH ĐẶT CỌC GIỮ CHỖ (100K - Tối đa 5 ngày)
  Future<void> _tienHanhDatCoc() async {
    if (_selectedRoom == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn phòng trọ bạn muốn đặt cọc giữ chỗ!'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập họ và tên của bạn!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final phoneClean = phone.replaceAll(RegExp(r'\s+'), '');
    final phoneRegExp = RegExp(r'^(0[3|5|7|8|9])+([0-9]{8})$');
    if (phoneClean.isEmpty || !phoneRegExp.hasMatch(phoneClean)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số điện thoại Việt Nam hợp lệ (10 chữ số)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final selDay = _displayDays[_selectedDayIndex];
    final dateCheck = DepositService.validateExpectedDate(selDay);
    if (!dateCheck.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dateCheck.error ?? 'Ngày dự kiến vào ở không hợp lệ!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final giuCho = await DepositService.tienHanhDatCoc(
        room: _selectedRoom!,
        hoTen: name,
        soDt: phoneClean,
        ngayDuKienO: selDay,
        soNguoiO: _guestCount,
        ghiChu: _noteController.text.trim(),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Chuyển sang màn hình thanh toán thế chân Napas 24/7 VietQR
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ManHinhThanhToanTheChan(
            giuCho: giuCho,
            room: _selectedRoom!,
            customerName: name,
            customerPhone: phoneClean,
            appointmentCode: giuCho.maGiuCho,
            appointmentDate:
                '${_getVietnameseDayName(selDay)}, ${selDay.day.toString().padLeft(2, '0')}/${selDay.month.toString().padLeft(2, '0')}/${selDay.year}',
            timeSlot: 'Giữ chỗ 5 ngày',
            guestCount: _guestCount,
            note: _noteController.text.trim(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final errorMsg = e.toString().replaceAll('Exception: ', '');
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 26),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Không Thể Đặt Cọc',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(errorMsg, style: const TextStyle(fontSize: 14, height: 1.45)),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF09638E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _fetchRooms(); // Tải lại danh sách phòng trống
              },
              child: const Text('Đã hiểu / Tải lại phòng', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF09638E)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _selectedRoom;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      body: Stack(
        children: [
          // ====== SCROLLABLE CONTENT ======
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // APP BAR
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0.5,
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
                  widget.isTabMode ? 'Đặt Lịch Hẹn Xem Phòng' : 'Đặt Lịch Xem Phòng',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                centerTitle: true,
                actions: [
                  IconButton(
                    tooltip: 'Lịch sử đặt hẹn',
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFF09638E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.history_rounded, size: 18, color: Colors.white),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BookingHistoryScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ====== HEADER BADGES ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEBF5FA),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.home_work_rounded,
                                      size: 13, color: Color(0xFF09638E)),
                                  SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Kiêu Giang • Chính chủ',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF09638E),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: _isDepositTab
                                  ? const Color(0xFFFEF3C7)
                                  : const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Thế chân 100k • Khóa phòng',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB45309),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ====== BỘ CHUYỂN ĐỔI: HẸN XEM PHÒNG VS ĐẶT CỌC GIỮ CHỖ ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _isDepositTab = false;
                                  if (_selectedTimeSlot == null && _displayDays.isNotEmpty) {
                                    _selectedTimeSlot = _firstAvailableSlot(_displayDays[_selectedDayIndex]);
                                  }
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: !_isDepositTab ? Colors.white : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: !_isDepositTab
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.calendar_today_rounded,
                                        size: 14,
                                        color: !_isDepositTab ? const Color(0xFF09638E) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          'Hẹn Xem Phòng',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: !_isDepositTab ? const Color(0xFF09638E) : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _isDepositTab = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: _isDepositTab ? const Color(0xFF09638E) : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: _isDepositTab
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF09638E).withValues(alpha: 0.25),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.security_rounded,
                                        size: 14,
                                        color: _isDepositTab ? Colors.white : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          'Cọc Giữ Chỗ (100k)',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                            color: _isDepositTab ? Colors.white : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ====== BANNER THÔNG TIN ĐẶT CỌC 100K & QUY ĐỊNH 5 NGÀY ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.shield_outlined, color: Color(0xFF1D4ED8), size: 17),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Chính sách đặt lịch & cọc thế chân giữ chỗ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1E3A8A),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '• Tiền thế chân giữ chỗ: 100.000 VNĐ.\n'
                              '• Thời hạn coi phòng: Giữ chỗ tối đa trong vòng 5 ngày tới (không chọn ngày quá khứ). Nếu sau 5 ngày không đến coi hoặc nhận phòng thì sẽ mất cọc.\n'
                              '• Đảm bảo: Ngay sau khi cọc, phòng được chuyển sang trạng thái "Đã cọc" để khóa khách khác.\n'
                              '• Sau khi ấn "Tiến hành đặt cọc", hệ thống hiển thị mã VietQR chuẩn Napas 24/7 có hiệu lực trong 15 phút để chuyển khoản cho chủ nhà.',
                              style: TextStyle(fontSize: 11.5, color: Color(0xFF1E40AF), height: 1.45),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ====== BỘ CHỌN PHÒNG (NẾU CÓ NHIỀU PHÒNG HOẶC Ở TAB ĐẶT LỊCH) ======
                    if (_rooms.length > 1)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Chọn phòng trọ bạn muốn xem:',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFCBD5E1)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedRoom?.maPhong,
                                  isExpanded: true,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF09638E)),
                                  items: _rooms.map((r) {
                                    return DropdownMenuItem<String>(
                                      value: r.maPhong,
                                      child: Text(
                                        '${r.tenHienThi} • ${_formatCurrency(r.giaThue)}/tháng (Tầng ${r.tang})',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newMaPhong) {
                                    if (newMaPhong != null) {
                                      setState(() {
                                        _selectedRoom = _rooms.firstWhere((r) => r.maPhong == newMaPhong);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ====== COMPACT ROOM INFO CARD ======
                    if (room != null)
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Thumbnail
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                room.hinhAnh,
                                width: 90,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 90,
                                  height: 80,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.meeting_room_rounded,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Room Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          room.tenHienThi,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF09638E),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Tầng ${room.tang}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  const Text(
                                    'Đường Số 8, Linh Xuân, TP. Thủ Đức',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatCurrency(room.giaThue)} /tháng',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF09638E),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: const [
                                      Icon(Icons.circle, size: 7, color: Color(0xFF22C55E)),
                                      SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Còn trống • Sẵn sàng dọn vào ngay',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11, color: Color(0xFF16A34A)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(16),
                        child: const Center(
                          child: CircularProgressIndicator(color: Color(0xFF09638E)),
                        ),
                      ),

                    const SizedBox(height: 10),

                    // ====== CHỌN NGÀY HẸN XEM ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isDepositTab ? Icons.event_available_rounded : Icons.calendar_month_rounded,
                                size: 18,
                                color: const Color(0xFF09638E),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Ngày coi phòng / dự kiến ở',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tháng ${_displayDays[0].month}, ${_displayDays[0].year}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            '100k giữ phòng tối đa 5 ngày tới. Nếu sau 5 ngày không coi phòng sẽ mất cọc.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFD97706),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),

                           // Day selector horizontal scroll
                          SizedBox(
                            height: 72,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: _displayDays.length,
                              itemBuilder: (context, index) {
                                final day = _displayDays[index];
                                final isSelected   = _selectedDayIndex == index;
                                final isSunday     = day.weekday == DateTime.sunday;
                                final hasSlots     = _isDepositTab ? true : _dayHasAnySlot(day);
                                final isDisabled   = !hasSlots;
                                final isToday      = index == 0;
                                final dayLabel     = isToday ? 'H.nay'
                                    : (index == 1 ? 'N.mai' : _getVietnameseDayName(day));
                                final subLabel     = _daySubLabel(day);

                                return GestureDetector(
                                  onTap: isDisabled ? null : () => _onDaySelected(index),
                                  child: Opacity(
                                    opacity: isDisabled ? 0.45 : 1.0,
                                    child: Container(
                                      width: 58,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF09638E)
                                            : isDisabled
                                                ? const Color(0xFFF1F5F9)
                                                : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF09638E)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          if (isSunday)
                                            Icon(
                                              Icons.block_rounded,
                                              size: 18,
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFFCBD5E1),
                                            )
                                          else
                                            Text(
                                              '${day.day}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: isSelected
                                                    ? Colors.white
                                                    : const Color(0xFF0F172A),
                                              ),
                                            ),
                                          Text(
                                            dayLabel,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isSelected
                                                  ? Colors.white.withValues(alpha: 0.9)
                                                  : isSunday
                                                      ? const Color(0xFFCBD5E1)
                                                      : const Color(0xFF64748B),
                                            ),
                                          ),
                                          Text(
                                            isSunday ? 'Nghỉ CN' : subLabel,
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: isSelected
                                                  ? Colors.white.withValues(alpha: 0.7)
                                                  : isSunday
                                                      ? const Color(0xFFEF4444)
                                                      : const Color(0xFF94A3B8),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (!_isDepositTab) ...[
                      const SizedBox(height: 10),

                      // ====== KHUNG GIỜ PHÙ HỢP ======
                      Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded,
                                  size: 18, color: Color(0xFF09638E)),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Khung giờ phù hợp',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEBF5FA),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.circle, size: 7, color: Color(0xFF22C55E)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Có người trực',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF16A34A),
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Morning slots
                          _buildTimeGroup(
                              icon: Icons.wb_sunny_outlined,
                              label: 'Buổi sáng (08:30 - 11:30)',
                              slots: _allSlots.where((s) => s['session'] == 'morning').toList()),
                          const SizedBox(height: 14),

                          // Afternoon slots
                          _buildTimeGroup(
                              icon: Icons.wb_cloudy_outlined,
                              label: 'Buổi chiều (14:00 - 16:30)',
                              slots: _allSlots.where((s) => s['session'] == 'afternoon').toList()),
                          const SizedBox(height: 14),

                          // Evening slots
                          _buildTimeGroup(
                              icon: Icons.nights_stay_outlined,
                              label: 'Buổi tối (Tan ca & Sau giờ học)',
                              slots: _allSlots.where((s) => s['session'] == 'evening').toList(),
                              trailingBadge: 'Rất thuận tiện'),

                          // Banner ngọ nghiệp vụ
                          if (_displayDays[_selectedDayIndex].weekday == DateTime.sunday)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFFCA5A5)),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Chủ nhật ban quản lý nghỉ tẫn hưởng gia đình. Vui lòng chọn ngày khác trong tuần để đặt lịch xem phòng nhé!',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF991B1B),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: const [
                                  Icon(Icons.calendar_today_rounded,
                                      size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Ban Quản Lý luôn có mặt trực tiếp tại khu để hỗ trợ đón và dẫn bạn xem phòng.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF475569),
                                        height: 1.4,
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

                    const SizedBox(height: 10),

                    // ====== THÔNG TIN NGƯỜI XEM / ĐẶT CỌC ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isDepositTab ? Icons.assignment_ind_rounded : Icons.person_outline_rounded,
                                size: 18,
                                color: const Color(0xFF09638E),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _isDepositTab ? 'Thông tin người đặt cọc giữ chỗ' : 'Thông tin người xem',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Name field
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: 'Trần Minh Khang',
                              hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                              labelText: 'Họ và tên của bạn',
                              labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              prefixIcon: const Icon(Icons.person_outline,
                                  size: 18, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF09638E), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Phone field
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              hintText: '0912 345 678',
                              hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
                              labelText: 'Số điện thoại liên hệ (Zalo)',
                              labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              prefixIcon: const Icon(Icons.phone_outlined,
                                  size: 18, color: Color(0xFF94A3B8)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF09638E), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Guest count
                          const Text(
                            'Số người dự kiến ở',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [1, 2, 3].map((count) {
                              final isSelected = _guestCount == count;
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: count < 3 ? 8 : 0),
                                  child: GestureDetector(
                                    onTap: () => setState(() => _guestCount = count),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF09638E)
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFF09638E)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            count == 1
                                                ? Icons.person_rounded
                                                : Icons.people_rounded,
                                            size: 15,
                                            color: isSelected
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$count người',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? Colors.white
                                                  : const Color(0xFF475569),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),

                          // Note field
                          TextField(
                            controller: _noteController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText:
                                  'Ví dụ: Tôi muốn xem thêm chỗ để xe máy và bạn cùng phòng đó...',
                              hintStyle: const TextStyle(
                                  fontSize: 12, color: Color(0xFFCBD5E1)),
                              labelText: 'Ghi chú thêm cho chủ nhà (Tùy chọn)',
                              labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF09638E), width: 1.5),
                              ),
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ====== CAM KẾT HỖ TRỢ TỪ KIÊU GIANG ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.verified_user_outlined,
                                  size: 18, color: Color(0xFF09638E)),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Cam kết hỗ trợ từ Kiêu Giang',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildCommitRow(
                              Icons.check_circle_outline_rounded,
                              'Miễn phí 100% dịch vụ: Trực tiếp ban quản lý nhà trọ tiếp đón, không qua môi giới, không thu bất kỳ khoản phí dẫn xem phòng nào.'),
                          const SizedBox(height: 8),
                          _buildCommitRow(
                              Icons.access_time_rounded,
                              'Ưu tiên giờ chót 24h: Nếu xem ưng ý, bạn được ưu tiên giữ phòng trong vòng 24 giờ trước khi mở lượt cho khách khác.'),
                          const SizedBox(height: 12),

                          // Hotline row
                          Row(
                            children: [
                              const Icon(Icons.phone_in_talk_rounded,
                                  size: 16, color: Color(0xFF09638E)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: 'Hotline quản lý Kiêu Giang: ',
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFF475569)),
                                    children: const [
                                      TextSpan(
                                        text: '0987.654.321',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF09638E),
                                        ),
                                      ),
                                    ],
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

                    // Bottom padding for the sticky button
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),

          // ====== STICKY BOTTOM CTA BUTTON ======
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: const Color(0xFFE2E8F0))),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting
                          ? null
                          : (_isDepositTab ? _tienHanhDatCoc : _confirmBooking),
                      icon: Icon(
                        _isDepositTab ? Icons.security_rounded : Icons.calendar_today_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSubmitting
                              ? 'Đang xử lý...'
                              : 'Tiến Hành Đặt Cọc (100.000đ)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF09638E),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Khi ấn "Tiến hành đặt cọc", phòng sẽ được chuyển sang Đã cọc và mã VietQR chuẩn Napas 24/7 có hiệu lực 15 phút để bạn chuyển tiền thế chân 100k tới chủ nhà.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                      height: 1.4,
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

  Widget _buildTimeGroup({
    required IconData icon,
    required String label,
    required List<Map<String, dynamic>> slots,
    String? trailingBadge,
  }) {
    final day = _displayDays[_selectedDayIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: const Color(0xFF64748B)),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569)),
            ),
            if (trailingBadge != null) ...
              [
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trailingBadge,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: slots.map((slot) {
            final status = _slotStatus(day, slot);
            final isAvailable = status == null;
            final isSelected = _selectedTimeSlot == slot['label'] && isAvailable;
            return _buildTimeChip(
              slot['label'] as String,
              isSelected: isSelected,
              isAvailable: isAvailable,
              status: status,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTimeChip(
    String label, {
    required bool isSelected,
    required bool isAvailable,
    String? status,
  }) {
    // Màu theo trạng thái
    Color bgColor, borderColor, textColor;
    if (!isAvailable) {
      bgColor     = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFE2E8F0);
      textColor   = const Color(0xFFCBD5E1);
    } else if (isSelected) {
      bgColor     = const Color(0xFF09638E);
      borderColor = const Color(0xFF09638E);
      textColor   = Colors.white;
    } else {
      bgColor     = Colors.white;
      borderColor = const Color(0xFFE2E8F0);
      textColor   = const Color(0xFF475569);
    }

    // Nhãn badge trạng thái khi không khả dụng
    String? badgeText;
    Color?  badgeColor;
    if (status == 'passed') {
      badgeText  = 'Đã qua';
      badgeColor = const Color(0xFF94A3B8);
    } else if (status == 'soon') {
      badgeText  = 'Quá gần';
      badgeColor = const Color(0xFFD97706);
    } else if (status == 'sunday') {
      badgeText  = 'Nghỉ';
      badgeColor = const Color(0xFFEF4444);
    }

    return GestureDetector(
      onTap: isAvailable
          ? () => setState(() => _selectedTimeSlot = label)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            if (badgeText != null) ...
              [
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor!.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommitRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: const Color(0xFF09638E)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

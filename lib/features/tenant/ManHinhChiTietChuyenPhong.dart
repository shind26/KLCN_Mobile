import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChuyenPhongThanhCong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Màn hình 3: Chi Tiết Phòng & Thẻ Đối Chiếu Chuyển Phòng Thực Tế
/// So sánh trực quan phòng hiện tại vs phòng muốn chuyển, tiện nghi, định mức phí và kế hoạch dọn.
class RoomTransferDetailScreen extends StatefulWidget {
  final Map<String, dynamic> targetRoom;
  final String currentRoomNumber;
  final num currentPrice;
  final String? maHopDong;
  final HopDongModel? hopDong;

  const RoomTransferDetailScreen({
    super.key,
    required this.targetRoom,
    this.currentRoomNumber = 'P.302',
    this.currentPrice = 3200000,
    this.maHopDong,
    this.hopDong,
  });

  @override
  State<RoomTransferDetailScreen> createState() =>
      _RoomTransferDetailScreenState();
}

class _RoomTransferDetailScreenState extends State<RoomTransferDetailScreen> {
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  late DateTime _moveInDate;
  int _selectedReasonIndex = 0;
  bool _isSubmitting = false;
  Map<String, dynamic>? _pendingRequest;
  final List<String> _reasons = [
    'Xuống tầng thấp hơn',
    'Phòng rộng hơn',
    'Cần phòng yên tĩnh',
  ];

  late TextEditingController _noteController;

  /// Tính ngày cuối tháng hợp lý: từ ngày 28 đến ngày cuối tháng hoặc mùng 1 đầu tháng sau
  DateTime _tinhNgayCuoiThangHopLy() {
    final now = DateTime.now();
    // Nếu hôm nay đã từ ngày 28 trở đi, có thể dọn ngay hôm nay
    if (now.day >= 28) {
      return now;
    }
    // Ngược lại, ngày kết toán hết tháng gần nhất là ngày 28 của tháng hiện tại
    return DateTime(now.year, now.month, 28);
  }

  /// Ràng buộc thực tế: Chỉ cho phép chuyển phòng vào dịp hết tháng (ngày 28..cuối tháng, hoặc mùng 1 đầu tháng)
  bool _laNgayCuoiThangHopLe(DateTime date) {
    final lastDay = DateTime(date.year, date.month + 1, 0).day;
    return (date.day >= 28 && date.day <= lastDay) || date.day == 1;
  }

  @override
  void initState() {
    super.initState();
    _moveInDate = _tinhNgayCuoiThangHopLy();
    _noteController = TextEditingController(
      text:
          'Xuống tầng ${widget.targetRoom["tang"]} cho tiện đi lại, mong BQL hỗ trợ mượn xe đẩy vào ngày dọn ạ.',
    );
    _checkPendingRequest();
  }

  Future<void> _checkPendingRequest() async {
    try {
      final activeHD = widget.maHopDong ?? widget.hopDong?.maHopDong ?? 'HD001';
      final activeRoom = widget.currentRoomNumber;
      final res = await Supabase.instance.client
          .from('yeu_cau_chuyen_phong')
          .select()
          .or('ma_hop_dong_ht.eq.$activeHD,ma_phong_cu.eq.$activeRoom')
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

      if (res.isNotEmpty && mounted) {
        setState(() => _pendingRequest = Map<String, dynamic>.from(res.first));
      }
    } catch (e) {
      debugPrint('Lỗi kiểm tra pending request: $e');
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  String get _moveInDateFormatted {
    final d = _moveInDate;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _pickMoveInDate() async {
    final now = DateTime.now();
    final firstAllowed = now.day >= 28 ? now : DateTime(now.year, now.month, 28);
    final initialDate = _moveInDate.isBefore(firstAllowed) ? firstAllowed : _moveInDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      helpText: 'CHỌN NGÀY DỰ KIẾN DỌN PHÒNG (HẾT THÁNG)',
      selectableDayPredicate: (DateTime val) {
        return _laNgayCuoiThangHopLe(val);
      },
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _primary,
            onPrimary: Colors.white,
            onSurface: _textDark,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _moveInDate = picked);
    }
  }

  Future<void> _submitTransferRequest() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final target = widget.targetRoom;
    final targetCode = (target['maPhong'] as String? ?? 'P205')
        .replaceAll('.', '')
        .trim();

    // Mã yêu cầu duy nhất
    final ticketId =
        'YCCP_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    try {
      // 1. Tìm thông tin hợp đồng hiện tại và tiền cọc từ Supabase
      String activeHopDong = widget.maHopDong ?? widget.hopDong?.maHopDong ?? 'HD001';
      String activeRoom = widget.currentRoomNumber;
      num deposit = widget.currentPrice;

      if (widget.hopDong != null) {
        activeHopDong = widget.hopDong!.maHopDong;
        activeRoom = widget.hopDong!.maPhong;
        deposit = widget.hopDong!.tienDatCoc > 0 ? widget.hopDong!.tienDatCoc : widget.hopDong!.giaThueThaoThuan;
      } else {
        try {
          final contractRes = await Supabase.instance.client
              .from('hop_dong')
              .select()
              .eq('ma_phong', widget.currentRoomNumber)
              .inFilter('trang_thai', ['Còn hạn', 'Còn hiệu lực', 'Đang thuê'])
              .order('ngay_bd', ascending: false)
              .limit(1);

          if (contractRes.isNotEmpty) {
            activeHopDong = contractRes[0]['ma_hop_dong'] ?? activeHopDong;
            activeRoom = contractRes[0]['ma_phong'] ?? activeRoom;
            deposit = contractRes[0]['tien_dat_coc'] ?? deposit;
          }
        } catch (err) {
          debugPrint('Không query được hợp đồng: $err');
        }
      }

      // RÀNG BUỘC 1: Kiểm tra thời gian lưu trú tối thiểu 30 ngày (1 tháng)
      if (widget.hopDong != null && !widget.hopDong!.duDieuKienThoiGianChuyenPhong) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Chưa Đủ Điều Kiện Chuyển Phòng',
          noiDung: 'Theo quy định của Ban Quản Lý, cư dân cần ở tối thiểu 30 ngày (1 tháng) tại phòng hiện tại trước khi chuyển phòng. Bạn mới ở được ${widget.hopDong!.soNgayDaO} ngày (còn thiếu ${widget.hopDong!.soNgayConThieuChuyenPhong} ngày nữa)!',
          type: ThongBaoType.canhBao,
        );
        return;
      }

      // RÀNG BUỘC 2: Không chuyển sang chính phòng mình đang ở
      if (targetCode.toLowerCase() == activeRoom.toLowerCase()) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Phòng Không Hợp Lệ',
          noiDung: 'Phòng mới phải khác phòng bạn đang thuê hiện tại ($activeRoom)!',
          type: ThongBaoType.canhBao,
        );
        return;
      }

      // RÀNG BUỘC THỰC TẾ 1: Hết tháng mới được chuyển phòng (ngày 28 đến ngày cuối tháng hoặc mùng 1)
      if (!_laNgayCuoiThangHopLe(_moveInDate)) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Chỉ Cho Phép Chuyển Phòng Hết Tháng',
          noiDung: 'Theo quy định thực tế của Ban Quản Lý, việc chuyển phòng chỉ được thực hiện vào dịp HẾT THÁNG (từ ngày 28 đến ngày cuối tháng hoặc mùng 1 đầu tháng sau) để đồng bộ thanh toán tiền phòng và chốt điện nước trọn kỳ!',
          type: ThongBaoType.canhBao,
        );
        return;
      }

      // RÀNG BUỘC THỰC TẾ 2: Kiểm tra công nợ - Phải thanh toán hết các hóa đơn phòng cũ
      try {
        final unpaidInvoices = await Supabase.instance.client
            .from('hoa_don')
            .select('ma_hoa_don, tong_tien, trang_thai')
            .eq('ma_hop_dong', activeHopDong)
            .eq('trang_thai', 'Chưa thanh toán')
            .gt('tong_tien', 0);

        if (unpaidInvoices.isNotEmpty) {
          if (!mounted) return;
          setState(() => _isSubmitting = false);
          final count = unpaidInvoices.length;
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Bắt Buộc Thanh Toán Hóa Đơn Kỳ Trước',
            noiDung: 'Phòng hiện tại ($activeRoom) đang còn $count hóa đơn kỳ trước chưa thanh toán. Theo quy định của Ban Quản Lý, bạn bắt buộc phải hoàn tất thanh toán hóa đơn kỳ trước thì mới được phép gửi đơn chuyển phòng!',
            type: ThongBaoType.canhBao,
          );
          return;
        }
      } catch (errInvoice) {
        debugPrint('Kiểm tra hóa đơn chưa thanh toán: $errInvoice');
      }

      // RÀNG BUỘC 3: Kiểm tra yêu cầu chuyển phòng đang chờ duyệt (CHỐNG GỬI LẦN 2)
      try {
        final existingYccp = await Supabase.instance.client
            .from('yeu_cau_chuyen_phong')
            .select()
            .or('ma_hop_dong_ht.eq.$activeHopDong,ma_phong_cu.eq.$activeRoom')
            .inFilter('trang_thai_tien_do', [
              'Chờ duyệt',
              'Đang xử lý',
              'Chờ khách xác nhận',
              'Đã kiểm tra',
              'Khách đã xác nhận',
              'Chờ chủ duyệt',
            ]);

        if (existingYccp.isNotEmpty) {
          final oldMaPhongMoi = existingYccp[0]['ma_phong_moi'];
          final oldMaYC = existingYccp[0]['ma_yeu_cau'];
          if (!mounted) return;
          setState(() {
            _isSubmitting = false;
            _pendingRequest = Map<String, dynamic>.from(existingYccp[0]);
          });
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Không Thể Gửi Thêm Đơn',
            noiDung: 'Hợp đồng $activeHopDong đang có một yêu cầu chuyển sang phòng $oldMaPhongMoi (Mã #$oldMaYC) đang chờ Ban Quản Lý phê duyệt! Theo quy định, mỗi cư dân chỉ được tạo 1 yêu cầu tại một thời điểm, không thể gửi lần 2.',
            type: ThongBaoType.canhBao,
          );
          return;
        }
      } catch (errCheck) {
        debugPrint('Bỏ qua lỗi kiểm tra trùng: $errCheck');
      }

      // Tính toán tiền cọc phòng mới và chênh lệch cọc
      final targetDeposit = (target['tienDatCoc'] as num?) ?? (target['giaThue'] as num?) ?? deposit;
      final diffDeposit = targetDeposit - deposit;

      final String reason = _reasons[_selectedReasonIndex];
      final String note = _noteController.text.trim();
      final String fullReason = note.isNotEmpty ? '$reason - $note' : reason;

      // 2. Ghi bản ghi vào bảng yeu_cau_chuyen_phong
      await Supabase.instance.client.from('yeu_cau_chuyen_phong').insert({
        'ma_yeu_cau': ticketId,
        'ma_hop_dong_ht': activeHopDong,
        'ma_phong_cu': activeRoom,
        'ma_phong_moi': targetCode,
        'tien_coc_bao_luu': deposit,
        'thoi_gian_hen': _moveInDate.toIso8601String(),
        'nguoi_don_bql': 'BQL Kiều Giang',
        'tien_phat_sinh': diffDeposit > 0 ? diffDeposit : 0,
        'tien_dien_nuoc_cu': 0,
        'tien_hu_hai_cu': 0,
        'ghi_chu_hu_hai': null,
        'ly_do_chuyen': fullReason,
        'trang_thai_tien_do': 'Chờ duyệt',
        'ngay_tao': DateTime.now().toIso8601String(),
      });
      debugPrint('[CHUYEN_PHONG] Đã ghi nhận duy nhất yeu_cau_chuyen_phong: $ticketId');

      // Khởi tạo bản ghi biên bản kiểm tra tương ứng (nếu bảng tồn tại)
      try {
        await Supabase.instance.client.from('bien_ban_kiem_tra_phong').insert({
          'ma_bien_ban': 'BBKT_$ticketId',
          'ma_yeu_cau': ticketId,
          'ma_phong': activeRoom,
          'ma_hop_dong': activeHopDong,
          'loai_bien_ban': 'Kiểm tra chuyển phòng',
          'nguoi_kiem_tra': 'Kỹ thuật BQL Kiều Giang',
          'chi_so_dien_cuoi': 0,
          'chi_so_nuoc_cuoi': 0,
          'tien_dien_nuoc': 0,
          'tien_khau_tru': 0,
          'tien_coc_hoan_tra': 0,
          'trang_thai': 'Chờ BQL kiểm tra',
          'ghi_chu': _noteController.text.trim(),
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // 4. Chuyển sang màn hình xác nhận thành công
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RoomTransferSuccessScreen(
            ticketCode: ticketId,
            targetRoom: widget.targetRoom,
            currentRoomNumber: activeRoom,
            currentPrice: widget.currentPrice,
            moveInDateFormatted: _moveInDateFormatted,
            reason: fullReason,
            note: note,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Không Thể Gửi Yêu Cầu',
        noiDung: 'Lỗi khi gửi yêu cầu chuyển phòng: $e',
        type: ThongBaoType.thatBai,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetRoom;
    final targetName = target['maPhong'] ?? 'P.205';
    final targetPrice = (target['giaThue'] as num?) ?? 3200000;
    final diff = targetPrice - widget.currentPrice;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopAppBar(targetName),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeroImage(target, diff),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPriceHeader(targetPrice, target),
                          const SizedBox(height: 14),
                          _buildComparisonCard(target, diff),
                          const SizedBox(height: 16),
                          _buildAmenitiesCard(),
                          const SizedBox(height: 16),
                          _buildMovePlanCard(),
                          const SizedBox(height: 20),
                          _buildSubmitButton(targetName),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 1. TOP APP BAR ───
  Widget _buildTopAppBar(String targetName) {
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
                Text(
                  'Chi Tiết Phòng $targetName',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Tầng ${widget.targetRoom["tang"]} • ${widget.targetRoom["toaNha"]} (Cùng tòa)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.favorite_border_rounded, color: _primary),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.share_outlined, color: _primary),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ─── 2. HERO IMAGE ───
  Widget _buildHeroImage(Map<String, dynamic> target, num diff) {
    final absDiff = diff.abs().toDouble();
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: 220,
          child: Image.network(
            target['hinhAnh'] ??
                'https://images.unsplash.com/photo-1522708323590-d24dbb6b0267?w=800',
            fit: BoxFit.cover,
            errorBuilder: (ctx, error, stackTrace) => Container(
              color: const Color(0xFFE2E8F0),
              child: const Center(
                child: Icon(Icons.image, size: 40, color: _primary),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Color(0xFF22C55E), size: 7),
                SizedBox(width: 5),
                Text(
                  'Trống sẵn sàng vào ở',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: diff < 0
                  ? const Color(0xFF15803D).withValues(alpha: 0.9)
                  : (diff > 0
                      ? const Color(0xFFD97706).withValues(alpha: 0.9)
                      : _primaryDark.withValues(alpha: 0.85)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              diff == 0
                  ? 'Bằng giá phòng cũ'
                  : (diff < 0
                      ? 'Tiết kiệm ${FormatUtils.currency(absDiff)}đ/th'
                      : 'Tăng +${FormatUtils.currency(absDiff)}đ/th'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 12,
                ),
                SizedBox(width: 4),
                Text(
                  '1/8',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
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

  // ─── 3. PRICE HEADER ───
  Widget _buildPriceHeader(num price, Map<String, dynamic> target) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Giá thuê niêm yết',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 3,
                children: [
                  Text(
                    FormatUtils.currency(price.toDouble()),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _textDark,
                    ),
                  ),
                  const Text(
                    'đ / tháng',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.explore_outlined, color: _primary, size: 13),
              SizedBox(width: 3),
              Text(
                'Hướng Đông',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.crop_square_rounded, color: _primary, size: 13),
              SizedBox(width: 3),
              Text(
                '22 m²',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _extractFloor(String roomCode) {
    final digits = roomCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 3) {
      return int.tryParse(digits.substring(0, digits.length - 2)) ?? 2;
    } else if (digits.isNotEmpty) {
      return int.tryParse(digits[0]) ?? 1;
    }
    return 2;
  }

  // ─── 4. COMPARISON CARD (ĐỐI CHIẾU CHUYỂN PHÒNG) ───
  Widget _buildComparisonCard(Map<String, dynamic> target, num diff) {
    final int oldFloor = _extractFloor(widget.currentRoomNumber);
    final int newFloor = (target['tang'] as num?)?.toInt() ??
        _extractFloor(target['maPhong']?.toString() ?? '');

    const int oldArea = 20;
    final int newArea = (target['dienTich'] as num?)?.toInt() ?? 25;
    final int areaDiff = newArea - oldArea;

    final num targetPrice =
        (target['giaThue'] as num?) ?? (widget.currentPrice + diff);
    final num priceDiff = targetPrice - widget.currentPrice;
    final num absDiff = priceDiff.abs();
    final bool isCheaper = priceDiff < 0;
    final bool isMoreExpensive = priceDiff > 0;
    final isSameBuilding = target['isSameBuilding'] != false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCheaper ? const Color(0xFF86EFAC) : const Color(0xFFBAE6FD),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.06),
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
                  color: isCheaper
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.sync_alt_rounded,
                  color: isCheaper ? const Color(0xFF16A34A) : _primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đối Chiếu Chuyển Phòng',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'So sánh phòng cũ và phòng mới',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSameBuilding
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isSameBuilding ? 'Cùng tòa nhà' : 'Khác tòa nhà',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSameBuilding
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2 Cột so sánh
          Row(
            children: [
              // Cột hiện tại
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HIỆN TẠI',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.currentRoomNumber,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• Tầng $oldFloor',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      Text(
                        '• $oldArea m²',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      Text(
                        '• ${FormatUtils.currency(widget.currentPrice.toDouble())}đ',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Cột phòng mới
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCheaper
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCheaper
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFF93C5FD),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PHÒNG MỚI',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isCheaper
                              ? const Color(0xFF16A34A)
                              : _primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        target['maPhong'] ?? '',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isCheaper
                              ? const Color(0xFF16A34A)
                              : _primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        newFloor < oldFloor
                            ? '• Tầng $newFloor (Đỡ leo tầng)'
                            : (newFloor > oldFloor
                                ? '• Tầng $newFloor (Thoáng hơn)'
                                : '• Tầng $newFloor (Cùng tầng)'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: newFloor <= oldFloor
                              ? const Color(0xFF16A34A)
                              : _primary,
                        ),
                      ),
                      Text(
                        areaDiff > 0
                            ? '• $newArea m² (+${areaDiff}m² rộng)'
                            : (areaDiff < 0
                                ? '• $newArea m² (${areaDiff}m²)'
                                : '• $newArea m²'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: areaDiff > 0
                              ? const Color(0xFF16A34A)
                              : _textDark,
                        ),
                      ),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 3,
                        children: [
                          Text(
                            '• ${FormatUtils.currency(targetPrice.toDouble())}đ',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isCheaper)
                            const Text(
                              '(Rẻ hơn)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF16A34A),
                              ),
                            )
                          else if (isMoreExpensive)
                            const Text(
                              '(Tăng)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD97706),
                              ),
                            )
                          else
                            const Text(
                              '(Bằng giá)',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // KHỐI GIẢI THÍCH CHI TIẾT TÀI CHÍNH & TIỀN CỌC
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCheaper
                  ? const Color(0xFFF0FDF4)
                  : (isMoreExpensive
                      ? const Color(0xFFFFFBEB)
                      : const Color(0xFFF0F9FF)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCheaper
                    ? const Color(0xFFBBF7D0)
                    : (isMoreExpensive
                        ? const Color(0xFFFDE68A)
                        : const Color(0xFFBAE6FD)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header khối
                Row(
                  children: [
                    Icon(
                      isCheaper
                          ? Icons.savings_rounded
                          : (isMoreExpensive
                              ? Icons.info_outline_rounded
                              : Icons.check_circle_outline_rounded),
                      size: 16,
                      color: isCheaper
                          ? const Color(0xFF15803D)
                          : (isMoreExpensive
                              ? const Color(0xFFB45309)
                              : const Color(0xFF0284C7)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isCheaper
                            ? 'ƯU ĐÃI: TIẾT KIỆM ${FormatUtils.currency(absDiff.toDouble())}Đ / THÁNG'
                            : (isMoreExpensive
                                ? 'CHÊNH LỆCH: TĂNG +${FormatUtils.currency(absDiff.toDouble())}Đ / THÁNG'
                                : 'ĐỒNG GIÁ THUÊ: ${FormatUtils.currency(targetPrice.toDouble())}Đ / THÁNG'),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isCheaper
                              ? const Color(0xFF15803D)
                              : (isMoreExpensive
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF0284C7)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: Color(0x22000000)),
                const SizedBox(height: 8),

                // Mục 1: Tiền thuê hàng tháng
                _buildExplainBullet(
                  title: 'Giá thuê phòng mới:',
                  content: isCheaper
                      ? 'Rẻ hơn ${FormatUtils.currency(absDiff.toDouble())}đ/tháng (giảm từ ${FormatUtils.currency(widget.currentPrice.toDouble())}đ ➔ còn ${FormatUtils.currency(targetPrice.toDouble())}đ/tháng).'
                      : (isMoreExpensive
                          ? 'Tăng thêm ${FormatUtils.currency(absDiff.toDouble())}đ/tháng (từ ${FormatUtils.currency(widget.currentPrice.toDouble())}đ ➔ lên ${FormatUtils.currency(targetPrice.toDouble())}đ/tháng).'
                          : 'Giữ nguyên ${FormatUtils.currency(targetPrice.toDouble())}đ/tháng (không thay đổi chi phí).'),
                ),
                const SizedBox(height: 6),

                // Mục 2: Tiền cọc phòng cũ
                _buildExplainBullet(
                  title: 'Bảo lưu tiền cọc:',
                  content:
                      'Toàn bộ tiền cọc phòng cũ (${FormatUtils.currency(widget.currentPrice.toDouble())}đ) được bảo lưu chuyển sang phòng mới. Miễn phí thủ tục chuyển đổi phòng.',
                ),
                const SizedBox(height: 6),

                // Mục 3: Xử lý cọc thừa hoặc bù thêm
                _buildExplainBullet(
                  title: isCheaper
                      ? 'Tiền cọc dôi dư (${FormatUtils.currency(absDiff.toDouble())}đ):'
                      : (isMoreExpensive
                          ? 'Khoản cọc bù thêm (${FormatUtils.currency(absDiff.toDouble())}đ):'
                          : 'Xử lý tiền cọc:'),
                  content: isCheaper
                      ? 'Do phòng mới có tiền thuê thấp hơn, số tiền cọc thừa ${FormatUtils.currency(absDiff.toDouble())}đ sẽ được TRỪ TRỰC TIẾP vào tiền phòng của Hóa đơn kỳ tới. Bạn không lo bị mất hay giam cọc.'
                      : (isMoreExpensive
                          ? 'Sẽ được CỘNG VÀO HÓA ĐƠN KỲ TỚI. Bạn được nhận phòng và dọn vào ở trước, đóng khoản bù cọc này sau cùng tiền phòng tháng đầu.'
                          : 'Được chuyển tiếp trọn vẹn 100%, không phát sinh chi phí bù cọc hay hoàn tiền.'),
                  highlight: true,
                  highlightColor: isCheaper
                      ? const Color(0xFF15803D)
                      : (isMoreExpensive
                          ? const Color(0xFFB45309)
                          : const Color(0xFF0284C7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplainBullet({
    required String title,
    required String content,
    bool highlight = false,
    Color? highlightColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5, right: 6),
          child: Icon(Icons.circle, size: 5, color: Color(0xFF64748B)),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF334155),
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: '$title ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: highlight && highlightColor != null
                        ? highlightColor
                        : const Color(0xFF0F172A),
                  ),
                ),
                TextSpan(text: content),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── 5. AMENITIES & HANDOVER CARD ───
  Widget _buildAmenitiesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tiện Nghi & Bàn Giao',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Đầy đủ',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 6 Items Grid
          _buildAmenityRow(
            icon1: Icons.ac_unit_rounded,
            title1: 'Máy lạnh Inverter',
            sub1: 'Đã test, tiết kiệm điện',
            icon2: Icons.water_drop_outlined,
            title2: 'Nước nóng NLMT',
            sub2: 'Áp lực mạnh 24/7',
          ),
          const SizedBox(height: 10),
          _buildAmenityRow(
            icon1: Icons.countertops_outlined,
            title1: 'Kệ bếp đá hoa cương',
            sub1: 'Bồn rửa inox đôi',
            icon2: Icons.kitchen_outlined,
            title2: 'Tủ lạnh 150L',
            sub2: 'Khử mùi Nano Fresh',
          ),
          const SizedBox(height: 10),
          _buildAmenityRow(
            icon1: Icons.bed_outlined,
            title1: 'Giường tầng thông minh',
            sub1: 'Kèm nệm cao su non',
            icon2: Icons.door_sliding_outlined,
            title2: 'Tủ áo âm tường',
            sub2: 'Gỗ MDF chống ẩm',
          ),
          const SizedBox(height: 14),

          // Chi phí cố định
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Định mức chi phí dịch vụ cố định:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '⚡ Điện: 3.500đ/kWh',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '💧 Nước: 15.000đ/m³',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '🧹 Rác: 100k/th',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '🛵 Xe: Miễn phí',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
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

  Widget _buildAmenityRow({
    required IconData icon1,
    required String title1,
    required String sub1,
    required IconData icon2,
    required String title2,
    required String sub2,
  }) {
    return Row(
      children: [
        Expanded(child: _buildAmenityTile(icon1, title1, sub1)),
        const SizedBox(width: 8),
        Expanded(child: _buildAmenityTile(icon2, title2, sub2)),
      ],
    );
  }

  Widget _buildAmenityTile(IconData icon, String title, String sub) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. MOVE PLAN FORM ───
  Widget _buildMovePlanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
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
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Kế Hoạch Dọn Phòng',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'BQL sẽ hỗ trợ xe đẩy chuyển đồ nội bộ',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),

          // Date picker
          const Text(
            'Ngày dự kiến dọn vào',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickMoveInDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCEAFE)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    color: _primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _moveInDateFormatted,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Chọn ngày',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Quy định chuyển phòng hết tháng
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFFB45309),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quy định BQL: Chỉ cho phép chuyển phòng vào dịp HẾT THÁNG (từ ngày 28 đến ngày 01 đầu tháng sau) và sau khi đã thanh toán hết các hóa đơn tiền phòng/điện nước cũ.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Reason pills
          const Text(
            'Lý do chuyển phòng',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(_reasons.length, (i) {
              final isSel = _selectedReasonIndex == i;
              return ChoiceChip(
                label: Text(_reasons[i]),
                selected: isSel,
                onSelected: (val) {
                  if (val) setState(() => _selectedReasonIndex = i);
                },
                selectedColor: _primary,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? Colors.white : const Color(0xFF334155),
                ),
                backgroundColor: const Color(0xFFF1F5F9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Notes
          const Text(
            'Ghi chú gửi Quản lý Kiêu Giang',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            style: const TextStyle(fontSize: 12.5),
            maxLines: 2,
            decoration: InputDecoration(
              hintText:
                  'Nhập yêu cầu hỗ trợ (vd: mượn xe đẩy, hẹn giờ khảo sát...)',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 7. SUBMIT BUTTON ───
  Widget _buildSubmitButton(String targetName) {
    final hasPending = _pendingRequest != null;
    final isNotEligible = widget.hopDong != null && !widget.hopDong!.duDieuKienThoiGianChuyenPhong;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_isSubmitting || hasPending || isNotEligible)
            ? () {
                if (hasPending) {
                  ThongBaoHelper.hienThongBao(
                    context,
                    tieuDe: 'Đang Có Đơn Chờ Duyệt',
                    noiDung:
                        'Bạn đang có yêu cầu #${_pendingRequest!["ma_yeu_cau"]} chuyển sang ${_pendingRequest!["ma_phong_moi"]} đang chờ BQL duyệt. Không thể gửi thêm đơn!',
                    type: ThongBaoType.canhBao,
                  );
                } else if (isNotEligible) {
                  ThongBaoHelper.hienThongBao(
                    context,
                    tieuDe: 'Chưa Đủ Điều Kiện',
                    noiDung:
                        'Cần ở tối thiểu 30 ngày (1 tháng). Bạn mới ở được ${widget.hopDong!.soNgayDaO} ngày (thiếu ${widget.hopDong!.soNgayConThieuChuyenPhong} ngày)!',
                    type: ThongBaoType.canhBao,
                  );
                }
              }
            : _submitTransferRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: hasPending
              ? const Color(0xFFD97706)
              : (isNotEligible ? const Color(0xFF94A3B8) : _primaryDark),
          foregroundColor: Colors.white,
          disabledBackgroundColor: _primaryDark.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    hasPending
                        ? Icons.lock_clock_rounded
                        : (isNotEligible
                            ? Icons.timer_outlined
                            : Icons.send_rounded),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      hasPending
                          ? 'Đang có đơn chờ duyệt (#${_pendingRequest!["ma_yeu_cau"]})'
                          : (isNotEligible
                              ? 'Chưa đủ 30 ngày ở (${widget.hopDong!.soNgayDaO}/30 ngày)'
                              : 'Tiếp tục: gửi yêu cầu chuyển phòng $targetName'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

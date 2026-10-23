import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChuyenPhongThanhCong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuHoaDon.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Màn hình Chi Tiết Phòng & Yêu Cầu Chuyển Phòng
/// Chuẩn hóa theo đúng quy trình trọn gói:
/// 1. Kiểm tra hóa đơn nợ phòng cũ (khóa không cho gửi nếu còn nợ).
/// 2. Bắt buộc ngày hẹn dọn vào ngày đầu tháng (ngày 01).
/// 3. Khách chỉ chọn phòng, ngày 01, lý do và gửi (không chụp ảnh AI/điện nước lúc này).
/// 4. Thông tin cọc tham khảo & toàn bộ tài chính kết chuyển vào hóa đơn kỳ tới của phòng mới.
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
    'Phòng rộng rãi hơn',
    'Cần không gian yên tĩnh',
    'Phòng thoáng mát hơn',
    'Lý do khác',
  ];

  late TextEditingController _noteController;

  // Kiểm tra công nợ hóa đơn phòng hiện tại
  bool _isLoadingInvoices = true;
  List<Map<String, dynamic>> _unpaidInvoices = [];
  bool get _hasUnpaidInvoices => _unpaidInvoices.isNotEmpty;

  // Bảng giá dịch vụ
  List<Map<String, dynamic>> _danhSachDichVu = [];
  bool _isLoadingDichVu = true;

  /// Tính ngày đầu tháng tiếp theo (ngày 01)
  static DateTime _tinhNgayDauThangToi() {
    final now = DateTime.now();
    if (now.month == 12) {
      return DateTime(now.year + 1, 1, 1);
    } else {
      return DateTime(now.year, now.month + 1, 1);
    }
  }

  @override
  void initState() {
    super.initState();
    // Mặc định ngày dọn là ngày 01 của tháng tới
    _moveInDate = _tinhNgayDauThangToi();
    _noteController = TextEditingController(
      text: 'Chuyển sang ${widget.targetRoom["maPhong"] ?? "phòng mới"} cho thuận tiện sinh hoạt.',
    );
    _checkPendingRequest();
    _taiDanhSachDichVu();
    _kiemTraHoaDonNo();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// 1. Kiểm tra hóa đơn nợ phòng cũ
  Future<void> _kiemTraHoaDonNo() async {
    try {
      final activeHD = widget.maHopDong ?? widget.hopDong?.maHopDong ?? 'HD001';
      final activeRoom = widget.currentRoomNumber;
      final res = await Supabase.instance.client
          .from('hoa_don')
          .select('ma_hoa_don, tong_tien, trang_thai, thang_nam')
          .or('ma_hop_dong.eq.$activeHD,ma_phong.eq.$activeRoom')
          .neq('trang_thai', 'Đã thanh toán')
          .gt('tong_tien', 0);

      if (mounted) {
        setState(() {
          _unpaidInvoices = List<Map<String, dynamic>>.from(res);
          _isLoadingInvoices = false;
        });
      }
    } catch (e) {
      debugPrint('[HOA_DON_NO] Lỗi kiểm tra hóa đơn nợ: $e');
      if (mounted) setState(() => _isLoadingInvoices = false);
    }
  }

  /// 2. Tải danh mục dịch vụ
  Future<void> _taiDanhSachDichVu() async {
    try {
      final res = await Supabase.instance.client
          .from('dich_vu')
          .select()
          .order('ma_dich_vu', ascending: true);
      if (res.isNotEmpty && mounted) {
        setState(() {
          _danhSachDichVu = List<Map<String, dynamic>>.from(res);
          _isLoadingDichVu = false;
        });
      }
    } catch (e) {
      debugPrint('[DICH_VU] Lỗi tải danh sách dịch vụ: $e');
      if (mounted) setState(() => _isLoadingDichVu = false);
    }
  }

  /// 3. Kiểm tra xem có đơn chuyển phòng đang chờ duyệt không (chống gửi trùng)
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
            'CHO_DUYET',
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

  String get _moveInDateFormatted {
    final d = _moveInDate;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Chọn ngày hẹn dọn phòng (bắt buộc ngày 01 đầu tháng)
  Future<void> _pickMoveInDate() async {
    final now = DateTime.now();
    final firstAllowed = _tinhNgayDauThangToi();
    final initialDate = (_moveInDate.day == 1 && !_moveInDate.isBefore(firstAllowed))
        ? _moveInDate
        : firstAllowed;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstAllowed,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'CHỌN LỊCH DỌN PHÒNG (NGÀY 01 ĐẦU THÁNG)',
      selectableDayPredicate: (DateTime val) {
        // RÀNG BUỘC: Lịch chuyển phòng chỉ áp dụng vào ngày đầu tháng (ngày 01)
        return val.day == 1;
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
      if (picked.day != 1) {
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Ngày Không Hợp Lệ',
          noiDung: 'Lịch chuyển phòng chỉ áp dụng vào ngày đầu tháng (ngày 01).',
          type: ThongBaoType.canhBao,
        );
        return;
      }
      setState(() => _moveInDate = picked);
    }
  }

  /// Gửi yêu cầu chuyển phòng
  Future<void> _submitTransferRequest() async {
    if (_isSubmitting) return;

    // RÀNG BUỘC 1: Kiểm tra hóa đơn nợ
    if (_hasUnpaidInvoices) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Chưa Hoàn Tất Hóa Đơn',
        noiDung:
            'Vui lòng thanh toán hết các hóa đơn của phòng hiện tại trước khi yêu cầu chuyển phòng.',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    // RÀNG BUỘC 2: Kiểm tra ngày hẹn chuyển (bắt buộc ngày 01)
    if (_moveInDate.day != 1) {
      ThongBaoHelper.hienThongBao(
        context,
        tieuDe: 'Ngày Không Hợp Lệ',
        noiDung: 'Lịch chuyển phòng chỉ áp dụng vào ngày đầu tháng (ngày 01).',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final target = widget.targetRoom;
    final targetCode = (target['maPhong'] as String? ?? 'P205')
        .replaceAll('.', '')
        .trim();

    final ticketId =
        'YCCP_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    try {
      // 1. Lấy thông tin hợp đồng hiện tại và tiền cọc từ Supabase
      String activeHopDong = widget.maHopDong ?? widget.hopDong?.maHopDong ?? 'HD001';
      String activeRoom = widget.currentRoomNumber;
      num deposit = widget.currentPrice;

      if (widget.hopDong != null) {
        activeHopDong = widget.hopDong!.maHopDong;
        activeRoom = widget.hopDong!.maPhong;
        deposit = widget.hopDong!.tienDatCoc > 0
            ? widget.hopDong!.tienDatCoc
            : widget.hopDong!.giaThueThaoThuan;
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

      // Live Check lại hóa đơn nợ từ Supabase ngay trước khi insert
      try {
        final unpaidCheck = await Supabase.instance.client
            .from('hoa_don')
            .select('ma_hoa_don, tong_tien, trang_thai')
            .or('ma_hop_dong.eq.$activeHopDong,ma_phong.eq.$activeRoom')
            .neq('trang_thai', 'Đã thanh toán')
            .gt('tong_tien', 0);

        if (unpaidCheck.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _unpaidInvoices = List<Map<String, dynamic>>.from(unpaidCheck);
            _isSubmitting = false;
          });
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Chưa Hoàn Tất Hóa Đơn',
            noiDung:
                'Vui lòng thanh toán hết các hóa đơn của phòng hiện tại trước khi yêu cầu chuyển phòng.',
            type: ThongBaoType.canhBao,
          );
          return;
        }
      } catch (eInv) {
        debugPrint('Kiểm tra hóa đơn nợ: $eInv');
      }

      // RÀNG BUỘC: Không chuyển sang chính phòng mình đang ở
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

      // RÀNG BUỘC: Chống gửi lần 2 nếu đang có đơn chờ duyệt
      if (_pendingRequest != null) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Không Thể Gửi Thêm Đơn',
          noiDung:
              'Bạn đang có yêu cầu #${_pendingRequest!["ma_yeu_cau"]} chuyển sang ${_pendingRequest!["ma_phong_moi"]} đang chờ Ban Quản Lý phê duyệt! Mỗi cư dân chỉ tạo 1 yêu cầu tại một thời điểm.',
          type: ThongBaoType.canhBao,
        );
        return;
      }

      final String reason = _reasons[_selectedReasonIndex];
      final String note = _noteController.text.trim();
      final String fullReason = note.isNotEmpty ? '$reason - $note' : reason;
      final String dateHenStr =
          '${_moveInDate.year}-${_moveInDate.month.toString().padLeft(2, '0')}-01';

      // 2. GHI BẢN GHI VÀO SUPABASE (Bảng yeu_cau_chuyen_phong) đúng chuẩn quy trình
      await Supabase.instance.client.from('yeu_cau_chuyen_phong').insert({
        'ma_yeu_cau': ticketId,
        'ma_hop_dong_ht': activeHopDong,
        'ma_phong_cu': activeRoom,
        'ma_phong_moi': targetCode,
        'tien_coc_bao_luu': deposit,
        'thoi_gian_hen': dateHenStr,
        'ly_do_chuyen': fullReason,
        'trang_thai_tien_do': 'CHO_DUYET',
        'trang_thai': 'CHO_DUYET',
        'tien_dien_nuoc_cu': 0,
        'tien_hu_hai_cu': 0,
        'tien_phat_sinh': 0,
        'ghi_chu_hu_hai': null,
        'nguoi_don_bql': 'BQL Kiều Giang',
        'ngay_tao': DateTime.now().toIso8601String(),
      });
      debugPrint('[CHUYEN_PHONG] Đã ghi nhận yeu_cau_chuyen_phong: $ticketId');

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // 3. Chuyển sang màn hình xác nhận thành công
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

                          // Cảnh báo nếu còn hóa đơn chưa thanh toán
                          if (_hasUnpaidInvoices) ...[
                            _buildUnpaidInvoiceBanner(),
                            const SizedBox(height: 14),
                          ],

                          // Đối chiếu phòng cũ & mới, thông tin cọc tham khảo
                          _buildComparisonCard(target, diff),
                          const SizedBox(height: 16),

                          // Thẻ giải thích quy trình tài chính trọn gói
                          _buildFinancialPolicyCard(),
                          const SizedBox(height: 16),

                          // Tiện nghi & định mức dịch vụ
                          _buildAmenitiesCard(),
                          const SizedBox(height: 16),

                          // Kế hoạch dọn phòng (ngày 01 & lý do)
                          _buildMovePlanCard(),
                          const SizedBox(height: 20),

                          // Nút gửi yêu cầu
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

  // ─── BANNER CẢNH BÁO HÓA ĐƠN NỢ ───
  Widget _buildUnpaidInvoiceBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.05),
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
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'CHƯA HOÀN TẤT THANH TOÁN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB91C1C),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_unpaidInvoices.length} HÓA ĐƠN',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Vui lòng thanh toán hết các hóa đơn của phòng hiện tại trước khi yêu cầu chuyển phòng.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF7F1D1D),
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen()),
                ).then((_) => _kiemTraHoaDonNo());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 9),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.payment_rounded, size: 15),
              label: const Text(
                'Thanh toán hóa đơn ngay',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
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
                  'Tầng ${widget.targetRoom["tang"]} • ${widget.targetRoom["toaNha"]}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2. HERO IMAGE ───
  Widget _buildHeroImage(Map<String, dynamic> target, num diff) {
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDBEAFE)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.crop_square_rounded, color: _primary, size: 14),
              const SizedBox(width: 4),
              Text(
                '${target["dienTich"] ?? 22} m²',
                style: const TextStyle(
                  fontSize: 12,
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

  // ─── 4. COMPARISON CARD (ĐỐI CHIẾU & THÔNG TIN CỌC THAM KHẢO) ───
  Widget _buildComparisonCard(Map<String, dynamic> target, num diff) {
    final int oldFloor = _extractFloor(widget.currentRoomNumber);
    final int newFloor = (target['tang'] as num?)?.toInt() ??
        _extractFloor(target['maPhong']?.toString() ?? '');

    final num targetPrice =
        (target['giaThue'] as num?) ?? (widget.currentPrice + diff);
    final bool isCheaper = (targetPrice - widget.currentPrice) < 0;

    // Tiền cọc phòng cũ & phòng mới
    final num oldDeposit = widget.hopDong?.tienDatCoc != null && widget.hopDong!.tienDatCoc > 0
        ? widget.hopDong!.tienDatCoc
        : widget.currentPrice;
    final num targetDeposit =
        (target['tienDatCoc'] as num?) ?? (target['giaThue'] as num?) ?? oldDeposit;
    final num depositDiff = targetDeposit - oldDeposit;
    final num absDepositDiff = depositDiff.abs();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBAE6FD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.05),
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
              Icon(Icons.sync_alt_rounded, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Đối Chiếu Phòng & Tiền Cọc Tham Khảo',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2 Cột Phòng cũ vs Phòng mới
          Row(
            children: [
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
                        'PHÒNG HIỆN TẠI',
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
                      const SizedBox(height: 4),
                      Text('• Tầng $oldFloor', style: const TextStyle(fontSize: 11.5)),
                      Text(
                        '• Giá: ${FormatUtils.currency(widget.currentPrice.toDouble())}đ',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCheaper ? const Color(0xFFF0FDF4) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isCheaper ? const Color(0xFF86EFAC) : const Color(0xFF93C5FD),
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
                          color: isCheaper ? const Color(0xFF16A34A) : _primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        target['maPhong'] ?? '',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isCheaper ? const Color(0xFF16A34A) : _primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('• Tầng $newFloor', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                      Text(
                        '• Giá: ${FormatUtils.currency(targetPrice.toDouble())}đ',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // KHỐI THÔNG TIN CỌC THAM KHẢO
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
                const Text(
                  'THÔNG TIN CỌC THAM KHẢO:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 8),
                _buildDepositRow('Cọc phòng cũ:', '${FormatUtils.currency(oldDeposit.toDouble())}đ (Bảo lưu chuyển sang)'),
                const SizedBox(height: 4),
                _buildDepositRow('Cọc phòng mới:', '${FormatUtils.currency(targetDeposit.toDouble())}đ'),
                const SizedBox(height: 6),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                const SizedBox(height: 6),
                _buildDepositRow(
                  'Chênh lệch cọc:',
                  depositDiff == 0
                      ? '0đ (Cọc 2 phòng bằng nhau)'
                      : (depositDiff > 0
                          ? '+${FormatUtils.currency(absDepositDiff.toDouble())}đ (Bù thêm)'
                          : '-${FormatUtils.currency(absDepositDiff.toDouble())}đ (Hoàn trả)'),
                  isBold: true,
                  valueColor: depositDiff == 0
                      ? const Color(0xFF0284C7)
                      : (depositDiff > 0 ? const Color(0xFFB45309) : const Color(0xFF15803D)),
                ),
                const SizedBox(height: 6),
                Text(
                  depositDiff == 0
                      ? '• Cọc bảo lưu 100%, không phát sinh bù cọc hay hoàn tiền.'
                      : (depositDiff > 0
                          ? '• Khoản bù thêm (${FormatUtils.currency(absDepositDiff.toDouble())}đ) sẽ được cộng trực tiếp vào hóa đơn kỳ tới của phòng mới.'
                          : '• Khoản hoàn trả (${FormatUtils.currency(absDepositDiff.toDouble())}đ) sẽ được trừ trực tiếp giảm giá vào hóa đơn kỳ tới của phòng mới.'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF64748B),
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

  Widget _buildDepositRow(String title, String value, {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11.5,
            color: const Color(0xFF475569),
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? _textDark,
          ),
        ),
      ],
    );
  }

  // ─── 5. FINANCIAL POLICY CARD (NGHIỆP VỤ TÀI CHÍNH KẾT CHUYỂN) ───
  Widget _buildFinancialPolicyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF15803D), size: 18),
              SizedBox(width: 8),
              Text(
                'Quy Trình Xử Lý Tài Chính Phát Sinh',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF166534),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Toàn bộ tiền bạc không thu/chi tiền mặt tại chỗ vào ngày dọn phòng mà sẽ ĐƯỢC TỔNG HỢP VÀO HÓA ĐƠN ĐẦU TIÊN CỦA PHÒNG MỚI:',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF15803D), fontWeight: FontWeight.bold, height: 1.35),
          ),
          SizedBox(height: 6),
          Text(
            '• Tiền điện nước phát sinh những ngày cuối ở phòng cũ (tính từ ngày chốt công tơ gần nhất đến ngày 01).\n'
            '• Tiền đền bù hư hỏng cơ sở vật chất phòng cũ (nếu có sau khi BQL kiểm tra bàn giao).\n'
            '• Tiền chênh lệch cọc: bù thêm nếu cọc phòng mới cao hơn, hoặc trừ giảm giá nếu cọc phòng mới thấp hơn.',
            style: TextStyle(fontSize: 11, color: Color(0xFF166534), height: 1.45),
          ),
        ],
      ),
    );
  }

  // ─── 6. AMENITIES CARD ───
  Widget _buildAmenitiesCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          const Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Tiện Nghi Phòng & Bảng Giá Dịch Vụ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAmenityRow(
            icon1: Icons.ac_unit_rounded,
            title1: 'Máy lạnh Inverter',
            sub1: 'Tiết kiệm điện',
            icon2: Icons.water_drop_outlined,
            title2: 'Nước nóng NLMT',
            sub2: 'Áp lực mạnh 24/7',
          ),
          const SizedBox(height: 8),
          _buildAmenityRow(
            icon1: Icons.countertops_outlined,
            title1: 'Kệ bếp đá hoa cương',
            sub1: 'Bồn rửa inox',
            icon2: Icons.kitchen_outlined,
            title2: 'Tủ lạnh 150L',
            sub2: 'Tiết kiệm điện',
          ),
          const SizedBox(height: 12),
          _buildDinhMucChiPhiDichVu(),
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
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDinhMucChiPhiDichVu() {
    num giaDien = 3500;
    num giaNuoc = 20000;
    num giaRac = 30000;
    num giaWifi = 50000;

    for (final dv in _danhSachDichVu) {
      final code = (dv['ma_dich_vu'] ?? '').toString().toUpperCase();
      final gia = num.tryParse(dv['don_gia']?.toString() ?? '') ?? 0;
      if (code.contains('DIEN')) giaDien = gia;
      if (code.contains('NUOC')) giaNuoc = gia;
      if (code.contains('RAC')) giaRac = gia;
      if (code.contains('WIFI')) giaWifi = gia;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 14, color: _primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Định mức chi phí dịch vụ cố định:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                ),
              ),
              if (_isLoadingDichVu)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: _primary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('⚡ Điện: ${FormatUtils.currency(giaDien)}đ/kWh', style: const TextStyle(fontSize: 11)),
              ),
              Expanded(
                child: Text('💧 Nước: ${FormatUtils.currency(giaNuoc)}đ/m³', style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text('🧹 Rác: ${FormatUtils.currency(giaRac)}đ/người', style: const TextStyle(fontSize: 11)),
              ),
              Expanded(
                child: Text('📶 Wifi: ${FormatUtils.currency(giaWifi)}đ/phòng', style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 7. MOVE PLAN CARD (NGÀY HẸN 01 ĐẦU THÁNG & LÝ DO) ───
  Widget _buildMovePlanCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Lịch Hẹn Dọn Phòng & Lý Do Chuyển',
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
            'Lịch chuyển phòng chỉ áp dụng vào ngày đầu tháng (ngày 01)',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),

          // Date picker
          const Text(
            'Ngày hẹn dọn phòng (bắt buộc ngày 01):',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
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
                  const Icon(Icons.event_available_rounded, color: _primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _moveInDateFormatted,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: _textDark),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF09638E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Đổi ngày', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _primary)),
                        SizedBox(width: 3),
                        Icon(Icons.edit_calendar_rounded, size: 13, color: _primary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Quy định chuyển phòng ngày 01
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quy định Ban Quản Lý: Lịch chuyển phòng chỉ áp dụng vào ngày đầu tháng (ngày 01) để thuận tiện chốt công tơ điện nước và kết chuyển tài chính trọn kỳ vào hóa đơn phòng mới.',
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
            'Lý do chuyển phòng:',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              );
            }),
          ),
          const SizedBox(height: 12),

          // Notes
          const Text(
            'Ghi chú thêm gửi Ban Quản Lý:',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _noteController,
            style: const TextStyle(fontSize: 12.5),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Nhập nội dung ghi chú (ví dụ: mượn xe đẩy, hẹn giờ khảo sát...)',
              hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

  // ─── 8. SUBMIT BUTTON ───
  Widget _buildSubmitButton(String targetName) {
    final hasPending = _pendingRequest != null;
    final hasUnpaid = _hasUnpaidInvoices;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: (_isSubmitting || hasPending || hasUnpaid)
            ? () {
                if (hasUnpaid) {
                  ThongBaoHelper.hienThongBao(
                    context,
                    tieuDe: 'Chưa Hoàn Tất Hóa Đơn',
                    noiDung:
                        'Vui lòng thanh toán hết các hóa đơn của phòng hiện tại trước khi yêu cầu chuyển phòng.',
                    type: ThongBaoType.canhBao,
                  );
                } else if (hasPending) {
                  ThongBaoHelper.hienThongBao(
                    context,
                    tieuDe: 'Đang Có Đơn Chờ Duyệt',
                    noiDung:
                        'Bạn đang có yêu cầu #${_pendingRequest!["ma_yeu_cau"]} chuyển sang ${_pendingRequest!["ma_phong_moi"]} đang chờ BQL duyệt. Không thể gửi thêm đơn!',
                    type: ThongBaoType.canhBao,
                  );
                }
              }
            : _submitTransferRequest,
        style: ElevatedButton.styleFrom(
          backgroundColor: hasUnpaid
              ? const Color(0xFFDC2626)
              : (hasPending ? const Color(0xFFD97706) : _primaryDark),
          foregroundColor: Colors.white,
          disabledBackgroundColor: hasUnpaid
              ? const Color(0xFFDC2626).withValues(alpha: 0.7)
              : _primaryDark.withValues(alpha: 0.6),
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
                    hasUnpaid
                        ? Icons.warning_rounded
                        : (hasPending ? Icons.lock_clock_rounded : Icons.send_rounded),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      hasUnpaid
                          ? 'Vui lòng thanh toán hết hóa đơn phòng cũ'
                          : (hasPending
                              ? 'Đang có đơn chờ duyệt (#${_pendingRequest!["ma_yeu_cau"]})'
                              : 'Gửi yêu cầu chuyển phòng $targetName'),
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

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhHopDong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToan.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhThanhToanXong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';

/// Màn hình: Lịch sử hóa đơn & Thống kê chi phí
/// Lấy trực tiếp từ bảng hoa_don & chi_tiet_hoa_don trên Supabase
/// Phong cách: Xanh Navy sang trọng, đồng bộ toàn hệ thống
class InvoiceHistoryScreen extends StatefulWidget {
  final String roomName;
  final String? maHopDong;

  const InvoiceHistoryScreen({
    super.key,
    this.roomName = 'Phòng 302 • Nhà trọ Kiêu Giang',
    this.maHopDong,
  });

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  // Theme Xanh Navy đồng bộ
  static const _navyDark = Color(0xFF0F2042);
  static const _navyAccent = Color(0xFF1E3A8A);
  static const _navyBlue = Color(0xFF09638E);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  String _selectedYear = 'Năm 2026';
  int _selectedFilterIndex =
      0; // 0: Tất cả, 1: Chưa thanh toán / Chờ duyệt, 2: Đã thanh toán

  bool _isLoading = true;
  List<HoaDonModel> _allHoaDons = [];
  Map<String, List<Map<String, dynamic>>> _chiTietMap = {};
  List<Map<String, dynamic>> _chiSoDienNuoc = [];

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
  }

  Future<void> _fetchInvoices() async {
    setState(() => _isLoading = true);
    try {
      final db = Supabase.instance.client;
      String? contractCode = widget.maHopDong;

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

      var query = db.from('hoa_don').select('*, chi_tiet_hoa_don(*)');
      if (contractCode != null && contractCode.isNotEmpty) {
        query = query.eq('ma_hop_dong', contractCode);
      }
      var rows = await query.order('ngay_lap', ascending: false);

      // Fallback: nếu lọc theo contractCode không ra thì lấy tất cả hóa đơn hiện có
      if ((rows as List).isEmpty) {
        rows = await db
            .from('hoa_don')
            .select('*, chi_tiet_hoa_don(*)')
            .order('ngay_lap', ascending: false);
      }

      final list = (rows as List)
          .map((r) => HoaDonModel.fromJson(Map<String, dynamic>.from(r)))
          // Chỉ hiện hóa đơn BQL đã gửi (loại trừ 'Chờ gửi' — chưa được BQL xác nhận)
          .where((h) => h.trangThai != 'Chờ gửi')
          .toList();

      final Map<String, List<Map<String, dynamic>>> details = {};
      for (final r in rows) {
        final maHd = r['ma_hoa_don']?.toString() ?? '';
        final ctList = r['chi_tiet_hoa_don'];
        if (ctList is List) {
          details[maHd] = List<Map<String, dynamic>>.from(ctList);
        }
      }

      // Tải chỉ số điện nước thực tế từ bảng chi_so_dien_nuoc
      var chiSoQuery = db.from('chi_so_dien_nuoc').select();
      if (contractCode != null && contractCode.isNotEmpty) {
        chiSoQuery = chiSoQuery.eq('ma_hop_dong', contractCode);
      }
      var chiSoRows = await chiSoQuery.order('thang_nam', ascending: true);
      if ((chiSoRows as List).isEmpty) {
        chiSoRows = await db
            .from('chi_so_dien_nuoc')
            .select()
            .order('thang_nam', ascending: true);
      }

      if (mounted) {
        setState(() {
          _allHoaDons = list;
          _chiTietMap = details;
          _chiSoDienNuoc = List<Map<String, dynamic>>.from(chiSoRows as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch sử hóa đơn: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _paidCount =>
      _allHoaDons.where((h) => h.trangThai == 'Đã thanh toán').length;
  // Chỉ đếm hóa đơn BQL đã gửi nhưng chưa thanh toán (loại trừ 'Chờ gửi')
  int get _unpaidCount => _allHoaDons
      .where((h) => h.trangThai != 'Đã thanh toán' && h.trangThai != 'Chờ gửi')
      .length;

  double get _avgElectricity {
    if (_chiSoDienNuoc.isEmpty) return 60.0;
    final total = _chiSoDienNuoc.fold<double>(0.0, (sum, item) {
      final cu =
          num.tryParse(item['chi_so_dien_cu']?.toString() ?? '0')?.toDouble() ??
          0.0;
      final moi =
          num.tryParse(
            item['chi_so_dien_moi']?.toString() ?? '0',
          )?.toDouble() ??
          0.0;
      return sum + (moi - cu).clamp(0.0, double.infinity);
    });
    return total / _chiSoDienNuoc.length;
  }

  double get _avgWater {
    if (_chiSoDienNuoc.isEmpty) return 6.0;
    final total = _chiSoDienNuoc.fold<double>(0.0, (sum, item) {
      final cu =
          num.tryParse(item['chi_so_nuoc_cu']?.toString() ?? '0')?.toDouble() ??
          0.0;
      final moi =
          num.tryParse(
            item['chi_so_nuoc_moi']?.toString() ?? '0',
          )?.toDouble() ??
          0.0;
      return sum + (moi - cu).clamp(0.0, double.infinity);
    });
    return total / _chiSoDienNuoc.length;
  }

  List<HoaDonModel> get _filteredList {
    if (_selectedFilterIndex == 1) {
      // Tab 'Chưa thanh toán': chỉ hiện hóa đơn đã được gửi (không tính 'Chờ gửi')
      return _allHoaDons
          .where(
            (h) => h.trangThai != 'Đã thanh toán' && h.trangThai != 'Chờ gửi',
          )
          .toList();
    }
    if (_selectedFilterIndex == 2) {
      return _allHoaDons.where((h) => h.trangThai == 'Đã thanh toán').toList();
    }
    return _allHoaDons;
  }

  num get _totalSpending => _allHoaDons.fold<num>(0, (sum, item) {
    if (item.tongTien > 0) return sum + item.tongTien;
    final details = _chiTietMap[item.maHoaDon] ?? [];
    if (details.isNotEmpty) {
      return sum +
          details.fold<num>(
            0,
            (s, ct) =>
                s + (num.tryParse(ct['thanh_tien']?.toString() ?? '0') ?? 0),
          );
    }
    return sum + item.tongTienGoc;
  });

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
                  ? const LoadingMeoMeo(
                      message: 'Đang tải hóa đơn...',
                      subMessage:
                          'Mèo con đang tính toán chi phí cho bạn nha~ 🐾',
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchInvoices,
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
                            _buildFilterTabs(),
                            const SizedBox(height: 14),
                            _buildYearSummaryCard(),
                            const SizedBox(height: 16),
                            _buildElectricityTrendCard(),
                            const SizedBox(height: 18),
                            _buildBillListHeader(),
                            const SizedBox(height: 10),
                            _buildBillList(),
                            const SizedBox(height: 16),
                            _buildNoticeCard(),
                            const SizedBox(height: 14),
                            _buildFooterNote(),
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

  // ─── 1. TOP APP BAR (NAVY THEME) ───
  Widget _buildTopAppBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kiêu Giang',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _navyDark,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'Hồ sơ cư dân',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF475569),
                  size: 20,
                ),
                if (_unpaidCount > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE6EDF5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: const Icon(Icons.person_rounded, color: _navyDark, size: 22),
          ),
        ],
      ),
    );
  }

  // ─── 2. SUB HEADER (TITLE & YEAR FILTER) ───
  Widget _buildSubHeader() {
    return Row(
      children: [
        InkWell(
          onTap: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const TenantHomeScreen(initialTabIndex: 2),
                ),
                (route) => false,
              );
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: _navyDark,
              size: 15,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lịch sử hóa đơn',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),
              Text(
                widget.roomName,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_rounded,
                color: _navyDark,
                size: 14,
              ),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedYear,
                  isDense: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _navyDark,
                    size: 16,
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _navyDark,
                  ),
                  items: ['Năm 2024', 'Năm 2025', 'Năm 2026'].map((y) {
                    return DropdownMenuItem<String>(value: y, child: Text(y));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedYear = val);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 3. FILTER TABS (NAVY STYLE) ───
  Widget _buildFilterTabs() {
    final filters = [
      'Tất cả (${_allHoaDons.length})',
      'Chưa thanh toán ($_unpaidCount)',
      'Đã thanh toán ($_paidCount)',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(filters.length, (index) {
          final isSelected = _selectedFilterIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () => setState(() => _selectedFilterIndex = index),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
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
                  filters[index],
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

  // ─── 4. YEAR SUMMARY CARD (NAVY BLUE ACCENTS) ───
  Widget _buildYearSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'Tổng chi phí $_selectedYear',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF94A3B8),
                      size: 13,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _unpaidCount == 0
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _unpaidCount == 0
                          ? Icons.check_circle_rounded
                          : Icons.access_time_filled_rounded,
                      color: _unpaidCount == 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _unpaidCount == 0
                          ? 'Đã quyết toán hết'
                          : 'Còn $_unpaidCount kỳ nợ',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: _unpaidCount == 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE11D48),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        FormatUtils.currency(
                          _totalSpending,
                        ).replaceAll('đ', '').trim(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: _navyDark,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'VNĐ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _navyBlue,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Đã đóng: $_paidCount/${_allHoaDons.length} kỳ',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Dữ liệu đồng bộ trực tiếp từ hệ thống quản lý Nhà trọ Kiêu Giang',
            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),

          // 2 Mini metrics: Điện & Nước bình quân
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFFD97706),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Điện bình quân',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '~${_avgElectricity.toStringAsFixed(0)} kWh/tháng',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.water_drop_outlined,
                        color: Color(0xFF0284C7),
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nước bình quân',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '~${_avgWater.toStringAsFixed(0)} m³/tháng',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: _textDark,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 5. ELECTRICITY TREND CARD ───
  Widget _buildElectricityTrendCard() {
    List<Widget> barWidgets = [];
    if (_chiSoDienNuoc.isNotEmpty) {
      // Chỉ lấy tối đa 5 tháng gần nhất để tránh tràn màn hình
      final displayData = _chiSoDienNuoc.length > 5
          ? _chiSoDienNuoc.sublist(_chiSoDienNuoc.length - 5)
          : _chiSoDienNuoc;

      double maxKwh = 1.0;
      for (final item in displayData) {
        final cu =
            num.tryParse(
              item['chi_so_dien_cu']?.toString() ?? '0',
            )?.toDouble() ??
            0.0;
        final moi =
            num.tryParse(
              item['chi_so_dien_moi']?.toString() ?? '0',
            )?.toDouble() ??
            0.0;
        final diff = (moi - cu).clamp(0.0, double.infinity);
        if (diff > maxKwh) maxKwh = diff;
      }

      for (int i = 0; i < displayData.length; i++) {
        final item = displayData[i];
        final thang = item['thang_nam']?.toString().split('/')[0] ?? '${i + 1}';
        final cu =
            num.tryParse(
              item['chi_so_dien_cu']?.toString() ?? '0',
            )?.toDouble() ??
            0.0;
        final moi =
            num.tryParse(
              item['chi_so_dien_moi']?.toString() ?? '0',
            )?.toDouble() ??
            0.0;
        final diff = (moi - cu).clamp(0.0, double.infinity).toInt();
        final isHighest = diff.toDouble() == maxKwh;
        barWidgets.add(_buildBar('T$thang', diff, isHighest, maxKwh));
      }
    } else {
      barWidgets = [
        _buildBar('T6', 55, false, 72),
        _buildBar('T7', 72, true, 72),
        _buildBar('T8', 65, false, 72),
        _buildBar('T9', 60, false, 72),
      ];
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          const Row(
            children: [
              Icon(Icons.query_stats_rounded, color: _navyDark, size: 18),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Biểu đồ chỉ số điện gần đây',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Đơn vị: kWh',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: barWidgets,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                color: Color(0xFFD97706),
                size: 14,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tiêu thụ điện kỳ này ở mức ổn định và tiết kiệm.',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBar(
    String label,
    int value,
    bool isHighest, [
    double maxVal = 100.0,
  ]) {
    final safeMax = maxVal > 0 ? maxVal : 100.0;
    final height = ((value / safeMax) * 60.0).clamp(12.0, 60.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isHighest ? _navyDark : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 28,
          height: height,
          decoration: BoxDecoration(
            color: isHighest ? _navyDark : const Color(0xFF93C5FD),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isHighest ? FontWeight.bold : FontWeight.normal,
            color: isHighest ? _navyDark : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // ─── 6. BILL LIST HEADER ───
  Widget _buildBillListHeader() {
    return Row(
      children: [
        const Text(
          'Danh sách kỳ hóa đơn',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const Spacer(),
        Text(
          'Hiển thị ${_filteredList.length} kỳ',
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  // ─── 7. REAL BILL LIST FROM SUPABASE ───
  Widget _buildBillList() {
    if (_filteredList.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: const [
            Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
            SizedBox(height: 10),
            Text(
              'Không tìm thấy hóa đơn nào',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Các hóa đơn mới sẽ tự động hiển thị tại đây.',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _filteredList.map((hd) => _buildInvoiceCard(hd)).toList(),
    );
  }

  Widget _buildInvoiceCard(HoaDonModel hd) {
    final isPaid = hd.trangThai == 'Đã thanh toán';
    final details = _chiTietMap[hd.maHoaDon] ?? [];

    num billTotal = hd.tongTien;
    if (billTotal <= 0) {
      if (details.isNotEmpty) {
        billTotal = details.fold<num>(
          0,
          (sum, item) =>
              sum + (num.tryParse(item['thanh_tien']?.toString() ?? '0') ?? 0),
        );
      } else {
        billTotal = hd.tongTienGoc;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPaid
              ? const Color(0xFFE2E8F0)
              : const Color(0xFF0F2042).withValues(alpha: 0.3),
          width: isPaid ? 1.0 : 1.5,
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
          // Header: Month & Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hd.thangNam.isNotEmpty
                          ? 'Hóa đơn ${hd.thangNam}'
                          : 'Hóa đơn #${hd.maHoaDon}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPaid
                          ? 'Đã thanh toán ngày: ${hd.hanDongTienFormatted}'
                          : 'Hạn thanh toán: ${hd.hanDongTienFormatted}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPaid
                          ? Icons.check_circle_rounded
                          : Icons.access_time_filled_rounded,
                      size: 11,
                      color: isPaid
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hd.trangThai,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: isPaid
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE11D48),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Total Amount Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F6FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Text(
                  'Tổng tiền:',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const Spacer(),
                Text(
                  FormatUtils.currency(billTotal),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _navyDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Line items (from chi_tiet_hoa_don with ten_khoan_thu)
          if (details.isNotEmpty) ...[
            for (final item in details) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _buildLineItemRow(
                  item['ten_khoan_thu']?.toString() ??
                      item['khoan_muc']?.toString() ??
                      'Khoản thu',
                  num.tryParse(item['thanh_tien']?.toString() ?? '0') ?? 0,
                ),
              ),
            ],
          ] else ...[
            _buildLineItemRow('Tiền phòng cơ bản', hd.tienPhong),
            _buildLineItemRow('Điện & Nước sinh hoạt', hd.tienDienNuoc),
            if (hd.tienDichVuKhac > 0)
              _buildLineItemRow('Dịch vụ chung', hd.tienDichVuKhac),
            if (hd.noCu > 0) _buildLineItemRow('Nợ kỳ trước', hd.noCu),
          ],
          const SizedBox(height: 12),

          // Bottom Action: Navy themed Button
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mã HĐ: #${hd.maHoaDon}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  if (isPaid) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentCompletedScreen(
                          hoaDon: hd,
                          tenPhong: widget.roomName,
                          bankName: 'MB Bank (Quân Đội)',
                          transactionTime: hd.hanDongTienFormatted,
                          amountPaid: billTotal,
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentScreen(
                          hoaDon: hd,
                          tenPhong: widget.roomName,
                        ),
                      ),
                    );
                  }
                },
                icon: Icon(
                  isPaid
                      ? Icons.receipt_rounded
                      : Icons.qr_code_scanner_rounded,
                  size: 13,
                ),
                label: Text(
                  isPaid ? 'Xem biên lai' : 'Thanh toán',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPaid ? const Color(0xFFE2E8F0) : _navyDark,
                  foregroundColor: isPaid ? _navyDark : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineItemRow(String title, num amount) {
    IconData icon = Icons.receipt_outlined;
    Color iconColor = _navyBlue;
    final lower = title.toLowerCase();

    if (lower.contains('phòng') || lower.contains('thuê')) {
      icon = Icons.bed_outlined;
      iconColor = _navyDark;
    } else if (lower.contains('điện')) {
      icon = Icons.bolt_rounded;
      iconColor = const Color(0xFFD97706);
    } else if (lower.contains('nước')) {
      icon = Icons.water_drop_outlined;
      iconColor = const Color(0xFF0284C7);
    } else if (lower.contains('rác') ||
        lower.contains('vệ sinh') ||
        lower.contains('dịch vụ')) {
      icon = Icons.cleaning_services_outlined;
      iconColor = const Color(0xFF0D9488);
    }

    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          FormatUtils.currency(amount),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  // ─── 8. NOTICE CARD ───
  Widget _buildNoticeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: _navyDark, size: 16),
              SizedBox(width: 6),
              Text(
                'Lưu ý thanh toán & Chỉ số',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _navyDark,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Chốt chỉ số điện nước vào ngày 28 - 30 hàng tháng bởi BQL.\n'
            '• Hạn thanh toán trước ngày 05 tháng tiếp theo để tránh phát sinh phí.\n'
            '• Hóa đơn và biên lai lưu trữ điện tử minh bạch, có thể xem lại bất kỳ lúc nào.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNote() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.security_rounded, size: 13, color: Color(0xFF94A3B8)),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Dữ liệu hóa đơn minh bạch • Lưu trữ an toàn 24/7 bởi Kiêu Giang',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 9. BOTTOM NAVIGATION BAR ───
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
        currentIndex: 2, // Hóa đơn active
        onTap: (index) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => TenantHomeScreen(initialTabIndex: index),
            ),
            (route) => false,
          );
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: _navyDark,
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
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.receipt_long_outlined),
                if (_unpaidCount > 0)
                  Positioned(
                    top: -2,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE11D48),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$_unpaidCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            activeIcon: const Icon(Icons.receipt_long_rounded),
            label: 'Hóa đơn',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            activeIcon: Icon(Icons.build_rounded),
            label: 'Sự cố',
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

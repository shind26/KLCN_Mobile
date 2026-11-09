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
  final String? maPhong;

  const InvoiceHistoryScreen({
    super.key,
    this.roomName = 'Nhà trọ Kiêu Giang',
    this.maHopDong,
    this.maPhong,
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
  Map<String, List<Map<String, dynamic>>> _phieuThuMap = {};

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
            final maKhach = kt['ma_khach']?.toString() ?? '';
            final chiTietList = await db
                .from('chi_tiet_hop_dong_khach_thue')
                .select('ma_hop_dong')
                .eq('ma_khach', maKhach);
            if (chiTietList.isNotEmpty) {
              final maHopDongs = (chiTietList as List)
                  .map((e) => e['ma_hop_dong']?.toString() ?? '')
                  .where((s) => s.isNotEmpty)
                  .toList();
              if (maHopDongs.isNotEmpty) {
                final hdRows = await db
                    .from('hop_dong')
                    .select('ma_hop_dong, trang_thai')
                    .inFilter('ma_hop_dong', maHopDongs)
                    .neq('trang_thai', 'Đã hủy')
                    .order('ngay_bd', ascending: false);
                if (hdRows.isNotEmpty) {
                  final activeRow = (hdRows as List).firstWhere((r) {
                    final st =
                        r['trang_thai']?.toString().toLowerCase().trim() ?? '';
                    return [
                      'còn hạn',
                      'đang thuê',
                      'hieuluc',
                      'chờ tl',
                      'chờ thanh lý',
                    ].contains(st);
                  }, orElse: () => hdRows.first);
                  contractCode = activeRow['ma_hop_dong']?.toString();
                }
              }
            }
          }
        }
      }

      // Nếu không xác định được hợp đồng của cư dân, hiển thị danh sách trống (không tải dữ liệu của phòng khác)
      if (contractCode == null || contractCode.isEmpty) {
        if (mounted) {
          setState(() {
            _allHoaDons = [];
            _chiTietMap = {};
            _chiSoDienNuoc = [];
            _phieuThuMap = {};
            _isLoading = false;
          });
        }
        return;
      }

      // 1. Tải hóa đơn CHÍNH XÁC theo mã hợp đồng của cư dân (phòng nào ra phòng nấy)
      final rows = await db
          .from('hoa_don')
          .select('*, chi_tiet_hoa_don(*)')
          .eq('ma_hop_dong', contractCode)
          .order('ngay_lap', ascending: false);

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

      // 2. Tải chỉ số điện nước CHÍNH XÁC theo hợp đồng này (không lấy của phòng khác)
      final chiSoRows = await db
          .from('chi_so_dien_nuoc')
          .select()
          .eq('ma_hop_dong', contractCode)
          .order('thang_nam', ascending: true);

      // Tải danh sách phiếu thu / giao dịch chuyển khoản thực tế từ bảng phieu_thu theo mã hóa đơn
      final List<String> maHds =
          list.map((e) => e.maHoaDon).where((s) => s.isNotEmpty).toList();
      final Map<String, List<Map<String, dynamic>>> ptMap = {};
      final List<String> redundantPtIds = [];
      try {
        if (maHds.isNotEmpty) {
          final ptRows = await db
              .from('phieu_thu')
              .select()
              .inFilter('ma_hoa_don', maHds)
              .order('ngay_thu', ascending: true);
          final Map<String, List<Map<String, dynamic>>> rawMap = {};
          for (final pt in (ptRows as List)) {
            final maHd = pt['ma_hoa_don']?.toString() ?? '';
            if (maHd.isNotEmpty) {
              rawMap
                  .putIfAbsent(maHd, () => [])
                  .add(Map<String, dynamic>.from(pt as Map));
            }
          }

          // Ràng buộc nghiệp vụ thanh toán và lọc chuẩn hóa theo từng hóa đơn
          for (final hd in list) {
            final maHd = hd.maHoaDon;
            final rawList = rawMap[maHd] ?? [];

            // 1. Nếu hóa đơn có trạng thái "Chưa thanh toán" hoặc không có phiếu thu nào
            if (hd.trangThai.toLowerCase().contains('chưa') || rawList.isEmpty) {
              ptMap[maHd] = [];
              continue;
            }

            // 2. Xác định tổng tiền chuẩn của hóa đơn từ hoa_don
            num tongTienHd = hd.tongTien;
            if (tongTienHd <= 0) {
              final dList = details[maHd] ?? [];
              if (dList.isNotEmpty) {
                tongTienHd = dList.fold<num>(
                  0,
                  (sum, item) =>
                      sum +
                      (num.tryParse(item['thanh_tien']?.toString() ?? '0') ?? 0),
                );
              } else {
                tongTienHd = hd.tongTienGoc;
              }
            }
            if (tongTienHd <= 0) tongTienHd = hd.tongTienGoc > 0 ? hd.tongTienGoc : 0;

            // 3. Phân loại các giao dịch hợp lệ (> 0đ)
            final validRaw = rawList.where((pt) {
              final amt =
                  num.tryParse(pt['so_tien_thu']?.toString() ?? '0') ?? 0;
              return amt > 0;
            }).toList();

            final List<Map<String, dynamic>> validReceipts = [];

            // Kiểm tra các giao dịch theo từng đợt (< tongTienHd, ví dụ: 2.100.000đ)
            final dotReceipts = validRaw.where((pt) {
              final amt =
                  num.tryParse(pt['so_tien_thu']?.toString() ?? '0') ?? 0;
              return amt < tongTienHd;
            }).toList();

            final num sumDots = dotReceipts.fold<num>(
              0,
              (sum, pt) =>
                  sum + (num.tryParse(pt['so_tien_thu']?.toString() ?? '0') ?? 0),
            );

            if (dotReceipts.length >= 2 && sumDots >= tongTienHd - 1000) {
              // Hóa đơn đã hoàn thành qua 2 đợt thanh toán (ví dụ: 2.100.000đ + 2.100.000đ = 4.200.000đ)
              // Chỉ giữ lại đúng 2 đợt hợp lệ đủ 100% hóa đơn, TUYỆT ĐỐI KHÔNG nhận thêm Đợt 3
              num currentSum = 0;
              for (final pt in dotReceipts) {
                final amt =
                    num.tryParse(pt['so_tien_thu']?.toString() ?? '0') ?? 0;
                if (validReceipts.length < 2 &&
                    currentSum + amt <= tongTienHd + 1000) {
                  validReceipts.add(pt);
                  currentSum += amt;
                } else {
                  final ptId = pt['ma_phieu_thu']?.toString() ?? '';
                  if (ptId.isNotEmpty) redundantPtIds.add(ptId);
                }
              }
              // Mọi bản ghi thừa khác (như giao dịch toàn phần 4.200.000đ chèn ngày 08/11) được gom để xóa
              for (final pt in validRaw) {
                if (!validReceipts.contains(pt)) {
                  final ptId = pt['ma_phieu_thu']?.toString() ?? '';
                  if (ptId.isNotEmpty && !redundantPtIds.contains(ptId)) {
                    redundantPtIds.add(ptId);
                  }
                }
              }
            } else {
              // Thanh toán 1 lần duy nhất (1 đợt) hoặc các đợt tích lũy không vượt quá tongTienHd
              num currentSum = 0;
              for (final pt in validRaw) {
                final amt =
                    num.tryParse(pt['so_tien_thu']?.toString() ?? '0') ?? 0;
                if (currentSum + amt <= tongTienHd + 1000) {
                  validReceipts.add(pt);
                  currentSum += amt;
                } else {
                  final ptId = pt['ma_phieu_thu']?.toString() ?? '';
                  if (ptId.isNotEmpty && !redundantPtIds.contains(ptId)) {
                    redundantPtIds.add(ptId);
                  }
                }
              }
            }

            ptMap[maHd] = validReceipts;
          }

          // Dọn sạch các bản ghi dư thừa / xung đột khỏi Supabase
          if (redundantPtIds.isNotEmpty) {
            for (final rId in redundantPtIds) {
              try {
                await db.from('phieu_thu').delete().eq('ma_phieu_thu', rId);
                debugPrint('[PHIEU_THU] Đã dọn bản ghi dư thừa khỏi Supabase: $rId');
              } catch (eDel) {
                debugPrint('[PHIEU_THU] Lỗi dọn bản ghi $rId: $eDel');
              }
            }
          }
        }
      } catch (ePt) {
        debugPrint('Lỗi tải phieu_thu: $ePt');
      }

      if (mounted) {
        setState(() {
          _allHoaDons = list;
          _chiTietMap = details;
          _chiSoDienNuoc = List<Map<String, dynamic>>.from(chiSoRows as List);
          _phieuThuMap = ptMap;
          _isLoading = false;

          // Nếu năm hiện tại chưa có dữ liệu mà có hóa đơn năm khác thì ưu tiên năm có hóa đơn
          if (list.isNotEmpty) {
            final targetY = _currentSelectedYearInt;
            final hasCurrent = list.any((h) => _getYearOfHoaDon(h) == targetY);
            if (!hasCurrent) {
              final firstY = _getYearOfHoaDon(list.first);
              if (firstY != null) {
                _selectedYear = 'Năm $firstY';
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch sử hóa đơn: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── HÀM BỔ TRỢ XÁC ĐỊNH NĂM THỰC TẾ ───
  int? _getYearOfHoaDon(HoaDonModel hd) {
    final tn = hd.thangNam;
    if (tn.contains('/')) {
      final y = int.tryParse(tn.split('/').last.trim());
      if (y != null) return y;
    }
    if (hd.ngayLap.isNotEmpty) {
      try {
        return DateTime.parse(hd.ngayLap).year;
      } catch (_) {
        final parts = hd.ngayLap.split('/');
        if (parts.length == 3) {
          final y = int.tryParse(parts[2].trim());
          if (y != null) return y;
        }
      }
    }
    if (hd.hanDongTien.isNotEmpty) {
      try {
        return DateTime.parse(hd.hanDongTien).year;
      } catch (_) {
        final parts = hd.hanDongTien.split('/');
        if (parts.length == 3) {
          final y = int.tryParse(parts[2].trim());
          if (y != null) return y;
        }
      }
    }
    final match = RegExp(r'202[0-9]').firstMatch('${hd.thangNam} ${hd.maHoaDon} ${hd.ngayLap}');
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  int? _getYearOfChiSo(Map<String, dynamic> item) {
    final tn = item['thang_nam']?.toString() ?? '';
    if (tn.contains('/')) {
      final parts = tn.split('/');
      final y = int.tryParse(parts.last.trim());
      if (y != null) return y;
    }
    final ngayGhi = item['ngay_ghi']?.toString() ?? '';
    if (ngayGhi.isNotEmpty) {
      try {
        return DateTime.parse(ngayGhi).year;
      } catch (_) {}
    }
    final match = RegExp(r'202[0-9]').firstMatch(tn);
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  int get _currentSelectedYearInt {
    final match = RegExp(r'\d{4}').firstMatch(_selectedYear);
    return match != null ? int.parse(match.group(0)!) : 2026;
  }

  List<String> get _availableYears {
    final Set<int> years = {2024, 2025, 2026};
    for (final hd in _allHoaDons) {
      final y = _getYearOfHoaDon(hd);
      if (y != null) years.add(y);
    }
    for (final cs in _chiSoDienNuoc) {
      final y = _getYearOfChiSo(cs);
      if (y != null) years.add(y);
    }
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted.map((y) => 'Năm $y').toList();
  }

  // Danh sách hóa đơn thuộc đúng năm đang chọn
  List<HoaDonModel> get _hoaDonsInSelectedYear {
    final targetYear = _currentSelectedYearInt;
    return _allHoaDons.where((h) {
      final y = _getYearOfHoaDon(h);
      return y == targetYear;
    }).toList();
  }

  int get _paidCount => _hoaDonsInSelectedYear
      .where((h) => h.trangThai == 'Đã thanh toán')
      .length;

  int get _unpaidCount => _hoaDonsInSelectedYear
      .where((h) => h.trangThai != 'Đã thanh toán' && h.trangThai != 'Chờ gửi')
      .length;

  // Danh sách chỉ số điện nước thuộc đúng năm đang chọn
  List<Map<String, dynamic>> get _chiSoDienNuocInSelectedYear {
    final targetYear = _currentSelectedYearInt;
    return _chiSoDienNuoc.where((cs) {
      final y = _getYearOfChiSo(cs);
      return y == targetYear;
    }).toList();
  }

  double get _avgElectricity {
    final list = _chiSoDienNuocInSelectedYear;
    if (list.isEmpty) return 0.0;
    final total = list.fold<double>(0.0, (sum, item) {
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
    return total / list.length;
  }

  double get _avgWater {
    final list = _chiSoDienNuocInSelectedYear;
    if (list.isEmpty) return 0.0;
    final total = list.fold<double>(0.0, (sum, item) {
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
    return total / list.length;
  }

  List<HoaDonModel> get _filteredList {
    final inYear = _hoaDonsInSelectedYear;
    if (_selectedFilterIndex == 1) {
      // Tab 'Chưa thanh toán': chỉ hiện hóa đơn đã được gửi (không tính 'Chờ gửi')
      return inYear
          .where(
            (h) => h.trangThai != 'Đã thanh toán' && h.trangThai != 'Chờ gửi',
          )
          .toList();
    }
    if (_selectedFilterIndex == 2) {
      return inYear.where((h) => h.trangThai == 'Đã thanh toán').toList();
    }
    return inYear;
  }

  num get _totalSpending => _hoaDonsInSelectedYear.fold<num>(0, (sum, item) {
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
                  value: _availableYears.contains(_selectedYear)
                      ? _selectedYear
                      : _availableYears.first,
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
                  items: _availableYears.map((y) {
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
      'Tất cả (${_hoaDonsInSelectedYear.length})',
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
                  color: _hoaDonsInSelectedYear.isEmpty
                      ? const Color(0xFFF1F5F9)
                      : (_unpaidCount == 0
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFFE4E6)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _hoaDonsInSelectedYear.isEmpty
                          ? Icons.info_outline_rounded
                          : (_unpaidCount == 0
                              ? Icons.check_circle_rounded
                              : Icons.access_time_filled_rounded),
                      color: _hoaDonsInSelectedYear.isEmpty
                          ? const Color(0xFF64748B)
                          : (_unpaidCount == 0
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE11D48)),
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _hoaDonsInSelectedYear.isEmpty
                          ? 'Chưa có hóa đơn'
                          : (_unpaidCount == 0
                              ? 'Đã quyết toán hết'
                              : 'Còn $_unpaidCount kỳ nợ'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: _hoaDonsInSelectedYear.isEmpty
                            ? const Color(0xFF64748B)
                            : (_unpaidCount == 0
                                ? const Color(0xFF16A34A)
                                : const Color(0xFFE11D48)),
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
                  'Đã đóng: $_paidCount/${_hoaDonsInSelectedYear.length} kỳ',
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
    final list = _chiSoDienNuocInSelectedYear;

    if (list.isNotEmpty) {
      // Chỉ lấy tối đa 5 tháng gần nhất để tránh tràn màn hình
      final displayData = list.length > 5
          ? list.sublist(list.length - 5)
          : list;

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
    }

    final bool hasData = barWidgets.isNotEmpty;

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
          Row(
            children: [
              const Icon(Icons.query_stats_rounded, color: _navyDark, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Biểu đồ chỉ số điện $_selectedYear',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Đơn vị: kWh',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (hasData) ...[
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
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Text(
                'Chưa có dữ liệu chỉ số điện trong $_selectedYear',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
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

  String _formatTransactionDate(String? raw) {
    if (raw == null || raw.isEmpty) return '30/10/2026 • 10:55';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year.toString();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year • $hour:$minute';
    } catch (_) {
      return raw;
    }
  }

  // ─── 6. BILL LIST HEADER ───
  Widget _buildBillListHeader() {
    return Row(
      children: [
        const Text(
          'Lịch sử giao dịch đóng tiền phòng',
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
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 40,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 10),
            Text(
              'Không tìm thấy hóa đơn nào trong $_selectedYear',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Các hóa đơn phát sinh trong $_selectedYear sẽ tự động hiển thị tại đây.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
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
    final details = _chiTietMap[hd.maHoaDon] ?? [];
    final receipts = _phieuThuMap[hd.maHoaDon] ?? [];
    final int soDotThucTe = receipts.length;
    final bool hasReceipts = receipts.isNotEmpty;

    // Hóa đơn chỉ coi là đã thanh toán khi không phải "Chưa thanh toán" và có phiếu thu hoặc DB đã cập nhật
    final bool isUnpaidStatus = hd.trangThai.toLowerCase().contains('chưa');
    final bool isPaid = !isUnpaidStatus &&
        ((hd.trangThai == 'Đã thanh toán') || hasReceipts);

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
    if (billTotal <= 0) billTotal = hd.tongTienGoc > 0 ? hd.tongTienGoc : 0;

    // Tính tổng tiền thực tế đã thu từ các phiếu thu trong database
    // TUYỆT ĐỐI KHÔNG vượt quá tổng tiền của hóa đơn
    num totalPaidFromReceipts = receipts.fold<num>(
      0,
      (sum, r) =>
          sum + (num.tryParse(r['so_tien_thu']?.toString() ?? '0') ?? 0),
    );
    if (totalPaidFromReceipts > billTotal) {
      totalPaidFromReceipts = billTotal;
    }

    // Tiêu đề phụ dưới mã hóa đơn: Gọn gàng, tránh rớt dòng
    String headerSubtitle;
    if (soDotThucTe > 1) {
      headerSubtitle = 'Mã HĐ: #${hd.maHoaDon} • $soDotThucTe đợt';
    } else {
      headerSubtitle = 'Mã HĐ: #${hd.maHoaDon}';
    }

    // Huy hiệu trạng thái trên header: Hoàn toàn động theo dữ liệu thực tế
    String badgeText;
    Color badgeColor;
    Color badgeBg;
    Color badgeBorder;
    IconData badgeIcon;

    if (soDotThucTe > 1) {
      badgeText = 'Đã thu $soDotThucTe đợt';
      badgeColor = const Color(0xFF15803D);
      badgeBg = const Color(0xFFDCFCE7);
      badgeBorder = const Color(0xFF86EFAC);
      badgeIcon = Icons.check_circle_rounded;
    } else if (soDotThucTe == 1 || isPaid) {
      badgeText = 'Đã thanh toán';
      badgeColor = const Color(0xFF15803D);
      badgeBg = const Color(0xFFDCFCE7);
      badgeBorder = const Color(0xFF86EFAC);
      badgeIcon = Icons.check_circle_rounded;
    } else {
      badgeText = 'Chưa thanh toán';
      badgeColor = const Color(0xFFD97706);
      badgeBg = const Color(0xFFFEF3C7);
      badgeBorder = const Color(0xFFFDE68A);
      badgeIcon = Icons.access_time_filled_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isPaid ? const Color(0xFFE2E8F0) : const Color(0xFFBAE6FD),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1. HEADER KỲ HÓA ĐƠN & HUY HIỆU NGÂN HÀNG ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: isPaid ? const Color(0xFFF8FAFC) : const Color(0xFFF0F9FF),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isPaid
                        ? Icons.account_balance_wallet_rounded
                        : Icons.pending_actions_rounded,
                    size: 18,
                    color: isPaid
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(width: 10),
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
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        headerSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: badgeBorder,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        badgeIcon,
                        size: 12,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── 2. DANH SÁCH GIAO DỊCH CHUYỂN KHOẢN TỪNG ĐỢT (BANKING STATEMENT STYLE) ──
          if (hasReceipts) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: const [
                  Icon(
                    Icons.history_edu_rounded,
                    size: 14,
                    color: Color(0xFF09638E),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Lịch sử giao dịch',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF09638E),
                    ),
                  ),
                ],
              ),
            ),
            for (int i = 0; i < receipts.length; i++) ...[
              _buildTransactionItem(
                receipt: receipts[i],
                hd: hd,
                dotIndex: i + 1,
                totalDots: receipts.length,
              ),
              if (i < receipts.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: Color(0xFFF1F5F9)),
                ),
            ],
          ] else ...[
            // Empty state: Khi hóa đơn chưa thanh toán hoặc chưa có bản ghi giao dịch nào
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      size: 20,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chưa có giao dịch thanh toán nào cho hóa đơn này',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF475569),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Hóa đơn đang chờ thanh toán. Sau khi bạn chuyển khoản thành công, giao dịch sẽ được lưu lại tại đây.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── 3. THẺ TỔNG TIỀN VÀ BẢNG KÊ CHI TIẾT ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Khối tổng tiền
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F6FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            soDotThucTe > 1
                                ? 'Tổng tiền đã thu ($soDotThucTe đợt):'
                                : 'Tổng tiền hóa đơn:',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            isPaid
                                ? 'Đã hoàn tất thanh toán 100%'
                                : 'Hạn đóng: ${hd.hanDongTienFormatted}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isPaid
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFE11D48),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        FormatUtils.currency(
                          (hasReceipts && totalPaidFromReceipts > 0)
                              ? totalPaidFromReceipts
                              : billTotal,
                        ),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: _navyDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Chi tiết các khoản thu
                if (details.isNotEmpty) ...[
                  for (final item in details) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: _buildLineItemRow(
                        item['ten_khoan_thu']?.toString() ??
                            item['khoan_muc']?.toString() ??
                            'Khoản thu',
                        num.tryParse(item['thanh_tien']?.toString() ?? '0') ??
                            0,
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

                if (!isPaid) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PaymentScreen(
                              hoaDon: hd,
                              tenPhong: widget.roomName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                      label: const Text(
                        'Thanh Toán Ngay (VietQR)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navyDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem({
    required Map<String, dynamic> receipt,
    required HoaDonModel hd,
    required int dotIndex,
    required int totalDots,
  }) {
    final amount =
        num.tryParse(receipt['so_tien_thu']?.toString() ?? '0') ?? 0;
    final maGD = receipt['ma_tra_cuu']?.toString() ??
        receipt['ma_phieu_thu']?.toString() ??
        'FT${receipt['ma_phieu_thu']}';
    final hinhThuc =
        receipt['hinh_thuc']?.toString() ?? 'Chuyển khoản MB Bank';
    final ngayThuFormatted =
        _formatTransactionDate(receipt['ngay_thu']?.toString());
    final titleDot = totalDots > 1
        ? 'Thanh toán đợt $dotIndex'
        : 'Thanh toán trọn gói';
    final tenDotStr =
        totalDots > 1 ? 'Đợt $dotIndex / $totalDots' : 'Kỳ ${hd.thangNam}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF5FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Color(0xFF09638E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleDot,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _textDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '- ${FormatUtils.currency(amount)}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF09638E),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$ngayThuFormatted • $hinhThuc',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Thành công',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
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
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFEDF2F7)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_2_rounded,
                        size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Mã GD: #$maGD',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentCompletedScreen(
                        hoaDon: hd,
                        tenPhong: widget.roomName,
                        bankName: 'MB Bank (Quân Đội)',
                        transactionTime: ngayThuFormatted,
                        amountPaid: amount,
                        tenDot: 'Hóa đơn $tenDotStr',
                        transactionRef: maGD,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.receipt_rounded, size: 13),
                label: Text(
                  totalDots > 1
                      ? 'Xem biên lai Đợt $dotIndex'
                      : 'Xem biên lai',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE2E8F0),
                  foregroundColor: _navyDark,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  minimumSize: const Size(0, 30),
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
      iconColor = const Color(0xFF09638E);
    } else if (lower.contains('nước')) {
      icon = Icons.water_drop_outlined;
      iconColor = const Color(0xFF0284C7);
    } else if (lower.contains('wifi') ||
        lower.contains('mạng') ||
        lower.contains('internet')) {
      icon = Icons.wifi_rounded;
      iconColor = const Color(0xFF6366F1);
    } else if (lower.contains('xe') || lower.contains('gửi xe')) {
      icon = Icons.two_wheeler_rounded;
      iconColor = const Color(0xFF8B5CF6);
    } else if (lower.contains('rác') || lower.contains('vệ sinh')) {
      icon = Icons.delete_outline_rounded;
      iconColor = const Color(0xFF059669);
    } else if (lower.contains('dịch vụ')) {
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

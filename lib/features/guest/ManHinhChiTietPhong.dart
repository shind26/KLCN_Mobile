import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhThongSoPhong.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhDichVu.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhDatPhong.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietChuyenPhong.dart';
import 'package:nhatro_kieugiang/core/widgets/LoadingMeoMeo.dart';
import 'package:nhatro_kieugiang/core/services/DichVuDatCoc.dart';
import 'package:nhatro_kieugiang/core/utils/LienHeHelper.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

class RoomDetailScreen extends StatefulWidget {
  final RoomModel room;
  final bool isTransferMode;
  final String? currentRoomNumber;
  final num? currentPrice;
  final VoidCallback? onSelectTransfer;

  const RoomDetailScreen({
    super.key,
    required this.room,
    this.isTransferMode = false,
    this.currentRoomNumber,
    this.currentPrice,
    this.onSelectTransfer,
  });

  @override
  State<RoomDetailScreen> createState() => _RoomDetailScreenState();
}

class _RoomDetailScreenState extends State<RoomDetailScreen> {
  bool _isFavorite = false;
  List<ThongSoPhongModel> _thongSo = [];
  bool _loadingSpec = true;
  List<DichVuModel> _dichVuList = [];

  @override
  void initState() {
    super.initState();
    _fetchThongSo();
    _fetchDichVu();
  }

  Future<void> _fetchDichVu() async {
    try {
      final resp = await Supabase.instance.client
          .from('dich_vu')
          .select()
          .order('ma_dich_vu');
      if (resp is List && resp.isNotEmpty) {
        final list = resp
            .map((e) => DichVuModel.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _dichVuList = list;
          });
        }
      }
    } catch (_) {}
  }

  // ===== ICON MAP: Thông số phòng =====
  static const Map<String, IconData> _specIconMap = {
    'Diện tích': Icons.straighten_rounded,
    'Sức chứa': Icons.groups_rounded,
    'Hướng': Icons.explore_rounded,
    'Kiểu kết cấu': Icons.architecture_rounded,
    'kết cấu': Icons.architecture_rounded,
    'Loại phòng': Icons.meeting_room_rounded,
    'Vị trí': Icons.apartment_rounded,
    'Tầng': Icons.layers_rounded,
    'Cửa sổ': Icons.window_rounded,
    'Ban công': Icons.balcony_rounded,
  };

  Color _colorForSpec(String tenThongSo) {
    final lower = tenThongSo.toLowerCase();
    if (lower.contains('diện tích')) return const Color(0xFFE0F2FE);
    if (lower.contains('sức chứa') || lower.contains('người'))
      return const Color(0xFFDCFCE7);
    if (lower.contains('kết cấu') || lower.contains('gác'))
      return const Color(0xFFFEF3C7);
    if (lower.contains('vị trí') ||
        lower.contains('tầng') ||
        lower.contains('tòa'))
      return const Color(0xFFEDE9FE);
    if (lower.contains('hướng') ||
        lower.contains('cửa sổ') ||
        lower.contains('ban công'))
      return const Color(0xFFFFEDD5);
    return const Color(0xFFEBF5FA);
  }

  Color _iconColorForSpec(String tenThongSo) {
    final lower = tenThongSo.toLowerCase();
    if (lower.contains('diện tích')) return const Color(0xFF0284C7);
    if (lower.contains('sức chứa') || lower.contains('người'))
      return const Color(0xFF16A34A);
    if (lower.contains('kết cấu') || lower.contains('gác'))
      return const Color(0xFFD97706);
    if (lower.contains('vị trí') ||
        lower.contains('tầng') ||
        lower.contains('tòa'))
      return const Color(0xFF7C3AED);
    if (lower.contains('hướng') ||
        lower.contains('cửa sổ') ||
        lower.contains('ban công'))
      return const Color(0xFFEA580C);
    return const Color(0xFF09638E);
  }

  // ===== ICON MAP: Tiện ích/Nội thất =====
  static const Map<String, IconData> _amenityIconMap = {
    'Máy lạnh': Icons.ac_unit_rounded,
    'Điều hòa': Icons.ac_unit_rounded,
    'Inverter': Icons.ac_unit_rounded,
    'Tủ lạnh': Icons.kitchen_rounded,
    'Nước nóng': Icons.hot_tub_rounded,
    'Ariston': Icons.hot_tub_rounded,
    'Vòi hoa sen': Icons.shower_rounded,
    'Bếp': Icons.soup_kitchen_rounded,
    'Hút mùi': Icons.air_rounded,
    'Ban công': Icons.balcony_rounded,
    'vân tay': Icons.fingerprint_rounded,
    'Khóa vân tay': Icons.fingerprint_rounded,
    'thẻ từ': Icons.credit_card_rounded,
    'Camera': Icons.videocam_rounded,
    'Tủ áo': Icons.door_sliding_rounded,
    'Máy giặt': Icons.local_laundry_service_rounded,
    'Sân phơi': Icons.wb_sunny_rounded,
    'sân phơi': Icons.wb_sunny_rounded,
    'Wifi': Icons.wifi_rounded,
    'Internet': Icons.wifi_rounded,
    'Giường': Icons.bed_rounded,
    'nệm': Icons.bed_rounded,
    'Bàn làm việc': Icons.desk_rounded,
    'Bàn học': Icons.desk_rounded,
    'Kệ sách': Icons.menu_book_rounded,
    'Sofa': Icons.chair_rounded,
    'bàn trà': Icons.table_restaurant_rounded,
    'Gương': Icons.face_retouching_natural_rounded,
    'Cửa sổ': Icons.window_rounded,
    'Thang máy': Icons.elevator_rounded,
    'Bảo vệ': Icons.security_rounded,
    'Xe': Icons.two_wheeler_rounded,
    'Hầm xe': Icons.garage_rounded,
    'Quạt': Icons.toys_rounded,
    'Tivi': Icons.tv_rounded,
    'Bồn rửa': Icons.countertops_rounded,
    'Cửa 2 lớp': Icons.sensor_door_rounded,
    'an toàn': Icons.verified_user_rounded,
    'Gác': Icons.stairs_rounded,
    'kệ': Icons.inventory_2_rounded,
  };

  // Màu nền icon theo nhóm tiện ích
  Color _colorForAmenity(String item) {
    final lower = item.toLowerCase();
    if (lower.contains('lạnh') || lower.contains('inverter'))
      return const Color(0xFFDBEAFE);
    if (lower.contains('bếp') || lower.contains('hút mùi'))
      return const Color(0xFFFFEDD5);
    if (lower.contains('nước nóng') ||
        lower.contains('vòi') ||
        lower.contains('ariston'))
      return const Color(0xFFCCFBF1);
    if (lower.contains('wifi') || lower.contains('internet'))
      return const Color(0xFFF0FDF4);
    if (lower.contains('vân tay') ||
        lower.contains('camera') ||
        lower.contains('thẻ từ') ||
        lower.contains('an toàn') ||
        lower.contains('bảo vệ'))
      return const Color(0xFFEDE9FE);
    if (lower.contains('máy giặt') || lower.contains('sân phơi'))
      return const Color(0xFFE0F2FE);
    if (lower.contains('tủ lạnh')) return const Color(0xFFE0F2FE);
    if (lower.contains('giường') ||
        lower.contains('nệm') ||
        lower.contains('sofa'))
      return const Color(0xFFFCE7F3);
    if (lower.contains('quạt')) return const Color(0xFFF0FDF4);
    if (lower.contains('gác') ||
        lower.contains('kệ') ||
        lower.contains('bàn') ||
        lower.contains('tủ áo'))
      return const Color(0xFFFFF7ED);
    return const Color(0xFFEBF5FA);
  }

  // Màu icon theo nhóm tiện ích
  Color _iconColorForAmenity(String item) {
    final lower = item.toLowerCase();
    if (lower.contains('lạnh') || lower.contains('inverter'))
      return const Color(0xFF3B82F6);
    if (lower.contains('bếp') || lower.contains('hút mùi'))
      return const Color(0xFFEA580C);
    if (lower.contains('nước nóng') ||
        lower.contains('vòi') ||
        lower.contains('ariston'))
      return const Color(0xFF0D9488);
    if (lower.contains('wifi') || lower.contains('internet'))
      return const Color(0xFF16A34A);
    if (lower.contains('vân tay') ||
        lower.contains('camera') ||
        lower.contains('thẻ từ') ||
        lower.contains('an toàn') ||
        lower.contains('bảo vệ'))
      return const Color(0xFF7C3AED);
    if (lower.contains('máy giặt') || lower.contains('sân phơi'))
      return const Color(0xFF0284C7);
    if (lower.contains('tủ lạnh')) return const Color(0xFF0369A1);
    if (lower.contains('giường') ||
        lower.contains('nệm') ||
        lower.contains('sofa'))
      return const Color(0xFFDB2777);
    if (lower.contains('quạt')) return const Color(0xFF059669);
    return const Color(0xFF09638E);
  }

  Future<void> _fetchThongSo() async {
    try {
      final resp = await Supabase.instance.client
          .from('thong_so_phong')
          .select()
          .eq('ma_phong', widget.room.maPhong)
          .order('ma_thong_so');

      if (resp is List) {
        final list = resp
            .map((e) => ThongSoPhongModel.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted)
          setState(() {
            _thongSo = list;
            _loadingSpec = false;
          });
        return;
      }
    } catch (_) {}
    // Fallback: build from room model
    if (mounted) {
      setState(() {
        _thongSo = [
          ThongSoPhongModel(
            maThongSo: 'DT',
            maPhong: widget.room.maPhong,
            tenThongSo: 'Diện tích',
            giaTri: '${widget.room.dienTich} m²',
            ghiChuPhu: 'Tiêu chuẩn',
          ),
          ThongSoPhongModel(
            maThongSo: 'SC',
            maPhong: widget.room.maPhong,
            tenThongSo: 'Sức chứa',
            giaTri: widget.room.moTaNgan.isNotEmpty
                ? widget.room.moTaNgan
                : '2 - 3 người',
            ghiChuPhu: 'Phù hợp SV & Đi làm',
          ),
          ThongSoPhongModel(
            maThongSo: 'KC',
            maPhong: widget.room.maPhong,
            tenThongSo: 'Kiểu kết cấu',
            giaTri: 'Gác đúc cao',
            ghiChuPhu: 'Không đụng đầu',
          ),
        ];
        _loadingSpec = false;
      });
    }
  }

  IconData _iconForSpec(String tenThongSo) {
    for (final key in _specIconMap.keys) {
      if (tenThongSo.contains(key)) return _specIconMap[key]!;
    }
    return Icons.info_outline_rounded;
  }

  IconData _iconForAmenity(String item) {
    for (final key in _amenityIconMap.keys) {
      if (item.contains(key)) return _amenityIconMap[key]!;
    }
    return Icons.check_circle_outline_rounded;
  }

  String _formatCurrency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.') + 'đ';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FA),
      body: Stack(
        children: [
          // Scrollable content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ====== SLIVER APP BAR ======
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                elevation: 0.5,
                leading: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  ),
                ),
                title: Text(
                  widget.isTransferMode
                      ? 'Chi Tiết Phòng Chuyển'
                      : 'Chi Tiết Phòng',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                centerTitle: true,
                actions: [
                  GestureDetector(
                    onTap: () {},
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.ios_share_rounded, size: 20),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _isFavorite = !_isFavorite),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16, left: 4),
                      child: Icon(
                        _isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 22,
                        color: _isFavorite
                            ? Colors.red
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),

              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ====== LOCATION BADGE ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.apartment_rounded,
                            size: 14,
                            color: Color(0xFF09638E),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${room.toaNha} • Nhà trọ Kiêu Giang 1',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF09638E),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ====== IMAGE GALLERY ======
                    Stack(
                      children: [
                        Image.network(
                          room.hinhAnh,
                          height: 240,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 240,
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
                                  right: -20,
                                  bottom: -20,
                                  child: Icon(
                                    Icons.apartment_rounded,
                                    size: 150,
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.meeting_room_rounded,
                                        size: 38,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      room.tenHienThi,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Kiêu Giang House • ${room.toaNha} • ${room.dienTich}m²',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Top badges
                        Positioned(
                          top: 12,
                          left: 12,
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
                              children: const [
                                Icon(
                                  Icons.star_rounded,
                                  size: 13,
                                  color: Color(0xFFF59E0B),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Phòng tiêu biểu',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF0284C7,
                              ).withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '● Sẵn sàng dọn vào ngay',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                        // Bottom: image count & 360 badge
                        Positioned(
                          bottom: 10,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              '1 / 4 ảnh thực tế',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.panorama_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Ảnh góc rộng 360°',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 0),

                    // ====== MAIN CARD: Tên phòng + thông tin ======
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.tenHienThi.replaceAll(' • ', ' • '),
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),

                          // Địa chỉ
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${room.toaNha} • Tầng ${room.tang} • Nhà trọ Kiêu Giang 1 (Đường Số 8, Bình Thạnh)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Rating row
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${room.danhGia}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '(${room.soDanhGia} đánh giá)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Chính chủ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Price box (2 columns)
                          Row(
                            children: [
                              Expanded(
                                child: _buildPriceBox(
                                  label: 'Giá thuê niêm yết',
                                  price: _formatCurrency(room.giaThue),
                                  sub: '/tháng',
                                  bgColor: const Color(0xFFEBF5FA),
                                  priceColor: const Color(0xFF09638E),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPriceBox(
                                  label: 'Tiền cọc an tâm',
                                  price: _formatCurrency(
                                    room.tienDatCoc > 0
                                        ? room.tienDatCoc
                                        : room.giaThue,
                                  ),
                                  sub: '(Bảo toàn hợp đồng)',
                                  bgColor: const Color(0xFFF8FAFC),
                                  priceColor: const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          if (widget.isTransferMode &&
                              widget.currentPrice != null) ...[
                            const SizedBox(height: 12),
                            _buildTransferComparisonCard(room),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ====== THÔNG SỐ PHÒNG ======
                    _buildSection(
                      title: 'Thông số phòng',
                      trailing: 'Quy chuẩn tiêu chuẩn',
                      content: _loadingSpec
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: LoadingMeoMeo(
                                  compact: true,
                                  size: 60,
                                  message: 'Đang tải thông số...',
                                ),
                              ),
                            )
                          : _buildSpecGrid(_thongSo),
                    ),

                    const SizedBox(height: 10),

                    // ====== TIỆN NGHI & NỘI THẤT ======
                    _buildSection(
                      title: 'Tiện nghi & Nội thất sẵn có',
                      trailing:
                          '${<String>{...room.noiThatSanCo, ...room.tienIch}.length} hạng mục',
                      trailingBgColor: const Color(0xFF09638E),
                      content: _buildAmenitiesGrid(
                        <String>{
                          ...room.noiThatSanCo,
                          ...room.tienIch,
                        }.toList(),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ====== BẢNG CHI PHÍ DỊCH VỤ MINH BẠCH ======
                    _buildSection(
                      title: 'Bảng chi phí dịch vụ minh bạch',
                      trailingIcon: Icons.verified_outlined,
                      content: Column(
                        children: () {
                          if (_dichVuList.isNotEmpty) {
                            return List.generate(_dichVuList.length, (index) {
                              final dv = _dichVuList[index];
                              IconData icon = Icons.receipt_long_rounded;
                              Color iconColor = const Color(0xFF09638E);
                              Color bgColor = const Color(0xFFEBF5FA);

                              final nameLower = dv.tenDichVu.toLowerCase();
                              if (nameLower.contains('điện')) {
                                icon = Icons.bolt_rounded;
                                iconColor = const Color(0xFFD97706);
                                bgColor = const Color(0xFFFEF3C7);
                              } else if (nameLower.contains('nước')) {
                                icon = Icons.water_drop_rounded;
                                iconColor = const Color(0xFF0284C7);
                                bgColor = const Color(0xFFE0F2FE);
                              } else if (nameLower.contains('wifi') ||
                                  nameLower.contains('internet')) {
                                icon = Icons.wifi_rounded;
                                iconColor = const Color(0xFF7C3AED);
                                bgColor = const Color(0xFFEDE9FE);
                              } else if (nameLower.contains('rác') ||
                                  nameLower.contains('vệ sinh')) {
                                icon = Icons.cleaning_services_rounded;
                                iconColor = const Color(0xFF0D9488);
                                bgColor = const Color(0xFFCCFBF1);
                              } else if (nameLower.contains('xe')) {
                                icon = Icons.two_wheeler_rounded;
                                iconColor = const Color(0xFF2563EB);
                                bgColor = const Color(0xFFDBEAFE);
                              }

                              final bool isFree = dv.donGia == 0;
                              final String priceStr = isFree
                                  ? 'Miễn phí'
                                  : _formatCurrency(dv.donGia);
                              final String unitStr = isFree
                                  ? ''
                                  : '/ ${dv.donViTinh}';

                              return _ServiceFeeRow(
                                icon: icon,
                                iconColor: iconColor,
                                bgColor: bgColor,
                                name: dv.tenDichVu,
                                sub: dv.ghiChu,
                                price: priceStr,
                                unit: unitStr,
                                isFree: isFree,
                                showDivider: index < _dichVuList.length - 1,
                              );
                            });
                          }

                          // Fallback mẫu
                          final fallback = [
                            {
                              'icon': Icons.bolt_rounded,
                              'iconColor': const Color(0xFFD97706),
                              'bgColor': const Color(0xFFFEF3C7),
                              'name': 'Điện tiêu thụ',
                              'sub': 'Công tơ điện tử riêng',
                              'price': '3.500 đ',
                              'unit': '/ kWh',
                              'isFree': false,
                            },
                            {
                              'icon': Icons.water_drop_rounded,
                              'iconColor': const Color(0xFF0284C7),
                              'bgColor': const Color(0xFFE0F2FE),
                              'name': 'Nước sinh hoạt',
                              'sub': 'Đồng hồ nước thủy cục riêng',
                              'price': '20.000 đ',
                              'unit': '/ m³',
                              'isFree': false,
                            },
                            {
                              'icon': Icons.wifi_rounded,
                              'iconColor': const Color(0xFF7C3AED),
                              'bgColor': const Color(0xFFEDE9FE),
                              'name': 'Wifi Mesh chuyên dụng',
                              'sub': 'Tốc độ cao mỗi tầng 1 modem',
                              'price': 'Miễn phí',
                              'unit': '',
                              'isFree': true,
                            },
                            {
                              'icon': Icons.cleaning_services_rounded,
                              'iconColor': const Color(0xFF0D9488),
                              'bgColor': const Color(0xFFCCFBF1),
                              'name': 'Rác & vệ sinh hành lang',
                              'sub': 'Lau dọn 3 lần/tuần',
                              'price': '50.000 đ',
                              'unit': '/ phòng / tháng',
                              'isFree': false,
                            },
                            {
                              'icon': Icons.two_wheeler_rounded,
                              'iconColor': const Color(0xFF2563EB),
                              'bgColor': const Color(0xFFDBEAFE),
                              'name': 'Phí gửi xe máy',
                              'sub': 'Free 02 xe • Hầm để xe bảo vệ 24/24',
                              'price': 'Miễn phí',
                              'unit': '',
                              'isFree': true,
                            },
                          ];

                          return List.generate(fallback.length, (index) {
                            final item = fallback[index];
                            return _ServiceFeeRow(
                              icon: item['icon'] as IconData,
                              iconColor: item['iconColor'] as Color,
                              bgColor: item['bgColor'] as Color,
                              name: item['name'] as String,
                              sub: item['sub'] as String,
                              price: item['price'] as String,
                              unit: item['unit'] as String,
                              isFree: item['isFree'] as bool,
                              showDivider: index < fallback.length - 1,
                            );
                          });
                        }(),
                      ),
                    ),

                    // Bottom padding cho bottom bar
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ],
          ),

          // ====== STICKY BOTTOM ACTION BAR CAO CẤP ======
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFFE2E8F0).withValues(alpha: 0.8),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  child: Row(
                    children: [
                      // Cột giá phòng trực quan
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                widget.isTransferMode
                                    ? Icons.swap_horiz_rounded
                                    : Icons.payments_outlined,
                                size: 12,
                                color: const Color(0xFF64748B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.isTransferMode
                                    ? 'GIÁ PHÒNG MỚI'
                                    : 'TỔNG TIỀN THUÊ',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _formatCurrency(room.giaThue),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0284C7),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const Text(
                                '/th',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),

                      if (!widget.isTransferMode) ...[
                        // Chat icon button
                        Material(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => LienHeHelper.moZaloChat(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFBAE6FD),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 19,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],

                      // Nút hành động chính cao cấp
                      Expanded(
                        child: widget.isTransferMode
                            ? Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF0284C7),
                                      Color(0xFF0369A1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF0284C7,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      if (widget.onSelectTransfer != null) {
                                        widget.onSelectTransfer!();
                                      } else {
                                        final diff =
                                            room.giaThue -
                                            (widget.currentPrice ?? 0);
                                        final isSameBuilding =
                                            room.toaNha.contains('2') ||
                                            room.toaNha.toLowerCase().contains(
                                              'kiêu giang 2',
                                            );
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => RoomTransferDetailScreen(
                                              targetRoom: {
                                                'maPhong': room.maPhong,
                                                'toaNha': room.toaNha,
                                                'isSameBuilding':
                                                    isSameBuilding,
                                                'tang': room.tang,
                                                'dienTich': room.dienTich,
                                                'giaThue': room.giaThue,
                                                'tienDatCoc':
                                                    room.tienDatCoc > 0
                                                    ? room.tienDatCoc
                                                    : room.giaThue,
                                                'dacDiem':
                                                    '${room.dienTich}m² • ${room.moTaNgan}',
                                                'highlight': diff == 0
                                                    ? 'Đồng giá'
                                                    : (diff > 0
                                                          ? '+${_formatCurrency(diff)}/tháng'
                                                          : '${_formatCurrency(diff)}/tháng'),
                                                'tagTang':
                                                    'Tầng ${room.tang} • ${room.toaNha}',
                                                'hinhAnh': room.hinhAnh,
                                                'tienIch': room.tienIch,
                                                'diffAmount': diff,
                                                'diffText': diff == 0
                                                    ? '0đ'
                                                    : '${_formatCurrency(diff)}/tháng',
                                                'roomModel': room,
                                              },
                                              currentRoomNumber:
                                                  widget.currentRoomNumber ??
                                                  'P.302',
                                              currentPrice:
                                                  widget.currentPrice ??
                                                  3200000,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.swap_horiz_rounded,
                                            size: 20,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              'Chọn chuyển phòng',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 15,
                                            color: Colors.white70,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient:
                                      (room.trangThai.trim().toLowerCase() ==
                                          'trống')
                                      ? const LinearGradient(
                                          colors: [
                                            Color(0xFF09638E),
                                            Color(0xFF0284C7),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFF94A3B8),
                                            Color(0xFF64748B),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (room.trangThai
                                                  .trim()
                                                  .toLowerCase() ==
                                              'trống')
                                          ? const Color(
                                              0xFF09638E,
                                            ).withValues(alpha: 0.35)
                                          : Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () async {
                                      String freshStatus = room.trangThai
                                          .trim()
                                          .toLowerCase();
                                      try {
                                        final pRes = await Supabase
                                            .instance
                                            .client
                                            .from('phong')
                                            .select('trang_thai')
                                            .eq('ma_phong', room.maPhong)
                                            .maybeSingle();
                                        if (pRes != null &&
                                            pRes['trang_thai'] != null) {
                                          freshStatus = pRes['trang_thai']
                                              .toString()
                                              .trim()
                                              .toLowerCase();
                                        }
                                      } catch (_) {}

                                      final isLocked =
                                          await DepositService.isRoomLocked(
                                            room.maPhong,
                                          );
                                      if (isLocked || freshStatus != 'trống') {
                                        if (context.mounted) {
                                          ThongBaoHelper.hienThongBao(
                                            context,
                                            tieuDe:
                                                'Phòng Đã Có Người / Đã Cọc',
                                            noiDung:
                                                'Phòng ${room.tenHienThi} hiện đang có người thuê hoặc đã có khách đặt cọc giữ chỗ trước. Vui lòng tham khảo các phòng trống khác bạn nhé!',
                                            type: ThongBaoType.canhBao,
                                          );
                                        }
                                        return;
                                      }
                                      if (!context.mounted) return;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BookingScreen(room: room),
                                        ),
                                      );
                                    },
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                (room.trangThai
                                                            .trim()
                                                            .toLowerCase() ==
                                                        'trống')
                                                    ? Icons
                                                          .calendar_month_rounded
                                                    : Icons.lock_clock_rounded,
                                                size: 18,
                                                color: Colors.white,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                (room.trangThai
                                                            .trim()
                                                            .toLowerCase() ==
                                                        'trống')
                                                    ? 'Đặt Lịch & Giữ Chỗ'
                                                    : 'Phòng Đã Có Khách Giữ Chỗ',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferComparisonCard(RoomModel room) {
    final curPrice = widget.currentPrice ?? 0;
    final diff = room.giaThue - curPrice;
    final isSame = diff == 0;
    final isCheaper = diff < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSame
            ? const Color(0xFFDCFCE7)
            : (isCheaper ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSame
              ? const Color(0xFF86EFAC)
              : (isCheaper ? const Color(0xFF7DD3FC) : const Color(0xFFFDE68A)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSame
                    ? Icons.check_circle_rounded
                    : (isCheaper
                          ? Icons.savings_rounded
                          : Icons.trending_up_rounded),
                color: isSame
                    ? const Color(0xFF16A34A)
                    : (isCheaper
                          ? const Color(0xFF0284C7)
                          : const Color(0xFFD97706)),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Đối chiếu chuyển từ ${widget.currentRoomNumber ?? "Phòng hiện tại"}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isSame
                        ? const Color(0xFF166534)
                        : (isCheaper
                              ? const Color(0xFF075985)
                              : const Color(0xFF92400E)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isSame
                ? '• Đồng giá thuê (${_formatCurrency(curPrice)}/tháng) - Không phải bù thêm tiền phòng.'
                : (isCheaper
                      ? '• Tiết kiệm ${_formatCurrency(-diff)}/tháng so với phòng cũ (${_formatCurrency(curPrice)}/tháng).'
                      : '• Chênh lệch +${_formatCurrency(diff)}/tháng so với phòng cũ (${_formatCurrency(curPrice)}/tháng).'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            '• Bảo lưu 100% tiền cọc hợp đồng cũ khi chuyển sang phòng này.',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBox({
    required String label,
    required String price,
    required String sub,
    required Color bgColor,
    required Color priceColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: priceColor,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    String? trailing,
    Color trailingBgColor = const Color(0xFFF1F5F9),
    IconData? trailingIcon,
    required Widget content,
  }) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: trailingBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: trailingBgColor == const Color(0xFF09638E)
                          ? Colors.white
                          : const Color(0xFF475569),
                    ),
                  ),
                ),
              if (trailingIcon != null)
                Icon(trailingIcon, size: 18, color: const Color(0xFF09638E)),
            ],
          ),
          const SizedBox(height: 14),
          content,
        ],
      ),
    );
  }

  // ===== BUILD SPEC GRID từ Supabase =====
  Widget _buildSpecGrid(List<ThongSoPhongModel> specs) {
    if (specs.isEmpty) return const SizedBox.shrink();

    // Chuẩn hóa danh sách để hiển thị cân đối
    final displaySpecs = List<ThongSoPhongModel>.from(specs);
    if (displaySpecs.length == 3) {
      final hasFloor = displaySpecs.any(
        (s) =>
            s.tenThongSo.toLowerCase().contains('tầng') ||
            s.tenThongSo.toLowerCase().contains('vị trí'),
      );
      if (!hasFloor) {
        displaySpecs.add(
          ThongSoPhongModel(
            maThongSo: 'VT',
            maPhong: widget.room.maPhong,
            tenThongSo: 'Vị trí & Tầng',
            giaTri: 'Tầng ${widget.room.tang} • ${widget.room.toaNha}',
            ghiChuPhu: 'An ninh, thoáng mát',
          ),
        );
      }
    }

    final rows = <Widget>[];
    for (int i = 0; i < displaySpecs.length; i += 2) {
      final left = displaySpecs[i];
      final right = i + 1 < displaySpecs.length ? displaySpecs[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(
              child: _buildSpecItem(
                icon: _iconForSpec(left.tenThongSo),
                iconColor: _iconColorForSpec(left.tenThongSo),
                bgColor: _colorForSpec(left.tenThongSo),
                label: left.tenThongSo,
                value: left.giaTri,
                subtitle: left.ghiChuPhu,
              ),
            ),
            if (right != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _buildSpecItem(
                  icon: _iconForSpec(right.tenThongSo),
                  iconColor: _iconColorForSpec(right.tenThongSo),
                  bgColor: _colorForSpec(right.tenThongSo),
                  label: right.tenThongSo,
                  value: right.giaTri,
                  subtitle: right.ghiChuPhu,
                ),
              ),
            ],
          ],
        ),
      );
      if (i + 2 < displaySpecs.length) {
        rows.add(const SizedBox(height: 10));
      }
    }
    return Column(children: rows);
  }

  Widget _buildSpecItem({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String value,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8F0F6), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF09638E),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildAmenitiesGrid(List<String> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Chưa có thông tin tiện ích',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(items.length, (index) {
        final item = items[index];
        final icon = _iconForAmenity(item);
        final bgColor = _colorForAmenity(item);
        final iconColor = _iconColorForAmenity(item);

        final cardWidth = (MediaQuery.of(context).size.width - 32 - 10) / 2;

        return SizedBox(
          width: cardWidth,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8F0F6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ====== WIDGET PHỤ: Hàng chi phí dịch vụ ======
class _ServiceFeeRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String name;
  final String sub;
  final String price;
  final String unit;
  final bool isFree;
  final bool showDivider;

  const _ServiceFeeRow({
    required this.icon,
    this.iconColor = const Color(0xFF09638E),
    this.bgColor = const Color(0xFFEBF5FA),
    required this.name,
    required this.sub,
    required this.price,
    required this.unit,
    this.isFree = false,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isFree)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF86EFAC),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: Color(0xFF16A34A),
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Miễn phí',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    if (unit.isNotEmpty)
                      Text(
                        unit,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 0.8, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}

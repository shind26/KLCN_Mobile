import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/core/utils/TienIchDinhDang.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhLichSuHoaDon.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhChiTietHopDong.dart';

/// Màn hình 4: Xác nhận gửi yêu cầu chuyển phòng thành công
/// Tóm tắt phiếu yêu cầu, tiến trình tiếp nhận & giữ phòng, hỗ trợ BQL, về trang chủ
class RoomTransferSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> targetRoom;
  final String currentRoomNumber;
  final num currentPrice;
  final String moveInDateFormatted;
  final String reason;
  final String note;
  final String? ticketCode;

  const RoomTransferSuccessScreen({
    super.key,
    required this.targetRoom,
    required this.currentRoomNumber,
    required this.currentPrice,
    required this.moveInDateFormatted,
    required this.reason,
    required this.note,
    this.ticketCode,
  });

  @override
  State<RoomTransferSuccessScreen> createState() =>
      _RoomTransferSuccessScreenState();
}

class _RoomTransferSuccessScreenState extends State<RoomTransferSuccessScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF09638E);
  static const _primaryDark = Color(0xFF064868);
  static const _bg = Color(0xFFF1F6FA);
  static const _textDark = Color(0xFF0F172A);

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _currentStatus = 'Chờ duyệt';
  String? _maHopDong;
  RealtimeChannel? _yccpRtChannel;
  Timer? _yccpPollTimer;
  bool _hasNotified = false;

  String? _maBienBan;
  bool _isInspectionDone = false;
  bool _hasAcceptedInspection = false;
  bool _hasDamage = false;
  num _damageFee = 0;
  num _utilityFee = 0;
  String? _damageNote;
  String? _lyDoChuyen;
  String _inspectorName = 'Ban Quản Lý Kiều Giang';
  List<Map<String, dynamic>> _roomAssets = [];
  Map<String, dynamic>? _targetRoomData;
  num? _tienCocBaoLuu;
  String? _thoiGianHen;
  String? _maPhongMoiFromDb;

  int _layTangTuMaPhong(String maPhong) {
    final match = RegExp(r'[A-Za-z]+(\d)').firstMatch(maPhong);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 1;
    }
    return 1;
  }

  String _formatDateString(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return 'Chưa xác định';
    try {
      final dt = DateTime.parse(dateStr.trim());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  void initState() {
    super.initState();
    _taiDanhSachTaiSanPhong();
    _taiThongTinPhongMoi();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _batDauLangNgheYccp();
  }

  Future<void> _taiThongTinPhongMoi([String? explicitMaPhong]) async {
    try {
      final client = Supabase.instance.client;
      final maPhongMoi = explicitMaPhong ?? _maPhongMoiFromDb ?? widget.targetRoom['maPhong']?.toString() ?? '';
      if (maPhongMoi.isNotEmpty) {
        final res = await client
            .from('phong')
            .select()
            .eq('ma_phong', maPhongMoi)
            .maybeSingle();
        if (res != null && mounted) {
          setState(() {
            _targetRoomData = res;
          });
        }
      }
    } catch (e) {
      debugPrint('[ROOM_TARGET] Lỗi tải thông tin phòng mới: $e');
    }
  }

  Future<void> _taiDanhSachTaiSanPhong() async {
    try {
      final client = Supabase.instance.client;
      final res = await client
          .from('tai_san')
          .select()
          .eq('ma_phong', widget.currentRoomNumber);

      if (res.isNotEmpty && mounted) {
        setState(() {
          _roomAssets = List<Map<String, dynamic>>.from(res);
        });
      }
    } catch (e) {
      debugPrint('[TAI_SAN] Lỗi tải tài sản phòng: $e');
    }
  }

  IconData _getIconForAsset(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('remote') || lowerName.contains('điều khiển')) {
      return Icons.settings_remote_rounded;
    } else if (lowerName.contains('tủ lạnh') || lowerName.contains('aqua') || lowerName.contains('sharp')) {
      return Icons.kitchen_rounded;
    } else if (lowerName.contains('máy lạnh') || lowerName.contains('điều hòa') || lowerName.contains('daikin') || lowerName.contains('casper')) {
      return Icons.ac_unit_rounded;
    } else if (lowerName.contains('nóng') || lowerName.contains('nước') || lowerName.contains('ariston')) {
      return Icons.water_drop_rounded;
    } else if (lowerName.contains('giường') || lowerName.contains('nệm')) {
      return Icons.bed_rounded;
    }
    return Icons.devices_other_rounded;
  }

  List<Map<String, dynamic>> _getEquipmentItems() {
    final List<Map<String, dynamic>> sourceAssets = _roomAssets.isNotEmpty
        ? _roomAssets
        : [
            {'ten_tai_san': 'Máy lạnh Inverter Daikin 1.5 HP', 'tinh_trang': 'Hoạt động tốt'},
            {'ten_tai_san': 'Tủ lạnh Aqua 140L Inverter', 'tinh_trang': 'Hoạt động tốt'},
            {'ten_tai_san': 'Bình nóng lạnh Ariston 20L', 'tinh_trang': 'Hoạt động tốt'},
            {'ten_tai_san': 'Giường gỗ sồi & Nệm cao su', 'tinh_trang': 'Bình thường'},
            {'ten_tai_san': 'Điều khiển (Remote) máy lạnh', 'tinh_trang': 'Hư hỏng nhẹ (Nứt màn hình)'},
          ];

    // 1. Trường hợp bình thường (không có hư hại hoặc chưa nghiệm thu)
    if (!_isInspectionDone || !_hasDamage || _damageFee <= 0) {
      return sourceAssets.map((ts) {
        final name = ts['ten_tai_san']?.toString() ?? ts['ten']?.toString() ?? 'Trang thiết bị';
        return {
          'ten': name,
          'icon': _getIconForAsset(name),
          'tinhTrang': _isInspectionDone ? 'Hoạt động tốt' : 'Bàn giao ban đầu',
          'isGood': true,
          'chiPhi': 0,
          'ghiChu': _isInspectionDone ? 'Đạt chuẩn bàn giao' : 'Chờ BQL kiểm tra',
        };
      }).toList();
    }

    // 2. Trường hợp có hư hại: Tìm DUY NHẤT thiết bị bị hư theo độ đặc trưng từ khóa
    final note = (_damageNote ?? '').toLowerCase().trim();
    int damagedIndex = -1;

    // Ưu tiên 1: Khớp chính xác nhất theo ghi chú hư hại từ BQL
    if (note.isNotEmpty) {
      for (int i = 0; i < sourceAssets.length; i++) {
        final name = (sourceAssets[i]['ten_tai_san']?.toString() ?? '').toLowerCase();
        if (note.contains('remote') || note.contains('điều khiển')) {
          if (name.contains('remote') || name.contains('điều khiển')) {
            damagedIndex = i;
            break;
          }
        } else if (note.contains('tủ lạnh')) {
          if (name.contains('tủ lạnh')) {
            damagedIndex = i;
            break;
          }
        } else if (note.contains('bình nóng') || note.contains('nước nóng') || note.contains('ariston')) {
          if (name.contains('bình nóng') || name.contains('nước nóng') || name.contains('ariston')) {
            damagedIndex = i;
            break;
          }
        } else if (note.contains('máy lạnh') || note.contains('điều hòa')) {
          if ((name.contains('máy lạnh') || name.contains('điều hòa')) && !name.contains('remote')) {
            damagedIndex = i;
            break;
          }
        } else if (note.contains('giường') || note.contains('nệm')) {
          if (name.contains('giường') || name.contains('nệm')) {
            damagedIndex = i;
            break;
          }
        }
      }
    }

    // Ưu tiên 2: Nếu ghi chú không chỉ đích danh, tìm thiết bị có tình trạng lỗi trong CSDL
    if (damagedIndex == -1) {
      for (int i = 0; i < sourceAssets.length; i++) {
        final dbStatus = (sourceAssets[i]['tinh_trang']?.toString() ?? '').toLowerCase();
        if (dbStatus.contains('hư') || dbStatus.contains('hỏng') || dbStatus.contains('nứt') || dbStatus.contains('vỡ')) {
          damagedIndex = i;
          break;
        }
      }
    }

    // Ưu tiên 3: Mặc định gán cho remote/linh kiện phụ
    if (damagedIndex == -1) {
      final remoteIdx = sourceAssets.indexWhere((ts) {
        final name = (ts['ten_tai_san']?.toString() ?? '').toLowerCase();
        return name.contains('remote') || name.contains('điều khiển');
      });
      damagedIndex = remoteIdx != -1 ? remoteIdx : sourceAssets.length - 1;
    }

    // 3. Phân bổ chi phí: CHỈ DUY NHẤT món tại damagedIndex bị trừ tiền, các món khác ĐẠT (0đ)
    final List<Map<String, dynamic>> result = [];
    for (int i = 0; i < sourceAssets.length; i++) {
      final ts = sourceAssets[i];
      final name = ts['ten_tai_san']?.toString() ?? ts['ten']?.toString() ?? 'Trang thiết bị';
      final dbStatus = ts['tinh_trang']?.toString() ?? 'Bình thường';
      final isThisItemDamaged = (i == damagedIndex);

      if (isThisItemDamaged) {
        result.add({
          'ten': name,
          'icon': _getIconForAsset(name),
          'tinhTrang': (dbStatus != 'Bình thường' && dbStatus != 'Hoạt động tốt')
              ? dbStatus
              : (_damageNote != null && _damageNote!.isNotEmpty ? _damageNote! : 'Có hư hại'),
          'isGood': false,
          'chiPhi': _damageFee.toInt(),
          'ghiChu': (_damageNote != null && _damageNote!.isNotEmpty)
              ? _damageNote!
              : 'Khấu trừ chi phí sửa chữa / thay thế linh kiện',
        });
      } else {
        result.add({
          'ten': name,
          'icon': _getIconForAsset(name),
          'tinhTrang': 'Hoạt động tốt',
          'isGood': true,
          'chiPhi': 0,
          'ghiChu': 'Đạt chuẩn bàn giao',
        });
      }
    }

    return result;
  }

  void _batDauLangNgheYccp() {
    try {
      final client = Supabase.instance.client;
      _yccpRtChannel = client.channel('public:yccp_realtime_${DateTime.now().millisecondsSinceEpoch}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'yeu_cau_chuyen_phong',
          callback: (payload) {
            _xuLyThayDoiRecord(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'phu_luc_hop_dong',
          callback: (payload) {
            _xuLyThayDoiRecord(payload.newRecord);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bien_ban_kiem_tra_phong',
          callback: (payload) {
            _xuLyThayDoiBienBan(payload.newRecord);
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('[CHUYEN_PHONG] Lỗi subscribe Realtime: $e');
    }

    _yccpPollTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) async {
      try {
        final client = Supabase.instance.client;
        // Lọc đúng theo mã yêu cầu của khách đang xem (nếu có)
        var query = client
            .from('yeu_cau_chuyen_phong')
            .select()
            .order('ngay_tao', ascending: false)
            .limit(1);
        if (widget.ticketCode != null && widget.ticketCode!.isNotEmpty) {
          query = client
              .from('yeu_cau_chuyen_phong')
              .select()
              .eq('ma_yeu_cau', widget.ticketCode!)
              .limit(1);
        }
        final res = await query;

        if (res.isNotEmpty) {
          _xuLyThayDoiRecord(res.first);
        }
      } catch (_) {}

      try {
        final client = Supabase.instance.client;
        final bbRes = await client
            .from('bien_ban_kiem_tra_phong')
            .select()
            .eq('ma_phong', widget.currentRoomNumber)
            .order('created_at', ascending: false)
            .limit(1);

        if (bbRes.isNotEmpty) {
          _xuLyThayDoiBienBan(bbRes.first);
        }
      } catch (_) {}
    });
  }

  void _xuLyThayDoiBienBan(Map<String, dynamic> bb) {
    if (bb.isEmpty || !mounted) return;
    setState(() {
      _maBienBan = bb['ma_bien_ban']?.toString();
      _isInspectionDone = true;
      _inspectorName = bb['nguoi_kiem_tra']?.toString() ?? _inspectorName;
      _damageFee = (bb['tien_khau_tru'] as num?)?.toDouble() ?? 0.0;
      _hasDamage = _damageFee > 0;
      _utilityFee = (bb['tien_dien_nuoc'] as num?)?.toDouble() ?? 0.0;
      _hasAcceptedInspection = (bb['trang_thai']?.toString() == 'Đã xác nhận');
    });
  }

  void _xuLyThayDoiRecord(Map<String, dynamic> record) {
    if (record.isEmpty || !mounted) return;
    final st = (record['trang_thai_tien_do'] ?? record['trang_thai'])?.toString() ?? '';
    final huHai = (record['tien_hu_hai_cu'] as num?)?.toDouble() ?? 0.0;
    final dienNuoc = (record['tien_dien_nuoc_cu'] as num?)?.toDouble() ?? 0.0;
    final bql = record['nguoi_don_bql']?.toString();
    final ghiChuHuHai = record['ghi_chu_hu_hai']?.toString() ?? record['chi_tiet_hu_hai']?.toString();
    final lyDoDb = record['ly_do_chuyen']?.toString();
    if (lyDoDb != null && lyDoDb.trim().isNotEmpty) {
      _lyDoChuyen = lyDoDb.trim();
    }
    final hdCode = record['ma_hop_dong_ht']?.toString();
    if (hdCode != null && hdCode.trim().isNotEmpty) {
      _maHopDong = hdCode.trim();
    }

    final tienCocBaoLuu = (record['tien_coc_bao_luu'] as num?)?.toDouble();
    final thoiGianHen = record['thoi_gian_hen']?.toString();
    final phongMoi = record['ma_phong_moi']?.toString();

    if (tienCocBaoLuu != null && _tienCocBaoLuu != tienCocBaoLuu) {
      _tienCocBaoLuu = tienCocBaoLuu;
    }
    if (thoiGianHen != null && thoiGianHen.isNotEmpty && _thoiGianHen != thoiGianHen) {
      _thoiGianHen = thoiGianHen;
    }
    if (phongMoi != null && phongMoi.isNotEmpty && _maPhongMoiFromDb != phongMoi) {
      _maPhongMoiFromDb = phongMoi;
      _taiThongTinPhongMoi(phongMoi);
    }

    // Bước 1 & 2: Tiếp nhận / BQL đang xử lý
    if (st == 'Chờ duyệt' || st == 'Đang xử lý') {
      setState(() {
        _currentStatus = st;
        _isInspectionDone = false;
        _hasAcceptedInspection = false;
        _damageFee = huHai;
        _hasDamage = huHai > 0;
        _utilityFee = dienNuoc;
        _damageNote = ghiChuHuHai;
        if (bql != null && bql.trim().isNotEmpty) {
          _inspectorName = bql;
        }
      });
    } else if (st == 'Đã kiểm tra' || st == 'Chờ khách xác nhận') {
      // Bước 2 hoàn tất -> Chuyển sang Bước 3 (Chờ khách xác nhận)
      setState(() {
        _currentStatus = 'Chờ khách xác nhận';
        _isInspectionDone = true;
        _hasAcceptedInspection = false;
        _damageFee = huHai;
        _hasDamage = huHai > 0;
        _utilityFee = dienNuoc;
        _damageNote = ghiChuHuHai;
        if (bql != null && bql.trim().isNotEmpty) {
          _inspectorName = bql;
        }
      });
      final maYeuCau = record["ma_yeu_cau"]?.toString() ?? widget.ticketCode ?? "";
      final approvalKey = 'yccp_${maYeuCau}_$st';
      if (!_hasNotified && !ThongBaoHelper.daXem(approvalKey)) {
        _hasNotified = true;
        ThongBaoHelper.danhDauDaXem(approvalKey);
        SystemNotificationService.show(
          title: '📋 BQL đã kiểm tra thiết bị phòng ${widget.currentRoomNumber}',
          body: 'Biên bản nghiệm thu phòng cũ đã sẵn sàng. Vui lòng kiểm tra và bấm xác nhận!',
          tag: approvalKey,
          loai: 'chuyen_phong',
        );
        ThongBaoHelper.hienThongBao(
          context,
          tieuDe: 'Biên Bản Nghiệm Thu Đã Sẵn Sàng',
          noiDung:
              'BQL đã hoàn tất kiểm tra hiện trạng thiết bị phòng ${widget.currentRoomNumber}. Vui lòng xem bảng kê chi tiết và xác nhận biên bản để gửi lên chủ trọ duyệt.',
          type: ThongBaoType.thongTin,
          nutText: 'Xem biên bản',
          tag: approvalKey,
        );
      }
    } else if (st == 'Khách đã xác nhận' || st == 'Chờ chủ duyệt') {
      // Bước 3 hoàn tất -> Chờ bước 4 (Chủ trọ / BQL phê duyệt)
      setState(() {
        _currentStatus = 'Chờ chủ duyệt';
        _isInspectionDone = true;
        _hasAcceptedInspection = true;
        _damageFee = huHai;
        _hasDamage = huHai > 0;
        _utilityFee = dienNuoc;
        _damageNote = ghiChuHuHai;
      });
    } else if (st == 'Đã duyệt' || st == 'Hoàn tất') {
      // Bước 4 hoàn tất: Đã phê duyệt chính thức
      if (_currentStatus != 'Đã duyệt' || !_isInspectionDone) {
        setState(() {
          _currentStatus = 'Đã duyệt';
          _isInspectionDone = true;
          _hasAcceptedInspection = true;
          _damageFee = huHai;
          _hasDamage = huHai > 0;
          _utilityFee = dienNuoc;
          _damageNote = ghiChuHuHai;
          if (bql != null && bql.trim().isNotEmpty) {
            _inspectorName = bql;
          }
        });
        _dongBoDuyetChuyenPhongTuDong(record);
        final maYeuCau = record["ma_yeu_cau"]?.toString() ?? widget.ticketCode ?? "";
        final approvalKey = 'yccp_${maYeuCau}_$st';
        if (!_hasNotified && !ThongBaoHelper.daXem(approvalKey)) {
          _hasNotified = true;
          ThongBaoHelper.danhDauDaXem(approvalKey);
          SystemNotificationService.show(
            title: '🎉 Yêu cầu chuyển phòng đã được duyệt!',
            body: 'Ban Quản Lý đã phê duyệt yêu cầu chuyển sang phòng ${widget.targetRoom["maPhong"]}.',
            tag: approvalKey,
            loai: 'chuyen_phong',
          );
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Ban Quản Lý Đã Duyệt Chuyển Phòng!',
            noiDung:
                'Yêu cầu chuyển sang phòng ${widget.targetRoom["maPhong"]} đã được Ban Quản Lý phê duyệt thành công! Hợp đồng và phòng mới đã được cập nhật.',
            type: ThongBaoType.thanhCong,
            nutText: 'Đã hiểu',
            tag: approvalKey,
          );
        }
      }
    } else if (st == 'Từ chối' || st == 'Đã hủy') {
      if (_currentStatus != st) {
        setState(() => _currentStatus = st);
        final maYeuCau = record["ma_yeu_cau"]?.toString() ?? widget.ticketCode ?? "";
        final approvalKey = 'yccp_${maYeuCau}_$st';
        if (!_hasNotified && st == 'Từ chối' && !ThongBaoHelper.daXem(approvalKey)) {
          _hasNotified = true;
          ThongBaoHelper.danhDauDaXem(approvalKey);
          SystemNotificationService.show(
            title: '⚠️ Yêu cầu chuyển phòng bị từ chối',
            body: 'Ban Quản Lý chưa thể phê duyệt yêu cầu chuyển sang phòng ${widget.targetRoom["maPhong"]}.',
            tag: approvalKey,
            loai: 'chuyen_phong',
            isError: true,
          );
          ThongBaoHelper.hienThongBao(
            context,
            tieuDe: 'Yêu Cầu Chuyển Phòng Bị Từ Chối',
            noiDung:
                'Ban Quản Lý chưa thể phê duyệt yêu cầu chuyển sang phòng ${widget.targetRoom["maPhong"]}.',
            type: ThongBaoType.thatBai,
            nutText: 'Đã hiểu',
            tag: approvalKey,
          );
        }
      }
    }
  }

  Future<void> _dongBoDuyetChuyenPhongTuDong(Map<String, dynamic> record) async {
    try {
      final db = Supabase.instance.client;
      final maYeuCau = record['ma_yeu_cau']?.toString() ?? widget.ticketCode ?? '';
      final recMaHD = record['ma_hop_dong_ht']?.toString() ?? '';
      final maPhongCu = record['ma_phong_cu']?.toString() ?? widget.currentRoomNumber;
      final maPhongMoi = record['ma_phong_moi']?.toString() ?? (widget.targetRoom["maPhong"]?.toString() ?? '');
      if (recMaHD.isEmpty || maPhongMoi.isEmpty) return;

      final giaPhongMoi = (widget.targetRoom['giaThue'] as num?) ?? (widget.targetRoom['tienDatCoc'] as num?) ?? 0;
      final diffDeposit = record['tien_phat_sinh'] ?? 0;

      final now = DateTime.now();
      final ngayLapDateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final cleanHd = recMaHD.replaceAll(' ', '');
      String maPhuLuc = 'PLCP_$cleanHd';
      if (maPhuLuc.length > 25) {
        maPhuLuc = maPhuLuc.substring(0, 25);
      }

      await db.from('phu_luc_hop_dong').upsert({
        'ma_phu_luc': maPhuLuc,
        'ngay_lap': ngayLapDateStr,
        'noi_dung_dieu_chinh':
            'Phụ lục chuyển đổi phòng từ $maPhongCu sang phòng $maPhongMoi theo phiếu yêu cầu chuyển phòng $maYeuCau. Tiền cọc được bảo lưu đầy đủ.',
        'gia_thue_moi': giaPhongMoi,
        'chenh_lech_tien_coc': diffDeposit,
        'ngay_gia_han_den': ngayLapDateStr,
        'ma_hop_dong': recMaHD,
        'ma_phong_moi': maPhongMoi,
        'trang_thai': 'Đã duyệt',
      });

      await db.from('hop_dong').update({'ma_phong': maPhongMoi}).eq('ma_hop_dong', recMaHD);
      if (maPhongCu.isNotEmpty) {
        await db.from('phong').update({'trang_thai': 'Trống'}).eq('ma_phong', maPhongCu);
      }
      await db.from('phong').update({'trang_thai': 'Đang thuê'}).eq('ma_phong', maPhongMoi);

      try {
        await db
            .from('bien_ban_kiem_tra_phong')
            .update({'trang_thai': 'Đã xác nhận'})
            .eq('ma_yeu_cau', maYeuCau);
      } catch (_) {}

      // TỰ ĐỘNG ĐỒNG BỘ HÓA ĐƠN KỲ TỚI (CẬP NHẬT HOẶC TẠO MỚI)
      try {
        final tienDienNuocCu = (record['tien_dien_nuoc_cu'] as num?)?.toDouble() ?? 0.0;
        final tienHuHaiCu = (record['tien_hu_hai_cu'] as num?)?.toDouble() ?? 0.0;
        final tienPhatSinh = (record['tien_phat_sinh'] as num?)?.toDouble() ?? 0.0;

        final double tienCocBaoLuu = (record['tien_coc_bao_luu'] as num?)?.toDouble() ?? widget.currentPrice.toDouble();
        final double targetDeposit = ((widget.targetRoom['tienDatCoc'] as num?) ?? (widget.targetRoom['giaThue'] as num?) ?? giaPhongMoi).toDouble();
        final double diffDeposit = targetDeposit - tienCocBaoLuu;
        final double tienBuCoc = diffDeposit > 0 ? diffDeposit : (tienPhatSinh > 0 ? tienPhatSinh : 0.0);
        final double tienDoiDuCoc = diffDeposit < 0 ? diffDeposit.abs() : 0.0;

        final unpaidBills = await db
            .from('hoa_don')
            .select()
            .eq('ma_hop_dong', recMaHD)
            .eq('trang_thai', 'Chưa thanh toán')
            .order('ngay_lap', ascending: false)
            .limit(1);

        if (unpaidBills.isNotEmpty) {
          final bill = unpaidBills.first;
          final billCode = bill['ma_hoa_don'].toString();
          final curDienNuoc = (bill['tien_dien_nuoc'] as num?)?.toDouble() ?? 0.0;
          final curDichVu = (bill['tien_dich_vu_khac'] as num?)?.toDouble() ?? 0.0;
          final curNoCu = (bill['no_cu'] as num?)?.toDouble() ?? 0.0;

          final newDienNuoc = curDienNuoc + tienDienNuocCu;
          final newDichVu = curDichVu + tienHuHaiCu + tienBuCoc - tienDoiDuCoc;
          final newTienPhong = giaPhongMoi > 0 ? giaPhongMoi.toDouble() : ((bill['tien_phong'] as num?)?.toDouble() ?? 0.0);
          final newTongTien = (newTienPhong + newDienNuoc + newDichVu + curNoCu).clamp(0.0, double.infinity);

          await db.from('hoa_don').update({
            'tien_phong': newTienPhong,
            'tien_dien_nuoc': newDienNuoc,
            'tien_dich_vu_khac': newDichVu,
            'tong_tien': newTongTien,
          }).eq('ma_hoa_don', billCode);

          final suffix = maYeuCau.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
          final shortCode = suffix.length > 6 ? suffix.substring(suffix.length - 6) : suffix;
          final cthdDn = 'CD_$shortCode';
          final cthdHh = 'CH_$shortCode';
          final cthdCoc = 'CC_$shortCode';

          if (tienDienNuocCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdDn,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Điện nước chốt bàn giao phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': tienDienNuocCu,
              'thanh_tien': tienDienNuocCu,
            });
          }
          if (tienHuHaiCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdHh,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Khấu trừ hư hại thiết bị phòng $maPhongCu',
              'so_luong': 1,
              'don_gia': tienHuHaiCu,
              'thanh_tien': tienHuHaiCu,
            });
          }
          if (tienBuCoc > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Bù chênh lệch tiền cọc phòng mới $maPhongMoi',
              'so_luong': 1,
              'don_gia': tienBuCoc,
              'thanh_tien': tienBuCoc,
            });
          } else if (tienDoiDuCoc > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': billCode,
              'ten_khoan_thu': 'Khấu trừ tiền cọc dư phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': -tienDoiDuCoc,
              'thanh_tien': -tienDoiDuCoc,
            });
          }
        } else {
          final newBillCode = 'HDCP_${cleanHd.substring(0, cleanHd.length > 5 ? 5 : cleanHd.length)}';
          final newTienPhong = giaPhongMoi > 0 ? giaPhongMoi.toDouble() : 0.0;
          final newDichVu = tienHuHaiCu + tienBuCoc - tienDoiDuCoc;
          final newTong = (newTienPhong + tienDienNuocCu + newDichVu).clamp(0.0, double.infinity);

          await db.from('hoa_don').upsert({
            'ma_hoa_don': newBillCode,
            'ngay_lap': ngayLapDateStr,
            'han_dong_tien': DateTime.now().add(const Duration(days: 5)).toIso8601String().substring(0, 10),
            'tien_phong': newTienPhong,
            'tien_dien_nuoc': tienDienNuocCu,
            'tien_dich_vu_khac': newDichVu,
            'no_cu': 0,
            'tong_tien': newTong,
            'trang_thai': 'Chưa thanh toán',
            'loai_giao_dich': 'Tiền phòng & Dịch vụ',
            'ma_hop_dong': recMaHD,
          });

          final suffix = maYeuCau.replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
          final shortCode = suffix.length > 6 ? suffix.substring(suffix.length - 6) : suffix;
          final cthdPhong = 'CP_$shortCode';
          final cthdDn = 'CD_$shortCode';
          final cthdHh = 'CH_$shortCode';
          final cthdCoc = 'CC_$shortCode';

          await db.from('chi_tiet_hoa_don').upsert({
            'ma_cthd': cthdPhong,
            'ma_hoa_don': newBillCode,
            'ten_khoan_thu': 'Tiền thuê phòng mới $maPhongMoi',
            'so_luong': 1,
            'don_gia': newTienPhong,
            'thanh_tien': newTienPhong,
          });

          if (tienDienNuocCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdDn,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Điện nước chốt bàn giao phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': tienDienNuocCu,
              'thanh_tien': tienDienNuocCu,
            });
          }
          if (tienHuHaiCu > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdHh,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Khấu trừ hư hại thiết bị phòng $maPhongCu',
              'so_luong': 1,
              'don_gia': tienHuHaiCu,
              'thanh_tien': tienHuHaiCu,
            });
          }
          if (tienBuCoc > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Bù chênh lệch tiền cọc phòng mới $maPhongMoi',
              'so_luong': 1,
              'don_gia': tienBuCoc,
              'thanh_tien': tienBuCoc,
            });
          } else if (tienDoiDuCoc > 0) {
            await db.from('chi_tiet_hoa_don').upsert({
              'ma_cthd': cthdCoc,
              'ma_hoa_don': newBillCode,
              'ten_khoan_thu': 'Khấu trừ tiền cọc dư phòng cũ $maPhongCu',
              'so_luong': 1,
              'don_gia': -tienDoiDuCoc,
              'thanh_tien': -tienDoiDuCoc,
            });
          }
        }
      } catch (errBill) {
        debugPrint('[CHUYEN_PHONG] Lỗi đồng bộ hóa đơn: $errBill');
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _yccpPollTimer?.cancel();
    if (_yccpRtChannel != null) {
      Supabase.instance.client.removeChannel(_yccpRtChannel!);
    }
    super.dispose();
  }

  String get _ticketCode {
    if (widget.ticketCode != null && widget.ticketCode!.isNotEmpty) {
      return widget.ticketCode!;
    }
    final cleanCur = widget.currentRoomNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanTarget = widget.targetRoom['maPhong'].toString().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return '#CP-$cleanCur-$cleanTarget';
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetRoom;
    final targetName = target['maPhong'] ?? 'P.205';

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                child: Column(
                  children: [
                    _buildSuccessHeroCard(targetName),
                    const SizedBox(height: 16),
                    _buildInspectionReportCard(),
                    const SizedBox(height: 16),
                    _buildTicketSummaryCard(targetName),
                    const SizedBox(height: 16),
                    _buildNextStepsCard(targetName),
                    const SizedBox(height: 16),
                    if (_currentStatus == 'Đã duyệt') ...[
                      _buildPhuLucLegalCard(targetName),
                      const SizedBox(height: 16),
                    ],
                    _buildNextBillEstimateCard(targetName),
                    const SizedBox(height: 16),
                    _buildSupportCard(),
                    const SizedBox(height: 20),
                    _buildActionButtons(),
                  ],
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
                  'Chuyển Phòng',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                Text(
                  'Phiếu $_ticketCode',
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
            icon: const Icon(Icons.share_outlined, color: _primary),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ─── 2. SUCCESS HERO CARD ───
  Widget _buildSuccessHeroCard(String targetName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF0F9FF), Color(0xFFE0F2FE), Color(0xFFF8FAFC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFBAE6FD)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Icon Circle
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: _primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 12),

          // Status pills for all 4 states
          if (_currentStatus == 'Đã duyệt') ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF16A34A)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '🎉 ĐÃ ĐƯỢC BQL PHÊ DUYỆT CHUYỂN PHÒNG!',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_currentStatus == 'Chờ khách xác nhận' || _currentStatus == 'Đã kiểm tra') ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.assignment_turned_in_rounded, size: 15, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '📋 BQL ĐÃ KIỂM TRA PHÒNG - CHỜ BẠN XÁC NHẬN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_currentStatus == 'Chờ chủ duyệt' || _currentStatus == 'Khách đã xác nhận') ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF38BDF8)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 15, color: Color(0xFF0284C7)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '⏳ ĐÃ GỬI BIÊN BẢN - CHỜ CHỦ TRỌ DUYỆT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0369A1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_currentStatus == 'Từ chối' || _currentStatus == 'Đã hủy') ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cancel_rounded, size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _currentStatus == 'Đã hủy' ? 'YÊU CẦU ĐÃ ĐƯỢC HỦY' : 'YÊU CẦU BỊ TỪ CHỐI',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(
                        0xFF0284C7,
                      ).withValues(alpha: _pulseAnimation.value),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF0284C7,
                          ).withValues(alpha: _pulseAnimation.value),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _currentStatus == 'Đang xử lý'
                              ? 'BQL Kiều Giang đang xử lý hồ sơ'
                              : 'Đang chờ BQL Kiêu Giang tiếp nhận',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 10),

          const Text(
            'Đã Gửi Yêu Cầu Chuyển Phòng!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Yêu cầu chuyển từ ${widget.currentRoomNumber} sang $targetName (${widget.targetRoom["toaNha"]}) đã được ghi nhận trên hệ thống.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 2.5 BIÊN BẢN KIỂM TRA THIẾT BỊ PHÒNG CŨ ───
  Widget _buildInspectionReportCard() {
    final double curDeposit = widget.currentPrice.toDouble();
    final double actualDeduction = _hasDamage ? _damageFee.toDouble() : 0.0;
    final double finalDeposit = curDeposit - actualDeduction - _utilityFee.toDouble();

    // ── KỊCH BẢN 1: BQL CHƯA ĐẾN KIỂM TRA PHÒNG (MẶC ĐỊNH KHI MỚI GỬI YÊU CẦU) ──
    if (!_isInspectionDone) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFDE68A),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: Color(0xFFD97706),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kiểm Tra Thiết Bị Phòng Cũ',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: _textDark,
                        ),
                      ),
                      Text(
                        'Phòng ${widget.currentRoomNumber} • Đang chờ BQL khảo sát',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Text(
                    'CHƯA KIỂM TRA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),

            // Tóm tắt trạng thái khảo sát
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRẠNG THÁI KHẢO SÁT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Chờ BQL liên hệ xếp lịch',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CỌC PHÒNG CŨ DỰ KIẾN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${FormatUtils.currency(curDeposit)}đ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Thông báo thực tế
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFEF3C7)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: Color(0xFFD97706),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'BQL sẽ liên hệ và trực tiếp đến phòng để khảo sát hiện trạng thiết bị & chốt số điện nước trước ngày bạn chuyển phòng. Sau khi kiểm tra xong, biên bản nghiệm thu và quyết toán cọc sẽ hiển thị tại đây.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Nút xem danh mục thiết bị bàn giao
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showInspectionDetailModal,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primary,
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text(
                  'Xem Danh Mục Thiết Bị Cần Bàn Giao',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // ── KỊCH BẢN 2: BQL ĐÃ KIỂM TRA PHÒNG & XUẤT BIÊN BẢN NGHIỆM THU ──
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _hasDamage ? const Color(0xFFFDE68A) : const Color(0xFF86EFAC),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _hasDamage
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _hasDamage
                      ? Icons.fact_check_outlined
                      : Icons.verified_outlined,
                  color: _hasDamage
                      ? const Color(0xFFD97706)
                      : const Color(0xFF16A34A),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Biên Bản Kiểm Tra Thiết Bị Phòng Cũ',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Phòng ${widget.currentRoomNumber} • Đã kiểm tra & nghiệm thu',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _currentStatus == 'Đã duyệt'
                      ? const Color(0xFFF0FDF4)
                      : (_hasAcceptedInspection
                          ? const Color(0xFFEFF6FF)
                          : const Color(0xFFFFFBEB)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _currentStatus == 'Đã duyệt'
                        ? const Color(0xFF86EFAC)
                        : (_hasAcceptedInspection
                            ? const Color(0xFF93C5FD)
                            : const Color(0xFFFCD34D)),
                  ),
                ),
                child: Text(
                  _currentStatus == 'Đã duyệt'
                      ? 'CHỦ TRỌ ĐÃ DUYỆT'
                      : (_hasAcceptedInspection
                          ? 'CHỜ CHỦ TRỌ DUYỆT'
                          : 'CHỜ BẠN XÁC NHẬN'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: _currentStatus == 'Đã duyệt'
                        ? const Color(0xFF15803D)
                        : (_hasAcceptedInspection
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFFB45309)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Tóm tắt kết quả kiểm tra
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HIỆN TRẠNG ĐỒ DÙNG',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Builder(builder: (context) {
                        final equipmentList = _getEquipmentItems();
                        final damagedCount = equipmentList.where((it) => it['isGood'] == false).length;
                        final totalCount = equipmentList.length;
                        return Text(
                          _hasDamage
                              ? '${totalCount - damagedCount} đạt • $damagedCount hư hỏng (-${FormatUtils.currency(_damageFee.toDouble())}đ)'
                              : '$totalCount/$totalCount thiết bị đạt chuẩn (0đ)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: _hasDamage
                                ? const Color(0xFFD97706)
                                : const Color(0xFF16A34A),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CỌC BẢO LƯU THỰC TẾ',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${FormatUtils.currency(finalDeposit)}đ',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_hasDamage && _damageNote != null && _damageNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.report_problem_rounded, size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chi tiết hư hại: $_damageNote',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),

          // Status banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _currentStatus == 'Đã duyệt'
                  ? const Color(0xFFF0FDF4)
                  : (_hasAcceptedInspection
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFFFFBEB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _currentStatus == 'Đã duyệt'
                      ? Icons.verified_rounded
                      : (_hasAcceptedInspection
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded),
                  size: 14,
                  color: _currentStatus == 'Đã duyệt'
                      ? const Color(0xFF16A34A)
                      : (_hasAcceptedInspection
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFD97706)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _currentStatus == 'Đã duyệt'
                        ? 'Chủ trọ đã phê duyệt yêu cầu chuyển phòng thành công.'
                        : (_hasAcceptedInspection
                            ? 'Bạn đã xác nhận biên bản. Đang chờ chủ trọ duyệt chuyển phòng.'
                            : 'BQL đã kiểm tra thiết bị. Vui lòng xác nhận biên bản để gửi lên chủ trọ.'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _currentStatus == 'Đã duyệt'
                          ? const Color(0xFF15803D)
                          : (_hasAcceptedInspection
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFFB45309)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Action button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showInspectionDetailModal,
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: Color(0xFF93C5FD)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined, size: 16),
              label: Text(
                _currentStatus == 'Đã duyệt'
                    ? 'Xem Biên Bản Nghiệm Thu Đã Duyệt'
                    : (_hasAcceptedInspection
                        ? 'Xem Lại Biên Bản Đã Gửi Chủ Trọ'
                        : 'Xem & Xác Nhận Biên Bản Nghiệm Thu'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── MODAL TOÀN VĂN PHỤ LỤC HỢP ĐỒNG ĐIỆN TỬ ───
  void _showPhuLucDetailModal() {
    final effectiveHd = _maHopDong ?? 'HD001';
    final cleanHd = effectiveHd.replaceAll(' ', '');
    final maPl = 'PLCP_$cleanHd';
    final targetMaPhong = widget.targetRoom['maPhong']?.toString() ?? '';
    final targetName = _targetRoomData?['ten_hien_thi']?.toString() ??
        widget.targetRoom['tenHienThi']?.toString() ??
        'Phòng $targetMaPhong';
    final double giaThueMoi = (_targetRoomData?['gia_thue'] as num?)?.toDouble() ??
        ((widget.targetRoom['giaThue'] as num?)?.toDouble() ?? 2600000.0);
    final double targetDeposit = (_targetRoomData?['tien_dat_coc'] as num?)?.toDouble() ?? giaThueMoi;
    final double curDeposit = widget.currentPrice.toDouble();
    final double dienNuoc = _utilityFee.toDouble();
    final double huHai = _hasDamage ? _damageFee.toDouble() : 0.0;
    final double tongChiPhiPhongCu = dienNuoc + huHai;
    final double chenhLechCoc = curDeposit - targetDeposit;
    final double quyetToanCuoiCung = chenhLechCoc - tongChiPhiPhongCu;
    final now = DateTime.now();
    final ngayLapStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    String formatNgay(String raw) {
      try {
        final d = DateTime.parse(raw);
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        return raw;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.description_rounded,
                        color: Color(0xFF0284C7),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Phụ Lục Hợp Đồng Chuyển Phòng',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                              color: _textDark,
                            ),
                          ),
                          Text(
                            'Văn bản điện tử được xác thực và có hiệu lực',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: const Text(
                        'ĐÃ DUYỆT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF16A34A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 22),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              // Content Document Paper
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFDFE),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Quốc hiệu
                        const Text(
                          'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: _textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Độc lập - Tự do - Hạnh phúc',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: _textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '-------o0o-------',
                          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // Title
                        const Text(
                          'PHỤ LỤC HỢP ĐỒNG THUÊ PHÒNG TRỌ',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: _primary,
                            letterSpacing: 0.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '(VỀ VIỆC ĐIỀU CHỈNH PHÒNG THUÊ & GIÁ THUÊ)',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Số hiệu: $maPl  •  Kèm theo Hợp đồng số: $effectiveHd',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF64748B),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // Căn cứ
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '• Căn cứ Hợp đồng thuê phòng số $effectiveHd đã ký kết giữa Bên A và Bên B.',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• Căn cứ Phiếu yêu cầu chuyển phòng #${widget.ticketCode ?? ""} đã được phê duyệt.',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '• Căn cứ Biên bản nghiệm thu & chốt chỉ số điện nước phòng cũ ${widget.currentRoomNumber}.',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Hai bên
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Hôm nay, hai bên thống nhất ký kết Phụ lục hợp đồng với các điều khoản như sau:',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ĐIỀU 1
                        _buildPlSectionHeader('ĐIỀU 1: ĐIỀU CHỈNH PHÒNG THUÊ'),
                        _buildPlItemRow('Phòng cũ chấm dứt thuê', 'Phòng ${widget.currentRoomNumber}'),
                        _buildPlItemRow('Phòng mới nhận bàn giao', '$targetName ($targetMaPhong)'),
                        _buildPlItemRow('Thời điểm bàn giao', formatNgay(widget.moveInDateFormatted)),
                        _buildPlItemRow('Hiện trạng bàn giao', 'Đã nghiệm thu đạt chuẩn theo biên bản'),
                        const SizedBox(height: 12),

                        // ĐIỀU 2
                        _buildPlSectionHeader('ĐIỀU 2: ĐIỀU CHỈNH GIÁ THUÊ & QUYẾT TOÁN CỌC'),
                        _buildPlItemRow('Giá thuê phòng mới', '${TienIchDinhDang.formatCurrency(giaThueMoi)} / tháng'),
                        _buildPlItemRow('Tiền đặt cọc phòng mới', '${TienIchDinhDang.formatCurrency(targetDeposit)} (kết chuyển từ cọc cũ sang)'),
                        _buildPlItemRow('Tiền cọc phòng cũ đã đóng', '${TienIchDinhDang.formatCurrency(curDeposit)}'),
                        if (chenhLechCoc > 0)
                          _buildPlItemRow('  ↳ Cọc cũ còn dư', '+${TienIchDinhDang.formatCurrency(chenhLechCoc)} (cọc cũ > cọc mới)'),
                        if (dienNuoc > 0)
                          _buildPlItemRow('Điện nước chốt phòng cũ', '-${TienIchDinhDang.formatCurrency(dienNuoc)} (khấu trừ)'),
                        if (huHai > 0)
                          _buildPlItemRow('Khấu trừ hao mòn/hư hại', '-${TienIchDinhDang.formatCurrency(huHai)}${_damageNote != null && _damageNote!.isNotEmpty ? " ($_damageNote)" : ""}'),
                        if (quyetToanCuoiCung > 0)
                          _buildPlItemRow(
                            'Quyết toán bù trừ cọc',
                            'DƯ +${TienIchDinhDang.formatCurrency(quyetToanCuoiCung)} (sẽ khấu trừ vào hóa đơn tiền phòng tháng tới của phòng mới)',
                            isBold: true,
                            isHighlight: true,
                          )
                        else if (quyetToanCuoiCung < 0)
                          _buildPlItemRow(
                            'Quyết toán bù trừ cọc',
                            'THIẾU ${TienIchDinhDang.formatCurrency(quyetToanCuoiCung.abs())} (thanh toán cùng hóa đơn tới)',
                            isBold: true,
                          )
                        else
                          _buildPlItemRow(
                            'Quyết toán bù trừ cọc',
                            '0đ (Đã cấn trừ đủ vào tiền cọc phòng mới)',
                            isBold: true,
                          ),
                        const SizedBox(height: 12),

                        // ĐIỀU 3
                        _buildPlSectionHeader('ĐIỀU 3: HIỆU LỰC THI HÀNH'),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '1. Phụ lục này là bộ phận không thể tách rời của Hợp đồng thuê phòng số nêu trên.\n'
                            '2. Mọi quyền, nghĩa vụ và trách nhiệm được quy định trong Hợp đồng gốc tiếp tục có giá trị thi hành đối với phòng thuê mới.\n'
                            '3. Phụ lục được lập và xác nhận bằng phương thức điện tử có giá trị pháp lý ràng buộc cả hai bên.',
                            style: TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.45),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Chữ ký 2 bên
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Bên A
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'ĐẠI DIỆN BÊN A\n(BÊN CHO THUÊ)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF166534),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 28),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'KIỀU GIANG HOUSE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                    const Text(
                                      'Đã phê duyệt điện tử',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                    Text(
                                      'Ngày $ngayLapStr',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Bên B
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'ĐẠI DIỆN BÊN B\n(BÊN THUÊ)',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E40AF),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB), size: 28),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'KHÁCH THUÊ',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                    const Text(
                                      'Đã xác nhận trên app',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                    Text(
                                      'Ngày $ngayLapStr',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Color(0xFF64748B),
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
                  ),
                ),
              ),

              // Bottom buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ContractDetailScreen(maHopDong: effectiveHd),
                            ),
                          );
                        },
                        icon: const Icon(Icons.source_rounded, size: 16, color: _primary),
                        label: const Text(
                          'Xem Hợp Đồng Gốc',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _primary),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFBAE6FD)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Đóng',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlSectionHeader(String title) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E293B),
        ),
      ),
    );
  }

  Widget _buildPlItemRow(String label, String value, {bool isBold = false, bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '• $label:',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: (isBold || isHighlight) ? FontWeight.w900 : FontWeight.bold,
                color: color ?? (isHighlight ? const Color(0xFF0284C7) : const Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── THẺ PHỤ LỤC HỢP ĐỒNG ĐÃ KÍCH HOẠT TRÊN TRANG ───
  Widget _buildPhuLucLegalCard(String targetName) {
    final effectiveHd = _maHopDong ?? 'HD001';
    final cleanHd = effectiveHd.replaceAll(' ', '');
    final maPl = 'PLCP_$cleanHd';
    final targetMaPhong = widget.targetRoom['maPhong']?.toString() ?? '';
    final double giaThueMoi = ((widget.targetRoom['giaThue'] as num?) ??
            (widget.targetRoom['tienDatCoc'] as num?) ??
            3200000)
        .toDouble();
    final double curDeposit = widget.currentPrice.toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF38BDF8), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.history_edu_rounded,
                  color: Color(0xFF0284C7),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phụ Lục Hợp Đồng Chuyển Phòng',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Đã tự động xác thực & có hiệu lực pháp lý',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: const Text(
                  'CÓ HIỆU LỰC',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _buildLegalSummaryRow('Mã phụ lục', maPl, isBold: true),
                const SizedBox(height: 6),
                _buildLegalSummaryRow('Hợp đồng gốc', effectiveHd),
                const SizedBox(height: 6),
                _buildLegalSummaryRow('Phòng chuyển đến', '$targetName ($targetMaPhong)', isHighlight: true),
                const SizedBox(height: 6),
                _buildLegalSummaryRow('Giá thuê mới', '${TienIchDinhDang.formatCurrency(giaThueMoi)} / tháng'),
                const SizedBox(height: 6),
                _buildLegalSummaryRow('Bảo lưu tiền cọc', TienIchDinhDang.formatCurrency(curDeposit)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showPhuLucDetailModal,
              icon: const Icon(Icons.description_rounded, size: 16),
              label: const Text(
                'XEM TOÀN VĂN PHỤ LỤC & CHỮ KÝ ĐIỆN TỬ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
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
    );
  }

  Widget _buildLegalSummaryRow(String label, String value, {bool isBold = false, bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: (isBold || isHighlight) ? FontWeight.bold : FontWeight.w600,
              color: isHighlight ? const Color(0xFF0284C7) : _textDark,
            ),
          ),
        ),
      ],
    );
  }

  void _showInspectionDetailModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final double curDeposit = widget.currentPrice.toDouble();
            final double actualDeduction = _hasDamage ? _damageFee.toDouble() : 0.0;
            final double finalDeposit = curDeposit - actualDeduction - _utilityFee.toDouble();
            final double targetPrice = (_targetRoomData?['gia_thue'] as num?)?.toDouble() ??
                ((widget.targetRoom['giaThue'] as num?)?.toDouble() ?? 2600000.0);
            final double diffWithNewRoom = finalDeposit - targetPrice;

            final List<Map<String, dynamic>> items = _getEquipmentItems();

            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _isInspectionDone
                                ? const Color(0xFFE0F2FE)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _isInspectionDone
                                ? Icons.fact_check_rounded
                                : Icons.inventory_2_rounded,
                            color: _isInspectionDone
                                ? _primary
                                : const Color(0xFFD97706),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isInspectionDone
                                    ? 'Biên Bản Nghiệm Thu Thiết Bị'
                                    : 'Danh Mục Thiết Bị Cần Bàn Giao',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: _textDark,
                                ),
                              ),
                              Text(
                                _isInspectionDone
                                    ? 'Phòng cũ ${widget.currentRoomNumber} • BBKT-${widget.currentRoomNumber}'
                                    : 'Phòng cũ ${widget.currentRoomNumber} • Đang chờ BQL khảo sát',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE2E8F0)),

                  // Scrollable Body
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── NẾU BQL CHƯA KIỂM TRA PHÒNG ──
                          if (!_isInspectionDone) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFDE68A)),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFD97706)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Đây là danh mục thiết bị ban đầu được bàn giao cho phòng của bạn. Trước ngày chuyển phòng, BQL sẽ xếp lịch đến kiểm tra hiện trạng từng món đồ và chốt số điện nước.',
                                      style: TextStyle(fontSize: 11.5, height: 1.35, color: Color(0xFF92400E)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Danh sách thiết bị chờ bàn giao
                            const Row(
                              children: [
                                Icon(Icons.checklist_rounded, size: 18, color: _primary),
                                SizedBox(width: 6),
                                Text(
                                  'Danh Sách Thiết Bị Cần Bàn Giao',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...items.map((it) => _buildInspectionItemTile(it)),

                            const SizedBox(height: 14),
                            // Thông tin cọc dự kiến
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  _buildModalInfoRow('Tiền cọc phòng cũ (${widget.currentRoomNumber}):', '${FormatUtils.currency(curDeposit)}đ'),
                                  const SizedBox(height: 6),
                                  _buildModalInfoRow('Tình trạng cọc:', 'Đang bảo lưu để chuyển sang phòng mới', isHighlight: true, highlightColor: _primary),
                                  const SizedBox(height: 6),
                                  _buildModalInfoRow('Khấu trừ hư hỏng:', 'Chưa phát sinh (Chờ BQL kiểm tra)'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Ghi chú thực tế
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.schedule_rounded, size: 16, color: Color(0xFF64748B)),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'BQL sẽ liên hệ và cùng bạn trực tiếp kiểm tra tình trạng các thiết bị trên khi đến khảo sát phòng.',
                                      style: TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // ── NẾU BQL ĐÃ KIỂM TRA PHÒNG XONG ──

                            // Bảng thông tin kiểm định
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  _buildModalInfoRow('Phòng kiểm tra:', widget.currentRoomNumber),
                                  const SizedBox(height: 6),
                                  _buildModalInfoRow('Thời gian khảo sát:', 'Hôm nay - ${widget.moveInDateFormatted}'),
                                  const SizedBox(height: 6),
                                  _buildModalInfoRow(
                                    'Kết luận nghiệm thu:',
                                    _hasDamage ? 'Có 1 thiết bị hư hại cần khấu trừ' : '100% đạt chuẩn bàn giao',
                                    isHighlight: true,
                                    highlightColor: _hasDamage ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_damageNote != null && _damageNote!.trim().isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFFECACA)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.report_problem_rounded, size: 18, color: Color(0xFFDC2626)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Chi tiết hư hại từ Ban Quản Lý:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF991B1B),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _damageNote!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFB91C1C),
                                              fontWeight: FontWeight.w600,
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Tiêu đề danh sách thiết bị
                            const Row(
                              children: [
                                Icon(Icons.checklist_rounded, size: 18, color: _primary),
                                SizedBox(width: 6),
                                Text(
                                  'Chi Tiết Kiểm Tra Từng Thiết Bị',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _textDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // List items
                            ...items.map((it) => _buildInspectionItemTile(it)),

                            const SizedBox(height: 16),



                            // Bảng quyết toán tiền cọc bảo lưu
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _hasDamage ? const Color(0xFFFFFBEB) : const Color(0xFFF0FDF4),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _hasDamage ? const Color(0xFFFDE68A) : const Color(0xFFBBF7D0),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_rounded,
                                        size: 16,
                                        color: _hasDamage ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Quyết Toán Tiền Đặt Cọc Bảo Lưu',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: _hasDamage ? const Color(0xFFB45309) : const Color(0xFF15803D),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _buildModalInfoRow(
                                    '1. Tiền cọc phòng cũ (${widget.currentRoomNumber}):',
                                    '+${FormatUtils.currency(curDeposit)}đ',
                                  ),
                                  const SizedBox(height: 4),
                                  _buildModalInfoRow(
                                    '2. Khấu trừ hư hỏng thiết bị:',
                                    '-${FormatUtils.currency(actualDeduction)}đ',
                                    highlightColor: const Color(0xFFDC2626),
                                  ),
                                  const SizedBox(height: 4),
                                  _buildModalInfoRow(
                                    '3. Trừ tiền điện nước phòng cũ:',
                                    '-${FormatUtils.currency(_utilityFee.toDouble())}đ',
                                    highlightColor: const Color(0xFFDC2626),
                                  ),
                                  const Divider(height: 14, color: Color(0x33000000)),
                                  _buildModalInfoRow(
                                    'CỌC THỰC TẾ CHUYỂN SANG PHÒNG MỚI:',
                                    '${FormatUtils.currency(finalDeposit)}đ',
                                    isHighlight: true,
                                    highlightColor: _primaryDark,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    diffWithNewRoom >= 0
                                        ? '👉 So với cọc phòng mới (${FormatUtils.currency(targetPrice)}đ): Bạn còn dư ${FormatUtils.currency(diffWithNewRoom)}đ được TRỪ VÀO HÓA ĐƠN THÁNG TỚI.'
                                        : '👉 So với cọc phòng mới (${FormatUtils.currency(targetPrice)}đ): Khoản bù thêm ${FormatUtils.currency((-diffWithNewRoom))}đ sẽ được CỘNG VÀO HÓA ĐƠN THÁNG TỚI.',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.35,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Xác nhận
                            if (_hasAcceptedInspection) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF86EFAC)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Bạn đã xác nhận biên bản này (Chờ chủ trọ duyệt)',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF15803D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    setModalState(() => _hasAcceptedInspection = true);
                                    setState(() {
                                      _hasAcceptedInspection = true;
                                      _currentStatus = 'Chờ chủ duyệt';
                                    });
                                    final ticket = widget.ticketCode;
                                    if (ticket != null && ticket.isNotEmpty) {
                                      Supabase.instance.client
                                          .from('yeu_cau_chuyen_phong')
                                          .update({
                                            'trang_thai_tien_do': 'Khách đã xác nhận',
                                          })
                                          .eq('ma_yeu_cau', ticket)
                                          .then((_) {})
                                          .catchError((e) {
                                        debugPrint('[YCCP] Lỗi cập nhật trạng thái: $e');
                                      });
                                    }
                                    if (_maBienBan != null && _maBienBan!.isNotEmpty) {
                                      Supabase.instance.client
                                          .from('bien_ban_kiem_tra_phong')
                                          .update({'trang_thai': 'Đã xác nhận'})
                                          .eq('ma_bien_ban', _maBienBan!)
                                          .then((_) {})
                                          .catchError((e) {
                                        debugPrint('[BIEN_BAN] Lỗi cập nhật trạng thái: $e');
                                      });
                                    }
                                    Navigator.pop(ctx);
                                    ThongBaoHelper.hienThongBao(
                                      context,
                                      tieuDe: 'Đã Gửi Xác Nhận Cho Chủ Trọ',
                                      noiDung:
                                          'Bạn đã xác nhận đồng ý với biên bản kiểm tra thiết bị phòng cũ và quyết toán cọc. Yêu cầu chuyển phòng đã được gửi lên chủ trọ để phê duyệt chính thức!',
                                      type: ThongBaoType.thanhCong,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.send_rounded, size: 18),
                                  label: const Text(
                                    'Xác Nhận Biên Bản & Gửi Lên Chủ Trọ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],

                          const SizedBox(height: 10),
                          Center(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                ThongBaoHelper.hienThongBao(
                                  context,
                                  tieuDe: 'Liên Hệ Khiếu Nại BQL',
                                  noiDung:
                                      'Vui lòng liên hệ Hotline Ban Quản Lý Kiều Giang hoặc nhắn tin qua mục Hỗ Trợ để phúc tra lại thiết bị phòng ${widget.currentRoomNumber}.',
                                  type: ThongBaoType.thongTin,
                                );
                              },
                              icon: const Icon(Icons.support_agent_rounded, size: 16, color: Color(0xFF64748B)),
                              label: const Text(
                                'Có thắc mắc hoặc cần khiếu nại? Bấm vào đây',
                                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInspectionItemTile(Map<String, dynamic> it) {
    final bool isGood = it['isGood'] == true;
    final int fee = it['chiPhi'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isGood ? const Color(0xFFF8FAFC) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGood ? const Color(0xFFE2E8F0) : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(it['icon'] as IconData, size: 18, color: isGood ? _primary : const Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  it['ten'] as String,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isGood ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isGood ? 'ĐẠT (0đ)' : '-${FormatUtils.currency(fee.toDouble())}đ',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isGood ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            it['tinhTrang'] as String,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                isGood ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                size: 13,
                color: isGood ? const Color(0xFF16A34A) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  it['ghiChu'] as String,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: isGood ? const Color(0xFF16A34A) : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModalInfoRow(
    String label,
    String value, {
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
        ),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: isHighlight ? 12 : 11.5,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              color: highlightColor ?? _textDark,
            ),
          ),
        ),
      ],
    );
  }

  // ─── 3. TICKET SUMMARY CARD ───
  Widget _buildTicketSummaryCard(String targetName) {
    final effectiveTargetName = _targetRoomData?['ma_phong']?.toString() ??
        _maPhongMoiFromDb ??
        widget.targetRoom['maPhong']?.toString() ??
        targetName;
    final int tangCu = _layTangTuMaPhong(widget.currentRoomNumber);
    final String toaNhaCu = widget.targetRoom['toaNha']?.toString() ?? 'Kiều Giang';
    final int tangMoi = (_targetRoomData?['tang'] as num?)?.toInt() ??
        (widget.targetRoom['tang'] as num?)?.toInt() ??
        _layTangTuMaPhong(effectiveTargetName);
    final int dienTichMoi = (_targetRoomData?['dien_tich'] as num?)?.toInt() ??
        (widget.targetRoom['dienTich'] as num?)?.toInt() ??
        26;
    final double giaThueMoi = ((_targetRoomData?['gia_thue'] as num?) ??
            (widget.targetRoom['giaThue'] as num?) ??
            3500000)
        .toDouble();
    final double giaThueCu = widget.currentPrice.toDouble();
    final double diffPrice = giaThueMoi - giaThueCu;
    final double tienCocBanDau = _tienCocBaoLuu?.toDouble() ?? widget.currentPrice.toDouble();

    // Chi phí phòng cũ chốt khi nghiệm thu bàn giao
    final double dienNuocCu = _utilityFee.toDouble();
    final double huHaiCu = _hasDamage ? _damageFee.toDouble() : 0.0;
    final double tongChiPhiPhongCu = _isInspectionDone ? (dienNuocCu + huHaiCu) : 0.0;

    // Tiền cọc phòng cũ còn lại sau khi trừ chi phí phòng cũ (Phương án 1)
    final double tienCocConLai = (tienCocBanDau - tongChiPhiPhongCu).clamp(0.0, double.infinity);

    final double targetDeposit = ((_targetRoomData?['tien_dat_coc'] as num?) ??
            (widget.targetRoom['tienDatCoc'] as num?) ??
            giaThueMoi)
        .toDouble();

    // Chênh lệch cọc thực tế: Cọc phòng mới - Cọc cũ còn lại
    final double diffDeposit = targetDeposit - tienCocConLai;
    final String ngayDon = _formatDateString(_thoiGianHen ?? widget.moveInDateFormatted);

    final String displayReason = (_lyDoChuyen != null && _lyDoChuyen!.trim().isNotEmpty)
        ? _lyDoChuyen!
        : (widget.reason.isNotEmpty
            ? (widget.note.isNotEmpty && widget.note != widget.reason
                ? ' - '
                : widget.reason)
            : (widget.note.isNotEmpty ? widget.note : 'Nhu cầu đổi không gian sinh hoạt'));

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
          Row(
            children: [
              const Icon(Icons.assignment_outlined, color: _primary, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Tóm Tắt Phiếu Yêu Cầu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Hôm nay 16:30',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Transfer box: P.203 -> P.201
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hiện tại',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        widget.currentRoomNumber,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _textDark,
                        ),
                      ),
                      Text(
                        'Tầng $tangCu • $toaNhaCu',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Đổi sang',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Phòng mới',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        effectiveTargetName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _primary,
                        ),
                      ),
                      Text(
                        'Tầng $tangMoi • $dienTichMoi m²',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          _buildSummaryRow('Ngày dự kiến dọn:', ngayDon),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),

          _buildSummaryRow(
            'Tiền cọc phòng cũ:',
            '${FormatUtils.currency(tienCocBanDau)}đ',
          ),
          if (_isInspectionDone && tongChiPhiPhongCu > 0) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Cọc còn lại sau trừ chi phí: ${FormatUtils.currency(tienCocConLai)}đ (đã trừ ${FormatUtils.currency(tongChiPhiPhongCu)}đ)',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 13,
                ),
              ),
              SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Tự động kết chuyển & cấn trừ chênh lệch vào Hóa đơn kỳ tới',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),

          _buildSummaryRow(
            'Giá thuê phòng mới:',
            '${FormatUtils.currency(giaThueMoi)}đ/tháng',
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Chênh lệch giá thuê:',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diffPrice == 0
                      ? '0đ (Đồng giá thuê)'
                      : (diffPrice < 0
                          ? '${FormatUtils.currency(diffPrice.abs())}đ/tháng (Tiết kiệm)'
                          : '${FormatUtils.currency(diffPrice)}đ/tháng'),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: diffPrice < 0
                        ? const Color(0xFF15803D)
                        : (diffPrice > 0 ? const Color(0xFFD97706) : _textDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'Chênh lệch tiền cọc:',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diffDeposit == 0
                      ? '0đ (Bảo lưu 100%)'
                      : (diffDeposit < 0
                          ? '${FormatUtils.currency(diffDeposit.abs())}đ (Dư cọc - cấn trừ kỳ tới)'
                          : (_isInspectionDone && tongChiPhiPhongCu > 0
                              ? '${FormatUtils.currency(diffDeposit)}đ (Thiếu cọc - cần bù sau trừ chi phí)'
                              : '${FormatUtils.currency(diffDeposit)}đ (Thiếu cọc - cần bù thêm)')),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: diffDeposit < 0
                        ? const Color(0xFF15803D)
                        : (diffDeposit > 0 ? const Color(0xFFDC2626) : _textDark),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: Color(0xFFF1F5F9)),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lý do xin chuyển:',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 3),
              Text(
                '"$displayReason"',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: _textDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: valueColor ?? _textDark,
          ),
        ),
      ],
    );
  }

  // ─── 4. NEXT STEPS CARD (4 BƯỚC CHUẨN) ───
  Widget _buildNextStepsCard(String targetName) {
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
              Icon(Icons.checklist_rounded, color: _primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Quy trình chuyển phòng (4 Bước)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Bước 1: Tiếp nhận & Tạm giữ phòng
          _buildStepRow(
            stepNum: '1',
            title: 'Khách gửi yêu cầu & Giữ phòng $targetName',
            status: 'Hoàn thành',
            desc:
                'Hệ thống đã ghi nhận yêu cầu và tạm khóa phòng $targetName để ưu tiên cho bạn.',
            isActive: true,
          ),
          const SizedBox(height: 12),

          // Bước 2: BQL kiểm tra & Nghiệm thu phòng cũ
          _buildStepRow(
            stepNum: '2',
            title: 'BQL kiểm tra & Nghiệm thu phòng cũ',
            status: _isInspectionDone ? 'Đã kiểm tra' : 'Chờ trong 24h',
            desc: _isInspectionDone
                ? 'Kỹ thuật viên ($_inspectorName) đã lập bảng kê hiện trạng thiết bị và chốt số điện nước.'
                : 'BQL Kiều Giang sẽ kiểm tra hiện trạng thiết bị phòng và chốt điện nước trước ngày dọn.',
            isActive: _isInspectionDone,
            extraWidget: _isInspectionDone
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: _showInspectionDetailModal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_rounded, size: 14, color: _primary),
                            SizedBox(width: 5),
                            Text(
                              'Xem bảng kê biên bản thiết bị',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // Bước 3: Khách thuê xác nhận biên bản & Đối soát cọc
          _buildStepRow(
            stepNum: '3',
            title: 'Khách xác nhận biên bản & Đối soát cọc',
            status: _hasAcceptedInspection
                ? 'Đã xác nhận'
                : (_currentStatus == 'Chờ khách xác nhận'
                    ? 'Cần xác nhận'
                    : 'Chờ sau bước 2'),
            desc: _hasAcceptedInspection
                ? 'Bạn đã ký xác nhận biên bản kiểm tra thiết bị và quyết toán cọc bảo lưu.'
                : (_currentStatus == 'Chờ khách xác nhận'
                    ? 'Biên bản đã sẵn sàng! Vui lòng bấm xem bảng kê và xác nhận để gửi BQL duyệt.'
                    : 'Bạn sẽ kiểm tra đối chiếu chi phí và ký xác nhận sau khi BQL kiểm tra xong.'),
            isActive: _hasAcceptedInspection || _currentStatus == 'Chờ khách xác nhận',
            extraWidget: (_currentStatus == 'Chờ khách xác nhận' && !_hasAcceptedInspection)
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: _showInspectionDetailModal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.touch_app_rounded, size: 14, color: Color(0xFFD97706)),
                            SizedBox(width: 5),
                            Text(
                              'Bấm vào đây để xem & xác nhận biên bản',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // Bước 4: BQL / Chủ trọ phê duyệt chính thức & Bàn giao
          _buildStepRow(
            stepNum: '4',
            title: 'BQL duyệt & Ký phụ lục hợp đồng mới',
            status: _currentStatus == 'Đã duyệt'
                ? 'Đã duyệt'
                : (_currentStatus == 'Chờ chủ duyệt' ? 'Chờ phê duyệt' : 'Chờ các bước trước'),
            desc: _currentStatus == 'Đã duyệt'
                ? 'Hợp đồng đã chuyển sang phòng $targetName, phụ lục đã có hiệu lực và nhận phòng đúng hẹn!'
                : 'Ban Quản Lý sẽ phê duyệt chính thức và cập nhật hợp đồng sau khi bạn ký biên bản.',
            isActive: _currentStatus == 'Đã duyệt',
            extraWidget: _currentStatus == 'Đã duyệt'
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: _showPhuLucDetailModal,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_rounded, size: 14, color: _primary),
                            SizedBox(width: 5),
                            Text(
                              'Xem phụ lục hợp đồng chuyển phòng',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String stepNum,
    required String title,
    required String status,
    required String desc,
    required bool isActive,
    Widget? extraWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isActive ? _primary : const Color(0xFFE2E8F0),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            stepNum,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : const Color(0xFF64748B),
            ),
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
                      title,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: isActive ? _primary : _textDark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isActive ? _primary : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
              ?extraWidget,
            ],
          ),
        ),
      ],
    );
  }

  // ─── 4B. DỰ TOÁN HÓA ĐƠN KỲ TỚI SAU KHI CHUYỂN PHÒNG ───
  Widget _buildNextBillEstimateCard(String targetName) {
    final effectiveTargetName = _targetRoomData?['ma_phong']?.toString() ??
        _maPhongMoiFromDb ??
        widget.targetRoom['maPhong']?.toString() ??
        targetName;
    final double giaThueMoi = ((_targetRoomData?['gia_thue'] as num?) ??
            (widget.targetRoom['giaThue'] as num?) ??
            3500000)
        .toDouble();
    final double dienNuocCu = _utilityFee.toDouble();
    final double huHaiCu = _hasDamage ? _damageFee.toDouble() : 0.0;
    final double curDeposit = _tienCocBaoLuu?.toDouble() ?? widget.currentPrice.toDouble();
    final double tongChiPhiPhongCu = _isInspectionDone ? (dienNuocCu + huHaiCu) : 0.0;
    final double tienCocConLai = (curDeposit - tongChiPhiPhongCu).clamp(0.0, double.infinity);
    final double targetDeposit = ((_targetRoomData?['tien_dat_coc'] as num?) ??
            (widget.targetRoom['tienDatCoc'] as num?) ??
            giaThueMoi)
        .toDouble();
    final double diffDeposit = targetDeposit - tienCocConLai;
    final double chenhLechCoc = diffDeposit > 0 ? diffDeposit : 0.0;
    final double duCocCu = diffDeposit < 0 ? diffDeposit.abs() : 0.0;
    // Tổng hóa đơn dự kiến kỳ tới = tiền phòng mới + bù cọc (sau khi trừ chi phí phòng cũ) - dư cọc (nếu có)
    final double tongHoaDonDuKien = (giaThueMoi + chenhLechCoc - duCocCu).clamp(0.0, double.infinity);

    final bool isApproved = _currentStatus == 'Đã duyệt';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isApproved ? const Color(0xFF86EFAC) : const Color(0xFFBAE6FD),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isApproved ? const Color(0xFF16A34A) : _primary).withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  color: isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: isApproved ? const Color(0xFF16A34A) : _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dự Toán Hóa Đơn Kỳ Tới',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Kết chuyển chi phí sau khi chuyển phòng',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isApproved ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isApproved ? const Color(0xFF86EFAC) : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Text(
                  isApproved ? 'ĐÃ KẾT CHUYỂN' : 'DỰ KIẾN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isApproved ? const Color(0xFF15803D) : _primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 1. Tiền phòng mới
          _buildBillRow(
            'Tiền phòng mới ($effectiveTargetName)',
            TienIchDinhDang.formatCurrency(giaThueMoi),
            icon: Icons.meeting_room_rounded,
            iconColor: _primary,
          ),
          const SizedBox(height: 8),

          // 2. Điện nước phòng cũ
          _buildBillRow(
            'Điện nước chốt phòng cũ (${widget.currentRoomNumber})',
            dienNuocCu > 0 ? '${TienIchDinhDang.formatCurrency(dienNuocCu)} (Đã cấn trừ vào cọc)' : '0đ (Chờ BQL chốt số)',
            icon: Icons.electric_bolt_rounded,
            iconColor: const Color(0xFFD97706),
          ),

          // 3. Khấu trừ hư hại (nếu có)
          if (huHaiCu > 0) ...[
            const SizedBox(height: 8),
            _buildBillRow(
              'Bồi thường hư hại thiết bị phòng cũ',
              '${TienIchDinhDang.formatCurrency(huHaiCu)} (Đã cấn trừ vào cọc)',
              icon: Icons.build_circle_rounded,
              iconColor: const Color(0xFFDC2626),
              valueColor: const Color(0xFFDC2626),
            ),
          ],

          // 4. Bù tiền cọc mới (nếu chuyển phòng đắt hơn hoặc sau trừ chi phí chưa đủ cọc)
          if (chenhLechCoc > 0) ...[
            const SizedBox(height: 8),
            _buildBillRow(
              'Bù chênh lệch tiền cọc phòng $effectiveTargetName',
              '+${TienIchDinhDang.formatCurrency(chenhLechCoc)}',
              icon: Icons.account_balance_wallet_rounded,
              iconColor: const Color(0xFF7C3AED),
              valueColor: const Color(0xFF7C3AED),
            ),
          ],

          // 5. Khấu trừ cọc dư phòng cũ (nếu có dư cọc)
          if (duCocCu > 0) ...[
            const SizedBox(height: 8),
            _buildBillRow(
              'Khấu trừ cọc dư phòng cũ (${widget.currentRoomNumber})',
              '-${TienIchDinhDang.formatCurrency(duCocCu)}',
              icon: Icons.savings_rounded,
              iconColor: const Color(0xFF16A34A),
              valueColor: const Color(0xFF15803D),
            ),
          ],

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFE2E8F0)),
          ),

          // Tổng cộng
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'TỔNG HÓA ĐƠN KỲ TỚI:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _textDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                TienIchDinhDang.formatCurrency(tongHoaDonDuKien),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF09638E),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Hộp giải thích rõ ràng tiền phát sinh gồm những gì
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.help_outline_rounded, size: 14, color: _primary),
                    SizedBox(width: 5),
                    Text(
                      'Tiền phát sinh khi chuyển phòng gồm những gì?',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '• Điện nước & hư hại phòng cũ: Được đo và chốt tại biên bản nghiệm thu, cấn trừ trực tiếp vào tiền cọc phòng cũ.\n'
                  '• Chênh lệch cọc: Nếu tiền cọc cũ sau khi trừ chi phí chưa đủ tiền cọc phòng mới thì bù thêm (+); nếu còn dư cọc thì được TRỪ TRỰC TIẾP (-) vào hóa đơn kỳ tới.',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isApproved
                        ? 'Khoản tiền trên đã được cập nhật vào hóa đơn của bạn trên hệ thống.'
                        : 'Chi phí trên sẽ được BQL kết chuyển tự động vào kỳ thu tiền tiếp theo khi duyệt chuyển phòng.',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.3),
                  ),
                ),
              ],
            ),
          ),

          if (isApproved) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InvoiceHistoryScreen()),
                  );
                },
                icon: const Icon(Icons.receipt_rounded, size: 16, color: _primary),
                label: const Text(
                  'Xem Hóa Đơn Kỳ Tới Của Bạn',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: _primary),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFBAE6FD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBillRow(
    String label,
    String value, {
    required IconData icon,
    required Color iconColor,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 15, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: valueColor ?? _textDark,
          ),
        ),
      ],
    );
  }

  // ─── 5. SUPPORT CARD ───
  Widget _buildSupportCard() {
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
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ban Quản Lý Nhà Trọ Kiêu Giang',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Yêu cầu chuyển phòng & dự thảo phụ lục đang được BQL tiếp nhận và xử lý trong 24 giờ làm việc.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 6. ACTION BUTTONS (ĐỘNG THEO TIẾN ĐỘ) ───
  Widget _buildActionButtons() {
    if (_currentStatus == 'Chờ khách xác nhận') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showInspectionDetailModal,
              icon: const Icon(Icons.verified_rounded, size: 20),
              label: const Text(
                'XÁC NHẬN BIÊN BẢN & GỬI LÊN CHỦ TRỌ',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Về Trang Chủ',
                style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    } else if (_currentStatus == 'Đã duyệt') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.vpn_key_rounded, size: 20),
              label: Text(
                'XEM PHÒNG MỚI (${_targetRoomData?["ma_phong"] ?? _maPhongMoiFromDb ?? widget.targetRoom["maPhong"]})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showPhuLucDetailModal,
              icon: const Icon(Icons.description_rounded, size: 18, color: Color(0xFF0284C7)),
              label: const Text(
                'XEM PHỤ LỤC HỢP ĐỒNG (PLCP)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0284C7),
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(color: Color(0xFF38BDF8), width: 1.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: const Color(0xFFF0F9FF),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              child: const Text(
                'Về Trang Chủ',
                style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.popUntil(context, (route) => route.isFirst);
        },
        icon: const Icon(Icons.home_rounded, size: 18),
        label: const Text(
          'Về Trang Chủ',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // ─── 7. BOTTOM NAVIGATION BAR ───
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
          Navigator.popUntil(context, (route) => route.isFirst);
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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhGiuCho.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';

class DepositService {
  static const double depositAmount = 100000.0; // 100k
  static const int maxHoldDays = 5; // Tối đa 5 ngày
  static const int paymentTimeoutMinutes = 15; // 15 phút đếm ngược

  /// Kiểm tra tính hợp lệ của ngày dự kiến vào ở:
  /// - Không cho đặt ở quá khứ
  /// - Tối đa 5 ngày kể từ ngày hiện tại
  static ({bool isValid, String? error}) validateExpectedDate(DateTime selectedDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chosen = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    if (chosen.isBefore(today)) {
      return (
        isValid: false,
        error: 'Không được chọn ngày dự kiến vào ở trong quá khứ!',
      );
    }

    final maxDate = today.add(const Duration(days: maxHoldDays));
    if (chosen.isAfter(maxDate)) {
      return (
        isValid: false,
        error:
            'Tiền thế chân 100k chỉ cho phép giữ chỗ tối đa 5 ngày (đến ngày ${maxDate.day.toString().padLeft(2, '0')}/${maxDate.month.toString().padLeft(2, '0')}/${maxDate.year})!',
      );
    }

    return (isValid: true, error: null);
  }

  /// Tiến hành đặt cọc phòng:
  /// Gọi RPC/Kiểm tra trạng thái phòng, nếu bị trùng sẽ ném HTTP 409 Conflict.
  /// Tạo phiếu giữ chỗ với trang_thai = 'ChoThanhToan', expires_at = NOW() + 15 phút.
  static Future<GiuChoModel> tienHanhDatCoc({
    required RoomModel room,
    required String hoTen,
    required String soDt,
    required DateTime ngayDuKienO,
    required int soNguoiO,
    String? ghiChu,
  }) async {
    // 1. Kiểm tra ràng buộc ngày
    final dateCheck = validateExpectedDate(ngayDuKienO);
    if (!dateCheck.isValid) {
      throw Exception(dateCheck.error);
    }

    final db = Supabase.instance.client;
    final cleanPhone = soDt.trim().replaceAll(' ', '');
    final cleanName = hoTen.trim();

    // 2. Thử gọi RPC Postgres 'dat_coc_phong' nếu có
    try {
      final rpcRes = await db.rpc('dat_coc_phong', params: {
        'p_ma_phong': room.maPhong,
        'p_ho_ten': cleanName,
        'p_so_dt': cleanPhone,
        'p_ngay_du_kien_o':
            '${ngayDuKienO.year}-${ngayDuKienO.month.toString().padLeft(2, '0')}-${ngayDuKienO.day.toString().padLeft(2, '0')}',
        'p_so_nguoi_o': soNguoiO,
        'p_ghi_chu': ghiChu ?? '',
      });

      if (rpcRes != null && rpcRes is Map) {
        final maGiuCho = rpcRes['ma_giu_cho']?.toString() ?? '';
        final resRow = await db
            .from('giu_cho')
            .select()
            .eq('ma_giu_cho', maGiuCho)
            .maybeSingle();
        if (resRow != null) {
          return GiuChoModel.fromJson(Map<String, dynamic>.from(resRow));
        }
      }
    } catch (e) {
      debugPrint('[RPC dat_coc_phong notice/fallback]: $e');
      final errStr = e.toString().toUpperCase();
      if (errStr.contains('409') ||
          errStr.contains('CONFLICT') ||
          errStr.contains('PHONG_DA_DAT')) {
        throw Exception(
          'HTTP 409 (Conflict): Phòng ${room.tenHienThi} vừa được khách khác đặt hoặc đã có người thuê! Giao dịch bị từ chối.',
        );
      }
    }

    // 3. Fallback xử lý trực tiếp nguyên tử trên Supabase Client
    // A. Kiểm tra dòng phòng hiện tại (FOR UPDATE logic)
    final phongRow = await db
        .from('phong')
        .select('ma_phong, trang_thai, ten_hien_thi')
        .eq('ma_phong', room.maPhong)
        .maybeSingle();

    if (phongRow == null) {
      throw Exception('Không tìm thấy thông tin phòng ${room.maPhong}!');
    }

    final currentStatus = phongRow['trang_thai']?.toString().trim() ?? '';
    if (currentStatus.toLowerCase() != 'trống') {
      throw Exception(
        'HTTP 409 (Conflict): Phòng ${room.tenHienThi} hiện không khả dụng (Trạng thái: $currentStatus). Vui lòng chọn phòng khác!',
      );
    }

    // B. Kiểm tra bảng giu_cho xem phòng có ai đang giữ chỗ trong 15 phút không
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final activeHold = await db
        .from('giu_cho')
        .select('ma_giu_cho, trang_thai, expires_at')
        .eq('ma_phong', room.maPhong)
        .or('trang_thai.eq.DangGiu,trang_thai.eq.DaDatCoc,and(trang_thai.eq.ChoThanhToan,expires_at.gt.$nowIso)')
        .maybeSingle();

    if (activeHold != null) {
      throw Exception(
        'HTTP 409 (Conflict): Phòng ${room.tenHienThi} vừa có khách khác giữ chỗ trước bạn! Vui lòng chọn phòng khác.',
      );
    }

    // C. Tìm hoặc tạo hồ sơ khách trong khach_thue
    String maKhach = 'KH_${cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 8) : cleanPhone}';
    try {
      final khachRow = await db
          .from('khach_thue')
          .select('ma_khach')
          .eq('so_dt', cleanPhone)
          .maybeSingle();

      if (khachRow != null && khachRow['ma_khach'] != null) {
        maKhach = khachRow['ma_khach'].toString();
      } else {
        await db.from('khach_thue').insert({
          'ma_khach': maKhach,
          'ho_ten_khach': cleanName,
          'so_dt': cleanPhone,
          'dia_chi_thuong_tru': 'Khách đặt cọc giữ chỗ online',
        });
      }
    } catch (eKhach) {
      debugPrint('[khach_thue upsert notice]: $eKhach');
    }

    // D. Chuyển phòng sang 'Đã cọc'
    await db.from('phong').update({
      'trang_thai': 'Đã cọc',
    }).eq('ma_phong', room.maPhong);

    // E. Tạo phiếu giữ chỗ lưu trạng thái 'ChoThanhToan', gán expires_at = NOW() + 15 phút
    final maGiuCho = 'GC_${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: paymentTimeoutMinutes));
    final ngayHetHan = now.add(const Duration(days: maxHoldDays));

    final giuCho = GiuChoModel(
      maGiuCho: maGiuCho,
      maPhong: room.maPhong,
      maKhach: maKhach,
      soTienTheChan: depositAmount,
      thoiGianGiuCho: now,
      ngayHetHan: ngayHetHan,
      trangThai: 'ChoThanhToan',
      expiresAt: expiresAt,
      soNguoiO: soNguoiO,
      ngayDuKienO: ngayDuKienO,
      ghiChu: ghiChu?.trim().isEmpty == true
          ? 'Đặt cọc giữ chỗ phòng ${room.maPhong}'
          : ghiChu?.trim(),
    );

    await db.from('giu_cho').insert(giuCho.toJson());

    return giuCho;
  }

  /// Xác nhận thanh toán tiền thế chân thành công:
  /// Cập nhật giu_cho -> 'DangGiu', phong -> 'Đã cọc'
  static Future<void> xacNhanThanhToanTheChan({
    required String maGiuCho,
    required String maPhong,
  }) async {
    final db = Supabase.instance.client;

    await db.from('giu_cho').update({
      'trang_thai': 'DangGiu',
    }).eq('ma_giu_cho', maGiuCho);

    await db.from('phong').update({
      'trang_thai': 'Đã cọc',
    }).eq('ma_phong', maPhong);
  }

  /// Xử lý hết hạn 15 phút không thanh toán:
  /// Chuyển giu_cho -> 'HetHan', phòng lập tức trở về 'Trống'
  static Future<void> xuLyHetHanGiuCho({
    required String maGiuCho,
    required String maPhong,
  }) async {
    final db = Supabase.instance.client;

    try {
      await db.from('giu_cho').update({
        'trang_thai': 'HetHan',
      }).eq('ma_giu_cho', maGiuCho);

      await db.from('phong').update({
        'trang_thai': 'Trống',
      }).eq('ma_phong', maPhong);
    } catch (e) {
      debugPrint('Lỗi xuLyHetHanGiuCho: $e');
    }
  }

  /// Lắng nghe trạng thái phiếu giữ chỗ theo thời gian thực (Supabase Realtime)
  static Stream<List<Map<String, dynamic>>> streamGiuCho(String maGiuCho) {
    return Supabase.instance.client
        .from('giu_cho')
        .stream(primaryKey: ['ma_giu_cho'])
        .eq('ma_giu_cho', maGiuCho);
  }
}

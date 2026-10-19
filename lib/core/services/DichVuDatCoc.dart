import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhGiuCho.dart';
import 'package:nhatro_kieugiang/data/models/MoHinhPhong.dart';

class DepositService {
  static const double depositPercent = 0.10; // 10% giá thuê phòng
  static const int maxHoldDays = 5; // Tối đa 5 ngày
  static const int paymentTimeoutMinutes = 15; // 15 phút đếm ngược

  /// Tính tiền thế chân giữ chỗ: 10% giá thuê phòng
  static double getDepositAmount(num giaThue) {
    if (giaThue <= 0) return 300000.0;
    return (giaThue * depositPercent).roundToDouble();
  }

  /// Tương thích ngược
  static double get depositAmount => 300000.0;

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
            'Tiền thế chân chỉ cho phép giữ chỗ tối đa 5 ngày (đến ngày ${maxDate.day.toString().padLeft(2, '0')}/${maxDate.month.toString().padLeft(2, '0')}/${maxDate.year})!',
      );
    }

    return (isValid: true, error: null);
  }

  /// Kiểm tra số điện thoại đã có tài khoản trên hệ thống hoặc đang có hợp đồng hiệu lực hay chưa
  static Future<bool> hasExistingAccount(String phone) async {
    final cleanPhone = phone.trim().replaceAll(RegExp(r'[\s\.\-\(\)]+'), '');
    if (cleanPhone.isEmpty) return false;

    // Chuẩn hóa dạng 0xxxxxxxxx
    String normalized = cleanPhone;
    if (normalized.startsWith('+84')) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('84') && normalized.length >= 10) {
      normalized = '0${normalized.substring(2)}';
    }

    final db = Supabase.instance.client;
    try {
      // 1. Kiểm tra trong bảng tai_khoan (cột ten_dang_nhap)
      final tkRow = await db
          .from('tai_khoan')
          .select('ma_tai_khoan, ten_dang_nhap')
          .or('ten_dang_nhap.eq.$cleanPhone,ten_dang_nhap.eq.$normalized')
          .limit(1)
          .maybeSingle();

      if (tkRow != null) {
        debugPrint('[hasExistingAccount]: Số $cleanPhone ($normalized) khớp tài khoản ${tkRow['ma_tai_khoan']} (${tkRow['ten_dang_nhap']})');
        return true;
      }

      // 2. Kiểm tra trong bảng khach_thue (so_dt có ma_tai_khoan hoặc đang có hợp đồng hiệu lực)
      final ktRows = await db
          .from('khach_thue')
          .select('ma_khach, ma_tai_khoan, so_dt')
          .or('so_dt.eq.$cleanPhone,so_dt.eq.$normalized')
          .limit(5);

      if (ktRows.isNotEmpty) {
        for (final row in ktRows) {
          final mtk = row['ma_tai_khoan']?.toString();
          if (mtk != null && mtk.trim().isNotEmpty && mtk.trim().toLowerCase() != 'null') {
            debugPrint('[hasExistingAccount]: Số $cleanPhone ($normalized) khớp khách thuê ${row['ma_khach']} có tài khoản $mtk');
            return true;
          }
        }

        // Kiểm tra xem khách này có hợp đồng đang thuê/còn hạn không
        final maKhachList = ktRows
            .map((e) => e['ma_khach']?.toString())
            .whereType<String>()
            .toList();
        if (maKhachList.isNotEmpty) {
          final activeHds = await db
              .from('hop_dong')
              .select('ma_hop_dong')
              .inFilter('ma_khach_dai_dien', maKhachList)
              .inFilter('trang_thai', ['Đang thuê', 'Còn hạn', 'HieuLuc'])
              .limit(1);
          if (activeHds.isNotEmpty) {
            debugPrint('[hasExistingAccount]: Số $cleanPhone ($normalized) thuộc khách thuê đang có hợp đồng hiệu lực');
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[hasExistingAccount error]: $e');
    }
    return false;
  }

  /// Kiểm tra xem phòng có đang bị khóa (đang có người thuê, hợp đồng còn hạn, đã cọc, đang giữ chỗ bởi khách khác, hoặc có lịch hẹn đã duyệt)
  static Future<bool> isRoomLocked(String maPhong, {String? excludePhone}) async {
    final db = Supabase.instance.client;
    final nowUtc = DateTime.now().toUtc();
    try {
      final cleanExcludePhone = excludePhone?.trim().replaceAll(' ', '');
      String? excludeMaKhach;
      if (cleanExcludePhone != null && cleanExcludePhone.isNotEmpty) {
        final phoneSuffix = cleanExcludePhone.length >= 6
            ? cleanExcludePhone.substring(cleanExcludePhone.length - 6)
            : cleanExcludePhone.padLeft(6, '0');
        excludeMaKhach = 'KH$phoneSuffix';
        try {
          final kRow = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('so_dt', cleanExcludePhone)
              .maybeSingle();
          if (kRow != null && kRow['ma_khach'] != null) {
            excludeMaKhach = kRow['ma_khach'].toString();
          }
        } catch (_) {}
      }

      // 1. Kiểm tra bảng hop_dong xem phòng có người đang thuê / hợp đồng còn hạn
      final hdRow = await db
          .from('hop_dong')
          .select('ma_hop_dong')
          .eq('ma_phong', maPhong)
          .inFilter('trang_thai', ['Đang thuê', 'Còn hạn', 'HieuLuc'])
          .maybeSingle();
      if (hdRow != null) return true;

      // 2. Kiểm tra bảng giu_cho
      final gcList = await db
          .from('giu_cho')
          .select('ma_giu_cho, ma_khach, trang_thai, expires_at')
          .eq('ma_phong', maPhong);

      bool hasOtherLocked = false;
      bool hasSelfPending = false;

      for (final row in (gcList as List)) {
        final st = row['trang_thai']?.toString();
        final rowMaKhach = row['ma_khach']?.toString();
        final isSelf = (excludeMaKhach != null && rowMaKhach == excludeMaKhach);

        if (st == 'Đã thanh toán' || st == 'DangGiu' || st == 'DaDatCoc') {
          return true; // Đã thanh toán tiền cọc thành công thì phòng đã được chốt
        }

        if (st == 'ChoThanhToan') {
          final expStr = row['expires_at']?.toString();
          if (expStr != null && expStr.isNotEmpty) {
            final exp = DateTime.tryParse(expStr)?.toUtc();
            if (exp != null && exp.isAfter(nowUtc)) {
              if (isSelf) {
                hasSelfPending = true;
              } else {
                hasOtherLocked = true;
              }
            }
          }
        }
      }

      if (hasOtherLocked) return true;

      // 4. Kiểm tra trạng thái trực tiếp trên bảng phong
      final pRow = await db
          .from('phong')
          .select('trang_thai')
          .eq('ma_phong', maPhong)
          .maybeSingle();
      if (pRow != null) {
        final st = pRow['trang_thai']?.toString().trim().toLowerCase() ?? '';
        if (st.isNotEmpty && st != 'trống') {
          // Nếu phòng đang là 'đã cọc' nhưng không có ai cọc thật, hoặc là phiên dở dang của chính khách này
          if (st == 'đã cọc' && !hasOtherLocked && (hasSelfPending || excludePhone == null)) {
            return false;
          }
          return true;
        }
      }
    } catch (e) {
      debugPrint('[isRoomLocked error]: $e');
    }
    return false;
  }

  /// Hủy phiên giữ chỗ dở dang khi khách thoát màn hình thanh toán mà chưa chuyển tiền:
  /// - Chuyển giu_cho -> 'DaHuy' (nếu chưa thanh toán)
  /// - Lập tức hoàn lại trạng thái phòng về 'Trống'
  /// - Xóa lịch hẹn nháp tương ứng trên bảng dat_lich_xem_phong
  static Future<void> huyGiuChoKhiThoat({
    required String maGiuCho,
    required String maPhong,
    String? appointmentCode,
  }) async {
    final db = Supabase.instance.client;
    try {
      // 1. Kiểm tra trạng thái thực tế của phiếu giữ chỗ
      final checkRow = await db
          .from('giu_cho')
          .select('trang_thai')
          .eq('ma_giu_cho', maGiuCho)
          .maybeSingle();

      if (checkRow != null) {
        final currentSt = checkRow['trang_thai']?.toString() ?? '';
        if (currentSt == 'Đã thanh toán' ||
            currentSt == 'DangGiu' ||
            currentSt == 'DaDatCoc') {
          debugPrint(
            '[huyGiuChoKhiThoat] Phiếu $maGiuCho đã thanh toán ($currentSt), giữ nguyên không hủy.',
          );
          return;
        }
      }

      // 2. Chuyển phiếu giữ chỗ sang 'DaHuy'
      await db.from('giu_cho').update({
        'trang_thai': 'DaHuy',
        'expires_at': null,
      }).eq('ma_giu_cho', maGiuCho);

      // 3. Trả phòng về 'Trống' ngay lập tức
      await db.from('phong').update({
        'trang_thai': 'Trống',
      }).eq('ma_phong', maPhong);

      debugPrint(
        '[huyGiuChoKhiThoat] Đã hủy phiên giữ chỗ $maGiuCho, trả phòng $maPhong về Trống.',
      );
    } catch (e) {
      debugPrint('[huyGiuChoKhiThoat error]: $e');
    }
  }

  static final Set<String> _processingRooms = <String>{};

  /// Tiến hành đặt cọc phòng:
  /// Kiểm tra trạng thái phòng, nếu bị trùng sẽ ném Exception.
  /// Nếu chính khách hàng này đã có phiếu ChoThanhToan còn hạn (15p) cho phòng này, tái sử dụng luôn phiếu đó,
  /// tuyệt đối không tạo thêm phiếu mới để tránh sinh 2 phiếu giữ chỗ.
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

    // 2. RÀNG BUỘC: Nếu số điện thoại đã có tài khoản trên hệ thống thì không cho giữ chỗ
    final hasAcc = await hasExistingAccount(soDt);
    if (hasAcc) {
      throw Exception(
        'Số điện thoại $soDt đã có tài khoản trên hệ thống. Theo quy định, số điện thoại đã đăng ký tài khoản không thể đặt giữ chỗ. Vui lòng sử dụng số điện thoại khác bạn nhé!',
      );
    }

    // Đợi nếu phòng này đang trong quá trình xử lý giữ chỗ song song
    while (_processingRooms.contains(room.maPhong)) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _processingRooms.add(room.maPhong);

    try {
      final db = Supabase.instance.client;
      final cleanPhone = soDt.trim().replaceAll(' ', '');
      final cleanName = hoTen.trim();
      final nowUtc = DateTime.now().toUtc();

      // Chuẩn bị maKhach (maKhach <= 10 ký tự)
      final phoneSuffix = cleanPhone.length >= 6
          ? cleanPhone.substring(cleanPhone.length - 6)
          : cleanPhone.padLeft(6, '0');
      String maKhach = 'KH$phoneSuffix';
      try {
        final khachRow = await db
            .from('khach_thue')
            .select('ma_khach')
            .eq('so_dt', cleanPhone)
            .maybeSingle();

        if (khachRow != null && khachRow['ma_khach'] != null) {
          maKhach = khachRow['ma_khach'].toString();
        } else {
          final checkDup = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('ma_khach', maKhach)
              .maybeSingle();
          if (checkDup != null) {
            final rand = (cleanPhone.hashCode.abs() % 900000) + 100000;
            maKhach = 'KH$rand';
          }

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

      // 2. Xử lý trực tiếp nguyên tử trên Supabase Client
      // A. Kiểm tra hợp đồng đang thuê / còn hạn trong bảng hop_dong
      final hdRow = await db
          .from('hop_dong')
          .select('ma_hop_dong, trang_thai')
          .eq('ma_phong', room.maPhong)
          .inFilter('trang_thai', ['Đang thuê', 'Còn hạn', 'HieuLuc'])
          .maybeSingle();

      if (hdRow != null) {
        final displayName = room.tenHienThi.trim();
        final cleanRoom = displayName.toLowerCase().startsWith('phòng')
            ? displayName
            : 'Phòng $displayName';
        throw Exception(
          '$cleanRoom hiện đang có cư dân thuê (hợp đồng có hiệu lực). Vui lòng chọn phòng khác bạn nhé!',
        );
      }

      // B. Kiểm tra bảng giu_cho xem phòng có ai đang giữ chỗ trong 15 phút không
      final gcList = await db
          .from('giu_cho')
          .select('ma_giu_cho, ma_khach, trang_thai, expires_at')
          .eq('ma_phong', room.maPhong);

      for (final row in (gcList as List)) {
        final st = row['trang_thai']?.toString();
        final rowMaKhach = row['ma_khach']?.toString();
        final mgc = row['ma_giu_cho']?.toString();
        final displayName = room.tenHienThi.trim();
        final cleanRoom = displayName.toLowerCase().startsWith('phòng')
            ? displayName
            : 'Phòng $displayName';

        if (st == 'Đã thanh toán' || st == 'DangGiu' || st == 'DaDatCoc') {
          throw Exception(
            '$cleanRoom hiện đã có khách đặt cọc giữ chỗ. Vui lòng chọn phòng khác bạn nhé!',
          );
        }

        if (st == 'ChoThanhToan') {
          final expStr = row['expires_at']?.toString();
          final exp = expStr != null ? DateTime.tryParse(expStr)?.toUtc() : null;
          final isStillValid = exp != null && exp.isAfter(nowUtc);

          // B.1 NẾU LÀ PHIÊN CỦA CHÍNH KHÁCH NÀY VÀ CÒN HẠN 15 PHÚT: TÁI SỬ DỤNG, KHÔNG TẠO MỚI!
          if (rowMaKhach == maKhach && isStillValid && mgc != null) {
            debugPrint('[tienHanhDatCoc]: Tái sử dụng phiếu giữ chỗ còn hiệu lực $mgc cho khách $maKhach');
            final formattedDate =
                '${ngayDuKienO.year}-${ngayDuKienO.month.toString().padLeft(2, '0')}-${ngayDuKienO.day.toString().padLeft(2, '0')}';
            final updateNote = ghiChu?.trim().isEmpty == true
                ? 'Đặt cọc giữ chỗ phòng ${room.maPhong}'
                : ghiChu?.trim();

            await db.from('giu_cho').update({
              'ngay_du_kien_o': formattedDate,
              'so_nguoi_o': soNguoiO,
              'ghi_chu': updateNote,
            }).eq('ma_giu_cho', mgc);

            final reloaded = await db
                .from('giu_cho')
                .select()
                .eq('ma_giu_cho', mgc)
                .maybeSingle();
            if (reloaded != null) {
              return GiuChoModel.fromJson(Map<String, dynamic>.from(reloaded));
            }
          }

          // B.2 Nếu là phiên cũ của chính khách này nhưng đã hết hạn, hoặc phiên của người khác đã hết hạn: hủy đi
          if (!isStillValid) {
            if (mgc != null) {
              await db.from('giu_cho').update({
                'trang_thai': 'DaHuy',
                'expires_at': null,
              }).eq('ma_giu_cho', mgc);
            }
          } else {
            // Là của khách khác đang trong 15 phút
            throw Exception(
              '$cleanRoom hiện đang có khách khác giữ chỗ thế chân (đang đếm ngược 15 phút). Vui lòng chọn phòng khác bạn nhé!',
            );
          }
        }
      }

    // C. Kiểm tra dòng phòng hiện tại
    final phongRow = await db
        .from('phong')
        .select('ma_phong, trang_thai, ten_hien_thi')
        .eq('ma_phong', room.maPhong)
        .maybeSingle();

    if (phongRow == null) {
      throw Exception('Không tìm thấy thông tin phòng ${room.maPhong}!');
    }

    final currentStatus = phongRow['trang_thai']?.toString().trim() ?? '';
    final statusLower = currentStatus.toLowerCase();
    if (statusLower != 'trống') {
      final displayName = room.tenHienThi.trim();
      final cleanRoom = displayName.toLowerCase().startsWith('phòng')
          ? displayName
          : 'Phòng $displayName';

      // Nếu phòng là 'đã cọc' nhưng không có cọc thật nào của người khác
      // thì đây chỉ là tàn dư của phiên ChoThanhToan cũ, cho phép ghi đè tiếp tục
      if (statusLower == 'đang thuê') {
        throw Exception(
          '$cleanRoom hiện đã có cư dân đang thuê. Vui lòng chọn phòng khác bạn nhé!',
        );
      }
    }

    // D. Chuyển phòng sang 'Đã cọc'
    await db.from('phong').update({
      'trang_thai': 'Đã cọc',
    }).eq('ma_phong', room.maPhong);

    // E. Tạo phiếu giữ chỗ lưu trạng thái 'ChoThanhToan' (maGiuCho <= 10 ký tự chuẩn VARCHAR(10))
    final tsStr = DateTime.now().millisecondsSinceEpoch.toString();
    final maGiuCho = 'GC${tsStr.substring(tsStr.length - 7)}';
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: paymentTimeoutMinutes));
    final ngayHetHan = now.add(const Duration(days: maxHoldDays));

    final actualDeposit = getDepositAmount(room.giaThue);

    final giuCho = GiuChoModel(
      maGiuCho: maGiuCho,
      maPhong: room.maPhong,
      maKhach: maKhach,
      soTienTheChan: actualDeposit,
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
  } finally {
    _processingRooms.remove(room.maPhong);
  }
}

  /// Xác nhận thanh toán tiền thế chân thành công:
  /// Cập nhật giu_cho -> 'Đã thanh toán', xóa expires_at để không bị tính hết hạn, phong -> 'Đã cọc'.
  /// Và đồng bộ cuộc hẹn vào dat_lich_xem_phong trên Supabase với trạng thái 'Chờ duyệt'.
  static Future<void> xacNhanThanhToanTheChan({
    required String maGiuCho,
    required String maPhong,
    String? appointmentCode,
    String? phone,
    String? customerName,
    String? appointmentDate,
    String? timeSlot,
    int? guestCount,
    String? note,
  }) async {
    final db = Supabase.instance.client;

    // 1. Cập nhật phiếu giữ chỗ giu_cho -> 'Đã thanh toán'
    await db.from('giu_cho').update({
      'trang_thai': 'Đã thanh toán',
      'expires_at': null,
    }).eq('ma_giu_cho', maGiuCho);

    // 2. Cập nhật trạng thái phòng -> 'Đã cọc'
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
      // Bảo vệ: Nếu phiếu giữ chỗ đã thanh toán thành công ('Đã thanh toán', 'DangGiu' hoặc 'DaDatCoc') thì tuyệt đối KHÔNG hủy!
      final checkRow = await db
          .from('giu_cho')
          .select('trang_thai')
          .eq('ma_giu_cho', maGiuCho)
          .maybeSingle();

      if (checkRow != null) {
        final currentSt = checkRow['trang_thai']?.toString() ?? '';
        if (currentSt == 'Đã thanh toán' || currentSt == 'DangGiu' || currentSt == 'DaDatCoc') {
          debugPrint(
            '[xuLyHetHanGiuCho] Phiếu $maGiuCho đã thanh toán ($currentSt), bỏ qua không hủy.',
          );
          return;
        }
      }

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

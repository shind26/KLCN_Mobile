/// Model cho bảng `hop_dong`
class HopDongModel {
  final String maHopDong;
  final String ngayBd;
  final String ngayKt;
  final num tienDatCoc;
  final num giaThueThaoThuan;
  final int chuKyThuTien;
  final String trangThai;
  final String maPhong;
  final String maKhachDaiDien;
  final String ngayKy;

  HopDongModel({
    required this.maHopDong,
    required this.ngayBd,
    required this.ngayKt,
    required this.tienDatCoc,
    required this.giaThueThaoThuan,
    required this.chuKyThuTien,
    required this.trangThai,
    required this.maPhong,
    required this.maKhachDaiDien,
    required this.ngayKy,
  });

  factory HopDongModel.fromJson(Map<String, dynamic> json) {
    return HopDongModel(
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
      ngayBd: json['ngay_bd']?.toString() ?? '',
      ngayKt: json['ngay_kt']?.toString() ?? '',
      tienDatCoc: num.tryParse(json['tien_dat_coc']?.toString() ?? '') ?? 0,
      giaThueThaoThuan: num.tryParse(json['gia_thue_thoa_thuan']?.toString() ?? '') ?? 0,
      chuKyThuTien: num.tryParse(json['chu_ky_thu_tien']?.toString() ?? '')?.toInt() ?? 1,
      trangThai: json['trang_thai']?.toString() ?? '',
      maPhong: json['ma_phong']?.toString() ?? '',
      maKhachDaiDien: json['ma_khach_dai_dien']?.toString() ?? '',
      ngayKy: json['ngay_ky']?.toString() ?? '',
    );
  }

  /// Số ngày còn lại đến ngày kết thúc hợp đồng
  int get soNgayConLai {
    try {
      final kt = DateTime.parse(ngayKt);
      return kt.difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  /// Số ngày đã lưu trú kể từ ngày bắt đầu hợp đồng
  int get soNgayDaO {
    try {
      final bd = DateTime.parse(ngayBd);
      final diff = DateTime.now().difference(bd).inDays;
      return diff < 0 ? 0 : diff;
    } catch (_) {
      return 0;
    }
  }

  /// Quy định thực tế của BQL: Cư dân cần ở tối thiểu 60 ngày (2 tháng) tại phòng hiện tại mới được xin chuyển phòng
  bool get duDieuKienThoiGianChuyenPhong => soNgayDaO >= 60;

  /// Số ngày còn thiếu để đủ 60 ngày (2 tháng) xin chuyển phòng
  int get soNgayConThieuChuyenPhong {
    final daO = soNgayDaO;
    return daO >= 60 ? 0 : (60 - daO);
  }

  /// Định dạng ngày dd/MM/yyyy
  String _formatDate(String raw) {
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String get ngayBdFormatted => _formatDate(ngayBd);
  String get ngayKtFormatted => _formatDate(ngayKt);
  String get ngayKyFormatted => _formatDate(ngayKy);

  /// Tổng số tháng thực tế của hợp đồng (tính từ ngayBd đến ngayKt)
  int get tongSoThang {
    try {
      final bd = DateTime.parse(ngayBd);
      final kt = DateTime.parse(ngayKt);
      int m = (kt.year - bd.year) * 12 + (kt.month - bd.month);
      if (kt.day >= 25 || (kt.day - bd.day) >= 20) {
        m += 1;
      }
      return m > 0 ? m : 1;
    } catch (_) {
      return 12;
    }
  }

  /// Tổng số ngày của hợp đồng
  int get tongSoNgay {
    try {
      final bd = DateTime.parse(ngayBd);
      final kt = DateTime.parse(ngayKt);
      return kt.difference(bd).inDays;
    } catch (_) {
      return 365;
    }
  }

  /// Chuỗi hiển thị thời hạn hợp đồng chuẩn xác
  String get thoiHanHopDongText {
    final m = tongSoThang;
    if (m % 12 == 0) {
      final y = m ~/ 12;
      return '$m tháng (${y} năm)';
    }
    return '$m tháng';
  }
}

/// Model cho bảng `khach_thue`
class KhachThueModel {
  final String maKhach;
  final String hoTenKhach;
  final String soDt;
  final String cccd;
  final String diaChiThuongTru;
  final String? maTaiKhoan;
  // vai_tro từ chi_tiet_hop_dong
  String vaiTro;
  String trangThaiLuuTru;

  KhachThueModel({
    required this.maKhach,
    required this.hoTenKhach,
    required this.soDt,
    required this.cccd,
    required this.diaChiThuongTru,
    this.maTaiKhoan,
    this.vaiTro = '',
    this.trangThaiLuuTru = '',
  });

  factory KhachThueModel.fromJson(Map<String, dynamic> json) {
    return KhachThueModel(
      maKhach: json['ma_khach']?.toString() ?? '',
      hoTenKhach: json['ho_ten_khach']?.toString() ?? '',
      soDt: json['so_dt']?.toString() ?? '',
      cccd: json['cccd']?.toString() ?? '',
      diaChiThuongTru: json['dia_chi_thuong_tru']?.toString() ?? '',
      maTaiKhoan: json['ma_tai_khoan']?.toString(),
      vaiTro: json['vai_tro']?.toString() ?? '',
      trangThaiLuuTru: json['trang_thai_luu_tru']?.toString() ?? '',
    );
  }

  /// Ẩn CCCD chỉ hiển thị 3 số cuối
  String get cccdMasked {
    if (cccd.length > 5) {
      return '${cccd.substring(0, 3)}*****${cccd.substring(cccd.length - 3)}';
    }
    return cccd;
  }

  /// Ẩn SĐT
  String get sdtMasked {
    if (soDt.length >= 7) {
      return '${soDt.substring(0, 3)} *** ${soDt.substring(soDt.length - 3)}';
    }
    return soDt;
  }
}

/// Model cho bảng `phu_luc_hop_dong`
class PhuLucHopDongModel {
  final String maPhuLuc;
  final String ngayLap;
  final String noiDungDieuChinh;
  final num giaTheMoi;
  final num chenhLechTienCoc;
  final String ngayGiaHanDen;
  final String maHopDong;
  final String? maPhongMoi;
  final String? trangThai;

  PhuLucHopDongModel({
    required this.maPhuLuc,
    required this.ngayLap,
    required this.noiDungDieuChinh,
    required this.giaTheMoi,
    required this.chenhLechTienCoc,
    required this.ngayGiaHanDen,
    required this.maHopDong,
    this.maPhongMoi,
    this.trangThai,
  });

  factory PhuLucHopDongModel.fromJson(Map<String, dynamic> json) {
    return PhuLucHopDongModel(
      maPhuLuc: json['ma_phu_luc']?.toString() ?? '',
      ngayLap: json['ngay_lap']?.toString() ?? '',
      noiDungDieuChinh: json['noi_dung_dieu_chinh']?.toString() ?? '',
      giaTheMoi: num.tryParse(json['gia_thue_moi']?.toString() ?? '') ?? 0,
      chenhLechTienCoc: num.tryParse(json['chenh_lech_tien_coc']?.toString() ?? '') ?? 0,
      ngayGiaHanDen: json['ngay_gia_han_den']?.toString() ?? '',
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
      maPhongMoi: json['ma_phong_moi']?.toString(),
      trangThai: json['trang_thai']?.toString(),
    );
  }

  String _fmt(String raw) {
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String get ngayLapFormatted => _fmt(ngayLap);
  String get ngayGiaHanDenFormatted => _fmt(ngayGiaHanDen);
}

/// Model cho bảng `hoa_don`
class HoaDonModel {
  final String maHoaDon;
  final String ngayLap;
  final String hanDongTien;
  final num tienPhong;
  final num tienDienNuoc;
  final num tienDichVuKhac;
  final num noCu;
  final num tongTien;
  final String trangThai;
  final String loaiGiaoDich;
  final String maHopDong;

  HoaDonModel({
    required this.maHoaDon,
    required this.ngayLap,
    required this.hanDongTien,
    required this.tienPhong,
    required this.tienDienNuoc,
    required this.tienDichVuKhac,
    required this.noCu,
    required this.tongTien,
    required this.trangThai,
    required this.loaiGiaoDich,
    required this.maHopDong,
  });

  factory HoaDonModel.fromJson(Map<String, dynamic> json) {
    return HoaDonModel(
      maHoaDon: json['ma_hoa_don']?.toString() ?? '',
      ngayLap: json['ngay_lap']?.toString() ?? '',
      hanDongTien: json['han_dong_tien']?.toString() ?? '',
      tienPhong: num.tryParse(json['tien_phong']?.toString() ?? '') ?? 0,
      tienDienNuoc: num.tryParse(json['tien_dien_nuoc']?.toString() ?? '') ?? 0,
      tienDichVuKhac: num.tryParse(json['tien_dich_vu_khac']?.toString() ?? '') ?? 0,
      noCu: num.tryParse(json['no_cu']?.toString() ?? '') ?? 0,
      tongTien: num.tryParse(json['tong_tien']?.toString() ?? '') ?? 0,
      trangThai: json['trang_thai']?.toString() ?? '',
      loaiGiaoDich: json['loai_giao_dich']?.toString() ?? '',
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
    );
  }

  HoaDonModel copyWith({
    String? maHoaDon,
    String? ngayLap,
    String? hanDongTien,
    num? tienPhong,
    num? tienDienNuoc,
    num? tienDichVuKhac,
    num? noCu,
    num? tongTien,
    String? trangThai,
    String? loaiGiaoDich,
    String? maHopDong,
  }) {
    return HoaDonModel(
      maHoaDon: maHoaDon ?? this.maHoaDon,
      ngayLap: ngayLap ?? this.ngayLap,
      hanDongTien: hanDongTien ?? this.hanDongTien,
      tienPhong: tienPhong ?? this.tienPhong,
      tienDienNuoc: tienDienNuoc ?? this.tienDienNuoc,
      tienDichVuKhac: tienDichVuKhac ?? this.tienDichVuKhac,
      noCu: noCu ?? this.noCu,
      tongTien: tongTien ?? this.tongTien,
      trangThai: trangThai ?? this.trangThai,
      loaiGiaoDich: loaiGiaoDich ?? this.loaiGiaoDich,
      maHopDong: maHopDong ?? this.maHopDong,
    );
  }

  String _fmt(String raw) {
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String get ngayLapFormatted => _fmt(ngayLap);
  String get hanDongTienFormatted => _fmt(hanDongTien);

  String get thangNam {
    try {
      final d = DateTime.parse(ngayLap);
      return 'T${d.month}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  String get thangNamShort {
    try {
      final d = DateTime.parse(ngayLap);
      return 'T${d.month}';
    } catch (_) {
      return '';
    }
  }

  int get soNgayConLai {
    try {
      final d = DateTime.parse(hanDongTien);
      final now = DateTime.now();
      return d.difference(DateTime(now.year, now.month, now.day)).inDays;
    } catch (_) {
      return 0;
    }
  }

  String get noiDungChuyenKhoan {
    final cleanHd = maHopDong.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final cleanBill = maHoaDon.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final billCode = cleanBill.isNotEmpty ? cleanBill : cleanHd;
    return 'KIEUGIANG $billCode $thangNamShort'.trim();
  }

  /// Tổng tiền gốc ban đầu (nếu tongTien == 0 do đã thanh toán, tính từ các khoản thu)
  num get tongTienGoc {
    if (tongTien > 0) return tongTien;
    final sumItems = tienPhong + tienDienNuoc + tienDichVuKhac + noCu;
    if (sumItems > 0) return sumItems;
    return tongTien;
  }
}

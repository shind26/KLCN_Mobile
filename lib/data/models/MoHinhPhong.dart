/// Model dữ liệu cho bảng `phong` trên Supabase
class RoomModel {
  final String maPhong;
  final String maLoaiPhong;
  final String tenHienThi;
  final String toaNha;
  final int tang;
  final num dienTich;
  final num giaThue;
  final num tienDatCoc;
  final String trangThai;
  final String hinhAnh;
  final double danhGia;
  final int soDanhGia;
  final String moTaNgan;
  final List<String> tienIch;
  final List<String> noiThatSanCo;
  final double chiSoDien;
  final double chiSoNuoc;
  final DateTime? ngayCapNhatChiSo;

  RoomModel({
    required this.maPhong,
    required this.maLoaiPhong,
    required this.tenHienThi,
    required this.toaNha,
    required this.tang,
    required this.dienTich,
    required this.giaThue,
    required this.tienDatCoc,
    required this.trangThai,
    required this.hinhAnh,
    required this.danhGia,
    required this.soDanhGia,
    required this.moTaNgan,
    required this.tienIch,
    required this.noiThatSanCo,
    this.chiSoDien = 0.0,
    this.chiSoNuoc = 0.0,
    this.ngayCapNhatChiSo,
  });

  static List<String> _parseStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) {
      return val.map((e) => e.toString()).toList();
    }
    if (val is String) {
      final cleaned = val.replaceAll('{', '').replaceAll('}', '').replaceAll('"', '');
      if (cleaned.trim().isEmpty) return [];
      return cleaned.split(',').map((e) => e.trim()).toList();
    }
    return [];
  }

  factory RoomModel.fromJson(Map<String, dynamic> json) {
    final num giaThueVal = num.tryParse(json['gia_thue']?.toString() ?? '') ??
        num.tryParse(json['don_gia_co_ban']?.toString() ?? '') ??
        0;

    DateTime? parsedNgayCapNhat;
    if (json['ngay_cap_nhat_chi_so'] != null &&
        json['ngay_cap_nhat_chi_so'].toString().trim().isNotEmpty) {
      parsedNgayCapNhat =
          DateTime.tryParse(json['ngay_cap_nhat_chi_so'].toString());
    }

    return RoomModel(
      maPhong: json['ma_phong']?.toString() ?? '',
      maLoaiPhong: json['ma_loai_phong']?.toString() ?? '',
      tenHienThi: json['ten_hien_thi']?.toString() ??
          json['ma_phong']?.toString() ??
          'Phòng trọ',
      toaNha: json['toa_nha']?.toString() ?? 'Tòa A',
      tang: num.tryParse(json['tang']?.toString() ?? '')?.toInt() ?? 1,
      dienTich: num.tryParse(json['dien_tich']?.toString() ?? '') ?? 20,
      giaThue: giaThueVal,
      tienDatCoc: num.tryParse(json['tien_dat_coc']?.toString() ?? '') ?? 0,
      trangThai: json['trang_thai']?.toString() ?? '',
      hinhAnh: json['hinh_anh']?.toString() ?? '',
      danhGia: double.tryParse(json['danh_gia']?.toString() ?? '') ?? 0.0,
      soDanhGia: num.tryParse(json['so_danh_gia']?.toString() ?? '')?.toInt() ?? 0,
      moTaNgan: json['mo_ta_ngan']?.toString() ?? '',
      tienIch: _parseStringList(json['tien_ich']),
      noiThatSanCo: _parseStringList(json['noi_that_san_co']),
      chiSoDien:
          double.tryParse(json['chi_so_dien']?.toString() ?? '') ?? 0.0,
      chiSoNuoc:
          double.tryParse(json['chi_so_nuoc']?.toString() ?? '') ?? 0.0,
      ngayCapNhatChiSo: parsedNgayCapNhat,
    );
  }
}


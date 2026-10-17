class PhuongTienModel {
  final String maPhuongTien;
  final String maKhach;
  final String maPhong;
  final String loaiXe;
  final String bienSoXe;
  final String? maTheXe;
  final String trangThai;
  final DateTime? ngayDangKy;

  PhuongTienModel({
    required this.maPhuongTien,
    required this.maKhach,
    required this.maPhong,
    required this.loaiXe,
    required this.bienSoXe,
    this.maTheXe,
    this.trangThai = 'Đang sử dụng',
    this.ngayDangKy,
  });

  factory PhuongTienModel.fromJson(Map<String, dynamic> json) {
    DateTime? dt;
    if (json['ngay_dang_ky'] != null) {
      try {
        dt = DateTime.parse(json['ngay_dang_ky'].toString());
      } catch (_) {}
    }

    return PhuongTienModel(
      maPhuongTien: json['ma_phuong_tien']?.toString() ?? '',
      maKhach: json['ma_khach']?.toString() ?? '',
      maPhong: json['ma_phong']?.toString() ?? '',
      loaiXe: json['loai_xe']?.toString() ?? 'Xe máy',
      bienSoXe: json['bien_so_xe']?.toString() ?? '',
      maTheXe: json['ma_the_xe']?.toString(),
      trangThai: json['trang_thai']?.toString() ?? 'Đang sử dụng',
      ngayDangKy: dt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ma_phuong_tien': maPhuongTien,
      'ma_khach': maKhach,
      'ma_phong': maPhong,
      'loai_xe': loaiXe,
      'bien_so_xe': bienSoXe,
      if (maTheXe != null && maTheXe!.isNotEmpty) 'ma_the_xe': maTheXe,
      'trang_thai': trangThai,
      if (ngayDangKy != null) 'ngay_dang_ky': ngayDangKy!.toIso8601String(),
    };
  }

  PhuongTienModel copyWith({
    String? maPhuongTien,
    String? maKhach,
    String? maPhong,
    String? loaiXe,
    String? bienSoXe,
    String? maTheXe,
    String? trangThai,
    DateTime? ngayDangKy,
  }) {
    return PhuongTienModel(
      maPhuongTien: maPhuongTien ?? this.maPhuongTien,
      maKhach: maKhach ?? this.maKhach,
      maPhong: maPhong ?? this.maPhong,
      loaiXe: loaiXe ?? this.loaiXe,
      bienSoXe: bienSoXe ?? this.bienSoXe,
      maTheXe: maTheXe ?? this.maTheXe,
      trangThai: trangThai ?? this.trangThai,
      ngayDangKy: ngayDangKy ?? this.ngayDangKy,
    );
  }
}

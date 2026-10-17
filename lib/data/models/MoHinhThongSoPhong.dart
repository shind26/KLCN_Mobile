/// Model cho bảng `thong_so_phong` trên Supabase
class ThongSoPhongModel {
  final String maThongSo;
  final String maPhong;
  final String tenThongSo;
  final String giaTri;
  final String? ghiChuPhu;

  ThongSoPhongModel({
    required this.maThongSo,
    required this.maPhong,
    required this.tenThongSo,
    required this.giaTri,
    this.ghiChuPhu,
  });

  factory ThongSoPhongModel.fromJson(Map<String, dynamic> json) {
    return ThongSoPhongModel(
      maThongSo:  json['ma_thong_so']?.toString() ?? '',
      maPhong:    json['ma_phong']?.toString() ?? '',
      tenThongSo: json['ten_thong_so']?.toString() ?? '',
      giaTri:     json['gia_tri']?.toString() ?? '',
      ghiChuPhu:  json['ghi_chu_phu']?.toString(),
    );
  }
}

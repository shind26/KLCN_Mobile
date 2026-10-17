/// Model dữ liệu cho bảng `dich_vu` trên Supabase
class DichVuModel {
  final String maDichVu;
  final String tenDichVu;
  final num donGia;
  final String donViTinh;
  final String ghiChu;

  DichVuModel({
    required this.maDichVu,
    required this.tenDichVu,
    required this.donGia,
    required this.donViTinh,
    required this.ghiChu,
  });

  factory DichVuModel.fromJson(Map<String, dynamic> json) {
    return DichVuModel(
      maDichVu: json['ma_dich_vu']?.toString() ?? '',
      tenDichVu: json['ten_dich_vu']?.toString() ?? '',
      donGia: (json['don_gia'] as num?) ?? 0,
      donViTinh: json['don_vi_tinh']?.toString() ?? '',
      ghiChu: json['ghi_chu']?.toString() ?? '',
    );
  }
}

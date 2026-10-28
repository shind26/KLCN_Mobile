/// Model dữ liệu cho bảng `giu_cho` trên Supabase
class GiuChoModel {
  final String maGiuCho;
  final String maPhong;
  final String maKhach;
  final num soTienTheChan;
  final DateTime? thoiGianGiuCho;
  final DateTime? ngayHetHan;
  final String trangThai; // 'ChoThanhToan', 'DangGiu', 'HetHan', 'Huy'
  final DateTime? expiresAt; // Thời gian hết hạn thanh toán cọc (15 phút)
  final int soNguoiO;
  final DateTime? ngayDuKienO;
  final String? ghiChu;

  GiuChoModel({
    required this.maGiuCho,
    required this.maPhong,
    required this.maKhach,
    this.soTienTheChan = 0,
    this.thoiGianGiuCho,
    this.ngayHetHan,
    this.trangThai = 'ChoThanhToan',
    this.expiresAt,
    this.soNguoiO = 1,
    this.ngayDuKienO,
    this.ghiChu,
  });

  factory GiuChoModel.fromJson(Map<String, dynamic> json) {
    return GiuChoModel(
      maGiuCho: json['ma_giu_cho']?.toString() ?? '',
      maPhong: json['ma_phong']?.toString() ?? '',
      maKhach: json['ma_khach']?.toString() ?? '',
      soTienTheChan:
          num.tryParse(json['so_tien_the_chan']?.toString() ?? '0') ?? 0,
      thoiGianGiuCho: json['thoi_gian_giu_cho'] != null
          ? DateTime.tryParse(json['thoi_gian_giu_cho'].toString())
          : null,
      ngayHetHan: json['ngay_het_han'] != null
          ? DateTime.tryParse(json['ngay_het_han'].toString())
          : null,
      trangThai: json['trang_thai']?.toString() ?? 'ChoThanhToan',
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      soNguoiO: int.tryParse(json['so_nguoi_o']?.toString() ?? '1') ?? 1,
      ngayDuKienO: json['ngay_du_kien_o'] != null
          ? DateTime.tryParse(json['ngay_du_kien_o'].toString())
          : null,
      ghiChu: json['ghi_chu']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ma_giu_cho': maGiuCho,
      'ma_phong': maPhong,
      'ma_khach': maKhach,
      'so_tien_the_chan': soTienTheChan,
      'thoi_gian_giu_cho': thoiGianGiuCho?.toIso8601String(),
      'ngay_het_han': ngayHetHan?.toIso8601String(),
      'trang_thai': trangThai,
      'expires_at': expiresAt?.toIso8601String(),
      'so_nguoi_o': soNguoiO,
      'ngay_du_kien_o': ngayDuKienO != null
          ? '${ngayDuKienO!.year}-${ngayDuKienO!.month.toString().padLeft(2, '0')}-${ngayDuKienO!.day.toString().padLeft(2, '0')}'
          : null,
      'ghi_chu': ghiChu,
    };
  }
}

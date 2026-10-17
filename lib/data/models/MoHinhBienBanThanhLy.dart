/// Model cho bảng `bien_ban_thanh_ly` trong Supabase
/// Khớp 100% với các cột trong cơ sở dữ liệu Supabase:
/// ma_thanh_ly, ngay_tra_phong, chi_so_dien_cuoi, chi_so_nuoc_cuoi,
/// tien_kh_tra_them, tien_coc_hoan_lai, ghi_chu, ma_hop_dong, trang_thai
class BienBanThanhLyModel {
  final String maThanhLy;
  final String maHopDong;
  final String ngayTraPhong;
  final double chiSoDienCuoi;
  final double chiSoNuocCuoi;
  final double tienKhTraThem;
  final double tienCocHoanLai;
  final String ghiChu;
  final String? trangThai;

  BienBanThanhLyModel({
    required this.maThanhLy,
    required this.maHopDong,
    required this.ngayTraPhong,
    required this.chiSoDienCuoi,
    required this.chiSoNuocCuoi,
    required this.tienKhTraThem,
    required this.tienCocHoanLai,
    this.ghiChu = '',
    this.trangThai,
  });

  factory BienBanThanhLyModel.fromJson(Map<String, dynamic> json) {
    return BienBanThanhLyModel(
      maThanhLy: json['ma_thanh_ly']?.toString() ?? '',
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
      ngayTraPhong: json['ngay_tra_phong']?.toString() ?? '',
      chiSoDienCuoi: (num.tryParse(json['chi_so_dien_cuoi']?.toString() ?? '') ?? 0).toDouble(),
      chiSoNuocCuoi: (num.tryParse(json['chi_so_nuoc_cuoi']?.toString() ?? '') ?? 0).toDouble(),
      tienKhTraThem: (num.tryParse(json['tien_kh_tra_them']?.toString() ?? '') ?? 0).toDouble(),
      tienCocHoanLai: (num.tryParse(json['tien_coc_hoan_lai']?.toString() ?? '') ?? 0).toDouble(),
      ghiChu: json['ghi_chu']?.toString() ?? '',
      trangThai: json['trang_thai']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'ma_thanh_ly': maThanhLy,
      'ma_hop_dong': maHopDong,
      'ngay_tra_phong': ngayTraPhong,
      'chi_so_dien_cuoi': chiSoDienCuoi,
      'chi_so_nuoc_cuoi': chiSoNuocCuoi,
      'tien_kh_tra_them': tienKhTraThem,
      'tien_coc_hoan_lai': tienCocHoanLai,
      'ghi_chu': ghiChu,
    };
    if (trangThai != null) {
      map['trang_thai'] = trangThai;
    }
    return map;
  }
}

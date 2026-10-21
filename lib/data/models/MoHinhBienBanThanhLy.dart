/// Model cho bảng `bien_ban_thanh_ly` trong Supabase
/// Khớp với các cột trong cơ sở dữ liệu Supabase:
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
  final String trangThai; // 'Chờ duyệt' | 'Đã duyệt' | 'Từ chối'
  final String? loaiTraPhong; // 'Đúng hạn' | 'Trước hạn'
  final String? anhDongHoDien;
  final String? anhDongHoNuoc;

  BienBanThanhLyModel({
    required this.maThanhLy,
    required this.maHopDong,
    required this.ngayTraPhong,
    required this.chiSoDienCuoi,
    required this.chiSoNuocCuoi,
    required this.tienKhTraThem,
    required this.tienCocHoanLai,
    this.ghiChu = '',
    this.trangThai = 'Chờ duyệt',
    this.loaiTraPhong,
    this.anhDongHoDien,
    this.anhDongHoNuoc,
  });

  factory BienBanThanhLyModel.fromJson(Map<String, dynamic> json) {
    String tt = json['trang_thai']?.toString() ?? '';
    String gc = json['ghi_chu']?.toString() ?? '';

    // Nếu chưa có cột trang_thai trong DB hoặc giá trị rỗng, bóc tách từ ghi_chu cũ
    if (tt.isEmpty) {
      final match = RegExp(r'\[Trạng thái:\s*([^\]]+)\]').firstMatch(gc);
      if (match != null) {
        tt = match.group(1)?.trim() ?? 'Chờ duyệt';
      } else {
        tt = 'Chờ duyệt';
      }
    }
    // Dọn dẹp tiền tố [Trạng thái: ...] trong ghi chú để trường ghi_chu sạch sẽ
    gc = gc.replaceFirst(RegExp(r'^\[Trạng thái:[^\]]+\]\s*'), '').trim();

    return BienBanThanhLyModel(
      maThanhLy: json['ma_thanh_ly']?.toString() ?? '',
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
      ngayTraPhong: json['ngay_tra_phong']?.toString() ?? '',
      chiSoDienCuoi: (num.tryParse(json['chi_so_dien_cuoi']?.toString() ?? '') ?? 0).toDouble(),
      chiSoNuocCuoi: (num.tryParse(json['chi_so_nuoc_cuoi']?.toString() ?? '') ?? 0).toDouble(),
      tienKhTraThem: (num.tryParse(json['tien_kh_tra_them']?.toString() ?? '') ?? 0).toDouble(),
      tienCocHoanLai: (num.tryParse(json['tien_coc_hoan_lai']?.toString() ?? '') ?? 0).toDouble(),
      ghiChu: gc,
      trangThai: tt,
      loaiTraPhong: json['loai_tra_phong']?.toString(),
      anhDongHoDien: json['anh_dong_ho_dien']?.toString(),
      anhDongHoNuoc: json['anh_dong_ho_nuoc']?.toString(),
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
      'trang_thai': trangThai,
    };
    if (loaiTraPhong != null) {
      map['loai_tra_phong'] = loaiTraPhong;
    }
    if (anhDongHoDien != null) {
      map['anh_dong_ho_dien'] = anhDongHoDien;
    }
    if (anhDongHoNuoc != null) {
      map['anh_dong_ho_nuoc'] = anhDongHoNuoc;
    }
    return map;
  }
}

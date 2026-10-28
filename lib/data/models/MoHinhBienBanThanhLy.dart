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
  final String trangThai; // 'CHO_DUYET' | 'DA_DUYET' | 'TU_CHOI'
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
    this.trangThai = 'CHO_DUYET',
    this.anhDongHoDien,
    this.anhDongHoNuoc,
  });

  bool get isChoDuyet {
    final s = trangThai.trim().toUpperCase();
    return s == 'CHO_DUYET' ||
        s == 'CHỜ DUYỆT' ||
        s == 'CHO DUYET' ||
        s == 'PENDING' ||
        s.startsWith('CHỜ');
  }

  bool get isDaDuyet {
    if (isChoDuyet) return false;
    final s = trangThai.trim().toUpperCase();
    return s == 'DA_DUYET' ||
        s == 'ĐÃ DUYỆT' ||
        s == 'DA DUYET' ||
        s == 'APPROVED' ||
        s == 'THANH_CONG' ||
        s == 'THÀNH CÔNG';
  }

  bool get isTuChoi {
    final s = trangThai.trim().toUpperCase();
    return s == 'TU_CHOI' ||
        s == 'TỪ CHỐI' ||
        s == 'TU CHOI' ||
        s == 'REJECTED' ||
        s == 'DA_HUY' ||
        s == 'ĐÃ HỦY';
  }

  factory BienBanThanhLyModel.fromJson(Map<String, dynamic> json) {
    String tt = json['trang_thai']?.toString() ?? '';
    String gc = json['ghi_chu']?.toString() ?? '';

    // Nếu chưa có cột trang_thai trong DB hoặc giá trị rỗng, bóc tách từ ghi_chu cũ
    if (tt.isEmpty) {
      final match = RegExp(r'\[Trạng thái:\s*([^\]]+)\]').firstMatch(gc);
      if (match != null) {
        tt = match.group(1)?.trim() ?? 'CHO_DUYET';
      } else {
        tt = 'CHO_DUYET';
      }
    }
    // Dọn dẹp tiền tố [Trạng thái: ...] trong ghi chú để trường ghi_chu sạch sẽ
    gc = gc.replaceFirst(RegExp(r'^\[Trạng thái:[^\]]+\]\s*'), '').trim();

    return BienBanThanhLyModel(
      maThanhLy: json['ma_thanh_ly']?.toString() ?? '',
      maHopDong: json['ma_hop_dong']?.toString() ?? '',
      ngayTraPhong: json['ngay_tra_phong']?.toString() ?? '',
      chiSoDienCuoi:
          (num.tryParse(json['chi_so_dien_cuoi']?.toString() ?? '') ?? 0)
              .toDouble(),
      chiSoNuocCuoi:
          (num.tryParse(json['chi_so_nuoc_cuoi']?.toString() ?? '') ?? 0)
              .toDouble(),
      tienKhTraThem:
          (num.tryParse(json['tien_kh_tra_them']?.toString() ?? '') ?? 0)
              .toDouble(),
      tienCocHoanLai:
          (num.tryParse(json['tien_coc_hoan_lai']?.toString() ?? '') ?? 0)
              .toDouble(),
      ghiChu: gc,
      trangThai: tt,
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
    if (anhDongHoDien != null) {
      map['anh_dong_ho_dien'] = anhDongHoDien;
    }
    if (anhDongHoNuoc != null) {
      map['anh_dong_ho_nuoc'] = anhDongHoNuoc;
    }
    return map;
  }
}

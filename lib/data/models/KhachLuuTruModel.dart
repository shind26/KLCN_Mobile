class KhachLuuTruModel {
  final String id;
  final String hoTen;
  final String cccd;
  final String sdt;
  final String thoiGian;
  final int soDem;
  final String phiLuuTru;
  final String moiQuanHe;
  final String trangThai; // 'Chờ duyệt', 'Đã duyệt', 'Hoàn tất', 'Từ chối'
  final String? maPhong;
  final String? anhMatTruoc;
  final String? anhMatSau;
  final String ngayDangKy;

  KhachLuuTruModel({
    required this.id,
    required this.hoTen,
    required this.cccd,
    required this.sdt,
    required this.thoiGian,
    required this.soDem,
    required this.phiLuuTru,
    required this.moiQuanHe,
    required this.trangThai,
    this.maPhong,
    this.anhMatTruoc,
    this.anhMatSau,
    required this.ngayDangKy,
  });

  factory KhachLuuTruModel.fromSupabase(Map<String, dynamic> map) {
    final tuNgay = map['tu_ngay']?.toString() ?? '';
    final denNgay = map['den_ngay']?.toString() ?? '';

    // Tính số đêm
    int dem = 1;
    try {
      if (tuNgay.isNotEmpty && denNgay.isNotEmpty) {
        final d1 = DateTime.parse(tuNgay);
        final d2 = DateTime.parse(denNgay);
        final diff = d2.difference(d1).inDays;
        if (diff > 0) dem = diff;
      }
    } catch (_) {}

    final phi = dem * 50000;
    final phiFormat =
        '${phi.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ';

    return KhachLuuTruModel(
      id: map['ma_dang_ky']?.toString() ?? '',
      hoTen: map['ho_ten_khach_ngoai']?.toString() ?? '',
      cccd: map['cccd_khach_ngoai']?.toString() ?? '',
      sdt: map['sdt_khach_ngoai']?.toString() ?? 'Chưa cập nhật',
      thoiGian: '$tuNgay - $denNgay',
      soDem: dem,
      phiLuuTru: phiFormat,
      moiQuanHe: 'Khách lưu trú',
      trangThai: map['trang_thai']?.toString() ?? 'Chờ duyệt',
      maPhong: map['ma_phong']?.toString() ?? 'P302',
      ngayDangKy: tuNgay,
    );
  }

  // Dữ liệu dùng chung trong suốt phiên chạy của ứng dụng (đồng bộ từ Supabase)
  static final List<KhachLuuTruModel> danhSachLuuTru = [];
}

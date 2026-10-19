class UserModel {
  final String maTaiKhoan;
  final String tenDangNhap;
  final String matKhau;
  final String vaiTro;
  final String coSoVanHanh;
  final String? ngayTao;
  final String trangThai;
  final String? hoTen; // Họ tên thật, hiển thị trên trang chủ

  UserModel({
    required this.maTaiKhoan,
    required this.tenDangNhap,
    required this.matKhau,
    required this.vaiTro,
    required this.coSoVanHanh,
    this.ngayTao,
    required this.trangThai,
    this.hoTen,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      maTaiKhoan: json['ma_tai_khoan']?.toString() ?? '',
      tenDangNhap: json['ten_dang_nhap']?.toString() ?? '',
      matKhau: json['mat_khau']?.toString() ?? '',
      vaiTro: json['vai_tro']?.toString() ?? 'KhachThue',
      coSoVanHanh: json['co_so_van_hanh']?.toString() ?? '',
      ngayTao: json['ngay_tao']?.toString(),
      trangThai: json['trang_thai']?.toString() ?? 'HoatDong',
      hoTen: json['ho_ten']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ma_tai_khoan': maTaiKhoan,
      'ten_dang_nhap': tenDangNhap,
      'mat_khau': matKhau,
      'vai_tro': vaiTro,
      'co_so_van_hanh': coSoVanHanh,
      'ngay_tao': ngayTao,
      'trang_thai': trangThai,
      'ho_ten': hoTen,
    };
  }

  /// Tên hiển thị: ưu tiên họ tên thật, nếu không có thì dùng tên đăng nhập
  String get tenHienThi => (hoTen != null && hoTen!.trim().isNotEmpty)
      ? hoTen!.trim()
      : tenDangNhap;

  bool get isAdmin => vaiTro.toLowerCase() == 'admin';
  bool get isActive => trangThai.toLowerCase() == 'hoatdong';

  UserModel copyWith({
    String? maTaiKhoan,
    String? tenDangNhap,
    String? matKhau,
    String? vaiTro,
    String? coSoVanHanh,
    String? ngayTao,
    String? trangThai,
    String? hoTen,
  }) {
    return UserModel(
      maTaiKhoan: maTaiKhoan ?? this.maTaiKhoan,
      tenDangNhap: tenDangNhap ?? this.tenDangNhap,
      matKhau: matKhau ?? this.matKhau,
      vaiTro: vaiTro ?? this.vaiTro,
      coSoVanHanh: coSoVanHanh ?? this.coSoVanHanh,
      ngayTao: ngayTao ?? this.ngayTao,
      trangThai: trangThai ?? this.trangThai,
      hoTen: hoTen ?? this.hoTen,
    );
  }
}

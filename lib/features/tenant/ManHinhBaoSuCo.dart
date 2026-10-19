import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhBaoSuCoThanhCong.dart';

class ManHinhBaoSuCo extends StatefulWidget {
  final String tenPhong;
  final String toaNha;
  final String? maPhong;

  const ManHinhBaoSuCo({
    super.key,
    this.tenPhong = 'Phòng 203 • Gác lửng',
    this.toaNha = 'Tòa A (Tầng 2)',
    this.maPhong,
  });

  @override
  State<ManHinhBaoSuCo> createState() => _ManHinhBaoSuCoState();
}

class _ManHinhBaoSuCoState extends State<ManHinhBaoSuCo> {
  static const _primary = Color(0xFF09638E);
  static const _bg = Color(0xFFF8FAFC);
  static const _textDark = Color(0xFF0F172A);

  final _formKey = GlobalKey<FormState>();
  final _moTaController = TextEditingController();

  int _selectedCategoryIndex = 0;
  final List<Map<String, dynamic>> _categories = [
    {'name': 'Điện', 'icon': Icons.bolt_rounded},
    {'name': 'Nước', 'icon': Icons.science_outlined},
    {'name': 'Điều hòa', 'icon': Icons.ac_unit_rounded},
    {'name': 'Cửa/Khóa', 'icon': Icons.lock_open_rounded},
    {'name': 'Wifi/Mạng', 'icon': Icons.wifi_rounded},
    {'name': 'Khác', 'icon': Icons.more_horiz_rounded},
  ];

  bool _isEmergency = false;
  bool _isSubmitting = false;
  final List<XFile> _pickedFiles = [];
  final List<Uint8List> _imageBytesList = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    if (_imageBytesList.length >= 4) {
      ThongBaoHelper.hienToast(
        context,
        tieuDe: 'Giới hạn ảnh',
        noiDung: 'Chỉ được tải lên tối đa 4 hình ảnh sự cố!',
        type: ThongBaoType.canhBao,
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Thêm hình ảnh hiện trạng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textDark,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: _primary),
                title: const Text('Chụp ảnh trực tiếp bằng Camera'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final xfile = await _picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 800,
                    maxHeight: 800,
                    imageQuality: 70,
                  );
                  if (xfile != null) {
                    final bytes = await xfile.readAsBytes();
                    setState(() {
                      _pickedFiles.add(xfile);
                      _imageBytesList.add(bytes);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: _primary,
                ),
                title: const Text('Chọn ảnh từ Thư viện'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final xfile = await _picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 800,
                    maxHeight: 800,
                    imageQuality: 70,
                  );
                  if (xfile != null) {
                    final bytes = await xfile.readAsBytes();
                    setState(() {
                      _pickedFiles.add(xfile);
                      _imageBytesList.add(bytes);
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final db = Supabase.instance.client;
      final user = AuthService.currentUser;

      // 1. Sinh mã sự cố tối đa 10 ký tự (chuẩn varchar(10) database)
      final timestampStr = DateTime.now().millisecondsSinceEpoch.toString();
      final maSuCo = 'SC${timestampStr.substring(timestampStr.length - 7)}';

      // 2. Xác định mã phòng & mã khách báo
      String maPhong = widget.maPhong ?? 'P302';
      String maKhach = '';

      if (user != null && user.maTaiKhoan.isNotEmpty) {
        try {
          final kt = await db
              .from('khach_thue')
              .select('ma_khach')
              .eq('ma_tai_khoan', user.maTaiKhoan)
              .maybeSingle();
          if (kt != null && kt['ma_khach'] != null) {
            maKhach = kt['ma_khach'].toString();
          }
        } catch (_) {}
      }

      // Fallback: Tìm mã khách thuê đang có hợp đồng tại phòng này
      if (maKhach.isEmpty) {
        try {
          final roomKt = await db
              .from('hop_dong')
              .select('chi_tiet_hop_dong_khach_thue(ma_khach)')
              .eq('ma_phong', maPhong)
              .eq('trang_thai', 'Còn hạn')
              .maybeSingle();
          final ct = roomKt?['chi_tiet_hop_dong_khach_thue'];
          if (ct is List && ct.isNotEmpty) {
            maKhach = ct[0]['ma_khach']?.toString() ?? '';
          }
        } catch (_) {}
      }
      if (maKhach.isEmpty) maKhach = 'KH_CU_DAN';

      // 3. Xử lý lưu ảnh lên Supabase (Storage + Base64 fallback)
      final List<String> listHinhAnh = [];
      for (int i = 0; i < _imageBytesList.length; i++) {
        final bytes = _imageBytesList[i];
        String imgData = '';
        try {
          final storagePath = 'incidents/${maSuCo}_$i.jpg';
          await db.storage.from('contracts').uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
          imgData = db.storage.from('contracts').getPublicUrl(storagePath);
        } catch (storageError) {
          // Lưu chuỗi Data URI Base64 trực tiếp vào database Supabase
          final b64 = base64Encode(bytes);
          imgData = 'data:image/jpeg;base64,$b64';
        }
        listHinhAnh.add(imgData);
      }

      // 4. Tạo payload nội dung có chứa mô tả và các ảnh
      final noiDungJson = jsonEncode({
        'mo_ta': _moTaController.text.trim(),
        'hinh_anh': listHinhAnh,
        'muc_do': _isEmergency ? 'Khẩn cấp' : 'Bình thường',
        'ngay_tao': DateTime.now().toIso8601String(),
      });

      // 5. Ghi bản ghi vào bảng su_co_bao_tri trên Supabase
      final rowData = {
        'ma_su_co': maSuCo,
        'danh_muc': _categories[_selectedCategoryIndex]['name'],
        'noi_dung': noiDungJson,
        'muc_do_uu_tien': _isEmergency ? 'Khẩn cấp' : 'Bình thường',
        'chi_phi_sua_chua': 0,
        'trang_thai': 'Chờ xử lý',
        'ngay_bao_cao': DateTime.now().toIso8601String(),
        'ma_phong': maPhong,
        'ma_khach_bao': maKhach,
      };

      try {
        await db.from('su_co_bao_tri').insert({
          ...rowData,
          if (listHinhAnh.isNotEmpty) 'hinh_anh': listHinhAnh.first,
        });
      } catch (_) {
        await db.from('su_co_bao_tri').insert(rowData);
      }

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ManHinhBaoSuCoThanhCong(
            maPhieu: maSuCo,
            tenPhong: widget.tenPhong,
            toaNha: widget.toaNha,
            danhMuc: _categories[_selectedCategoryIndex]['name'],
            moTa: _moTaController.text.trim(),
            danhSachAnh: listHinhAnh,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Lỗi gửi sự cố lên Supabase: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        ThongBaoHelper.hienToast(
          context,
          tieuDe: 'Lỗi gửi sự cố',
          noiDung: 'Lỗi kết nối Supabase: $e',
          type: ThongBaoType.thatBai,
        );
      }
    }
  }

  @override
  void dispose() {
    _moTaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardThongTinPhong(),
                const SizedBox(height: 16),
                _buildPhanDanhMuc(),
                const SizedBox(height: 16),
                _buildCardMoTa(),
                const SizedBox(height: 16),
                _buildCardMucDo(),
                const SizedBox(height: 16),
                _buildCardHinhAnh(),
                const SizedBox(height: 24),
                _buildNutGui(),
                const SizedBox(height: 10),
                const Center(
                  child: Text(
                    '* Ban quản lý sẽ phản hồi và hẹn lịch sửa chữa trong vòng 24h.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: _primary,
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: Column(
        children: [
          const Text(
            'Báo Sự Cố',
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${widget.tenPhong} • ${widget.toaNha}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.help_outline_rounded,
            color: Color(0xFF0284C7),
          ),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildCardThongTinPhong() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.home_work_outlined,
              color: _primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tenPhong,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.toaNha,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhanDanhMuc() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Danh mục sự cố',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final cat = _categories[index];
            final isSelected = _selectedCategoryIndex == index;
            return InkWell(
              onTap: () => setState(() => _selectedCategoryIndex = index),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFE0F2FE) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? _primary : const Color(0xFFE2E8F0),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      cat['icon'],
                      color: isSelected ? _primary : const Color(0xFF475569),
                      size: 24,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cat['name'],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isSelected ? _primary : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCardMoTa() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mô tả chi tiết sự cố *',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _moTaController,
            maxLines: 4,
            style: const TextStyle(fontSize: 13, color: _textDark),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Vui lòng mô tả chi tiết sự cố bạn gặp phải'
                : null,
            decoration: InputDecoration(
              hintText:
                  'Ví dụ: Vòi nước ở bồn rửa mặt bị rỉ nước liên tục từ tối qua, chảy khá nhiều...',
              hintStyle: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF94A3B8),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMucDo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mức độ khẩn cấp',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: _textDark,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isEmergency = false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isEmergency ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !_isEmergency
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Bình thường',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: !_isEmergency
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: !_isEmergency
                            ? _primary
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _isEmergency = true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isEmergency ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: _isEmergency
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Khẩn cấp 🚨',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _isEmergency
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _isEmergency
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardHinhAnh() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hình ảnh hiện trạng',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFBAE6FD),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: _primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '+ Thêm hình ảnh',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Tải lên tối đa 4 ảnh chụp thực tế sự cố',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
          if (_imageBytesList.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _imageBytesList.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          _imageBytesList[idx],
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => setState(() {
                            _imageBytesList.removeAt(idx);
                            if (idx < _pickedFiles.length) {
                              _pickedFiles.removeAt(idx);
                            }
                          }),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutGui() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _submit,
        icon: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, size: 18),
        label: Text(
          _isSubmitting ? 'Đang gửi lên hệ thống...' : 'Gửi báo cáo sự cố',
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

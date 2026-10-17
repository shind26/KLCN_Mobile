-- ============================================================================
-- SQL RPC Function: Đặt Cọc Giữ Chỗ Phòng Có Khóa Dòng (FOR UPDATE)
-- Ngăn chặn Race-Condition khi nhiều khách cùng ấn Đặt Cọc tại 1 thời điểm.
-- Từ chối ngay lập tức với mã lỗi 409 nếu phòng vừa bị khách khác đặt.
-- ============================================================================

CREATE OR REPLACE FUNCTION dat_coc_phong(
  p_ma_phong VARCHAR,
  p_ho_ten VARCHAR,
  p_so_dt VARCHAR,
  p_ngay_du_kien_o DATE,
  p_so_nguoi_o INT,
  p_ghi_chu TEXT DEFAULT ''
) RETURNS JSON AS $$
DECLARE
  v_phong RECORD;
  v_ma_giu_cho VARCHAR;
  v_ma_khach VARCHAR;
  v_expires_at TIMESTAMPTZ;
  v_ngay_het_han TIMESTAMPTZ;
BEGIN
  -- 1. FOR UPDATE: Khóa dòng phòng được chọn để chống xung đột đặt cọc đồng thời
  SELECT * INTO v_phong 
  FROM phong 
  WHERE ma_phong = p_ma_phong 
  FOR UPDATE;
  
  -- Nếu không tìm thấy phòng hoặc phòng không ở trạng thái 'Trống'
  IF NOT FOUND OR LOWER(v_phong.trang_thai) <> 'trống' THEN
    RAISE EXCEPTION 'PHONG_DA_DAT_409: Phòng % hiện không khả dụng (Trạng thái: %) hoặc vừa được khách khác đặt!', 
      p_ma_phong, v_phong.trang_thai;
  END IF;

  -- 2. Kiểm tra nếu phòng đang có phiếu giữ chỗ trong vòng 15 phút chưa hết hạn
  IF EXISTS (
    SELECT 1 FROM giu_cho 
    WHERE ma_phong = p_ma_phong 
      AND (
        (trang_thai = 'ChoThanhToan' AND expires_at > NOW())
        OR trang_thai IN ('DangGiu', 'DaDatCoc')
      )
  ) THEN
    RAISE EXCEPTION 'PHONG_DA_DAT_409: Phòng % đang có khách khác giữ chỗ thanh toán!', p_ma_phong;
  END IF;

  -- 3. Tạo hoặc lấy thông tin khách trong bảng khach_thue
  SELECT ma_khach INTO v_ma_khach 
  FROM khach_thue 
  WHERE so_dt = p_so_dt 
  LIMIT 1;

  IF v_ma_khach IS NULL THEN
    v_ma_khach := 'KH' || RIGHT(REPLACE(p_so_dt, ' ', ''), 6);
    INSERT INTO khach_thue (ma_khach, ho_ten_khach, so_dt, dia_chi_thuong_tru) 
    VALUES (v_ma_khach, p_ho_ten, p_so_dt, 'Khách đặt cọc giữ chỗ online')
    ON CONFLICT (ma_khach) DO NOTHING;
  END IF;

  -- 4. Tạo mã phiếu giữ chỗ và thời gian hết hạn 15 phút, hạn giữ chỗ 5 ngày (đảm bảo <= 10 ký tự)
  v_ma_giu_cho := 'GC' || TO_CHAR(NOW(), 'HH24MISS') || SUBSTRING(p_ma_phong, 1, 2);
  v_expires_at := NOW() + INTERVAL '15 minutes';
  v_ngay_het_han := NOW() + INTERVAL '5 days';

  -- 5. Cập nhật phòng sang trạng thái Đã cọc
  UPDATE phong 
  SET trang_thai = 'Đã cọc' 
  WHERE ma_phong = p_ma_phong;

  -- 6. Tạo phiếu giữ chỗ mới với trang_thai = 'ChoThanhToan'
  INSERT INTO giu_cho (
    ma_giu_cho,
    ma_phong,
    ma_khach,
    so_tien_the_chan,
    thoi_gian_giu_cho,
    ngay_het_han,
    trang_thai,
    expires_at,
    so_nguoi_o,
    ngay_du_kien_o,
    ghi_chu
  ) VALUES (
    v_ma_giu_cho,
    p_ma_phong,
    v_ma_khach,
    100000,
    NOW(),
    v_ngay_het_han,
    'ChoThanhToan',
    v_expires_at,
    p_so_nguoi_o,
    p_ngay_du_kien_o,
    p_ghi_chu
  );

  RETURN json_build_object(
    'success', true,
    'ma_giu_cho', v_ma_giu_cho,
    'expires_at', v_expires_at,
    'so_tien_the_chan', 100000
  );
END;
$$ LANGUAGE plpgsql;

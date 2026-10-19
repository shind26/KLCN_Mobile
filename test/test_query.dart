import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  test('test exact query', () async {
    final client = SupabaseClient(
      'https://umxyotycpumkkpjwfvlz.supabase.co',
      'sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6',
    );

    final testPhones = ['0865109632', '0865847367', '0988776655', '0123456789', '0328004663'];

    for (final phone in testPhones) {
      print('\n--- TESTING PHONE: $phone ---');
      try {
        final cleanPhone = phone.trim().replaceAll(' ', '').replaceAll('-', '').replaceAll('.', '');
        String normalized = cleanPhone;
        if (normalized.startsWith('+84')) {
          normalized = '0${normalized.substring(3)}';
        } else if (normalized.startsWith('84') && normalized.length > 9) {
          normalized = '0${normalized.substring(2)}';
        }

        print('Step 1: Query tai_khoan...');
        final tkRow = await client
            .from('tai_khoan')
            .select('ma_tai_khoan, ten_dang_nhap')
            .or('ten_dang_nhap.eq.$cleanPhone,ten_dang_nhap.eq.$normalized')
            .limit(1)
            .maybeSingle();
        print('tkRow: $tkRow');

        print('Step 2: Query khach_thue...');
        final ktRows = await client
            .from('khach_thue')
            .select('ma_khach, ma_tai_khoan, so_dt')
            .or('so_dt.eq.$cleanPhone,so_dt.eq.$normalized')
            .limit(5);
        print('ktRows: $ktRows');
      } catch (e, stack) {
        print('EXCEPTION: $e\n$stack');
      }
    }
  });
}

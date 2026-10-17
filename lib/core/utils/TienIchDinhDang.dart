/// Các tiện ích format/hỗ trợ dùng chung toàn ứng dụng
class FormatUtils {
  FormatUtils._();

  /// Format số tiền sang dạng "3.800.000đ"
  static String currency(num amount) {
    final str = amount.toInt().toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]}.') + 'đ';
  }

  /// Format số tiền ngắn gọn "3.8 triệu"
  static String currencyShort(num amount) {
    if (amount >= 1000000) {
      final millions = amount / 1000000;
      final formatted = millions == millions.truncate()
          ? '${millions.truncate()}'
          : millions.toStringAsFixed(1);
      return '$formatted triệu';
    }
    return currency(amount);
  }

  /// Format số tiền (alias cho currency)
  static String formatCurrency(num amount) => currency(amount);

  /// Format ngày sang dạng dd/MM/yyyy (nhận DateTime hoặc String ISO)
  static String formatDate(dynamic date) {
    if (date == null) return '';
    if (date is DateTime) {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    }
    if (date is String) {
      final dt = DateTime.tryParse(date);
      if (dt != null) {
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      }
      return date;
    }
    return date.toString();
  }

  /// Tên thứ trong tuần tiếng Việt từ weekday (1=T2 .. 7=CN)
  static String weekdayName(int weekday) {
    const names = ['Th 2', 'Th 3', 'Th 4', 'Th 5', 'Th 6', 'Th 7', 'CN'];
    return names[(weekday - 1).clamp(0, 6)];
  }
}

/// Alias tiếng Việt để tương thích với các màn hình gọi TienIchDinhDang
typedef TienIchDinhDang = FormatUtils;

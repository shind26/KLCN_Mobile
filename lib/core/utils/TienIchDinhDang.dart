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

  /// Chuyển chuỗi về chữ thường và loại bỏ toàn bộ dấu tiếng Việt
  /// Hỗ trợ tìm kiếm thông minh không phân biệt hoa thường và dấu tiếng Việt (VD: "bAn cong" -> "ban cong")
  static String removeDiacritics(String str) {
    if (str.isEmpty) return '';
    String result = str.toLowerCase().trim();

    // 1. Thay thế các ký tự tiếng Việt dựng sẵn (precomposed)
    result = result.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
    result = result.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
    result = result.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
    result = result.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
    result = result.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
    result = result.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
    result = result.replaceAll(RegExp(r'[đ]'), 'd');

    // 2. Thay thế các ký tự tổ hợp (combining marks / decomposed NFD)
    result = result.replaceAll(RegExp(r'[\u0300\u0301\u0303\u0309\u0323]'), ''); // huyền, sắc, ngã, hỏi, nặng
    result = result.replaceAll(RegExp(r'[\u02C6\u0306\u031B]'), ''); // nón (â, ê, ô), trăng (ă), móc (ơ, ư)

    return result;
  }
}

/// Alias tiếng Việt để tương thích với các màn hình gọi TienIchDinhDang
typedef TienIchDinhDang = FormatUtils;

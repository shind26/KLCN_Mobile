import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'payment_sound_stub.dart'
    if (dart.library.js_interop) 'payment_sound_web.dart';

/// Tiện ích phát âm thanh thanh toán thành công (Ting / Chime Fintech)
class PaymentSoundHelper {
  static void playSuccess() {
    try {
      // Rung phản hồi xúc giác
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);

      // Trên Web: gọi hàm tổng hợp âm thanh Web Audio API
      if (kIsWeb) {
        try {
          playWebPaymentSoundPlatform();
        } catch (_) {}
      }
    } catch (_) {}
  }
}

import 'dart:js_interop' as js;

@js.JS('playPaymentSuccessSound')
external void _playWebPaymentSound();

void playWebPaymentSoundPlatform() {
  _playWebPaymentSound();
}

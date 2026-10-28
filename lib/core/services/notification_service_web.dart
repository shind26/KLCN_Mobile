import 'dart:js_interop' as js;

@js.JS('requestSystemNotificationPermission')
external void _jsRequestPermission();

@js.JS('showSystemNotification')
external void _jsShowNotification(
  js.JSString title,
  js.JSString body,
  js.JSString tag,
);

void requestNotificationPermissionPlatform() {
  _jsRequestPermission();
}

void showNotificationPlatform({
  required String title,
  required String body,
  required String tag,
}) {
  _jsShowNotification(title.toJS, body.toJS, tag.toJS);
}

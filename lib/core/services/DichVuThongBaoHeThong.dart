import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service_stub.dart'
    if (dart.library.js_interop) 'notification_service_web.dart';

/// Dịch vụ thông báo toàn diện: Ngoài hệ thống (OS / Thanh thông báo điện thoại thiệt)
/// và Trung tâm thông báo Cái Chuông trong ứng dụng
class SystemNotificationService {
  static bool _requested = false;
  static bool _isMobileInitialized = false;
  static final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'kieugiang_approval_channel',
    'Thông báo Kiêu Giang House',
    description:
        'Kênh thông báo phê duyệt chuyển phòng, hợp đồng, hóa đơn và sự cố',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // Bộ nhớ đệm chống bắn trùng lặp thông báo (In-memory + SharedPreferences)
  static final Set<String> _sentNotificationTags = {};
  static final Set<String> _readNotificationIds = {};

  // Danh sách thông báo hiển thị trên Cái Chuông (Centralized In-App Notification Center)
  static final ValueNotifier<List<Map<String, dynamic>>> danhSachThongBaoNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  // Trạng thái bật/tắt nhận thông báo ứng dụng (Người dùng điều khiển ở Tab Cá nhân)
  static bool isNotificationEnabled = true;

  static Future<void> setNotificationEnabled(bool enabled) async {
    isNotificationEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('kieugiang_thong_bao_ung_dung', enabled);
    } catch (_) {}
  }

  static int get soThongBaoChuaDoc =>
      danhSachThongBaoNotifier.value.where((t) => t['da_doc'] == false).length;

  /// Khởi tạo dịch vụ thông báo trên Mobile (Android/iOS)
  static Future<void> init() async {
    if (kIsWeb || _isMobileInitialized) return;
    try {
      // Tải các tag đã gửi & thông báo đã đọc từ SharedPreferences
      await _loadPersistedStates();

      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotif.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[NOTIF] Người dùng bấm vào thông báo: ${response.payload}');
        },
      );

      // Tạo notification channel trên Android
      final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(_androidChannel);
      }

      _isMobileInitialized = true;
      debugPrint('[NOTIF] Đã khởi tạo FlutterLocalNotifications thành công');
    } catch (e) {
      debugPrint('[NOTIF] Lỗi init FlutterLocalNotifications: $e');
    }
  }

  static Future<void> _loadPersistedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      isNotificationEnabled = prefs.getBool('kieugiang_thong_bao_ung_dung') ?? true;
      final sentList = prefs.getStringList('kieugiang_sent_notif_tags') ?? [];
      _sentNotificationTags.addAll(sentList);

      final readList = prefs.getStringList('kieugiang_read_notif_ids') ?? [];
      _readNotificationIds.addAll(readList);
    } catch (e) {
      debugPrint('[NOTIF] Lỗi load persisted states: $e');
    }
  }

  static Future<void> _saveSentTag(String tag) async {
    try {
      _sentNotificationTags.add(tag);
      final prefs = await SharedPreferences.getInstance();
      final list = _sentNotificationTags.toList();
      if (list.length > 100) {
        list.removeRange(0, list.length - 100);
      }
      await prefs.setStringList('kieugiang_sent_notif_tags', list);
    } catch (_) {}
  }

  /// Đánh dấu một thông báo đã đọc
  static Future<void> markAsRead(String id) async {
    _readNotificationIds.add(id);
    final current = List<Map<String, dynamic>>.from(danhSachThongBaoNotifier.value);
    for (var item in current) {
      if (item['id'] == id) {
        item['da_doc'] = true;
      }
    }
    danhSachThongBaoNotifier.value = current;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('kieugiang_read_notif_ids', _readNotificationIds.toList());
    } catch (_) {}
  }

  /// Đánh dấu tất cả thông báo đã đọc
  static Future<void> markAllAsRead() async {
    final current = List<Map<String, dynamic>>.from(danhSachThongBaoNotifier.value);
    for (var item in current) {
      item['da_doc'] = true;
      final id = item['id']?.toString();
      if (id != null) _readNotificationIds.add(id);
    }
    danhSachThongBaoNotifier.value = current;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('kieugiang_read_notif_ids', _readNotificationIds.toList());
    } catch (_) {}
  }

  /// Thêm hoặc cập nhật thông báo hiển thị trên Cái Chuông
  static void addInAppNotification({
    required String id,
    required String tieuDe,
    required String noiDung,
    String loai = 'thong_bao',
    bool isError = false,
    DateTime? thoiGian,
    VoidCallback? onXem,
  }) {
    final current = List<Map<String, dynamic>>.from(danhSachThongBaoNotifier.value);
    final existingIdx = current.indexWhere((it) => it['id'] == id);
    final bool daDoc = _readNotificationIds.contains(id);

    final map = {
      'id': id,
      'tieu_de': tieuDe,
      'noi_dung': noiDung,
      'loai': loai,
      'thoi_gian': thoiGian ?? DateTime.now(),
      'da_doc': daDoc,
      'is_error': isError,
      'on_xem': onXem,
    };

    if (existingIdx >= 0) {
      current[existingIdx] = map;
    } else {
      current.insert(0, map);
    }
    danhSachThongBaoNotifier.value = current;
  }

  /// Xin quyền gửi thông báo từ người dùng (gọi lúc khởi động ứng dụng)
  static Future<void> requestPermission() async {
    if (_requested) return;
    _requested = true;

    if (kIsWeb) {
      try {
        requestNotificationPermissionPlatform();
      } catch (e) {
        debugPrint('[NOTIF] Lỗi requestPermission web: $e');
      }
      return;
    }

    // Trên Android / iOS
    try {
      await init();
      final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('[NOTIF] Lỗi requestPermission mobile: $e');
    }
  }

  /// Bắn thông báo nổi ngoài hệ thống (trên thanh thông báo điện thoại thiệt)
  /// và TỰ ĐỘNG ĐỒNG BỘ VÀO CÁI CHUÔNG của app.
  /// Đảm bảo DUY NHẤT 1 LẦN cho mỗi sự kiện (chống trùng lặp tuyệt đối).
  static Future<void> show({
    required String title,
    required String body,
    String tag = 'kieugiang_approval',
    String? payload,
    String loai = 'thong_bao',
    bool isError = false,
    VoidCallback? onXem,
    bool force = false,
  }) async {
    try {
      // 1. TỰ ĐỘNG THÊM VÀO CÁI CHUÔNG TRONG APP
      addInAppNotification(
        id: tag,
        tieuDe: title,
        noiDung: body,
        loai: loai,
        isError: isError,
        onXem: onXem,
      );

      // 2. CHỐNG BẮN TRÙNG LẶP: Nếu cùng sự kiện (cùng tag) đã được thông báo, KHÔNG bắn lại lần 2
      if (!force && _sentNotificationTags.contains(tag)) {
        // debugPrint('[NOTIF] Đã chặn thông báo trùng lặp tag=$tag: $title');
        return;
      }
      await _saveSentTag(tag);

      // Nếu người dùng đã tắt thông báo ứng dụng trong Cài đặt, không bắn cảnh báo ra hệ thống
      if (!isNotificationEnabled) {
        debugPrint('[NOTIF] Đã tắt thông báo ứng dụng, bỏ qua hiển thị ngoài hệ thống: $title');
        return;
      }

      if (kIsWeb) {
        showNotificationPlatform(title: title, body: body, tag: tag);
        return;
      }

      // Mobile (Android / iOS)
      if (!_isMobileInitialized) {
        await init();
      }

      final AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        _androidChannel.id,
        _androidChannel.name,
        channelDescription: _androidChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        visibility: NotificationVisibility.public,
        channelShowBadge: true,
        showWhen: true,
        autoCancel: true,
        category: AndroidNotificationCategory.status,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'Kiêu Giang House',
        ),
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final NotificationDetails notifDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // ID cố định theo hash của tag để Android OS không bao giờ sinh ra 2 thông báo cùng lúc
      final int notifId = tag.hashCode & 0x7FFFFFFF;
      await _localNotif.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: notifDetails,
        payload: payload ?? tag,
      );
      debugPrint('[NOTIF] Đã bắn thông báo điện thoại thiệt thành công (id=$notifId, tag=$tag): $title');
    } catch (e) {
      debugPrint('[NOTIF] Lỗi showNotification mobile: $e');
    }
  }
}

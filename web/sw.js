// Service Worker cho Web & Mobile Push Notifications (Android / iOS / Desktop)
const CACHE_NAME = 'kieugiang-notif-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// Xử lý khi người dùng nhấn vào thông báo trên thanh thông báo điện thoại
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const targetUrl = (event.notification.data && event.notification.data.url) 
    ? event.notification.data.url 
    : self.location.origin;

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (let i = 0; i < clientList.length; i++) {
        let client = clientList[i];
        if (client.url.startsWith(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
    })
  );
});

// Lắng nghe push event từ server (nếu sau này tích hợp Web Push protocol)
self.addEventListener('push', (event) => {
  let data = {};
  if (event.data) {
    try {
      data = event.data.json();
    } catch (_) {
      data = { title: 'Nhà Trọ Kiêu Giang', body: event.data.text() };
    }
  }
  const title = data.title || 'Nhà Trọ Kiêu Giang';
  const options = {
    body: data.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    vibrate: [200, 100, 200, 100, 300],
    data: { url: data.url || '/' },
    tag: data.tag || 'kieugiang_push',
    renotify: true,
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

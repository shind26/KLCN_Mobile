import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:nhatro_kieugiang/features/splash/ManHinhKhoiDong.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';

import 'package:nhatro_kieugiang/core/services/DichVuThongBaoHeThong.dart';
import 'package:nhatro_kieugiang/core/utils/ThongBaoHelper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Supabase Client
  await Supabase.initialize(
    url: 'https://umxyotycpumkkpjwfvlz.supabase.co',
    anonKey: 'sb_publishable_49LvKuRkKsV6EII-OfUiPA_IWg_eOa6',
  );

  // Khởi tạo dịch vụ thông báo hệ thống (chuông & rung ngoài app)
  await SystemNotificationService.init();
  await SystemNotificationService.requestPermission();

  // Khởi tạo bộ nhớ đệm chống lặp thông báo
  await ThongBaoHelper.init();

  // Khởi tạo trạng thái phiên đăng nhập
  await AuthService.init();

  runApp(const MyApp());
}

// Biến gọi tắt dùng để truy vấn database từ bất kỳ màn hình nào
SupabaseClient get supabase => Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quản Lý Nhà Trọ Kiêu Giang',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF145D85)),
        useMaterial3: true,
        fontFamilyFallback: const ['Roboto', 'sans-serif'],
      ),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child ?? const SizedBox(),
        );
      },
      home: const SplashScreen(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF145D85),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        elevation: 2,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_rounded, size: 72, color: Color(0xFF145D85)),
            SizedBox(height: 16),
            Text(
              'Chào mừng đến với\nQuản Lý Nhà Trọ Kiêu Giang',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF145D85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

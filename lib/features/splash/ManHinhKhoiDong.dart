import 'package:flutter/material.dart';
import 'package:nhatro_kieugiang/core/services/DichVuXacThuc.dart';
import 'package:nhatro_kieugiang/features/guest/ManHinhTrangChuKhach.dart';
import 'package:nhatro_kieugiang/features/tenant/ManHinhTrangChuCuDan.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _sweepController;
  late AnimationController _floatController;
  late AnimationController _pulseController;
  late Animation<double> _sweepAnimation;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();

    // Controller cho thanh load trượt qua lại (1.3s cho mỗi chiều)
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _sweepAnimation = CurvedAnimation(
      parent: _sweepController,
      curve: Curves.easeInOut,
    );

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(begin: -8.0, end: 8.0).animate(
      CurvedAnimation(
        parent: _floatController,
        curve: Curves.easeInOutSine,
      ),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    // Bắt đầu đếm ngược 4s trước khi chuyển màn hình
    _startLoadingProcess();
  }

  Future<void> _startLoadingProcess() async {
    // Đảm bảo nạp lại session chính xác từ SharedPreferences
    await AuthService.init();
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final isLoggedIn = AuthService.isLoggedIn;
    final currentUser = AuthService.currentUser;
    debugPrint('>>> [SplashScreen] Kiểm tra đăng nhập: isLoggedIn = $isLoggedIn, user = ${currentUser?.tenDangNhap}');

    final Widget targetScreen = isLoggedIn
        ? TenantHomeScreen(
            tenantName: currentUser?.tenDangNhap,
          )
        : const GuestHomeScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 800),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ),
            child: child,
          );
        },
      ),
    );
  }


  @override
  void dispose() {
    _sweepController.dispose();
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF145D85),
                  Color(0xFF2276A3),
                  Color(0xFF4C98BD), 
                  Color(0xFF6FB6D7), 
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),

          AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              return CustomPaint(
                painter: BackgroundEffectPainter(
                  floatValue: _floatController.value,
                  pulseValue: _pulseController.value,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _floatAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _floatAnimation.value),
                      child: Container(
                        width: 170,
                        height: 170,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(36),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                            BoxShadow(
                              color: const Color(0xFF145D85).withValues(alpha: 0.2),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.home_work_rounded,
                                      size: 56, color: Color(0xFF2276A3)),
                                  SizedBox(height: 8),
                                  Text(
                                    'Kiêu Giang',
                                    style: TextStyle(
                                      color: Color(0xFF2276A3),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  )
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 32),

                Text(
                  'Nhà Trọ',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.9),
                    letterSpacing: 0.5,
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Kiêu Giang',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 24),

                // THANH LOAD 
                AnimatedBuilder(
                  animation: _sweepAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 90,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment(
                                -1.0 + 2.0 * _sweepAnimation.value,
                                0.0,
                              ),
                              child: Container(
                                width: 35,
                                height: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // 4. CHỮ VERSION 2.0 & HOME 
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'VERSION 2.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.0,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 134,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class BackgroundEffectPainter extends CustomPainter {
  final double floatValue;
  final double pulseValue;

  BackgroundEffectPainter({
    required this.floatValue,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45);

   
    paint.color = Colors.white.withValues(alpha: 0.08 + pulseValue * 0.04);
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.2 + (floatValue * 3)),
      110,
      paint,
    );

  
    paint.color = Colors.white.withValues(alpha: 0.06 + floatValue.abs() * 0.005);
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.75 - (floatValue * 2)),
      140,
      paint,
    );

    paint.color = Colors.white.withValues(alpha: 0.05 + pulseValue * 0.03);
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.42),
      130 + pulseValue * 15,
      paint,
    );

    final particlePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.35);

    final particles = [
      Offset(size.width * 0.2, size.height * 0.35 + floatValue * 2),
      Offset(size.width * 0.8, size.height * 0.25 - floatValue * 1.5),
      Offset(size.width * 0.25, size.height * 0.65 - floatValue * 2),
      Offset(size.width * 0.75, size.height * 0.55 + floatValue * 1.8),
      Offset(size.width * 0.5, size.height * 0.18 + floatValue * 2.5),
    ];

    final radii = [3.0, 4.0, 2.5, 3.5, 2.0];

    for (int i = 0; i < particles.length; i++) {
      canvas.drawCircle(particles[i], radii[i], particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundEffectPainter oldDelegate) {
    return oldDelegate.floatValue != floatValue ||
        oldDelegate.pulseValue != pulseValue;
  }
}

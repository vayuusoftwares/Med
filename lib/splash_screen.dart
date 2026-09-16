import 'dart:async';
import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'models/user_model.dart';
import 'services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _busPositionAnimation;
  int _progressPercent = 0;
  Timer? _timer;

  // Theming Colors matching MedSafe
  static const _emeraldPrimary = Color(0xFF00A86B);
  static const _darkText = Color(0xFF1E293B);

  @override
  void initState() {
    super.initState();

    // ── Animation Setup (3 seconds total duration) ──
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // Animates from left off-screen (-1.5) to right off-screen (1.5)
    _busPositionAnimation = Tween<double>(begin: -1.3, end: 1.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutQuad),
    );

    _controller.forward();

    // ── Progress Counter Setup ──
    const interval = Duration(milliseconds: 30); // 30ms * 100 steps = 3000ms
    _timer = Timer.periodic(interval, (timer) {
      if (mounted) {
        setState(() {
          if (_progressPercent < 100) {
            _progressPercent++;
          } else {
            _timer?.cancel();
            _navigateToLogin();
          }
        });
      }
    });
  }

  /// After the splash animation completes, check for a stored token.
  /// If one exists, go straight to HomeScreen; otherwise show LoginScreen.
  Future<void> _navigateToLogin() async {
    final storage = StorageService();
    final token = await storage.getToken();
    final User? user = await storage.getUser();

    if (!mounted) return;

    final Widget destination = (token != null && user != null)
        ? HomeScreen(user: user, token: token)
        : const LoginScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: Stack(
          children: [
            // ── Background Decorative Elements ──
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0F00A86B),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x0A00A86B),
                ),
              ),
            ),

            // ── Main UI Layout ──
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Brand Badge
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0x1A00A86B),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x3300A86B), width: 1.5),
                      ),
                      child: const Icon(
                        Icons.medical_services_rounded,
                        color: _emeraldPrimary,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'MEDSAFE',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _darkText,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const Text(
                      'Life Science Force',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _emeraldPrimary,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 120),

                    // ── Bus Loading Path (The Road) ──
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // The road line
                        Container(
                          width: double.infinity,
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 48),
                          decoration: BoxDecoration(
                            color: const Color(0x3300A86B),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Animated Bus
                        AnimatedBuilder(
                          animation: _busPositionAnimation,
                          builder: (context, child) {
                            return Align(
                              alignment: Alignment(_busPositionAnimation.value, 0.0),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 48),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Glow shadow behind bus
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(0x4000A86B),
                                            blurRadius: 16,
                                            spreadRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.directions_bus_rounded,
                                      color: _emeraldPrimary,
                                      size: 38,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    // ── Progress Counter Text ──
                    Text(
                      '$_progressPercent%',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: _emeraldPrimary,
                        fontFamily: 'Courier', // Monospace for numbers
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Loading Field Force Modules...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0x991E293B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

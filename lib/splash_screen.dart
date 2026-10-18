import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart';
import 'welcome_screen.dart';

/// The first screen the user sees: an animated brand mark that fades and scales
/// in, then hands control to [VidSaveHomePage].
///
/// Kept deliberately short (see [SplashScreen.duration]) so the app never feels
/// like it is stalling on launch.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// How long the splash stays on screen before navigating away.
  static const duration = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _navigationTimer;

  // The app-wide brand colour, matching the seed colour in main.dart.
  static const Color _brandColor = Color(0xFF087E8B);

  @override
  void initState() {
    super.initState();

    // A light hardware tap gives the launch a polished, physical feel.
    HapticFeedback.mediumImpact();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _animationController.forward();

    _navigationTimer = Timer(SplashScreen.duration, _goToHome);
  }

  Future<void> _goToHome() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome) ?? false;
    if (!mounted) return;

    final nextScreen = hasSeenWelcome ? const VidSaveHomePage() : const WelcomeScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 700),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: Stack(
        children: [
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: _brandColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: _brandColor.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.file_download_outlined,
                          size: 50,
                          color: _brandColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'VidSave',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.black.withValues(alpha: 0.85),
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'PREMIUM VIDEO & MP3 DOWNLOADER',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withValues(alpha: 0.3),
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 70,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _brandColor.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

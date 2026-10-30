import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'screens/onboarding_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    this.authService,
    this.isFirstTime,
    required this.authenticatedBuilder,
    required this.guestBuilder,
  });

  final AuthService? authService;
  final bool? isFirstTime;
  final WidgetBuilder authenticatedBuilder;
  final WidgetBuilder guestBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<bool> _initialDestination = _resolveInitialDestination();

  Future<bool> _resolveInitialDestination() async {
    final auth = widget.authService ?? AuthService.instance;
    if (await auth.hasStoredSession) {
      try {
        if (await auth.currentUser() != null) return true;
      } catch (_) {
        // Preserve offline access for a previously authenticated installation.
        return true;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(WelcomeScreen.prefKeyHasSeenWelcome) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Uygulamaya ilk kez giriş yapan kullanıcılar için OnboardingScreen gösterilir.
    // Tanıtım bittiğinde veya atlandığında doğrudan ana sayfaya yönlendirilir.
    if (widget.isFirstTime == true) {
      return OnboardingScreen(
        homeBuilder: widget.authenticatedBuilder,
      );
    }

    return FutureBuilder<bool>(
      future: _initialDestination,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == true) return widget.authenticatedBuilder(context);
        return widget.guestBuilder(context);
      },
    );
  }
}

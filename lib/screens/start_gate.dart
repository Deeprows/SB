import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../services/ad_scheduler.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'shell_screen.dart';

/// First screen: Gmail login (when nobody is signed in), then Free or
/// Premium. Premium people go straight into the app.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  static const _kSeen = 'plans_seen';

  bool _decided = false;
  bool _showPlans = false;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuth);
    _decide();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuth);
    super.dispose();
  }

  /// Signed in (or out): swap between the login page and the app.
  void _onAuth() {
    if (!mounted) return;
    if (AuthService.instance.signedIn && _decided && !_showPlans) {
      unawaited(AdScheduler.instance.start());
    }
    setState(() {});
  }

  Future<void> _decide() async {
    final sub = SubscriptionService.instance;
    var show = sub.visible && !sub.isPremium;
    if (show && !AppConfig.showPlansEveryStart) {
      try {
        final prefs = await SharedPreferences.getInstance();
        show = !(prefs.getBool(_kSeen) ?? false);
      } catch (_) {}
    }
    if (!show && AuthService.instance.signedIn) {
      unawaited(AdScheduler.instance.start());
    }
    if (!mounted) return;
    setState(() {
      _showPlans = show;
      _decided = true;
    });
  }

  Future<void> _enter() async {
    try {
      (await SharedPreferences.getInstance()).setBool(_kSeen, true);
    } catch (_) {}
    if (AuthService.instance.signedIn) unawaited(AdScheduler.instance.start());
    if (mounted) setState(() => _showPlans = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_decided) return Scaffold(backgroundColor: Ui.bg);
    // Gmail login comes first; the plans page / app follow once signed in.
    if (!AuthService.instance.signedIn) {
      return LoginScreen(onSignedIn: () {});
    }
    if (_showPlans) return PlansScreen(onContinue: _enter);
    return const ShellScreen();
  }
}

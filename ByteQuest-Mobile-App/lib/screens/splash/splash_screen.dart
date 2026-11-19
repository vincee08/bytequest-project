import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../core/config/supabase_config.dart';
import '../../services/app_version_service.dart';
import '../../services/auth_service.dart';
import 'update_required_panel.dart';

enum _VersionGate { checking, updateRequired, checkFailed, proceeding }

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.checkAppVersion,
    this.splashDelay = const Duration(seconds: 3),
  });

  /// Overrides the minimum-version check (tests). Defaults to the server
  /// value in `app_release_config`.
  final AppVersionChecker? checkAppVersion;

  /// Minimum time the brand splash stays visible.
  final Duration splashDelay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  Timer? _navigationTimer;
  late Future<AppVersionCheck> _versionCheck;
  _VersionGate _gate = _VersionGate.checking;
  AppVersionCheck? _lastCheck;
  bool _rechecking = false;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    _animationController.forward();

    // The version check runs while the splash is visible; navigation waits
    // for both the splash delay and the check.
    _versionCheck = _runVersionCheck();
    _navigationTimer = Timer(widget.splashDelay, _afterSplash);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: show the final frame instead of animating.
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _animationController.value = 1;
    }
  }

  Future<AppVersionCheck> _runVersionCheck() async {
    try {
      return await (widget.checkAppVersion ?? AppVersionService().check)();
    } catch (_) {
      return const AppVersionCheck(
        status: AppVersionStatus.unknown,
        currentVersion: kAppVersion,
      );
    }
  }

  Future<void> _afterSplash() async {
    final check = await _versionCheck;
    if (!mounted) return;
    _applyVersionCheck(check);
  }

  void _applyVersionCheck(AppVersionCheck check) {
    switch (check.status) {
      case AppVersionStatus.supported:
        setState(() {
          _lastCheck = check;
          _gate = _VersionGate.proceeding;
        });
        _navigateFromAuthState();
      case AppVersionStatus.updateRequired:
        // Blocking: an outdated app never reaches the learner shell.
        setState(() {
          _lastCheck = check;
          _gate = _VersionGate.updateRequired;
        });
      case AppVersionStatus.unknown:
        // Offline or unreachable: fail open, but offer a retry.
        setState(() {
          _lastCheck = check;
          _gate = _VersionGate.checkFailed;
        });
    }
  }

  Future<void> _recheckVersion() async {
    if (_rechecking) return;
    setState(() => _rechecking = true);
    final check = await _runVersionCheck();
    if (!mounted) return;
    setState(() => _rechecking = false);
    _applyVersionCheck(check);
  }

  void _continueWithoutVersion() {
    if (_gate != _VersionGate.checkFailed) return;
    setState(() => _gate = _VersionGate.proceeding);
    _navigateFromAuthState();
  }

  /// Check if user is logged in and navigate accordingly
  Future<void> _navigateFromAuthState() async {
    if (!mounted) return;

    try {
      // Check if user is already logged in
      final currentUser = SupabaseConfig.currentUser;
      final session = SupabaseConfig.client.auth.currentSession;

      if (currentUser != null && session != null) {
        // A session alone is not sufficient: a deactivated account must not
        // enter the learner shell. AuthService performs the trusted profile
        // state check against Supabase before navigation.
        final isActive = await AuthService().isAccountActive();
        if (!mounted) return;
        if (isActive) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        } else {
          await AuthService().signOut();
          if (!mounted) return;
          Navigator.of(context).pushReplacementNamed('/onboarding');
        }
      } else {
        // No active session - go to onboarding
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    } catch (e) {
      debugPrint('Error checking auth state: $e');
      // On error, go to onboarding to be safe
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/onboarding');
      }
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  Widget _statusArea() {
    final check = _lastCheck;
    switch (_gate) {
      case _VersionGate.updateRequired:
        return UpdateRequiredPanel(
          currentVersion: check?.currentVersion ?? kAppVersion,
          minimumVersion: check?.minimumVersion ?? kAppVersion,
          checking: _rechecking,
          onCheckAgain: _recheckVersion,
        );
      case _VersionGate.checkFailed:
        return VersionCheckFailedPanel(
          checking: _rechecking,
          onRetry: _recheckVersion,
          onContinue: _continueWithoutVersion,
        );
      case _VersionGate.checking:
      case _VersionGate.proceeding:
        return SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation<Color>(
              AppTheme.primaryBlue,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _gate == _VersionGate.updateRequired ||
        _gate == _VersionGate.checkFailed;
    return Scaffold(
      backgroundColor: AppTheme.cardWhite,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 24.0, horizontal: 16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // System Unit Mascot
                      Container(
                        width: blocked ? 120 : 200,
                        height: blocked ? 120 : 200,
                        decoration: BoxDecoration(
                          color: AppTheme.backgroundPaleBlue,
                          borderRadius: BorderRadius.circular(32),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: Image.asset(
                          'assets/images/System Unit Mascot.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                      SizedBox(height: blocked ? 20 : 32),

                      // ByteQuest Logo with Name
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            padding: const EdgeInsets.all(8),
                            child: Image.asset(
                              'assets/images/ByteQuest Logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              AppConstants.appName,
                              style: AppTheme.displayMedium.copyWith(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Tagline with colored words
                      if (!blocked) ...[
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: AppTheme.headlineMedium.copyWith(
                              color: AppTheme.textDark,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                            children: [
                              TextSpan(
                                text: 'Learn',
                                style: TextStyle(color: AppTheme.primaryBlue),
                              ),
                              const TextSpan(text: '. '),
                              TextSpan(
                                text: 'Build',
                                style: TextStyle(color: AppTheme.primaryBlue),
                              ),
                              const TextSpan(text: '. '),
                              TextSpan(
                                text: 'Level Up',
                                style: TextStyle(color: AppTheme.accentOrange),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 60),
                      ] else
                        const SizedBox(height: 8),

                      // Loading indicator or the version gate
                      AnimatedSwitcher(
                        duration: MediaQuery.maybeDisableAnimationsOf(
                                    context) ==
                                true
                            ? Duration.zero
                            : AppTheme.simulationTransitionDuration,
                        child: KeyedSubtree(
                          key: ValueKey(_gate),
                          child: _statusArea(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

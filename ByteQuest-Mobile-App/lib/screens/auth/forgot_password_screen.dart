import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../data/mission_content_data.dart';
import '../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      await authService.resetPassword(_emailController.text.trim());

      if (mounted) {
        setState(() {
          _isLoading = false;
          _emailSent = true;
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(MissionContentData.recoveryEmailSent),
            backgroundColor: AppTheme.accentGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(MissionContentData.recoveryEmailUnavailable),
            backgroundColor: AppTheme.errorRed,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: MissionContentData.backLabel,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Icon
                Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      _emailSent ? Icons.mark_email_read : Icons.lock_reset,
                      size: 50,
                      color: AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Title
                Center(
                  child: Text(
                    _emailSent ? 'Check Your Email' : 'Forgot Password?',
                    textAlign: TextAlign.center,
                    style: AppTheme.displaySmall.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Description
                Center(
                  child: Text(
                    _emailSent
                        ? MissionContentData.recoveryEmailSent
                        : 'Enter your email address and we\'ll send you a link to reset your password.',
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                if (!_emailSent) ...[
                  // Email Field
                  Text('Email Address', style: AppTheme.labelLarge),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: MissionContentData.emailFieldLabel,
                      hintText: 'Enter your email address',
                      prefixIcon:
                          Icon(Icons.email, color: AppTheme.primaryBlue),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Send Reset Link Button
                  AppButton.primary(
                    label: 'Send Reset Link',
                    onPressed: _handleResetPassword,
                    isLoading: _isLoading,
                    width: double.infinity,
                  ),
                ] else ...[
                  // Back to Login Button
                  AppButton.primary(
                    label: 'Back to Login',
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed('/login');
                    },
                    width: double.infinity,
                  ),
                ],
                const SizedBox(height: 16),

                // Back to Login Link
                if (!_emailSent)
                  Center(
                    child: AppButton.text(
                      label: 'Back to Login',
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

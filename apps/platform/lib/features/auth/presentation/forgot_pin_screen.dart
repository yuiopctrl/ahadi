import 'package:flutter/material.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';

enum _Step { phone, otp }

class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  _Step _step = _Step.phone;
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.requestForgotPinOtp(
      _phoneController.text.trim(),
    );
    setState(() {
      _busy = false;
      if (ok) {
        _step = _Step.otp;
      } else {
        _error = widget.controller.lastError;
      }
    });
  }

  Future<void> _verifyAndSetPin() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.verifyForgotPinOtpAndSetPin(
      phone: _phoneController.text.trim(),
      token: _otpController.text.trim(),
      newPin: _pinController.text.trim(),
    );
    setState(() => _busy = false);
    if (ok && mounted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.controller.lastError);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset PIN')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_step == _Step.phone) ...[
                  const Text(
                    'Enter your phone number to receive a verification code.',
                    style: PlatformTypography.secondary,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone number (+2557XXXXXXXX)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _requestOtp,
                    child: _busy ? const _Spinner() : const Text('Send code'),
                  ),
                ] else ...[
                  Text(
                    'Enter the code sent to ${_phoneController.text}',
                    style: PlatformTypography.secondary,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _otpController,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    decoration: const InputDecoration(
                      labelText: 'New 4-digit PIN',
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _verifyAndSetPin,
                    child: _busy ? const _Spinner() : const Text('Reset PIN'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: PlatformColors.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}

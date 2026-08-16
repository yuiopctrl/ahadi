import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../data/session_controller.dart';
import 'pin_input.dart';

class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final confirmPinController = TextEditingController();
  ForgotPinStep step = ForgotPinStep.phone;
  String pendingPin = '';

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Forgot PIN')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AhadiColors.muted),
                ),
                const SizedBox(height: 24),
                if (step == ForgotPinStep.phone) ...[
                  TextField(
                    key: const Key('forgot-phone-input'),
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('request-otp-button'),
                    onPressed: widget.controller.isSubmitting
                        ? null
                        : () async {
                            await widget.controller.requestForgotPinOtp(
                              phoneController.text,
                            );
                            if (mounted) {
                              setState(() => step = ForgotPinStep.otp);
                            }
                          },
                    child: const Text('Send code'),
                  ),
                ],
                if (step == ForgotPinStep.otp) ...[
                  TextField(
                    key: const Key('otp-input'),
                    controller: otpController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Verification code',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('verify-otp-button'),
                    onPressed: widget.controller.isSubmitting
                        ? null
                        : () async {
                            await widget.controller.verifyForgotPinOtp(
                              phone: phoneController.text,
                              token: otpController.text,
                            );
                            if (mounted) {
                              setState(() => step = ForgotPinStep.newPin);
                            }
                          },
                    child: const Text('Verify code'),
                  ),
                ],
                if (step == ForgotPinStep.newPin) ...[
                  PinInput(
                    key: const Key('new-pin-input'),
                    label: 'New PIN',
                    onCompleted: (pin) => pendingPin = pin,
                    enabled: !widget.controller.isSubmitting,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('confirm-pin-input'),
                    controller: confirmPinController,
                    maxLength: 4,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new PIN',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('set-pin-button'),
                    onPressed: widget.controller.isSubmitting
                        ? null
                        : () async {
                            await widget.controller.setForgottenPin(
                              pin: pendingPin,
                              confirmPin: confirmPinController.text,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                    child: const Text('Set PIN'),
                  ),
                ],
                if (widget.controller.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.controller.errorMessage!,
                    style: const TextStyle(color: AhadiColors.danger),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String get _title {
    return switch (step) {
      ForgotPinStep.phone => 'Recover your PIN',
      ForgotPinStep.otp => 'Enter the code',
      ForgotPinStep.newPin => 'Set a new PIN',
    };
  }

  String get _subtitle {
    return switch (step) {
      ForgotPinStep.phone =>
        'We will verify your phone before allowing a PIN reset.',
      ForgotPinStep.otp => 'Use the SMS code sent by Ahadi.',
      ForgotPinStep.newPin =>
        'Choose a 4 digit PIN you have not used elsewhere.',
    };
  }
}

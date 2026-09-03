import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
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
          appBar: AppBar(title: Text(context.t('auth.forgotPinTitle'))),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _title(context),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  _subtitle(context),
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: AhadiColors.muted),
                ),
                const SizedBox(height: 24),
                if (step == ForgotPinStep.phone) ...[
                  TextField(
                    key: const Key('forgot-phone-input'),
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: context.t('auth.phoneNumber'),
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
                    child: Text(context.t('auth.sendCode')),
                  ),
                ],
                if (step == ForgotPinStep.otp) ...[
                  TextField(
                    key: const Key('otp-input'),
                    controller: otpController,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.t('auth.verificationCode'),
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
                    child: Text(context.t('auth.verifyCode')),
                  ),
                ],
                if (step == ForgotPinStep.newPin) ...[
                  PinInput(
                    key: const Key('new-pin-input'),
                    label: context.t('auth.newPin'),
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
                    decoration: InputDecoration(
                      labelText: context.t('auth.confirmNewPin'),
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
                    child: Text(context.t('auth.setPin')),
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

  String _title(BuildContext context) {
    return switch (step) {
      ForgotPinStep.phone => context.t('auth.recoverPin'),
      ForgotPinStep.otp => context.t('auth.enterTheCode'),
      ForgotPinStep.newPin => context.t('auth.setNewPin'),
    };
  }

  String _subtitle(BuildContext context) {
    return switch (step) {
      ForgotPinStep.phone => context.t('auth.recoverPinHint'),
      ForgotPinStep.otp => context.t('auth.enterCodeHint'),
      ForgotPinStep.newPin => context.t('auth.setNewPinHint'),
    };
  }
}

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/presentation/pin_input.dart';

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  String currentPin = '';
  String newPin = '';
  final confirmPin = TextEditingController();

  @override
  void dispose() {
    confirmPin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('shell.changePin'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                context.t('profile.currentPin'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              PinInput(
                onCompleted: (value) => currentPin = value,
                enabled: !widget.controller.isSubmitting,
              ),
              const SizedBox(height: 16),
              Text(
                context.t('auth.newPin'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              PinInput(
                onCompleted: (value) => newPin = value,
                enabled: !widget.controller.isSubmitting,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmPin,
                maxLength: 4,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.t('auth.confirmNewPin'),
                  counterText: '',
                ),
              ),
              if (widget.controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.controller.errorMessage!,
                  style: const TextStyle(color: AhadiColors.danger),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: widget.controller.isSubmitting
                    ? null
                    : () async {
                        await widget.controller.changePin(
                          currentPin: currentPin,
                          newPin: newPin,
                          confirmNewPin: confirmPin.text,
                        );
                        if (context.mounted) Navigator.of(context).pop();
                      },
                child: Text(context.t('profile.savePin')),
              ),
            ],
          ),
        );
      },
    );
  }
}

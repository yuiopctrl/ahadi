import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/brand_header.dart';
import '../data/session_controller.dart';
import 'forgot_pin_screen.dart';
import 'pin_input.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final phoneController = TextEditingController();
  final pinKey = GlobalKey<PinInputState>();

  @override
  void dispose() {
    phoneController.dispose();
    super.dispose();
  }

  Future<void> submit(String pin) async {
    try {
      await widget.controller.loginWithPin(
        phone: phoneController.text,
        pin: pin,
      );
    } catch (_) {
      pinKey.currentState?.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const BrandHeader(subtitle: 'Mobile'),
                          const SizedBox(height: 28),
                          Text(
                            'Sign in',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use your verified phone number and 4 digit PIN.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AhadiColors.muted),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            key: const Key('phone-input'),
                            controller: phoneController,
                            enabled: !widget.controller.isSubmitting,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Phone number',
                              hintText: '0712 345 678',
                            ),
                          ),
                          const SizedBox(height: 16),
                          PinInput(
                            key: pinKey,
                            enabled: !widget.controller.isSubmitting,
                            onCompleted: submit,
                          ),
                          if (widget.controller.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              widget.controller.errorMessage!,
                              style: const TextStyle(color: AhadiColors.danger),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton(
                            key: const Key('login-button'),
                            onPressed: widget.controller.isSubmitting
                                ? null
                                : () {
                                    final pin =
                                        pinKey.currentState?.controller.text ??
                                        '';
                                    if (pin.length == 4) submit(pin);
                                  },
                            child: widget.controller.isSubmitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Login'),
                          ),
                          TextButton(
                            onPressed: widget.controller.isSubmitting
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ForgotPinScreen(
                                          controller: widget.controller,
                                        ),
                                      ),
                                    );
                                  },
                            child: const Text('Forgot PIN?'),
                          ),
                          const Divider(height: 28),
                          Center(
                            child: Text(
                              'New to Ahadi?',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: AhadiColors.muted),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            key: const Key('create-account-signup'),
                            onPressed: widget.controller.isSubmitting
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => RegisterScreen(
                                        controller: widget.controller,
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Create Account'),
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
      },
    );
  }
}

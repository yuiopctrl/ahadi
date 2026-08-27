import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: _LanguageToggle(
                      key: const Key('login-language-switcher'),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AhadiColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AhadiColors.border),
                            boxShadow: [
                              BoxShadow(
                                color: AhadiColors.text.withValues(alpha: 0.06),
                                blurRadius: 48,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const BrandHeader(),
                                const SizedBox(height: 32),
                                Text(
                                  context.t('auth.signIn'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context.t('auth.signInHint'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: AhadiColors.muted),
                                ),
                                const SizedBox(height: 24),
                                TextField(
                                  key: const Key('phone-input'),
                                  controller: phoneController,
                                  enabled: !widget.controller.isSubmitting,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  decoration: InputDecoration(
                                    labelText: context.t('auth.phoneNumber'),
                                    hintText: '0712 345 678',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                PinInput(
                                  key: pinKey,
                                  enabled: !widget.controller.isSubmitting,
                                  onCompleted: submit,
                                ),
                                if (widget.controller.errorMessage !=
                                    null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    widget.controller.errorMessage!,
                                    style: const TextStyle(
                                      color: AhadiColors.danger,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                FilledButton(
                                  key: const Key('login-button'),
                                  onPressed: widget.controller.isSubmitting
                                      ? null
                                      : () {
                                          final pin =
                                              pinKey.currentState?.controller
                                                  .text ??
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
                                      : Text(context.t('auth.login')),
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
                                  child: Text(context.t('auth.forgotPin')),
                                ),
                                const Divider(height: 28),
                                Center(
                                  child: Text(
                                    context.t('auth.newToAhadi'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
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
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: Text(context.t('auth.createAccount')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.appLanguage;
    final controller = AppLocaleScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LanguageOption(
          label: 'SW',
          selected: current == AppLanguage.sw,
          onTap: () => controller.setLanguage(AppLanguage.sw),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('|', style: TextStyle(color: AhadiColors.border)),
        ),
        _LanguageOption(
          label: 'EN',
          selected: current == AppLanguage.en,
          onTap: () => controller.setLanguage(AppLanguage.en),
        ),
      ],
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AhadiColors.primary : AhadiColors.muted,
          ),
        ),
      ),
    );
  }
}

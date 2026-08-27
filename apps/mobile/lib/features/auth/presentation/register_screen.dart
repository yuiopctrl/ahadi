import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../data/phone_normalization.dart';
import '../data/session_controller.dart';
import 'forgot_pin_screen.dart';
import 'invitation_review_card.dart';
import 'pin_input.dart';

enum _RegisterStep { phone, existing, otp, pin, profile, invitations, welcome }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final phone = TextEditingController();
  final otp = TextEditingController();
  final fullName = TextEditingController();
  final email = TextEditingController();
  final pinKey = GlobalKey<PinInputState>();
  final confirmPinKey = GlobalKey<PinInputState>();
  _RegisterStep step = _RegisterStep.phone;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    otp.dispose();
    fullName.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      setState(() => error = null);
      final normalized = normalizeTanzaniaPhone(phone.text);
      phone.text = normalized;
      final state = await widget.controller.accountState(normalized);
      if (state['existingVerifiedAccount'] == true) {
        setState(() => step = _RegisterStep.existing);
        return;
      }
      await widget.controller.requestRegistrationOtp(normalized);
      setState(() => step = _RegisterStep.otp);
    } catch (err) {
      setState(() => error = _message(err));
    }
  }

  Future<void> _verifyOtp() async {
    try {
      setState(() => error = null);
      await widget.controller.verifyRegistrationOtp(
        phone: phone.text,
        token: otp.text,
      );
      setState(() => step = _RegisterStep.pin);
    } catch (err) {
      setState(() => error = _message(err));
    }
  }

  Future<void> _setPin() async {
    try {
      setState(() => error = null);
      final pin = pinKey.currentState?.controller.text ?? '';
      final confirmPin = confirmPinKey.currentState?.controller.text ?? '';
      await widget.controller.setRegistrationPin(
        pin: pin,
        confirmPin: confirmPin,
      );
      final invitation =
          widget.controller.userContext?.pendingInvitations.firstOrNull;
      fullName.text =
          widget.controller.userContext?.profile?.fullName.isNotEmpty == true
          ? widget.controller.userContext!.profile!.fullName
          : invitation?.fullName ?? '';
      email.text =
          widget.controller.userContext?.profile?.email ??
          invitation?.email ??
          '';
      setState(() => step = _RegisterStep.profile);
    } catch (err) {
      pinKey.currentState?.clear();
      confirmPinKey.currentState?.clear();
      setState(() => error = _message(err));
    }
  }

  Future<void> _saveProfile() async {
    try {
      setState(() => error = null);
      await widget.controller.updateProfile(
        fullName: fullName.text,
        email: email.text,
      );
      setState(() {
        step =
            widget.controller.userContext?.pendingInvitations.isNotEmpty == true
            ? _RegisterStep.invitations
            : _RegisterStep.welcome;
      });
    } catch (err) {
      setState(() => error = _message(err));
    }
  }

  Future<void> _join(String invitationId) async {
    try {
      await widget.controller.acceptInvitation(invitationId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (err) {
      setState(() => error = _message(err));
    }
  }

  Future<void> _decline(String invitationId) async {
    try {
      await widget.controller.declineInvitation(invitationId);
      setState(() {
        step =
            widget.controller.userContext?.pendingInvitations.isNotEmpty == true
            ? _RegisterStep.invitations
            : _RegisterStep.welcome;
      });
    } catch (err) {
      setState(() => error = _message(err));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('auth.createAccount'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _title(),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _subtitle(),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 20),
              ..._content(),
              if (error != null || widget.controller.errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  error ?? widget.controller.errorMessage!,
                  style: const TextStyle(color: AhadiColors.danger),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  List<Widget> _content() {
    final busy = widget.controller.isSubmitting;
    switch (step) {
      case _RegisterStep.phone:
        return [
          TextField(
            controller: phone,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: context.t('auth.phoneNumber'),
              hintText: '0712 345 678',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _start,
            child: Text(busy ? context.t('auth.checking') : context.t('auth.continue')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('auth.backToLogin')),
          ),
        ];
      case _RegisterStep.existing:
        return [
          Text(context.t('auth.existingAccountMessage')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('auth.backToLogin')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ForgotPinScreen(controller: widget.controller),
              ),
            ),
            child: Text(context.t('auth.forgotPin')),
          ),
        ];
      case _RegisterStep.otp:
        return [
          Text('${context.t('auth.codeSentTo')} ${phone.text}'),
          const SizedBox(height: 12),
          TextField(
            controller: otp,
            enabled: !busy,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.t('auth.sixDigitCode')),
            onChanged: (value) {
              if (value.length == 6) _verifyOtp();
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy || otp.text.length != 6 ? null : _verifyOtp,
            child: Text(busy ? context.t('auth.verifying') : context.t('auth.verifyCode')),
          ),
        ];
      case _RegisterStep.pin:
        return [
          PinInput(key: pinKey, enabled: !busy, onCompleted: (_) {}),
          const SizedBox(height: 12),
          PinInput(
            key: confirmPinKey,
            enabled: !busy,
            label: context.t('auth.confirmPin'),
            onCompleted: (_) => _setPin(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _setPin,
            child: Text(busy ? context.t('auth.saving') : context.t('auth.continue')),
          ),
        ];
      case _RegisterStep.profile:
        return [
          TextField(
            controller: fullName,
            enabled: !busy,
            decoration: InputDecoration(labelText: context.t('auth.fullName')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: context.t('auth.email')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _saveProfile,
            child: Text(busy ? context.t('auth.saving') : context.t('auth.continue')),
          ),
        ];
      case _RegisterStep.invitations:
        final invitations =
            widget.controller.userContext?.pendingInvitations ?? const [];
        return [
          for (final invitation in invitations) ...[
            InvitationReviewCard(
              invitation: invitation,
              busy: busy,
              onDecline: () => _decline(invitation.invitationId),
              onJoin: () => _join(invitation.invitationId),
            ),
            const SizedBox(height: 12),
          ],
        ];
      case _RegisterStep.welcome:
        return [
          Text(context.t('auth.notAMemberYet')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t('auth.createOrganization')),
          ),
        ];
    }
  }

  String _title() {
    return switch (step) {
      _RegisterStep.phone => context.t('auth.createAccount'),
      _RegisterStep.existing => context.t('auth.accountExists'),
      _RegisterStep.otp => context.t('auth.verifyPhone'),
      _RegisterStep.pin => context.t('auth.setPin'),
      _RegisterStep.profile => context.t('auth.completeProfile'),
      _RegisterStep.invitations => context.t('auth.youreInvited'),
      _RegisterStep.welcome => context.t('auth.welcomeToAhadi'),
    };
  }

  String _subtitle() {
    return switch (step) {
      _RegisterStep.phone => context.t('auth.phoneStepHint'),
      _RegisterStep.existing => context.t('auth.existingStepHint'),
      _RegisterStep.otp => context.t('auth.otpStepHint'),
      _RegisterStep.pin => context.t('auth.pinStepHint'),
      _RegisterStep.profile => context.t('auth.profileStepHint'),
      _RegisterStep.invitations => context.t('auth.invitationsStepHint'),
      _RegisterStep.welcome => context.t('auth.welcomeStepHint'),
    };
  }
}

String _message(Object error) {
  if (error is FormatException) return error.message;
  return 'Something went wrong. Please try again.';
}

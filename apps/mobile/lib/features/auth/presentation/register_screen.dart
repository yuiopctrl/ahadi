import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../data/phone_normalization.dart';
import '../data/session_controller.dart';
import 'forgot_pin_screen.dart';
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
          appBar: AppBar(title: const Text('Create Account')),
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
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: '0712 345 678',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _start,
            child: Text(busy ? 'Checking...' : 'Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Login'),
          ),
        ];
      case _RegisterStep.existing:
        return [
          const Text(
            'This phone number already has an Ahadi account.\nLog in using your PIN.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Login'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => ForgotPinScreen(controller: widget.controller),
              ),
            ),
            child: const Text('Forgot PIN?'),
          ),
        ];
      case _RegisterStep.otp:
        return [
          Text('Code sent to ${phone.text}'),
          const SizedBox(height: 12),
          TextField(
            controller: otp,
            enabled: !busy,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Six-digit code'),
            onChanged: (value) {
              if (value.length == 6) _verifyOtp();
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy || otp.text.length != 6 ? null : _verifyOtp,
            child: Text(busy ? 'Verifying...' : 'Verify code'),
          ),
        ];
      case _RegisterStep.pin:
        return [
          PinInput(key: pinKey, enabled: !busy, onCompleted: (_) {}),
          const SizedBox(height: 12),
          PinInput(
            key: confirmPinKey,
            enabled: !busy,
            onCompleted: (_) => _setPin(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _setPin,
            child: Text(busy ? 'Saving...' : 'Continue'),
          ),
        ];
      case _RegisterStep.profile:
        return [
          TextField(
            controller: fullName,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : _saveProfile,
            child: Text(busy ? 'Saving...' : 'Continue'),
          ),
        ];
      case _RegisterStep.invitations:
        final invitations =
            widget.controller.userContext?.pendingInvitations ?? const [];
        return [
          for (final invitation in invitations) ...[
            Card(
              child: ListTile(
                title: Text(invitation.tenantName),
                subtitle: Text(
                  'Role ${invitation.roleCode.replaceAll('_', ' ')}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _decline(invitation.invitationId),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _join(invitation.invitationId),
                      child: const Text('Join'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ];
      case _RegisterStep.welcome:
        return [
          const Text('You are not currently a member of an organization.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Create Organization'),
          ),
        ];
    }
  }

  String _title() {
    return switch (step) {
      _RegisterStep.phone => 'Create Account',
      _RegisterStep.existing => 'Account exists',
      _RegisterStep.otp => 'Verify phone',
      _RegisterStep.pin => 'Set PIN',
      _RegisterStep.profile => 'Complete Profile',
      _RegisterStep.invitations => "You're Invited",
      _RegisterStep.welcome => 'Welcome to Ahadi',
    };
  }

  String _subtitle() {
    return switch (step) {
      _RegisterStep.phone =>
        'Enter your phone number to start account verification.',
      _RegisterStep.existing =>
        'Use normal login for returning Ahadi accounts.',
      _RegisterStep.otp => 'Enter the code sent by SMS.',
      _RegisterStep.pin => 'Create a secure 4-digit PIN.',
      _RegisterStep.profile => 'This name is used across your Ahadi account.',
      _RegisterStep.invitations =>
        'Review organization invitations for your verified phone.',
      _RegisterStep.welcome =>
        'Create an organization only after your account is ready.',
    };
  }
}

String _message(Object error) {
  if (error is FormatException) return error.message;
  return 'Something went wrong. Please try again.';
}

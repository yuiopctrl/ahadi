import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import 'change_pin_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final profile = controller.userContext?.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          context.t('shell.more.profile'),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AhadiColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AhadiColors.border),
              ),
              child: const Icon(
                Icons.person_outline,
                color: AhadiColors.primary,
              ),
            ),
            title: Text(
              profile?.fullName.isNotEmpty == true
                  ? profile!.fullName
                  : context.t('shell.ahadiUser'),
            ),
            subtitle: Text(profile?.email ?? context.t('profile.noEmailAdded')),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.t('profile.editProfile')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: Text(context.t('shell.changePin')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangePinScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout_outlined),
                title: Text(context.t('common.signOut')),
                onTap: () async {
                  await controller.signOut();
                  if (context.mounted) {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController fullName;
  late final TextEditingController email;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.userContext?.profile;
    fullName = TextEditingController(text: profile?.fullName ?? '');
    email = TextEditingController(text: profile?.email ?? '');
  }

  @override
  void dispose() {
    fullName.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.updateProfile(
      fullName: fullName.text,
      email: email.text,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final phone = widget.controller.userContext?.profile?.phoneE164 ?? '';
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AhadiColors.background,
          appBar: AppBar(title: Text(context.t('profile.editProfile'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: fullName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.t('auth.fullName')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: context.t('auth.email')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: false,
                initialValue: phone,
                decoration: InputDecoration(labelText: context.t('auth.phoneNumber')),
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
                onPressed: widget.controller.isSubmitting ? null : _save,
                child: Text(
                  widget.controller.isSubmitting ? context.t('auth.saving') : context.t('profile.saveProfile'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

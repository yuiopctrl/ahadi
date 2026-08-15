import 'package:flutter/material.dart';

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
          'Profile',
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
                  : 'Ahadi user',
            ),
            subtitle: Text(profile?.email ?? 'No email added'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Profile'),
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
                title: const Text('Change PIN'),
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
                title: const Text('Sign out'),
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
          appBar: AppBar(title: const Text('Edit Profile')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: fullName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                enabled: false,
                initialValue: phone,
                decoration: const InputDecoration(labelText: 'Phone Number'),
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
                  widget.controller.isSubmitting ? 'Saving...' : 'Save Profile',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
            leading: const CircleAvatar(
              backgroundColor: AhadiColors.primary,
              foregroundColor: Colors.white,
              child: Icon(Icons.person_outline),
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
                leading: const Icon(Icons.logout),
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

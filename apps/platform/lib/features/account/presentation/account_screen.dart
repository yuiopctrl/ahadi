import 'package:flutter/material.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    final profile = session?.profile;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account', style: PlatformTypography.pageTitle),
                const SizedBox(height: 16),
                _row('Name', profile?.fullName ?? '-'),
                _row('Phone', profile?.phoneE164 ?? '-'),
                _row('Email', profile?.email ?? '-'),
                _row('Platform role', session?.platformRole ?? '-'),
                _row('Status', session?.platformStatus ?? '-'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: controller.logout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: PlatformTypography.label),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Organization')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Create your Ahadi organization',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Registration uses phone verification and the existing onboarding flow. Verification starts only after you continue.',
            style: TextStyle(color: AhadiColors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Mobile onboarding will continue in the registration flow.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

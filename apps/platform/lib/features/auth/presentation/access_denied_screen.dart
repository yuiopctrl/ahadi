import 'package:flutter/material.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/brand_header.dart';

/// Shown when an authenticated user has no active platform access.
/// Never renders platform data first -- SessionController only reaches
/// BootstrapState.ready after confirming hasActivePlatformAccess, so this
/// screen and the platform shell are mutually exclusive by construction.
class AccessDeniedScreen extends StatelessWidget {
  const AccessDeniedScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandHeader(),
              const SizedBox(height: 32),
              const Icon(
                Icons.lock_outline,
                size: 40,
                color: PlatformColors.muted,
              ),
              const SizedBox(height: 16),
              const Text(
                'Your account does not have access to Changisha Platform.',
                textAlign: TextAlign.center,
                style: PlatformTypography.cardTitle,
              ),
              const SizedBox(height: 8),
              const Text(
                'If you believe this is a mistake, contact a Changisha platform administrator.',
                textAlign: TextAlign.center,
                style: PlatformTypography.secondary,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: controller.logout,
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

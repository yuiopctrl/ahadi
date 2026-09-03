import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../core/localization/app_locale.dart';
import '../core/networking/ahadi_api.dart';
import '../core/networking/api_client.dart';
import '../core/storage/session_storage.dart';
import '../core/theme/ahadi_theme.dart';
import '../features/auth/data/session_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/organizations/presentation/organization_selection_screen.dart';
import '../features/shell/presentation/mobile_shell.dart';

class AhadiApp extends StatefulWidget {
  const AhadiApp({
    super.key,
    this.config,
    this.api,
    this.storage,
    this.controller,
    this.localeController,
  });

  final AppConfig? config;
  final AhadiApi? api;
  final SessionStorage? storage;
  final SessionController? controller;
  final AppLocaleController? localeController;

  @override
  State<AhadiApp> createState() => _AhadiAppState();
}

class _AhadiAppState extends State<AhadiApp> {
  late final SessionController controller;
  late final AppLocaleController localeController;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      controller = widget.controller!;
    } else {
      final storage = widget.storage ?? SecureSessionStorage();
      late final ApiClient api;
      api = ApiClient(
        config: widget.config ?? AppConfig.fromEnvironment(),
        accessTokenProvider: () async => controller.accessToken,
      );
      controller = SessionController(api: widget.api ?? api, storage: storage);
    }
    localeController = widget.localeController ?? AppLocaleController();
    localeController.load();
    controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AppLocaleScope(
      controller: localeController,
      child: MaterialApp(
        title: 'Changisha',
        debugShowCheckedModeBanner: false,
        theme: ahadiTheme(),
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return switch (controller.bootstrapState) {
              BootstrapState.initializing ||
              BootstrapState.restoringSession ||
              BootstrapState.resolvingAccess => const SplashScreen(),
              BootstrapState.unauthenticated => LoginScreen(
                controller: controller,
              ),
              BootstrapState.error => BootstrapErrorScreen(
                controller: controller,
              ),
              BootstrapState.ready => _ReadyScreen(controller: controller),
            };
          },
        ),
      ),
    );
  }
}

class _ReadyScreen extends StatelessWidget {
  const _ReadyScreen({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.needsInvitationReview) {
      return InvitationsReviewScreen(controller: controller);
    }
    if (controller.needsOrganizationCreation) {
      return EmptyOrganizationsScreen(controller: controller);
    }
    if (controller.needsOrganizationSelection) {
      return OrganizationSelectionScreen(
        controller: controller,
        memberships: controller.activeMemberships,
      );
    }
    if (controller.selectedTenantContext != null) {
      return MobileShell(
        key: ValueKey(controller.selectedTenantId),
        controller: controller,
      );
    }
    return OrganizationSelectionScreen(
      controller: controller,
      memberships: controller.activeMemberships,
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 34,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class BootstrapErrorScreen extends StatelessWidget {
  const BootstrapErrorScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(
                controller.errorMessage ?? 'Unable to start Ahadi.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.initialize,
                child: const Text('Try again'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await controller.signOut();
                },
                child: const Text('Sign in again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

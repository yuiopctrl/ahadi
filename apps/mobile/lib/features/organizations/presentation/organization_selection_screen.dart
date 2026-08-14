import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'create_organization_screen.dart';

class OrganizationSelectionScreen extends StatelessWidget {
  const OrganizationSelectionScreen({
    super.key,
    required this.controller,
    required this.memberships,
  });

  final SessionController controller;
  final List<TenantMembership> memberships;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Organization')),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: memberships.length + 1,
          separatorBuilder: (_, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            if (index == memberships.length) {
              return OutlinedButton.icon(
                key: const Key('create-organization-entry'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        CreateOrganizationScreen(controller: controller),
                  ),
                ),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Create another organization'),
              );
            }
            final membership = memberships[index];
            return Card(
              child: ListTile(
                key: Key('organization-${membership.tenantId}'),
                title: Text(
                  membership.tenantName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  membership.subscription?.planName ?? 'Ahadi workspace',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => controller.selectTenant(membership.tenantId),
              ),
            );
          },
        ),
      ),
    );
  }
}

class EmptyOrganizationsScreen extends StatelessWidget {
  const EmptyOrganizationsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizations'),
        actions: [
          IconButton(
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.business_outlined,
              size: 44,
              color: AhadiColors.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Create or join an organization',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'This account does not belong to an active Ahadi organization yet.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AhadiColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CreateOrganizationScreen(controller: controller),
                ),
              ),
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Create organization'),
            ),
          ],
        ),
      ),
    );
  }
}

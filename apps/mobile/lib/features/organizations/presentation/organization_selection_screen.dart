import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/presentation/invitation_review_card.dart';
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
      appBar: AppBar(title: Text(context.t('organizations.chooseOrganization'))),
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
                label: Text(context.t('shell.createAnotherOrganization')),
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
                  membership.subscription?.planName ?? context.t('organizations.ahadiWorkspace'),
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
        title: Text(context.t('shell.organizations')),
        actions: [
          IconButton(
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
            tooltip: context.t('common.signOut'),
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
              context.t('organizations.createOrJoin'),
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('organizations.noActiveOrgHint'),
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
              label: Text(context.t('organizations.createOrganization')),
            ),
          ],
        ),
      ),
    );
  }
}

class InvitationsReviewScreen extends StatelessWidget {
  const InvitationsReviewScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final invitations = controller.userContext?.pendingInvitations ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('organizations.invitations')),
        actions: [
          IconButton(
            onPressed: controller.signOut,
            icon: const Icon(Icons.logout),
            tooltip: context.t('common.signOut'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          Text(
            invitations.length == 1 ? context.t('auth.youreInvited') : context.t('organizations.invitations'),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            context.t('organizations.acceptInvitationHint'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AhadiColors.muted),
          ),
          const SizedBox(height: 18),
          for (final invitation in invitations) ...[
            InvitationReviewCard(
              invitation: invitation,
              busy: controller.isSubmitting,
              onDecline: () =>
                  controller.declineInvitation(invitation.invitationId),
              onJoin: () =>
                  controller.acceptInvitation(invitation.invitationId),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

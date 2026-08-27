import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../domain/auth_models.dart';

class InvitationReviewCard extends StatelessWidget {
  const InvitationReviewCard({
    super.key,
    required this.invitation,
    required this.busy,
    required this.onDecline,
    required this.onJoin,
  });

  final TenantInvitation invitation;
  final bool busy;
  final VoidCallback onDecline;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final role = invitation.roleCode.replaceAll('_', ' ');
    return Container(
      decoration: BoxDecoration(
        color: AhadiColors.surface,
        border: Border.all(color: AhadiColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AhadiColors.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AhadiColors.primary),
                ),
                child: const Icon(
                  Icons.business_outlined,
                  color: AhadiColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.tenantName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('auth.invitedToJoin'),
                      style: AhadiTypography.secondary,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _InfoRow(label: context.t('auth.role'), value: role),
          if (invitation.fullName.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(label: context.t('auth.name'), value: invitation.fullName.trim()),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDecline,
                  child: Text(context.t('auth.decline')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onJoin,
                  child: Text(busy ? context.t('auth.joining') : context.t('auth.joinOrganization')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AhadiColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AhadiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: AhadiColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

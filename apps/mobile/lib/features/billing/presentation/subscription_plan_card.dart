import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/domain/auth_models.dart';

class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.plan,
    this.selected = false,
    this.onTap,
    this.current = false,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected || current
        ? AhadiColors.primary
        : AhadiColors.border;
    final title = current ? '${plan.name} · Current' : plan.name;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: AhadiColors.primary),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _planPrice(plan),
          style: AhadiTypography.financialValue.copyWith(
            color: AhadiColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${_billingInterval(plan.billingInterval)} billing · ${plan.trialDays} trial days',
          style: AhadiTypography.secondary,
        ),
        if ((plan.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(plan.description!.trim(), style: AhadiTypography.secondary),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LimitChip(text: _activeEventLimit(plan.maxActiveEvents)),
            _LimitChip(text: '${plan.maxUsers} users'),
            _LimitChip(text: '${plan.maxMembers} members'),
            _LimitChip(text: '${plan.includedSms} SMS'),
          ],
        ),
      ],
    );

    return Material(
      color: AhadiColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0f000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: body,
        ),
      ),
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: AhadiColors.primaryStrong,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

String _planPrice(SubscriptionPlan plan) {
  final amount = plan.priceAmount;
  final price = plan.currency.toUpperCase() == 'TZS'
      ? moneyText(amount)
      : '${plan.currency.toUpperCase()} ${amount.round()}';
  return '$price / ${_billingInterval(plan.billingInterval)}';
}

String _billingInterval(String value) {
  return value.toLowerCase().replaceAll('_', ' ');
}

String _activeEventLimit(int value) {
  if (value <= 0) return 'No active events';
  if (value == 1) return '1 active event';
  return '$value active events';
}

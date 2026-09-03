import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../billing/presentation/subscription_plan_card.dart';

class CreateOrganizationScreen extends StatefulWidget {
  const CreateOrganizationScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<CreateOrganizationScreen> createState() =>
      _CreateOrganizationScreenState();
}

class _CreateOrganizationScreenState extends State<CreateOrganizationScreen> {
  final tenantName = TextEditingController();
  final tenantPhone = TextEditingController();
  final tenantEmail = TextEditingController();
  final adminFullName = TextEditingController();
  final adminEmail = TextEditingController();
  final firstEventName = TextEditingController();
  final eventDate = TextEditingController();
  final venue = TextEditingController();
  final targetAmount = TextEditingController();
  final pledgeDeadline = TextEditingController();
  Future<List<SubscriptionPlan>>? plansFuture;
  String? planCode;
  String eventType = 'WEDDING';

  @override
  void initState() {
    super.initState();
    plansFuture = widget.controller.plans();
    adminFullName.text = widget.controller.userContext?.profile?.fullName ?? '';
    adminEmail.text = widget.controller.userContext?.profile?.email ?? '';
  }

  @override
  void dispose() {
    tenantName.dispose();
    tenantPhone.dispose();
    tenantEmail.dispose();
    adminFullName.dispose();
    adminEmail.dispose();
    firstEventName.dispose();
    eventDate.dispose();
    venue.dispose();
    targetAmount.dispose();
    pledgeDeadline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(context.t('organizations.createOrganizationTitle'))),
          body: FutureBuilder<List<SubscriptionPlan>>(
            future: plansFuture,
            builder: (context, snapshot) {
              final plans = snapshot.data ?? const <SubscriptionPlan>[];
              planCode ??= plans.isNotEmpty ? plans.first.code : null;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.t('organizations.package'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const LinearProgressIndicator()
                  else if (plans.isEmpty)
                    const _PlanUnavailableCard()
                  else
                    ...plans.map(
                      (plan) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SubscriptionPlanCard(
                          key: Key('plan-card-${plan.code}'),
                          plan: plan,
                          selected: planCode == plan.code,
                          onTap: () => setState(() => planCode = plan.code),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    context.t('organizations.organizationDetails'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(
                    tenantName,
                    context.t('organizations.organizationName'),
                    key: 'tenant-name-input',
                  ),
                  _field(
                    tenantPhone,
                    context.t('organizations.organizationPhone'),
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    tenantEmail,
                    context.t('organizations.organizationEmail'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.t('organizations.firstEvent'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(firstEventName, context.t('events.eventName')),
                  DropdownButtonFormField<String>(
                    initialValue: eventType,
                    items: [
                      DropdownMenuItem(
                        value: 'WEDDING',
                        child: Text(context.t('events.type.WEDDING')),
                      ),
                      DropdownMenuItem(
                        value: 'SENDOFF',
                        child: Text(context.t('events.type.SENDOFF')),
                      ),
                      DropdownMenuItem(
                        value: 'FUNERAL',
                        child: Text(context.t('events.type.FUNERAL')),
                      ),
                      DropdownMenuItem(
                        value: 'FUNDRAISER',
                        child: Text(context.t('events.type.FUNDRAISER')),
                      ),
                      DropdownMenuItem(value: 'OTHER', child: Text(context.t('events.type.OTHER'))),
                    ],
                    onChanged: (value) =>
                        setState(() => eventType = value ?? 'WEDDING'),
                    decoration: InputDecoration(labelText: context.t('events.eventType')),
                  ),
                  const SizedBox(height: 12),
                  _field(eventDate, context.t('events.eventDate')),
                  _field(venue, context.t('events.venue')),
                  _field(
                    targetAmount,
                    context.t('events.targetAmount'),
                    keyboardType: TextInputType.number,
                  ),
                  _field(pledgeDeadline, context.t('events.pledgeDeadline')),
                  const SizedBox(height: 12),
                  Text(
                    context.t('organizations.accountOwner'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(adminFullName, context.t('auth.fullName')),
                  _field(
                    adminEmail,
                    context.t('auth.email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  if (widget.controller.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.controller.errorMessage!,
                      style: const TextStyle(color: AhadiColors.danger),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('create-organization-button'),
                    onPressed:
                        widget.controller.isSubmitting || planCode == null
                        ? null
                        : () async {
                            await widget.controller.createOrganization(
                              planCode: planCode!,
                              tenantName: tenantName.text,
                              tenantPhone: tenantPhone.text,
                              tenantEmail: tenantEmail.text,
                              adminFullName: adminFullName.text,
                              adminEmail: adminEmail.text,
                              firstEventName: firstEventName.text,
                              eventType: eventType,
                              eventDate: eventDate.text,
                              venue: venue.text,
                              targetAmount: targetAmount.text,
                              pledgeDeadline: pledgeDeadline.text,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            Navigator.of(context).pop();
                          },
                    child: Text(context.t('organizations.createOrganization')),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? key,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: key == null ? null : Key(key),
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: keyboardType == TextInputType.number
            ? const [MoneyInputFormatter()]
            : null,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _PlanUnavailableCard extends StatelessWidget {
  const _PlanUnavailableCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AhadiColors.surface,
        border: Border.all(color: AhadiColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        context.t('organizations.noPlansAvailable'),
        style: AhadiTypography.secondary,
      ),
    );
  }
}

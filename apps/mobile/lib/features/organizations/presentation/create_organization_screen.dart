import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';

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
          appBar: AppBar(title: const Text('Create Organization')),
          body: FutureBuilder<List<SubscriptionPlan>>(
            future: plansFuture,
            builder: (context, snapshot) {
              final plans = snapshot.data ?? const <SubscriptionPlan>[];
              planCode ??= plans.isNotEmpty ? plans.first.code : null;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Package',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const Key('plan-dropdown'),
                    initialValue: planCode,
                    items: plans
                        .map(
                          (plan) => DropdownMenuItem(
                            value: plan.code,
                            child: Text(plan.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => planCode = value),
                    decoration: const InputDecoration(labelText: 'Package'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Organization details',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(
                    tenantName,
                    'Organization name',
                    key: 'tenant-name-input',
                  ),
                  _field(
                    tenantPhone,
                    'Organization phone',
                    keyboardType: TextInputType.phone,
                  ),
                  _field(
                    tenantEmail,
                    'Organization email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'First event',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(firstEventName, 'Event name'),
                  DropdownButtonFormField<String>(
                    initialValue: eventType,
                    items: const [
                      DropdownMenuItem(
                        value: 'WEDDING',
                        child: Text('Wedding'),
                      ),
                      DropdownMenuItem(
                        value: 'SENDOFF',
                        child: Text('Sendoff'),
                      ),
                      DropdownMenuItem(
                        value: 'FUNERAL',
                        child: Text('Funeral'),
                      ),
                      DropdownMenuItem(
                        value: 'FUNDRAISER',
                        child: Text('Fundraiser'),
                      ),
                      DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setState(() => eventType = value ?? 'WEDDING'),
                    decoration: const InputDecoration(labelText: 'Event type'),
                  ),
                  const SizedBox(height: 12),
                  _field(eventDate, 'Event date YYYY-MM-DD'),
                  _field(venue, 'Venue'),
                  _field(
                    targetAmount,
                    'Target amount',
                    keyboardType: TextInputType.number,
                  ),
                  _field(pledgeDeadline, 'Pledge deadline YYYY-MM-DD'),
                  const SizedBox(height: 12),
                  Text(
                    'Account owner',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _field(adminFullName, 'Full name'),
                  _field(
                    adminEmail,
                    'Email',
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
                    child: const Text('Create organization'),
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
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

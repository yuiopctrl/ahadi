import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  Key _reloadKey = UniqueKey();
  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _changeStatus(Map<String, dynamic> org, String status) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set subscription to $status'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || reasonController.text.trim().isEmpty) return;
    try {
      await widget.controller.api.setSubscriptionStatus(
        tenantId: org['id'] as String,
        status: status,
        reason: reasonController.text.trim(),
      );
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  Future<void> _changePlan(Map<String, dynamic> org) async {
    final plans = await widget.controller.api.listPlans();
    if (!mounted) return;
    final reasonController = TextEditingController();
    String? selectedPlanId;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change plan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedPlanId,
                decoration: const InputDecoration(labelText: 'New plan'),
                items: plans
                    .map(
                      (p) => DropdownMenuItem(
                        value: p['id'] as String,
                        child: Text('${p['name']}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => selectedPlanId = value),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    if (result != true ||
        selectedPlanId == null ||
        reasonController.text.trim().isEmpty)
      return;
    try {
      await widget.controller.api.changeSubscriptionPlan(
        tenantId: org['id'] as String,
        planId: selectedPlanId!,
        reason: reasonController.text.trim(),
      );
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.controller.hasPermission(
      PlatformPermission.subscriptionsManage,
    );
    return AsyncStateView<List<Map<String, dynamic>>>(
      key: _reloadKey,
      future: widget.controller.api.listOrganizations,
      isEmpty: (data) => data.isEmpty,
      emptyMessage: 'No subscriptions yet.',
      builder: (context, organizations) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Organization')),
                DataColumn(label: Text('Plan')),
                DataColumn(label: Text('Billing')),
                DataColumn(label: Text('Price')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Trial ends')),
                DataColumn(label: Text('Period end')),
                DataColumn(label: Text('Actions')),
              ],
              rows: organizations.map((org) {
                return DataRow(
                  cells: [
                    DataCell(Text('${org['name']}')),
                    DataCell(Text('${org['plan_name'] ?? '-'}')),
                    DataCell(Text('${org['plan_billing_interval'] ?? '-'}')),
                    DataCell(
                      Text(
                        org['plan_price_amount'] != null
                            ? '${org['plan_price_amount']} ${org['plan_currency'] ?? ''}'
                            : '-',
                      ),
                    ),
                    DataCell(
                      Chip(label: Text('${org['subscription_status'] ?? '-'}')),
                    ),
                    DataCell(Text('${org['trial_ends_at'] ?? '-'}')),
                    DataCell(Text('${org['current_period_end'] ?? '-'}')),
                    DataCell(
                      canManage
                          ? PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'plan') {
                                  _changePlan(org);
                                } else {
                                  _changeStatus(org, value);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'plan',
                                  child: Text('Change plan'),
                                ),
                                PopupMenuItem(
                                  value: 'ACTIVE',
                                  child: Text('Activate'),
                                ),
                                PopupMenuItem(
                                  value: 'SUSPENDED',
                                  child: Text('Suspend'),
                                ),
                                PopupMenuItem(
                                  value: 'CANCELLED',
                                  child: Text('Cancel'),
                                ),
                                PopupMenuItem(
                                  value: 'TRIAL',
                                  child: Text('Restore to trial'),
                                ),
                              ],
                            )
                          : const Text(
                              '-',
                              style: PlatformTypography.secondary,
                            ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

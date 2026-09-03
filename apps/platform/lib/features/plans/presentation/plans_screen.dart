import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/widgets/async_state_view.dart';
import 'plan_editor_dialog.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  Key _reloadKey = UniqueKey();
  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _create() async {
    final result = await showPlanEditorDialog(context);
    if (result == null) return;
    try {
      await widget.controller.api.createPlan(result.input);
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  Future<void> _edit(Map<String, dynamic> plan) async {
    final result = await showPlanEditorDialog(context, existing: plan);
    if (result == null) return;
    try {
      await widget.controller.api.updatePlan(
        plan['id'] as String,
        result.input,
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
      PlatformPermission.plansManage,
    );
    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New plan'),
            )
          : null,
      body: AsyncStateView<List<Map<String, dynamic>>>(
        key: _reloadKey,
        future: widget.controller.api.listPlans,
        isEmpty: (data) => data.isEmpty,
        emptyMessage: 'No plans configured yet.',
        builder: (context, plans) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: plans.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final plan = plans[index];
              return Card(
                child: ListTile(
                  title: Text('${plan['name']} (${plan['code']})'),
                  subtitle: Text(
                    '${plan['price_amount']} ${plan['currency']} / ${plan['billing_interval']}  •  '
                    'Events: ${plan['max_active_events']}  •  Members: ${plan['max_members']}  •  Users: ${plan['max_users']}  •  SMS: ${plan['included_sms']}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (plan['is_public'] != true)
                        const Chip(label: Text('Hidden')),
                      if (plan['is_active'] != true)
                        const Chip(label: Text('Inactive')),
                      if (canManage)
                        IconButton(
                          onPressed: () => _edit(plan),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

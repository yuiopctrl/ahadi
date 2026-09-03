import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class OrganizationDetailScreen extends StatefulWidget {
  const OrganizationDetailScreen({
    super.key,
    required this.controller,
    required this.tenantId,
  });

  final SessionController controller;
  final String tenantId;

  @override
  State<OrganizationDetailScreen> createState() =>
      _OrganizationDetailScreenState();
}

class _OrganizationDetailScreenState extends State<OrganizationDetailScreen> {
  Key _reloadKey = UniqueKey();

  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _promptReasonAndRun(
    String title,
    Future<void> Function(String reason) action,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    try {
      await action(reason);
      _reload();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Done.')));
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  Future<void> _extendTrial() async {
    final daysController = TextEditingController(text: '14');
    final reasonController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Extend trial'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: daysController,
              decoration: const InputDecoration(labelText: 'Days'),
              keyboardType: TextInputType.number,
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
            child: const Text('Extend'),
          ),
        ],
      ),
    );
    if (result != true) return;
    final days = int.tryParse(daysController.text.trim()) ?? 0;
    if (days <= 0 || reasonController.text.trim().isEmpty) return;
    try {
      await widget.controller.api.extendTrial(
        tenantId: widget.tenantId,
        days: days,
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
      PlatformPermission.tenantsManage,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Organization detail')),
      body: AsyncStateView<Map<String, dynamic>>(
        key: _reloadKey,
        future: () => widget.controller.api.organizationDetail(widget.tenantId),
        builder: (context, detail) {
          final tenant = detail['tenant'] as Map<String, dynamic>? ?? const {};
          final subscription = detail['subscription'] as Map<String, dynamic>?;
          final owner = detail['owner'] as Map<String, dynamic>?;
          final events =
              (detail['events'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
          final users =
              (detail['users'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
          final health = detail['health'] as Map<String, dynamic>?;
          final status = tenant['status'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${tenant['name'] ?? '-'}',
                        style: PlatformTypography.pageTitle,
                      ),
                    ),
                    if (status != null) Chip(label: Text(status)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Code: ${tenant['code'] ?? '-'}',
                  style: PlatformTypography.secondary,
                ),
                const SizedBox(height: 16),
                if (canManage)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status != 'SUSPENDED')
                        OutlinedButton(
                          onPressed: () => _promptReasonAndRun(
                            'Suspend organization',
                            (reason) =>
                                widget.controller.api.setOrganizationStatus(
                                  tenantId: widget.tenantId,
                                  status: 'SUSPENDED',
                                  reason: reason,
                                ),
                          ),
                          child: const Text('Suspend'),
                        ),
                      if (status == 'SUSPENDED')
                        FilledButton(
                          onPressed: () => widget.controller.api
                              .setOrganizationStatus(
                                tenantId: widget.tenantId,
                                status: 'ACTIVE',
                              )
                              .then((_) => _reload()),
                          child: const Text('Reactivate'),
                        ),
                      OutlinedButton(
                        onPressed: _extendTrial,
                        child: const Text('Extend trial'),
                      ),
                      if (widget.controller.hasPermission(
                        PlatformPermission.supportSessionStart,
                      ))
                        OutlinedButton(
                          onPressed: () => _promptReasonAndRun(
                            'Start support session',
                            (reason) => widget.controller.api
                                .startSupportSession(
                                  tenantId: widget.tenantId,
                                  reason: reason,
                                )
                                .then((_) {}),
                          ),
                          child: const Text('Start support session'),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                _SectionCard(
                  title: 'Subscription',
                  child: subscription == null
                      ? const Text(
                          'No subscription on record.',
                          style: PlatformTypography.secondary,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv(
                              'Plan',
                              '${subscription['planName'] ?? '-'} (${subscription['planCode'] ?? '-'})',
                            ),
                            _kv('Status', '${subscription['status'] ?? '-'}'),
                            _kv(
                              'Trial ends',
                              '${subscription['trial_ends_at'] ?? '-'}',
                            ),
                            _kv(
                              'Current period end',
                              '${subscription['current_period_end'] ?? '-'}',
                            ),
                          ],
                        ),
                ),
                _SectionCard(
                  title: 'Owner / Contact',
                  child: owner == null
                      ? const Text(
                          'No owner on record.',
                          style: PlatformTypography.secondary,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kv('Name', '${owner['full_name'] ?? '-'}'),
                            _kv(
                              'Phone',
                              '${owner['phone_e164'] ?? tenant['phone_e164'] ?? '-'}',
                            ),
                          ],
                        ),
                ),
                if (health != null)
                  _SectionCard(
                    title: 'Health',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('State', '${health['state'] ?? '-'}'),
                        if (health['warning'] != null)
                          _kv('Warning', '${health['warning']}'),
                        _kv(
                          'Last activity',
                          '${health['lastActivityAt'] ?? '-'}',
                        ),
                      ],
                    ),
                  ),
                _SectionCard(
                  title: 'Events (${events.length})',
                  child: events.isEmpty
                      ? const Text(
                          'No events yet.',
                          style: PlatformTypography.secondary,
                        )
                      : Column(
                          children: events
                              .map(
                                (e) => ListTile(
                                  dense: true,
                                  title: Text('${e['name']}'),
                                  trailing: Text('${e['status']}'),
                                ),
                              )
                              .toList(),
                        ),
                ),
                _SectionCard(
                  title: 'Users (${users.length})',
                  child: users.isEmpty
                      ? const Text(
                          'No users yet.',
                          style: PlatformTypography.secondary,
                        )
                      : Column(
                          children: users
                              .map(
                                (u) => ListTile(
                                  dense: true,
                                  title: Text('${u['fullName']}'),
                                  subtitle: Text('${u['phone']}'),
                                  trailing: Text(
                                    u['isOwner'] == true
                                        ? 'Owner'
                                        : '${u['status']}',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: PlatformTypography.label),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PlatformTypography.cardTitle),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

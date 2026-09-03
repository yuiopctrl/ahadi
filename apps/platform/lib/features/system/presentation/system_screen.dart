import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: PlatformColors.primary,
          tabs: const [
            Tab(text: 'Health & Errors'),
            Tab(text: 'Rollout / Configuration'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _HealthTab(controller: widget.controller),
              _RolloutTab(controller: widget.controller),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthTab extends StatelessWidget {
  const _HealthTab({required this.controller});

  final SessionController controller;

  Future<Map<String, dynamic>> _load() async {
    final health = await controller.api.systemHealth();
    final errors = await controller.api.systemErrors();
    return {'health': health, 'errors': errors};
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'HEALTHY':
        return PlatformColors.success;
      case 'WARNING':
        return PlatformColors.warning;
      default:
        return PlatformColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncStateView<Map<String, dynamic>>(
      future: _load,
      builder: (context, data) {
        final health = data['health'] as Map<String, dynamic>;
        final errors = (data['errors'] as List).cast<Map<String, dynamic>>();
        final smsQueue =
            health['smsQueue'] as Map<String, dynamic>? ?? const {};
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _HealthChip(
                    label: 'API',
                    status: (health['api'] as Map?)?['status'] as String?,
                    color: _statusColor,
                  ),
                  _HealthChip(
                    label: 'Database',
                    status: (health['database'] as Map?)?['status'] as String?,
                    color: _statusColor,
                  ),
                  _HealthChip(
                    label: 'SMS queue',
                    status: smsQueue['status'] as String?,
                    color: _statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SMS queue',
                        style: PlatformTypography.cardTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pending: ${smsQueue['pending']}   •   Failed (24h): ${smsQueue['failedLast24h']}   •   Sent today: ${smsQueue['sentToday']}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Support & errors',
                        style: PlatformTypography.cardTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open support requests: ${health['openSupportRequests']}',
                      ),
                      Text(
                        'Frontend errors (24h): ${health['recentErrors24h']}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Recent error groups (14 days)',
                style: PlatformTypography.cardTitle,
              ),
              const SizedBox(height: 8),
              if (errors.isEmpty)
                const Text(
                  'No errors recorded.',
                  style: PlatformTypography.secondary,
                )
              else
                ...errors.map(
                  (e) => ListTile(
                    dense: true,
                    title: Text('${e['error_code']}'),
                    subtitle: Text('${e['route']}'),
                    trailing: Text('${e['occurrences']}x'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({
    required this.label,
    required this.status,
    required this.color,
  });

  final String label;
  final String? status;
  final Color Function(String?) color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color(status)),
      label: Text('$label: ${status ?? 'UNKNOWN'}'),
    );
  }
}

class _RolloutTab extends StatefulWidget {
  const _RolloutTab({required this.controller});

  final SessionController controller;

  @override
  State<_RolloutTab> createState() => _RolloutTabState();
}

class _RolloutTabState extends State<_RolloutTab> {
  Key _reloadKey = UniqueKey();
  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _edit(Map<String, dynamic> settings) async {
    var registrationMode = settings['registrationMode'] as String? ?? 'OPEN';
    var maintenanceMode = settings['maintenanceMode'] as String? ?? 'OFF';
    var betaModeEnabled = settings['betaModeEnabled'] as bool? ?? false;
    final trialDaysController = TextEditingController(
      text: '${settings['defaultTrialDays'] ?? 14}',
    );
    final supportEmailController = TextEditingController(
      text: settings['supportEmail'] as String? ?? '',
    );
    final supportPhoneController = TextEditingController(
      text: settings['supportPhone'] as String? ?? '',
    );
    final maintenanceNoticeController = TextEditingController(
      text: settings['maintenanceNotice'] as String? ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Update rollout settings'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: registrationMode,
                    decoration: const InputDecoration(
                      labelText: 'Registration mode',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                      DropdownMenuItem(
                        value: 'INVITE_ONLY',
                        child: Text('Invite only'),
                      ),
                      DropdownMenuItem(value: 'PAUSED', child: Text('Paused')),
                    ],
                    onChanged: (value) => setState(
                      () => registrationMode = value ?? registrationMode,
                    ),
                  ),
                  SwitchListTile(
                    value: betaModeEnabled,
                    title: const Text('Beta mode enabled'),
                    onChanged: (v) => setState(() => betaModeEnabled = v),
                  ),
                  TextField(
                    controller: trialDaysController,
                    decoration: const InputDecoration(
                      labelText: 'Default trial days',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: supportEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Support email',
                    ),
                  ),
                  TextField(
                    controller: supportPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'Support phone',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: maintenanceMode,
                    decoration: const InputDecoration(
                      labelText: 'Maintenance mode',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'OFF', child: Text('Off')),
                      DropdownMenuItem(
                        value: 'READ_ONLY',
                        child: Text('Read-only'),
                      ),
                    ],
                    onChanged: (value) => setState(
                      () => maintenanceMode = value ?? maintenanceMode,
                    ),
                  ),
                  TextField(
                    controller: maintenanceNoticeController,
                    decoration: const InputDecoration(
                      labelText: 'Maintenance notice',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.api.updateRolloutSettings({
        'registrationMode': registrationMode,
        'betaModeEnabled': betaModeEnabled,
        'defaultTrialDays': int.tryParse(trialDaysController.text.trim()) ?? 14,
        'supportEmail': supportEmailController.text.trim().isEmpty
            ? null
            : supportEmailController.text.trim(),
        'supportPhone': supportPhoneController.text.trim().isEmpty
            ? null
            : supportPhoneController.text.trim(),
        'maintenanceMode': maintenanceMode,
        'maintenanceNotice': maintenanceNoticeController.text.trim().isEmpty
            ? null
            : maintenanceNoticeController.text.trim(),
      });
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
      PlatformPermission.betaManage,
    );
    return AsyncStateView<Map<String, dynamic>>(
      key: _reloadKey,
      future: () async =>
          (await widget.controller.api.rollout())['settings']
              as Map<String, dynamic>? ??
          const {},
      builder: (context, settings) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Rollout / System settings',
                          style: PlatformTypography.cardTitle,
                        ),
                      ),
                      if (canManage)
                        FilledButton(
                          onPressed: () => _edit(settings),
                          child: const Text('Edit'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _row(
                    'Registration mode',
                    '${settings['registrationMode'] ?? '-'}',
                  ),
                  _row(
                    'Beta mode enabled',
                    '${settings['betaModeEnabled'] ?? '-'}',
                  ),
                  _row(
                    'Default trial days',
                    '${settings['defaultTrialDays'] ?? '-'}',
                  ),
                  _row('Support email', '${settings['supportEmail'] ?? '-'}'),
                  _row('Support phone', '${settings['supportPhone'] ?? '-'}'),
                  _row(
                    'Maintenance mode',
                    '${settings['maintenanceMode'] ?? '-'}',
                  ),
                  _row(
                    'Maintenance notice',
                    '${settings['maintenanceNotice'] ?? '-'}',
                  ),
                  _row(
                    'Release channel',
                    '${settings['releaseChannel'] ?? '-'}',
                  ),
                  _row('Web version', '${settings['webVersion'] ?? '-'}'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: PlatformTypography.label),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

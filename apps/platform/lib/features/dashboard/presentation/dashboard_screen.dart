import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.controller});

  final SessionController controller;

  Future<Map<String, dynamic>> _load() async {
    final dashboard = await controller.api.dashboard();
    Map<String, dynamic> health = const {};
    if (controller.hasPermission(PlatformPermission.systemErrorsView)) {
      health = await controller.api.systemHealth();
    }
    return {'dashboard': dashboard, 'health': health};
  }

  @override
  Widget build(BuildContext context) {
    return AsyncStateView<Map<String, dynamic>>(
      future: _load,
      builder: (context, data) {
        final d = data['dashboard'] as Map<String, dynamic>;
        final health = data['health'] as Map<String, dynamic>;
        final smsQueue = health['smsQueue'] as Map<String, dynamic>?;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _StatCard(label: 'Total Organizations', value: d['totalTenants']),
              _StatCard(
                label: 'Active Organizations',
                value: d['activeTenants'],
              ),
              _StatCard(label: 'Trial Organizations', value: d['trialTenants']),
              _StatCard(
                label: 'Suspended Organizations',
                value: d['suspendedTenants'],
              ),
              _StatCard(
                label: 'Subscriptions Ending Soon',
                value: d['subscriptionsExpiringSoon'],
              ),
              _StatCard(label: 'Active Events', value: d['totalEvents']),
              _StatCard(
                label: 'Open Support Requests',
                value: d['openSupportRequests'],
              ),
              _StatCard(label: 'New Feedback', value: d['newFeedbackItems']),
              _StatCard(
                label: 'SMS Failed (backlog)',
                value: d['failedSmsBacklog'],
              ),
              if (smsQueue != null) ...[
                _StatCard(
                  label: 'SMS Queue Pending',
                  value: smsQueue['pending'],
                ),
                _StatCard(
                  label: 'SMS Sent Today',
                  value: smsQueue['sentToday'],
                ),
              ],
              _StatCard(
                label: 'Recent Errors (24h)',
                value: d['recentSystemErrors'],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: PlatformTypography.label),
              const SizedBox(height: 8),
              Text(
                '${value ?? '-'}',
                style: const TextStyle(
                  fontFamily: PlatformTypography.condensed,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

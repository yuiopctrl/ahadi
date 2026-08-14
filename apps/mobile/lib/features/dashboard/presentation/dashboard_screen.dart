import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> summaryFuture;

  @override
  void initState() {
    super.initState();
    summaryFuture = widget.controller.billingSummary();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.controller.selectedTenantContext;
    final events = tenant?.events ?? const [];
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => summaryFuture = widget.controller.billingSummary());
        await summaryFuture;
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Home',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            tenant?.tenantName ?? 'Ahadi',
            style: const TextStyle(color: AhadiColors.muted),
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: summaryFuture,
            builder: (context, snapshot) {
              final billing = snapshot.data ?? const <String, dynamic>{};
              final subscription =
                  billing['subscription'] is Map<String, dynamic>
                  ? billing['subscription'] as Map<String, dynamic>
                  : const <String, dynamic>{};
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatTile(
                    label: 'Events',
                    value: events.length.toString(),
                    icon: Icons.event_outlined,
                  ),
                  _StatTile(
                    label: 'Subscription',
                    value:
                        '${subscription['status'] ?? tenant?.subscription?.status ?? 'Active'}',
                    icon: Icons.workspace_premium_outlined,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Recent events',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No events are available for this organization yet.',
                ),
              ),
            )
          else
            ...events
                .take(5)
                .map(
                  (event) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.event_note_outlined),
                      title: Text(event.name),
                      subtitle: Text(event.status),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AhadiColors.primary),
              const SizedBox(height: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AhadiColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

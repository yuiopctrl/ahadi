import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../events/presentation/event_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;

  @override
  void initState() {
    super.initState();
    loadedEventId = widget.controller.selectedEventId;
    future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final event = widget.controller.selectedEvent;
    if (event == null) return const <String, dynamic>{};
    return widget.controller.eventFinancialSummary(event.id);
  }

  @override
  Widget build(BuildContext context) {
    final selectedEventId = widget.controller.selectedEventId;
    if (loadedEventId != selectedEventId) {
      loadedEventId = selectedEventId;
      future = _load();
    }
    final event = widget.controller.selectedEvent;
    final events =
        widget.controller.selectedTenantContext?.events ??
        const <EventSummary>[];
    return RefreshIndicator(
      onRefresh: () async {
        await widget.controller.refreshTenantContext();
        setState(() {
          loadedEventId = widget.controller.selectedEventId;
          future = _load();
        });
        await future;
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ErrorPanel(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => future = _load()),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: const [LoadingCards(count: 4)],
            );
          }
          final summary = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                event?.name ?? 'No event selected',
                style: const TextStyle(color: AhadiColors.muted),
              ),
              if (event == null) ...[
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Choose an event to view operational dashboard figures.',
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatTile(
                      label: 'Total Pledged',
                      value: moneyText(
                        summary['totalPledged'] ?? event.totalPledged,
                      ),
                      icon: Icons.volunteer_activism_outlined,
                    ),
                    _StatTile(
                      label: 'Received',
                      value: moneyText(
                        summary['totalAllocated'] ??
                            summary['totalAllocatedToPledges'] ??
                            event.totalCollected,
                      ),
                      icon: Icons.payments_outlined,
                    ),
                    _StatTile(
                      label: 'Outstanding',
                      value: moneyText(
                        summary['totalOutstanding'] ?? event.totalOutstanding,
                      ),
                      icon: Icons.pending_actions_outlined,
                    ),
                    _StatTile(
                      label: 'Members',
                      value:
                          '${numberFrom(summary['memberCount'] ?? event.memberCount)?.round() ?? '-'}',
                      icon: Icons.groups_outlined,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Events',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No events have been created yet.'),
                  ),
                )
              else
                ...events.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text(
                        row.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${row.status}\nPledged ${moneyText(row.totalPledged)} · Received ${moneyText(row.totalCollected)}',
                      ),
                      isThreeLine: true,
                      trailing: row.id == widget.controller.selectedEventId
                          ? const Icon(Icons.check, color: AhadiColors.success)
                          : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await widget.controller.selectEvent(row.id);
                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventDetailScreen(
                                controller: widget.controller,
                                event: row,
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
            ],
          );
        },
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
      width: 164,
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
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

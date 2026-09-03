import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../events/presentation/event_detail_screen.dart';
import '../../events/presentation/event_summary_card.dart';

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
                  message: friendlyErrorText(
                    snapshot.error,
                    context.t('dashboard.loadError'),
                  ),
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
                context.t('dashboard.title'),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                event?.name ?? context.t('common.noEventSelected'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              if (event == null) ...[
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.t('dashboard.chooseEventHint')),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _StatTile(
                      label: context.t('dashboard.totalPledged'),
                      value: moneyText(
                        summary['totalPledged'] ?? event.totalPledged,
                      ),
                      icon: Icons.volunteer_activism_outlined,
                    ),
                    _StatTile(
                      label: context.t('dashboard.received'),
                      value: moneyText(
                        summary['totalAllocated'] ??
                            summary['totalAllocatedToPledges'] ??
                            event.totalCollected,
                      ),
                      icon: Icons.payments_outlined,
                    ),
                    _StatTile(
                      label: context.t('dashboard.outstanding'),
                      value: moneyText(
                        summary['totalOutstanding'] ?? event.totalOutstanding,
                      ),
                      icon: Icons.pending_actions_outlined,
                    ),
                    _StatTile(
                      label: context.t('dashboard.members'),
                      value:
                          '${numberFrom(summary['memberCount'] ?? event.memberCount)?.round() ?? '-'}',
                      icon: Icons.groups_outlined,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Text(
                context.t('shell.nav.events'),
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.t('dashboard.noEventsYet')),
                  ),
                )
              else
                ...events.map(
                  (row) => EventSummaryCard(
                    event: row,
                    selected: row.id == widget.controller.selectedEventId,
                    onTap: () async {
                      await widget.controller.selectEvent(row.id);
                      if (context.mounted) {
                        final refreshed = await Navigator.of(context)
                            .push<EventSummary>(
                              MaterialPageRoute(
                                builder: (_) => EventDetailScreen(
                                  controller: widget.controller,
                                  event: row,
                                ),
                              ),
                            );
                        if (mounted && refreshed != null) {
                          setState(() {
                            loadedEventId = widget.controller.selectedEventId;
                            future = _load();
                          });
                        }
                      }
                    },
                    onSelect: () async {
                      await widget.controller.selectEvent(row.id);
                      setState(() {
                        loadedEventId = widget.controller.selectedEventId;
                        future = _load();
                      });
                    },
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

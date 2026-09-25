import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'invitations_screen.dart';

/// Event -> RSVP dashboard. Deliberately keeps "N attending invitations"
/// visually distinct from "N confirmed guests" (two separate cards/
/// sections) -- these are never the same number and must never look like
/// interchangeable stats.
class RsvpDashboardTab extends StatefulWidget {
  const RsvpDashboardTab({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<RsvpDashboardTab> createState() => _RsvpDashboardTabState();
}

class _RsvpDashboardTabState extends State<RsvpDashboardTab> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = widget.controller.eventRsvpDashboard(widget.event.id);
  }

  // Block body, not `() => future = ...` -- an assignment expression
  // evaluates to the assigned Future, which trips Flutter's "setState
  // callback returned a Future" guard.
  void _refresh() => setState(() {
    future = widget.controller.eventRsvpDashboard(widget.event.id);
  });

  void _openList(String rsvpStatus) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RsvpResponseListScreen(
          controller: widget.controller,
          event: widget.event,
          initialRsvpStatus: rsvpStatus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorPanel(
              message: friendlyErrorText(
                snapshot.error,
                context.t('rsvpDashboard.loadError'),
              ),
              onRetry: _refresh,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LoadingCards(count: 3),
          );
        }
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              AhadiInfoRow(
                label: context.t('rsvpDashboard.totalInvitations'),
                value: '${numberFrom(data['totalInvitations'])?.round() ?? 0}',
              ),
              AhadiInfoRow(
                label: context.t('rsvpDashboard.activeInvitations'),
                value: '${numberFrom(data['activeInvitations'])?.round() ?? 0}',
              ),
              const SizedBox(height: 12),
              AhadiSectionCard(
                title: context.t('rsvpDashboard.responses'),
                children: [
                  _ResponseRow(
                    label: context.t('invitations.rsvpFilter.attending'),
                    value: data['attendingInvitations'],
                    color: AhadiColors.success,
                    onTap: () => _openList('ATTENDING'),
                  ),
                  _ResponseRow(
                    label: context.t('invitations.rsvpFilter.maybe'),
                    value: data['maybeInvitations'],
                    color: AhadiColors.warning,
                    onTap: () => _openList('MAYBE'),
                  ),
                  _ResponseRow(
                    label: context.t('invitations.rsvpFilter.notAttending'),
                    value: data['notAttendingInvitations'],
                    color: AhadiColors.danger,
                    onTap: () => _openList('NOT_ATTENDING'),
                  ),
                  _ResponseRow(
                    label: context.t('invitations.rsvpFilter.noResponse'),
                    value: data['noResponseInvitations'],
                    color: AhadiColors.muted,
                    onTap: () => _openList('NO_RESPONSE'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AhadiSectionCard(
                title: context.t('rsvpDashboard.guestCount'),
                children: [
                  _ResponseRow(
                    label: context.t('rsvpDashboard.confirmedGuests'),
                    value: data['confirmedGuests'],
                    color: AhadiColors.success,
                    bold: true,
                  ),
                  _ResponseRow(
                    label: context.t('rsvpDashboard.possibleGuests'),
                    value: data['possibleGuests'],
                    color: AhadiColors.warning,
                    bold: true,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResponseRow extends StatelessWidget {
  const _ResponseRow({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
    this.bold = false,
  });

  final String label;
  final Object? value;
  final Color color;
  final VoidCallback? onTap;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${numberFrom(value)?.round() ?? 0}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: bold ? 18 : 16,
              color: color,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AhadiColors.muted, size: 18),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// Below the dashboard: filtered people lists for each RSVP bucket. Reuses
/// the same invitation-list endpoint and filters rather than a separate
/// data pipeline.
class RsvpResponseListScreen extends StatefulWidget {
  const RsvpResponseListScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.initialRsvpStatus,
  });

  final SessionController controller;
  final EventSummary event;
  final String initialRsvpStatus;

  @override
  State<RsvpResponseListScreen> createState() => _RsvpResponseListScreenState();
}

class _RsvpResponseListScreenState extends State<RsvpResponseListScreen> {
  static const pageSize = 20;
  late String rsvpStatus;
  int page = 0;
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    rsvpStatus = widget.initialRsvpStatus;
    future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.listEventInvitations(
      widget.event.id,
      rsvpStatus: rsvpStatus,
      limit: pageSize,
      offset: page * pageSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_rsvpLabelPublic(context, rsvpStatus))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 3),
            );
          }
          final rows = objectList(snapshot.data!['data']);
          final pagination = objectMap(snapshot.data!['pagination']);
          final totalRows =
              numberFrom(pagination['totalRows'])?.round() ?? rows.length;
          final totalPages = totalRows == 0
              ? 1
              : ((totalRows - 1) ~/ pageSize) + 1;
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.t('invitations.emptyFiltered')),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...rows.map((row) {
                final maxGuests = numberFrom(row['max_guests'])?.round() ?? 1;
                final attendingCount = numberFrom(row['attending_count'])
                    ?.round();
                return AhadiListRow(
                  title: stringFrom(row, 'display_name'),
                  subtitle: attendingCount != null
                      ? '${context.t('invitationDetail.attendingCount')}: $attendingCount'
                      : null,
                  meta:
                      '${context.t('invitationDetail.maxGuests')}: $maxGuests',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InvitationDetailScreen(
                        controller: widget.controller,
                        event: widget.event,
                        invitationId: stringFrom(row, 'invitation_id'),
                      ),
                    ),
                  ),
                );
              }),
              InvitationsPaginationControls(
                page: page,
                totalPages: totalPages,
                totalRows: totalRows,
                onPrevious: page == 0
                    ? null
                    : () => setState(() {
                        page -= 1;
                        future = _load();
                      }),
                onNext: page >= totalPages - 1
                    ? null
                    : () => setState(() {
                        page += 1;
                        future = _load();
                      }),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _rsvpLabelPublic(BuildContext context, String status) {
  switch (status) {
    case 'ATTENDING':
      return context.t('invitations.rsvpFilter.attending');
    case 'MAYBE':
      return context.t('invitations.rsvpFilter.maybe');
    case 'NOT_ATTENDING':
      return context.t('invitations.rsvpFilter.notAttending');
    default:
      return context.t('invitations.rsvpFilter.noResponse');
  }
}

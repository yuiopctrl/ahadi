import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/api_failure.dart';
import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'invitation_card_renderer.dart';

// Reused as-is from the payment-receipt PNG share flow
// (financial_screens.dart) -- this is the "existing project share
// mechanism" RSVP-3A says to reuse rather than adding a new dependency: a
// native MethodChannel backed by a real OS share sheet (Intent.ACTION_SEND
// on Android, UIActivityViewController on iOS), not a clipboard copy.
const _cardShareChannel = MethodChannel('work.yuiop.ahadi/share');

// Deliberately does NOT check `isOwner` as a bypass. `isOwner` is a
// denormalized restatement of "this user's assigned role is TENANT_OWNER"
// (set server-side as `is_owner = (role_code = 'TENANT_OWNER')`), not an
// independent authorization concept -- so treating it as a shortcut here
// would be the same "hard-code TENANT_OWNER as an authorization shortcut"
// anti-pattern Changisha's effective-permissions model exists to avoid.
// `permissions` (the tenant context's effective permission list) already
// includes every invitation.*/rsvp.* permission a TENANT_OWNER's role
// currently grants, so this is behavior-identical today and additionally
// correct if a permission is ever narrowed or overridden for a specific
// user in the future.
bool _hasPermission(SessionController controller, String permission) =>
    controller.selectedTenantContext?.permissions.contains(permission) == true;

String _rsvpLabel(BuildContext context, String? response) {
  switch (response) {
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

const _statusFilterOptions = <(String, String)>[
  ('ALL', 'invitations.status.all'),
  ('DRAFT', 'invitations.status.draft'),
  ('ACTIVE', 'invitations.status.active'),
  ('CANCELLED', 'invitations.status.cancelled'),
];

const _rsvpFilterOptions = <(String, String)>[
  ('ALL', 'invitations.rsvpFilter.all'),
  ('ATTENDING', 'invitations.rsvpFilter.attending'),
  ('MAYBE', 'invitations.rsvpFilter.maybe'),
  ('NOT_ATTENDING', 'invitations.rsvpFilter.notAttending'),
  ('NO_RESPONSE', 'invitations.rsvpFilter.noResponse'),
];

class _ChipFilter extends StatelessWidget {
  const _ChipFilter({
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final String label;
  final void Function(String value) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.firstWhere(
      (option) => option.$1 == value,
      orElse: () => options.first,
    );
    final active = value != 'ALL';
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => options
          .map(
            (option) => PopupMenuItem(
              value: option.$1,
              child: Text(context.t(option.$2)),
            ),
          )
          .toList(),
      child: Chip(
        label: Text('$label: ${context.t(current.$2)}'),
        backgroundColor: active ? AhadiColors.primarySoft : null,
        labelStyle: TextStyle(
          color: active ? AhadiColors.primary : null,
          fontWeight: active ? FontWeight.w700 : null,
        ),
      ),
    );
  }
}

/// Event -> Invitations tab. Self-sufficient: owns its own search/filter/
/// pagination state and calls the server-side list endpoint directly,
/// mirroring `_MembersTab` in event_detail_screen.dart.
class InvitationsTab extends StatefulWidget {
  const InvitationsTab({
    super.key,
    required this.controller,
    required this.event,
    required this.onChanged,
  });

  final SessionController controller;
  final EventSummary event;
  final VoidCallback onChanged;

  @override
  State<InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends State<InvitationsTab> {
  static const pageSize = 20;

  String query = '';
  String statusFilter = 'ALL';
  String rsvpFilter = 'ALL';
  int page = 0;
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  Future<Map<String, dynamic>>? dashboardFuture;

  @override
  void initState() {
    super.initState();
    future = _load();
    dashboardFuture = widget.controller.eventRsvpDashboard(widget.event.id);
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.listEventInvitations(
      widget.event.id,
      search: query,
      status: statusFilter,
      rsvpStatus: rsvpFilter,
      limit: pageSize,
      offset: page * pageSize,
    );
  }

  void _refresh() {
    setState(() {
      future = _load();
      dashboardFuture = widget.controller.eventRsvpDashboard(widget.event.id);
    });
  }

  void _onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        query = value;
        page = 0;
        future = _load();
      });
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BulkCreateInvitationsScreen(
          controller: widget.controller,
          event: widget.event,
        ),
      ),
    );
    if (created == true && mounted) {
      _refresh();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _hasPermission(widget.controller, 'invitation.create');
    final canEditSettings = _hasPermission(
      widget.controller,
      'invitation.edit',
    );
    final filtersActive = statusFilter != 'ALL' || rsvpFilter != 'ALL';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t('invitations.title'),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        // Wrap, not Row: on a narrow phone width the settings icon plus the
        // "Create Invitations" label button don't both fit on one line --
        // Wrap moves the overflow to a second line instead of clipping it.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (canEditSettings)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InvitationSettingsScreen(
                      controller: widget.controller,
                      event: widget.event,
                    ),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined),
                label: Text(context.t('invitationSettings.title')),
              ),
            if (canCreate)
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.mail_outline),
                label: Text(context.t('invitations.createInvitations')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(
          future: dashboardFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox();
            return _InvitationsSummaryStrip(dashboard: snapshot.data!);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            labelText: context.t('invitations.searchHint'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: _onSearch,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipFilter(
              value: statusFilter,
              options: _statusFilterOptions,
              label: context.t('invitations.status.label'),
              onChanged: (value) => setState(() {
                statusFilter = value;
                page = 0;
                future = _load();
              }),
            ),
            _ChipFilter(
              value: rsvpFilter,
              options: _rsvpFilterOptions,
              label: context.t('invitations.rsvpFilter.label'),
              onChanged: (value) => setState(() {
                rsvpFilter = value;
                page = 0;
                future = _load();
              }),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              if (snapshot.error is ApiFailure &&
                  (snapshot.error as ApiFailure).isSessionExpired) {
                return const SizedBox();
              }
              return ErrorPanel(
                message: friendlyErrorText(
                  snapshot.error,
                  context.t('invitations.loadError'),
                ),
                onRetry: _refresh,
              );
            }
            if (!snapshot.hasData) return const LoadingCards(count: 3);
            final response = snapshot.data!;
            final rows = objectList(response['data']);
            final pagination = objectMap(response['pagination']);
            final totalRows =
                numberFrom(pagination['totalRows'])?.round() ?? rows.length;
            final totalPages = totalRows == 0
                ? 1
                : ((totalRows - 1) ~/ pageSize) + 1;
            if (rows.isEmpty) {
              final hasNoInvitationsAtAll =
                  query.isEmpty && !filtersActive && totalRows == 0;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        hasNoInvitationsAtAll
                            ? context.t('invitations.emptyState')
                            : context.t('invitations.emptyFiltered'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AhadiColors.muted),
                      ),
                      if (hasNoInvitationsAtAll && canCreate) ...[
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _openCreate,
                          icon: const Icon(Icons.mail_outline),
                          label: Text(
                            context.t('invitations.createInvitations'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows.map(
                  (row) => _InvitationListRow(
                    row: row,
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => InvitationDetailScreen(
                              controller: widget.controller,
                              event: widget.event,
                              invitationId: stringFrom(row, 'invitation_id'),
                            ),
                          ),
                        )
                        .then((_) {
                          _refresh();
                          widget.onChanged();
                        }),
                  ),
                ),
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
      ],
    );
  }
}

class _InvitationsSummaryStrip extends StatelessWidget {
  const _InvitationsSummaryStrip({required this.dashboard});

  final Map<String, dynamic> dashboard;

  @override
  Widget build(BuildContext context) {
    final items = <(String, Object?, Color)>[
      (
        context.t('invitations.total'),
        dashboard['totalInvitations'],
        AhadiColors.text,
      ),
      (
        context.t('invitations.draft'),
        dashboard['draftInvitations'],
        AhadiColors.warning,
      ),
      (
        context.t('invitations.active'),
        dashboard['activeInvitations'],
        AhadiColors.success,
      ),
      (
        context.t('invitations.cancelled'),
        dashboard['cancelledInvitations'],
        AhadiColors.danger,
      ),
      (
        context.t('invitations.noResponse'),
        dashboard['noResponseInvitations'],
        AhadiColors.muted,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AhadiColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AhadiColors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            color: AhadiColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${numberFrom(item.$2)?.round() ?? 0}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: item.$3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _InvitationListRow extends StatelessWidget {
  const _InvitationListRow({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final maxGuests = numberFrom(row['max_guests'])?.round() ?? 1;
    final attendingCount = numberFrom(row['attending_count'])?.round();
    final rsvpStatus = stringFrom(row, 'rsvp_status', 'NO_RESPONSE');
    final phone = stringFrom(row, 'phone');
    return AhadiListRow(
      title: titleCaseName(row['member_name']),
      subtitle: [
        stringFrom(row, 'display_name'),
        if (phone.isNotEmpty) phone,
      ].where((value) => value.isNotEmpty).join('\n'),
      status: stringFrom(row, 'status', 'DRAFT'),
      meta: attendingCount != null
          ? context
                .t('invitations.rsvpSummary')
                .replaceFirst(
                  '{response}',
                  _rsvpLabel(context, row['rsvp_response'] as String?),
                )
                .replaceFirst('{count}', '$attendingCount')
                .replaceFirst('{max}', '$maxGuests')
          : '${context.t('invitations.rsvpFilter.label')}: ${_rsvpLabel(context, rsvpStatus == 'NO_RESPONSE' ? null : rsvpStatus)}',
      onTap: onTap,
    );
  }
}

class InvitationsPaginationControls extends StatelessWidget {
  const InvitationsPaginationControls({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalRows,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalRows;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${context.t('common.page')} ${page + 1} ${context.t('common.of')} $totalPages · $totalRows',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

Future<Set<String>> _fetchAllInvitedEventMemberIds(
  SessionController controller,
  String eventId,
) async {
  final ids = <String>{};
  var offset = 0;
  const limit = 100;
  while (offset <= 2000) {
    final response = await controller.listEventInvitations(
      eventId,
      limit: limit,
      offset: offset,
    );
    final rows = objectList(response['data']);
    for (final row in rows) {
      final id = stringFrom(row, 'event_member_id');
      if (id.isNotEmpty) ids.add(id);
    }
    final pagination = objectMap(response['pagination']);
    if (pagination['hasMore'] != true || rows.isEmpty) break;
    offset += limit;
  }
  return ids;
}

/// Event -> Invitations -> Create Invitations. Three steps: select event
/// members (already-invited ones shown but not selectable), invitation
/// defaults (naming/max guests/template), confirmation -- one transactional
/// bulk-create call, never a per-member HTTP loop.
class BulkCreateInvitationsScreen extends StatefulWidget {
  const BulkCreateInvitationsScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<BulkCreateInvitationsScreen> createState() =>
      _BulkCreateInvitationsScreenState();
}

class _BulkCreateInvitationsScreenState
    extends State<BulkCreateInvitationsScreen> {
  int step = 0;
  late Future<(List<Map<String, dynamic>> members, Set<String> invitedIds)>
  future;
  String query = '';
  final Set<String> selected = {};

  bool useFamily = false;
  final maxGuests = TextEditingController(text: '1');
  String? templateId;
  List<Map<String, dynamic>> templates = [];

  bool submitting = false;
  String? error;
  Map<String, dynamic>? result;

  @override
  void initState() {
    super.initState();
    future = _load();
    widget.controller.invitationTemplates().then((rows) {
      if (!mounted) return;
      setState(() => templates = rows);
    });
  }

  @override
  void dispose() {
    maxGuests.dispose();
    super.dispose();
  }

  Future<(List<Map<String, dynamic>>, Set<String>)> _load() async {
    final results = await Future.wait([
      widget.controller.eventMembers(widget.event.id),
      _fetchAllInvitedEventMemberIds(widget.controller, widget.event.id),
    ]);
    return (
      results[0] as List<Map<String, dynamic>>,
      results[1] as Set<String>,
    );
  }

  Future<void> _submit() async {
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final response = await widget.controller.bulkCreateEventInvitations(
        widget.event.id,
        {
          'eventMemberIds': selected.toList(),
          'defaultMaxGuests': int.tryParse(maxGuests.text.trim()) ?? 1,
          if (templateId != null) 'templateId': templateId,
          if (useFamily) 'displayNameSuffix': '& Family',
        },
      );
      if (!mounted) return;
      setState(() => result = response);
    } catch (err) {
      setState(() => error = friendlyErrorText(err));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('bulkCreate.title'))),
      body: result != null
          ? _BulkCreateResult(result: result!)
          : FutureBuilder<(List<Map<String, dynamic>>, Set<String>)>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ErrorPanel(
                    message: friendlyErrorText(snapshot.error),
                    onRetry: () => setState(() {
                      future = _load();
                    }),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: LoadingCards(count: 4),
                  );
                }
                final members = snapshot.data!.$1;
                final invitedIds = snapshot.data!.$2;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _StepIndicator(step: step),
                    ),
                    Expanded(
                      child: step == 0
                          ? _StepSelectMembers(
                              members: members,
                              invitedIds: invitedIds,
                              selected: selected,
                              query: query,
                              onQueryChanged: (value) =>
                                  setState(() => query = value),
                              onToggle: (id) => setState(() {
                                if (selected.contains(id)) {
                                  selected.remove(id);
                                } else {
                                  selected.add(id);
                                }
                              }),
                              onSelectAllEligible: () => setState(() {
                                selected.addAll(
                                  members
                                      .map(
                                        (m) => stringFrom(m, 'event_member_id'),
                                      )
                                      .where((id) => !invitedIds.contains(id)),
                                );
                              }),
                            )
                          : step == 1
                          ? SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _StepDefaults(
                                useFamily: useFamily,
                                onNamingChanged: (value) =>
                                    setState(() => useFamily = value),
                                maxGuests: maxGuests,
                                templates: templates,
                                templateId: templateId,
                                onTemplateChanged: (value) =>
                                    setState(() => templateId = value),
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: _StepConfirm(
                                selectedCount: selected.length,
                                alreadyInvitedCount: invitedIds.length,
                                error: error,
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (step > 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: submitting
                                    ? null
                                    : () => setState(() => step -= 1),
                                child: Text(context.t('bulkCreate.back')),
                              ),
                            ),
                          if (step > 0) const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: submitting
                                  ? null
                                  : () {
                                      if (step == 0) {
                                        if (selected.isEmpty) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    context.t(
                                                      'bulkCreate.selectMembersFirst',
                                                    ),
                                                  ),
                                                ),
                                              );
                                          return;
                                        }
                                        setState(() => step = 1);
                                      } else if (step == 1) {
                                        setState(() => step = 2);
                                      } else {
                                        _submit();
                                      }
                                    },
                              child: Text(
                                submitting
                                    ? context.t('auth.saving')
                                    : step < 2
                                    ? context.t('bulkCreate.next')
                                    : context
                                          .t('bulkCreate.createCount')
                                          .replaceFirst(
                                            '{count}',
                                            '${selected.length}',
                                          ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.t('bulkCreate.step1Title'),
      context.t('bulkCreate.step2Title'),
      context.t('bulkCreate.step3Title'),
    ];
    return Row(
      children: List.generate(labels.length, (index) {
        final active = index == step;
        final done = index < step;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: active || done
                    ? AhadiColors.primary
                    : AhadiColors.border,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  labels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? AhadiColors.text : AhadiColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _StepSelectMembers extends StatelessWidget {
  const _StepSelectMembers({
    required this.members,
    required this.invitedIds,
    required this.selected,
    required this.query,
    required this.onQueryChanged,
    required this.onToggle,
    required this.onSelectAllEligible,
  });

  final List<Map<String, dynamic>> members;
  final Set<String> invitedIds;
  final Set<String> selected;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final void Function(String id) onToggle;
  final VoidCallback onSelectAllEligible;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final visible = members.where((member) {
      if (needle.isEmpty) return true;
      final haystack =
          '${member['full_name'] ?? ''} ${member['phone_e164'] ?? ''}'
              .toLowerCase();
      return haystack.contains(needle);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              labelText: context.t('bulkCreate.searchMembers'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: onQueryChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: onSelectAllEligible,
            icon: const Icon(Icons.done_all),
            label: Text(context.t('bulkCreate.selectAllEligible')),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text(context.t('bulkCreate.noEligibleMembers')))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final member = visible[index];
                    final id = stringFrom(member, 'event_member_id');
                    final alreadyInvited = invitedIds.contains(id);
                    if (alreadyInvited) {
                      return ListTile(
                        leading: const Icon(
                          Icons.remove,
                          color: AhadiColors.muted,
                        ),
                        title: Text(
                          titleCaseName(member['full_name']),
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                        subtitle: Text(
                          context.t('bulkCreate.alreadyInvited'),
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                      );
                    }
                    return CheckboxListTile(
                      value: selected.contains(id),
                      onChanged: (_) => onToggle(id),
                      title: Text(titleCaseName(member['full_name'])),
                      subtitle: Text(
                        stringFrom(
                          member,
                          'phone_e164',
                          context.t('contacts.noPhone'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _NamingChoiceTile extends StatelessWidget {
  const _NamingChoiceTile({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AhadiColors.primary : AhadiColors.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepDefaults extends StatelessWidget {
  const _StepDefaults({
    required this.useFamily,
    required this.onNamingChanged,
    required this.maxGuests,
    required this.templates,
    required this.templateId,
    required this.onTemplateChanged,
  });

  final bool useFamily;
  final ValueChanged<bool> onNamingChanged;
  final TextEditingController maxGuests;
  final List<Map<String, dynamic>> templates;
  final String? templateId;
  final ValueChanged<String?> onTemplateChanged;

  @override
  Widget build(BuildContext context) {
    return AhadiSectionCard(
      title: context.t('bulkCreate.namingLabel'),
      children: [
        _NamingChoiceTile(
          selected: !useFamily,
          label: context.t('bulkCreate.namingUseMemberName'),
          onTap: () => onNamingChanged(false),
        ),
        _NamingChoiceTile(
          selected: useFamily,
          label: context.t('bulkCreate.namingFamily'),
          onTap: () => onNamingChanged(true),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: maxGuests,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.t('bulkCreate.defaultMaxGuests'),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: templateId,
          decoration: InputDecoration(
            labelText: context.t('bulkCreate.template'),
          ),
          items: templates
              .map(
                (template) => DropdownMenuItem(
                  value: stringFrom(template, 'id'),
                  child: Text(
                    stringFrom(template, 'name'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onTemplateChanged,
        ),
      ],
    );
  }
}

class _StepConfirm extends StatelessWidget {
  const _StepConfirm({
    required this.selectedCount,
    required this.alreadyInvitedCount,
    required this.error,
  });

  final int selectedCount;
  final int alreadyInvitedCount;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return AhadiSectionCard(
      children: [
        AhadiInfoRow(
          label: context.t('bulkCreate.selectedMembers'),
          value: '$selectedCount',
        ),
        AhadiInfoRow(
          label: context.t('bulkCreate.alreadyInvitedCount'),
          value: '$alreadyInvitedCount',
        ),
        AhadiInfoRow(
          label: context.t('bulkCreate.willCreate'),
          value: '$selectedCount',
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: AhadiColors.danger)),
        ],
      ],
    );
  }
}

class _BulkCreateResult extends StatelessWidget {
  const _BulkCreateResult({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final created = numberFrom(result['created'])?.round() ?? 0;
    final alreadyExisted = numberFrom(result['alreadyExisted'])?.round() ?? 0;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AhadiSectionCard(
            title: context.t('bulkCreate.resultTitle'),
            children: [
              AhadiInfoRow(
                label: context.t('bulkCreate.resultCreated'),
                value: '$created',
              ),
              AhadiInfoRow(
                label: context.t('bulkCreate.resultAlreadyExisted'),
                value: '$alreadyExisted',
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('bulkCreate.done')),
          ),
        ],
      ),
    );
  }
}

/// From Event Member Detail: create a single invitation. Tenant/event/
/// member are already known -- the user is never asked to pick the member
/// again.
class SingleCreateInvitationScreen extends StatefulWidget {
  const SingleCreateInvitationScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.eventMemberId,
    required this.memberName,
  });

  final SessionController controller;
  final EventSummary event;
  final String eventMemberId;
  final String memberName;

  @override
  State<SingleCreateInvitationScreen> createState() =>
      _SingleCreateInvitationScreenState();
}

class _SingleCreateInvitationScreenState
    extends State<SingleCreateInvitationScreen> {
  late final displayName = TextEditingController(text: widget.memberName);
  final maxGuests = TextEditingController(text: '1');
  String? templateId;
  List<Map<String, dynamic>> templates = [];
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    widget.controller.invitationTemplates().then((rows) {
      if (!mounted) return;
      setState(() => templates = rows);
    });
  }

  @override
  void dispose() {
    displayName.dispose();
    maxGuests.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final detail = await widget.controller.createEventInvitation(
        widget.event.id,
        {
          'eventMemberId': widget.eventMemberId,
          'displayName': displayName.text.trim(),
          'maxGuests': int.tryParse(maxGuests.text.trim()) ?? 1,
          if (templateId != null) 'templateId': templateId,
        },
      );
      if (mounted) Navigator.of(context).pop(detail);
    } catch (err) {
      setState(
        () =>
            error = err is ApiFailure && err.code == 'INVITATION_ALREADY_EXISTS'
            ? context.t('bulkCreate.alreadyInvited')
            : friendlyErrorText(err),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('createInvitation.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: displayName,
            decoration: InputDecoration(
              labelText: context.t('createInvitation.displayName'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: maxGuests,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.t('createInvitation.maxGuests'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: templateId,
            decoration: InputDecoration(
              labelText: context.t('createInvitation.template'),
            ),
            items: templates
                .map(
                  (template) => DropdownMenuItem(
                    value: stringFrom(template, 'id'),
                    child: Text(stringFrom(template, 'name')),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => templateId = value),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : _submit,
            child: Text(
              saving
                  ? context.t('auth.saving')
                  : context.t('createInvitation.create'),
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(BuildContext context, String status) {
  switch (status) {
    case 'DRAFT':
      return context.t('invitations.status.draft');
    case 'ACTIVE':
      return context.t('invitations.status.active');
    case 'CANCELLED':
      return context.t('invitations.status.cancelled');
    default:
      return status;
  }
}

/// Authenticated organizer's invitation detail screen.
class InvitationDetailScreen extends StatefulWidget {
  const InvitationDetailScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.invitationId,
  });

  final SessionController controller;
  final EventSummary event;
  final String invitationId;

  @override
  State<InvitationDetailScreen> createState() => _InvitationDetailScreenState();
}

class _InvitationDetailScreenState extends State<InvitationDetailScreen> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.eventInvitationDetail(
      widget.event.id,
      widget.invitationId,
    );
  }

  // Block body, not `() => future = _load()` -- an assignment expression
  // evaluates to the assigned Future, which trips Flutter's "setState
  // callback returned a Future" guard.
  void _refresh() => setState(() {
    future = _load();
  });

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('invitationDetail.linkCopied'))),
    );
  }

  // Copies the full bilingual invitation message (event details + link) to
  // the clipboard so the organizer can paste it into WhatsApp/SMS/etc.
  // themselves. This does NOT open a native OS share sheet -- no
  // share_plus/url_launcher dependency exists in this project, and the
  // task explicitly says not to add one solely for this. The label/icon
  // must say "copy", not "share", so the UI never implies a share sheet
  // opened when it didn't.
  Future<void> _copyInvitationText(
    Map<String, dynamic> detail,
    String url,
  ) async {
    final text = _shareText(context, widget.event, detail, url);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('invitationDetail.copyInvitationText'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(text),
            const SizedBox(height: 12),
            Text(
              context.t('invitationDetail.linkCopied'),
              style: const TextStyle(color: AhadiColors.muted),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: Text(context.t('common.cancel')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('activateInvitation.confirmTitle')),
        content: Text(context.t('activateInvitation.confirmBody')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('invitationDetail.activate')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.activateEventInvitation(
        widget.event.id,
        widget.invitationId,
      );
      _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorText(err))));
    }
  }

  Future<void> _rotateLink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('invitationDetail.rotateLinkConfirmTitle')),
        content: Text(context.t('invitationDetail.rotateLinkConfirmBody')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('invitationDetail.rotateLink')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.rotateInvitationLink(
        widget.event.id,
        widget.invitationId,
      );
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('invitationDetail.rotateLink'))),
      );
      // The QR baked into any card the organizer already downloaded/shared
      // still points at the invalidated link -- rotating the token cannot
      // reach into someone's camera roll and fix that, so the UI must say
      // so explicitly instead of silently implying every existing card is
      // still fine.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t('invitationDetail.rotateLinkCardWarning')),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorText(err))));
    }
  }

  Future<void> _cancelInvitation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t('invitationDetail.cancelConfirmTitle')),
        content: Text(context.t('invitationDetail.cancelConfirmBody')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('invitationDetail.cancelInvitation')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.cancelEventInvitation(
        widget.event.id,
        widget.invitationId,
      );
      _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorText(err))));
    }
  }

  Future<void> _edit(Map<String, dynamic> detail) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditInvitationScreen(
          controller: widget.controller,
          event: widget.event,
          invitation: detail,
        ),
      ),
    );
    if (updated == true) _refresh();
  }

  Future<void> _recordRsvp(Map<String, dynamic> detail) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ManualRsvpForm(
          controller: widget.controller,
          event: widget.event,
          invitation: detail,
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _previewCard() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvitationCardPreviewScreen(
          controller: widget.controller,
          event: widget.event,
          invitationId: widget.invitationId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('invitationDetail.title'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(
                message: friendlyErrorText(
                  snapshot.error,
                  context.t('invitationDetail.loadError'),
                ),
                onRetry: _refresh,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 4),
            );
          }
          final detail = snapshot.data!;
          final status = stringFrom(detail, 'status', 'DRAFT');
          final rsvp = detail['rsvp'] is Map<String, dynamic>
              ? detail['rsvp'] as Map<String, dynamic>
              : null;
          final template = detail['template'] is Map<String, dynamic>
              ? detail['template'] as Map<String, dynamic>
              : null;
          final shareUrl = stringFrom(detail, 'shareUrl');
          final maxGuests = numberFrom(detail['maxGuests'])?.round() ?? 1;
          // invitation.view -> preview card; never a role-name/isOwner
          // shortcut (see _hasPermission above).
          final canView = _hasPermission(widget.controller, 'invitation.view');
          final canEdit = _hasPermission(widget.controller, 'invitation.edit');
          final canCancel = _hasPermission(
            widget.controller,
            'invitation.cancel',
          );
          final canManageRsvp = _hasPermission(
            widget.controller,
            'rsvp.manage',
          );
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (canView) ...[
                  OutlinedButton.icon(
                    onPressed: _previewCard,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(context.t('invitationDetail.previewCard')),
                  ),
                  const SizedBox(height: 12),
                ],
                AhadiSectionCard(
                  title: context.t('invitationDetail.guest'),
                  children: [
                    Text(
                      titleCaseName(detail['memberName']),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      stringFrom(
                        detail,
                        'phone',
                        context.t('contacts.noPhone'),
                      ),
                      style: const TextStyle(color: AhadiColors.muted),
                    ),
                  ],
                ),
                AhadiSectionCard(
                  title: context.t('invitationDetail.invitation'),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stringFrom(detail, 'displayName'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        StatusPill(status: _statusLabel(context, status)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AhadiInfoRow(
                      label: context.t('invitationDetail.maxGuests'),
                      value: '$maxGuests',
                    ),
                    AhadiInfoRow(
                      label: context.t('invitationDetail.template'),
                      value: template == null
                          ? context.t('invitationDetail.noTemplate')
                          : stringFrom(template, 'name'),
                    ),
                    AhadiInfoRow(
                      label: context.t('invitationDetail.created'),
                      value: dateText(stringFrom(detail, 'createdAt')),
                    ),
                    AhadiInfoRow(
                      label: context.t('invitationDetail.updated'),
                      value: dateText(stringFrom(detail, 'updatedAt')),
                    ),
                  ],
                ),
                AhadiSectionCard(
                  title: context.t('invitationDetail.rsvp'),
                  children: rsvp == null
                      ? [
                          Text(
                            context.t('invitationDetail.noRsvpYet'),
                            style: const TextStyle(color: AhadiColors.muted),
                          ),
                        ]
                      : [
                          AhadiInfoRow(
                            label: context.t('invitationDetail.response'),
                            value: _rsvpLabel(
                              context,
                              rsvp['response'] as String?,
                            ),
                          ),
                          AhadiInfoRow(
                            label: context.t('invitationDetail.attendingCount'),
                            value:
                                '${numberFrom(rsvp['attendingCount'])?.round() ?? 0}',
                          ),
                          if (objectList(rsvp['guestNames']).isNotEmpty ||
                              (rsvp['guestNames'] is List &&
                                  (rsvp['guestNames'] as List).isNotEmpty))
                            AhadiInfoRow(
                              label: context.t('invitationDetail.guestNames'),
                              value: (rsvp['guestNames'] as List)
                                  .map((name) => name.toString())
                                  .join(', '),
                            ),
                          if (stringFrom(rsvp, 'note').isNotEmpty)
                            AhadiInfoRow(
                              label: context.t('invitationDetail.note'),
                              value: stringFrom(rsvp, 'note'),
                            ),
                          AhadiInfoRow(
                            label: context.t('invitationDetail.respondedAt'),
                            value: dateText(stringFrom(rsvp, 'respondedAt')),
                          ),
                          AhadiInfoRow(
                            label: context.t('invitationDetail.responseSource'),
                            value: rsvp['submittedByType'] == 'PUBLIC_GUEST'
                                ? context.t(
                                    'invitationDetail.responseSource.publicGuest',
                                  )
                                : context.t(
                                    'invitationDetail.responseSource.tenantUser',
                                  ),
                          ),
                        ],
                ),
                if (status != 'DRAFT')
                  AhadiSectionCard(
                    title: context.t('invitationDetail.publicLink'),
                    children: [
                      if (status == 'CANCELLED')
                        Text(
                          context.t('invitationDetail.cancelledNoticeBody'),
                          style: const TextStyle(color: AhadiColors.muted),
                        )
                      else if (shareUrl.isEmpty)
                        Text(
                          context.t('invitationDetail.noLinkYet'),
                          style: const TextStyle(color: AhadiColors.muted),
                        )
                      else ...[
                        SelectableText(
                          shareUrl,
                          style: const TextStyle(color: AhadiColors.primary),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _copyLink(shareUrl),
                              icon: const Icon(Icons.copy),
                              label: Text(
                                context.t('invitationDetail.copyLink'),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _copyInvitationText(detail, shareUrl),
                              icon: const Icon(Icons.content_copy_outlined),
                              label: Text(
                                context.t(
                                  'invitationDetail.copyInvitationText',
                                ),
                              ),
                            ),
                            if (canEdit)
                              OutlinedButton.icon(
                                onPressed: _rotateLink,
                                icon: const Icon(Icons.autorenew),
                                label: Text(
                                  context.t('invitationDetail.rotateLink'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (status == 'DRAFT' && canEdit)
                      OutlinedButton.icon(
                        onPressed: () => _edit(detail),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(context.t('invitationDetail.edit')),
                      ),
                    if (status == 'DRAFT' && canEdit)
                      FilledButton.icon(
                        onPressed: _activate,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(context.t('invitationDetail.activate')),
                      ),
                    if (status == 'ACTIVE' && canEdit)
                      OutlinedButton.icon(
                        onPressed: () => _edit(detail),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text(context.t('invitationDetail.edit')),
                      ),
                    if (status == 'ACTIVE' && canManageRsvp)
                      FilledButton.icon(
                        onPressed: () => _recordRsvp(detail),
                        icon: const Icon(Icons.how_to_reg_outlined),
                        label: Text(
                          rsvp == null
                              ? context.t('invitationDetail.recordRsvp')
                              : context.t('invitationDetail.editRsvp'),
                        ),
                      ),
                    if (status == 'ACTIVE' && canCancel)
                      OutlinedButton.icon(
                        onPressed: _cancelInvitation,
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: AhadiColors.danger,
                        ),
                        label: Text(
                          context.t('invitationDetail.cancelInvitation'),
                          style: const TextStyle(color: AhadiColors.danger),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _shareText(
  BuildContext context,
  EventSummary event,
  Map<String, dynamic> detail,
  String url,
) {
  final displayName = stringFrom(detail, 'displayName');
  final venue = event.venue ?? '';
  final date = dateText(event.eventDate);
  final buffer = StringBuffer()
    ..writeln('$displayName,')
    ..writeln()
    ..writeln('umealikwa kwenye ${event.name}.')
    ..writeln()
    ..writeln(date)
    ..writeln(venue)
    ..writeln()
    ..writeln('Thibitisha mahudhurio:')
    ..write(url);
  return buffer.toString();
}

/// Editable: display_name, max_guests, template. Backend remains
/// authoritative -- INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT is surfaced with
/// a friendly message rather than a raw code.
class EditInvitationScreen extends StatefulWidget {
  const EditInvitationScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.invitation,
  });

  final SessionController controller;
  final EventSummary event;
  final Map<String, dynamic> invitation;

  @override
  State<EditInvitationScreen> createState() => _EditInvitationScreenState();
}

class _EditInvitationScreenState extends State<EditInvitationScreen> {
  late final displayName = TextEditingController(
    text: stringFrom(widget.invitation, 'displayName'),
  );
  late final maxGuests = TextEditingController(
    text: '${numberFrom(widget.invitation['maxGuests'])?.round() ?? 1}',
  );
  String? templateId;
  List<Map<String, dynamic>> templates = [];
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    templateId = (widget.invitation['template'] as Map<String, dynamic>?)?['id']
        ?.toString();
    widget.controller.invitationTemplates().then((rows) {
      if (!mounted) return;
      setState(() => templates = rows);
    });
  }

  @override
  void dispose() {
    displayName.dispose();
    maxGuests.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.updateEventInvitation(
        widget.event.id,
        stringFrom(widget.invitation, 'id'),
        {
          'displayName': displayName.text.trim(),
          'maxGuests': int.tryParse(maxGuests.text.trim()) ?? 1,
          if (templateId != null) 'templateId': templateId,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(
        () => error =
            err is ApiFailure &&
                err.code == 'INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT'
            ? context.t('editInvitation.guestLimitBelowRsvp')
            : friendlyErrorText(err),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('editInvitation.title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: displayName,
            decoration: InputDecoration(
              labelText: context.t('createInvitation.displayName'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: maxGuests,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.t('createInvitation.maxGuests'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: templateId,
                  decoration: InputDecoration(
                    labelText: context.t('createInvitation.template'),
                  ),
                  items: templates
                      .map(
                        (template) => DropdownMenuItem(
                          value: stringFrom(template, 'id'),
                          child: Text(stringFrom(template, 'name')),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => templateId = value),
                ),
              ),
              IconButton(
                tooltip: context.t('cardPreview.browseTemplates'),
                icon: const Icon(Icons.grid_view_outlined),
                onPressed: () async {
                  final selected = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => TemplateGalleryScreen(
                        controller: widget.controller,
                        sampleData: sampleInvitationCardData(
                          context,
                          event: widget.event,
                          guestDisplayName: displayName.text.trim().isEmpty
                              ? stringFrom(widget.invitation, 'displayName')
                              : displayName.text.trim(),
                        ),
                        selectedTemplateId: templateId,
                      ),
                    ),
                  );
                  if (selected != null) setState(() => templateId = selected);
                },
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(
              saving ? context.t('auth.saving') : context.t('common.save'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Organizer manual RSVP form -- shown as a bottom sheet from both
/// Invitation Detail and Event Member Detail. Client-side validation is
/// defensive only; the backend transaction is authoritative.
class ManualRsvpForm extends StatefulWidget {
  const ManualRsvpForm({
    super.key,
    required this.controller,
    required this.event,
    required this.invitation,
  });

  final SessionController controller;
  final EventSummary event;
  final Map<String, dynamic> invitation;

  @override
  State<ManualRsvpForm> createState() => _ManualRsvpFormState();
}

class _ManualRsvpFormState extends State<ManualRsvpForm> {
  late String response;
  late final guestCount = TextEditingController();
  final note = TextEditingController();
  final List<TextEditingController> guestNameControllers = [];
  bool saving = false;
  String? error;

  Map<String, dynamic>? get _rsvp =>
      widget.invitation['rsvp'] as Map<String, dynamic>?;

  int get maxGuests => numberFrom(widget.invitation['maxGuests'])?.round() ?? 1;

  @override
  void initState() {
    super.initState();
    final existing = _rsvp;
    response = existing?['response'] as String? ?? 'ATTENDING';
    guestCount.text =
        '${numberFrom(existing?['attendingCount'])?.round() ?? 1}';
    note.text = stringFrom(existing ?? {}, 'note');
    final existingNames = (existing?['guestNames'] as List?) ?? [];
    for (final name in existingNames) {
      guestNameControllers.add(TextEditingController(text: name.toString()));
    }
  }

  @override
  void dispose() {
    guestCount.dispose();
    note.dispose();
    for (final controller in guestNameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addGuestNameField() {
    setState(() => guestNameControllers.add(TextEditingController()));
  }

  Future<void> _save() async {
    final isNotAttending = response == 'NOT_ATTENDING';
    final count = isNotAttending
        ? 0
        : (int.tryParse(guestCount.text.trim()) ?? 0);
    if (!isNotAttending && (count < 1 || count > maxGuests)) {
      setState(() => error = context.t('manualRsvp.guestCountInvalid'));
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.recordManualRsvp(
        widget.event.id,
        stringFrom(widget.invitation, 'id'),
        {
          'response': response,
          'attendingCount': count,
          'guestNames': isNotAttending
              ? <String>[]
              : guestNameControllers
                    .map((c) => c.text.trim())
                    .where((name) => name.isNotEmpty)
                    .toList(),
          'note': note.text.trim().isEmpty ? null : note.text.trim(),
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => error = friendlyErrorText(err));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNotAttending = response == 'NOT_ATTENDING';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t('manualRsvp.title'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.t('manualRsvp.attending')),
                selected: response == 'ATTENDING',
                onSelected: (_) => setState(() => response = 'ATTENDING'),
              ),
              ChoiceChip(
                label: Text(context.t('manualRsvp.maybe')),
                selected: response == 'MAYBE',
                onSelected: (_) => setState(() => response = 'MAYBE'),
              ),
              ChoiceChip(
                label: Text(context.t('manualRsvp.notAttending')),
                selected: response == 'NOT_ATTENDING',
                onSelected: (_) => setState(() => response = 'NOT_ATTENDING'),
              ),
            ],
          ),
          if (!isNotAttending) ...[
            const SizedBox(height: 12),
            TextField(
              controller: guestCount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '${context.t('manualRsvp.guests')} (1-$maxGuests)',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.t('manualRsvp.guestNames'),
              style: const TextStyle(color: AhadiColors.muted),
            ),
            const SizedBox(height: 6),
            ...guestNameControllers.map(
              (controller) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(controller: controller),
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addGuestNameField,
              icon: const Icon(Icons.add),
              label: Text(context.t('manualRsvp.addGuestName')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              decoration: InputDecoration(
                labelText: context.t('manualRsvp.note'),
              ),
              maxLines: 2,
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(
              saving ? context.t('auth.saving') : context.t('manualRsvp.save'),
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).viewInsets.bottom > 0 ? 12 : 0,
          ),
        ],
      ),
    );
  }
}

/// Event -> Invitations -> Settings.
class InvitationSettingsScreen extends StatefulWidget {
  const InvitationSettingsScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<InvitationSettingsScreen> createState() =>
      _InvitationSettingsScreenState();
}

class _InvitationSettingsScreenState extends State<InvitationSettingsScreen> {
  late Future<Map<String, dynamic>> future;
  final hostDisplayName = TextEditingController();
  final invitationTitle = TextEditingController();
  final invitationMessage = TextEditingController();
  final venueOverride = TextEditingController();
  final addressOverride = TextEditingController();
  final mapsUrl = TextEditingController();
  final eventTimeDisplay = TextEditingController();
  final defaultMaxGuests = TextEditingController(text: '1');
  bool rsvpEnabled = true;
  bool allowLateRsvp = false;
  DateTime? rsvpDeadline;
  String? templateId;
  List<Map<String, dynamic>> templates = [];
  bool saving = false;
  bool loaded = false;
  String? error;

  @override
  void initState() {
    super.initState();
    future = _load();
    widget.controller.invitationTemplates().then((rows) {
      if (!mounted) return;
      setState(() => templates = rows);
    });
  }

  @override
  void dispose() {
    hostDisplayName.dispose();
    invitationTitle.dispose();
    invitationMessage.dispose();
    venueOverride.dispose();
    addressOverride.dispose();
    mapsUrl.dispose();
    eventTimeDisplay.dispose();
    defaultMaxGuests.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() async {
    final response = await widget.controller.eventInvitationSettings(
      widget.event.id,
    );
    if (!loaded) {
      final settings = objectMap(response['settings']);
      hostDisplayName.text = stringFrom(settings, 'hostDisplayName');
      invitationTitle.text = stringFrom(settings, 'invitationTitle');
      invitationMessage.text = stringFrom(settings, 'invitationMessage');
      venueOverride.text = stringFrom(settings, 'venueNameOverride');
      addressOverride.text = stringFrom(settings, 'venueAddressOverride');
      mapsUrl.text = stringFrom(settings, 'mapsUrl');
      eventTimeDisplay.text = stringFrom(settings, 'eventTimeDisplay');
      rsvpEnabled = settings['rsvpEnabled'] != false;
      allowLateRsvp = settings['allowLateRsvp'] == true;
      defaultMaxGuests.text =
          '${numberFrom(settings['defaultMaxGuests'])?.round() ?? 1}';
      templateId = settings['templateId']?.toString();
      final deadlineText = stringFrom(settings, 'rsvpDeadline');
      rsvpDeadline = deadlineText.isEmpty
          ? null
          : DateTime.tryParse(deadlineText)?.toLocal();
      loaded = true;
    }
    return response;
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: rsvpDeadline ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(rsvpDeadline ?? now),
    );
    if (!mounted) return;
    setState(() {
      rsvpDeadline = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 23,
        time?.minute ?? 59,
      );
    });
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.upsertEventInvitationSettings(widget.event.id, {
        'hostDisplayName': hostDisplayName.text.trim().isEmpty
            ? null
            : hostDisplayName.text.trim(),
        'invitationTitle': invitationTitle.text.trim().isEmpty
            ? null
            : invitationTitle.text.trim(),
        'invitationMessage': invitationMessage.text.trim().isEmpty
            ? null
            : invitationMessage.text.trim(),
        'venueNameOverride': venueOverride.text.trim().isEmpty
            ? null
            : venueOverride.text.trim(),
        'venueAddressOverride': addressOverride.text.trim().isEmpty
            ? null
            : addressOverride.text.trim(),
        'mapsUrl': mapsUrl.text.trim().isEmpty ? null : mapsUrl.text.trim(),
        'eventTimeDisplay': eventTimeDisplay.text.trim().isEmpty
            ? null
            : eventTimeDisplay.text.trim(),
        'rsvpEnabled': rsvpEnabled,
        'rsvpDeadline': rsvpDeadline?.toUtc().toIso8601String(),
        'allowLateRsvp': allowLateRsvp,
        'defaultMaxGuests': int.tryParse(defaultMaxGuests.text.trim()) ?? 1,
        if (templateId != null) 'templateId': templateId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('invitationSettings.saved'))),
      );
    } catch (err) {
      setState(() => error = friendlyErrorText(err));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('invitationSettings.title'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 4),
            );
          }
          final event = objectMap(snapshot.data!['event']);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.t('invitationSettings.overrideHint'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 4),
              Text(
                '${stringFrom(event, 'name')} · ${dateText(stringFrom(event, 'eventDate'))} · ${stringFrom(event, 'venue')}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hostDisplayName,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.hostDisplayName'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: invitationTitle,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.invitationTitle'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: invitationMessage,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.invitationMessage'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: eventTimeDisplay,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.eventTimeDisplay'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: venueOverride,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.venueOverride'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressOverride,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.addressOverride'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: mapsUrl,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.mapsUrl'),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: rsvpEnabled,
                onChanged: (value) => setState(() => rsvpEnabled = value),
                title: Text(context.t('invitationSettings.rsvpEnabled')),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.t('invitationSettings.rsvpDeadline')),
                subtitle: Text(
                  rsvpDeadline == null
                      ? context.t('invitationSettings.deadlineHint')
                      : dateText(rsvpDeadline!.toIso8601String()),
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    if (rsvpDeadline != null)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: context.t('invitationSettings.clearDeadline'),
                        onPressed: () => setState(() => rsvpDeadline = null),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today_outlined),
                      onPressed: _pickDeadline,
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: allowLateRsvp,
                onChanged: (value) => setState(() => allowLateRsvp = value),
                title: Text(context.t('invitationSettings.allowLateRsvp')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: defaultMaxGuests,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.t('invitationSettings.defaultMaxGuests'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: templateId,
                      decoration: InputDecoration(
                        labelText: context.t(
                          'invitationSettings.defaultTemplate',
                        ),
                      ),
                      items: templates
                          .map(
                            (template) => DropdownMenuItem(
                              value: stringFrom(template, 'id'),
                              child: Text(stringFrom(template, 'name')),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => templateId = value),
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('cardPreview.browseTemplates'),
                    icon: const Icon(Icons.grid_view_outlined),
                    onPressed: () async {
                      final selected = await Navigator.of(context).push<String>(
                        MaterialPageRoute(
                          builder: (_) => TemplateGalleryScreen(
                            controller: widget.controller,
                            sampleData: sampleInvitationCardData(
                              context,
                              event: widget.event,
                            ),
                            selectedTemplateId: templateId,
                          ),
                        ),
                      );
                      if (selected != null) {
                        setState(() => templateId = selected);
                      }
                    },
                  ),
                ],
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: AhadiColors.danger)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: saving ? null : _save,
                child: Text(
                  saving ? context.t('auth.saving') : context.t('common.save'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Event Member Detail integration -- shows the invitation/RSVP section
/// (cases A-G from the RSVP-2 spec) and never silently creates a second
/// invitation: creation only happens through the explicit "Create
/// Invitation" action, which itself surfaces INVITATION_ALREADY_EXISTS as a
/// friendly message rather than retrying/duplicating.
class EventMemberInvitationSection extends StatefulWidget {
  const EventMemberInvitationSection({
    super.key,
    required this.controller,
    required this.event,
    required this.eventMemberId,
    required this.memberName,
  });

  final SessionController controller;
  final EventSummary event;
  final String eventMemberId;
  final String memberName;

  @override
  State<EventMemberInvitationSection> createState() =>
      _EventMemberInvitationSectionState();
}

class _EventMemberInvitationSectionState
    extends State<EventMemberInvitationSection> {
  late Future<Map<String, dynamic>?> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  // Exact (tenant, event, event_member) identity lookup -- never resolve
  // this by Contact/member name. Two Contacts can share a full_name, names
  // can change, and invitation display_name can diverge from the Contact's
  // name entirely; Member Detail must never show another person's
  // invitation.
  Future<Map<String, dynamic>?> _load() {
    return widget.controller.eventMemberInvitation(
      widget.event.id,
      widget.eventMemberId,
    );
  }

  // Block body, not `() => future = _load()` -- an assignment expression
  // evaluates to the assigned Future, which trips Flutter's "setState
  // callback returned a Future" guard.
  void _refresh() => setState(() {
    future = _load();
  });

  Future<void> _createInvitation() async {
    final detail = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SingleCreateInvitationScreen(
          controller: widget.controller,
          event: widget.event,
          eventMemberId: widget.eventMemberId,
          memberName: widget.memberName,
        ),
      ),
    );
    if (detail != null) _refresh();
  }

  Future<void> _openDetail(String invitationId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvitationDetailScreen(
          controller: widget.controller,
          event: widget.event,
          invitationId: invitationId,
        ),
      ),
    );
    _refresh();
  }

  Future<void> _previewCard(String invitationId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvitationCardPreviewScreen(
          controller: widget.controller,
          event: widget.event,
          invitationId: invitationId,
        ),
      ),
    );
  }

  Future<void> _recordRsvp(Map<String, dynamic> detail) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ManualRsvpForm(
          controller: widget.controller,
          event: widget.event,
          invitation: detail,
        ),
      ),
    );
    if (saved == true) _refresh();
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('invitationDetail.linkCopied'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = _hasPermission(widget.controller, 'invitation.create');
    final canEdit = _hasPermission(widget.controller, 'invitation.edit');
    final canManageRsvp = _hasPermission(widget.controller, 'rsvp.manage');
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return AhadiSectionCard(
            title: context.t('memberDetail.invitation'),
            children: const [LinearProgressIndicator(minHeight: 4)],
          );
        }
        final detail = snapshot.data;
        if (detail == null) {
          return AhadiSectionCard(
            title: context.t('memberDetail.invitation'),
            children: [
              Text(
                context.t('memberDetail.invitationNotCreated'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              if (canCreate) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _createInvitation,
                  icon: const Icon(Icons.mail_outline),
                  label: Text(context.t('memberDetail.createInvitation')),
                ),
              ],
            ],
          );
        }
        final status = stringFrom(detail, 'status', 'DRAFT');
        final rsvp = detail['rsvp'] as Map<String, dynamic>?;
        final maxGuests = numberFrom(detail['maxGuests'])?.round() ?? 1;
        final shareUrl = stringFrom(detail, 'shareUrl');
        final invitationId = stringFrom(detail, 'id');
        return AhadiSectionCard(
          title: context.t('memberDetail.invitation'),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stringFrom(detail, 'displayName'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(status: _statusLabel(context, status)),
              ],
            ),
            if (status == 'DRAFT') ...[
              const SizedBox(height: 8),
              AhadiInfoRow(
                label: context.t('invitationDetail.maxGuests'),
                value: '$maxGuests',
              ),
            ],
            if (status == 'ACTIVE') ...[
              const SizedBox(height: 10),
              Text(
                context.t('memberDetail.rsvp'),
                style: const TextStyle(
                  color: AhadiColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rsvp == null
                    ? context.t('memberDetail.rsvpNoResponse')
                    : _rsvpLabel(context, rsvp['response'] as String?),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (rsvp != null && rsvp['response'] != 'NOT_ATTENDING')
                Text(
                  (rsvp['response'] == 'MAYBE'
                          ? context.t('memberDetail.potentialGuestsOf')
                          : context.t('memberDetail.guestsOf'))
                      .replaceFirst(
                        '{count}',
                        '${numberFrom(rsvp['attendingCount'])?.round() ?? 0}',
                      )
                      .replaceFirst('{max}', '$maxGuests'),
                  style: const TextStyle(color: AhadiColors.muted),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'DRAFT' && canEdit)
                  FilledButton.icon(
                    onPressed: () => _openDetail(invitationId),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(context.t('invitationDetail.edit')),
                  ),
                if (status != 'DRAFT')
                  OutlinedButton.icon(
                    onPressed: () => _openDetail(invitationId),
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(context.t('memberDetail.viewInvitation')),
                  ),
                if (status == 'ACTIVE' && canManageRsvp)
                  FilledButton.icon(
                    onPressed: () => _recordRsvp(detail),
                    icon: const Icon(Icons.how_to_reg_outlined),
                    label: Text(
                      rsvp == null
                          ? context.t('invitationDetail.recordRsvp')
                          : context.t('invitationDetail.editRsvp'),
                    ),
                  ),
                if (status == 'ACTIVE' && shareUrl.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _copyLink(shareUrl),
                    icon: const Icon(Icons.copy),
                    label: Text(context.t('invitationDetail.copyLink')),
                  ),
                if (status != 'DRAFT' &&
                    _hasPermission(widget.controller, 'invitation.view'))
                  OutlinedButton.icon(
                    onPressed: () => _previewCard(invitationId),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(context.t('invitationDetail.previewCard')),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// RSVP-3A: Invitation Card Engine -- template gallery + personalized
// preview + QR + PNG export. Rendering itself lives in
// invitation_card_renderer.dart (pure, testable); everything here is UI
// wiring that reuses this file's existing helpers (_hasPermission,
// _shareText, _statusLabel) rather than duplicating them in a second file.
// ---------------------------------------------------------------------

/// Generic placeholder personalization used only for gallery thumbnails and
/// the "browse templates" launcher before an invitation's own real data is
/// known -- literally the example card copy from the RSVP-3A spec, since
/// that is already a realistic sample.
InvitationCardData sampleInvitationCardData(
  BuildContext context, {
  required EventSummary event,
  String? guestDisplayName,
}) {
  return InvitationCardData(
    leadInText: context.t('cardPreview.leadIn'),
    connectorText: context.t('cardPreview.connector'),
    hostDisplayName: 'Mr. Victor Prever Kinabo & Family',
    guestDisplayName: guestDisplayName?.trim().isNotEmpty == true
        ? guestDisplayName!.trim()
        : 'Julias Kinabo',
    eventName: event.name.isNotEmpty
        ? event.name
        : 'Jennifer Ludovick Swai Send Off',
    dateText: dateText(event.eventDate),
    timeText: '6:00 PM',
    venueName: event.venue ?? 'Riverside Hall',
    venueAddress: 'Dar es Salaam',
    rsvpDeadlineText: '',
    shareUrl: 'https://app.changisha.co/i/preview',
  );
}

String _sanitizeFilenameSegment(String input) {
  final lower = input.toLowerCase().trim();
  final replaced = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final collapsed = replaced.replaceAll(RegExp(r'-+'), '-');
  final trimmed = collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'guest' : trimmed;
}

/// e.g. "changisha-victor-kinabo-portrait.png" -- sanitized so the guest's
/// name can never inject path separators or otherwise-unsafe characters
/// into a filename.
String invitationCardFilename(
  String guestDisplayName,
  InvitationCardFormat format,
) {
  return 'changisha-${_sanitizeFilenameSegment(guestDisplayName)}-${format.name}.png';
}

/// Writes the exported PNG to a temp file for handoff to the native share
/// sheet -- same shape as `receiptImageSharePayload` in
/// financial_screens.dart (this project's one existing image-share
/// pattern), reused rather than reinvented.
Future<Map<String, Object?>> invitationCardSharePayload(
  Uint8List bytes,
  String filename, {
  Directory? directory,
}) async {
  final file = File('${(directory ?? Directory.systemTemp).path}/$filename');
  await file.writeAsBytes(bytes);
  return {
    'path': file.path,
    'mimeType': 'image/png',
    'title': 'Changisha Invitation Card',
  };
}

/// Browse active templates (PLATFORM + this tenant's own TENANT-scope
/// templates -- rpc_list_invitation_templates already enforces that
/// isolation server-side) and pick one. Returns the selected template id via
/// `Navigator.pop`, or null if the organizer backs out.
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({
    super.key,
    required this.controller,
    required this.sampleData,
    this.selectedTemplateId,
    this.renderCard = renderInvitationCardPng,
  });

  final SessionController controller;
  final InvitationCardData sampleData;
  final String? selectedTemplateId;
  final InvitationCardRenderer renderCard;

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  late Future<List<Map<String, dynamic>>> future;

  @override
  void initState() {
    super.initState();
    future = widget.controller.invitationTemplates();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('templateGallery.title'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(
                message: friendlyErrorText(snapshot.error),
                onRetry: () => setState(() {
                  future = widget.controller.invitationTemplates();
                }),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 4),
            );
          }
          final templates = snapshot.data!;
          if (templates.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t('templateGallery.empty'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.66,
            ),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final template = templates[index];
              return _TemplateGalleryCard(
                template: template,
                sampleData: widget.sampleData,
                selected:
                    stringFrom(template, 'id') == widget.selectedTemplateId,
                onUse: () =>
                    Navigator.of(context).pop(stringFrom(template, 'id')),
                renderCard: widget.renderCard,
              );
            },
          );
        },
      ),
    );
  }
}

class _TemplateGalleryCard extends StatefulWidget {
  const _TemplateGalleryCard({
    required this.template,
    required this.sampleData,
    required this.selected,
    required this.onUse,
    required this.renderCard,
  });

  final Map<String, dynamic> template;
  final InvitationCardData sampleData;
  final bool selected;
  final VoidCallback onUse;
  final InvitationCardRenderer renderCard;

  @override
  State<_TemplateGalleryCard> createState() => _TemplateGalleryCardState();
}

class _TemplateGalleryCardState extends State<_TemplateGalleryCard> {
  late Future<Uint8List> future;

  @override
  void initState() {
    super.initState();
    future = widget.renderCard(
      templateConfig: objectMap(widget.template['configJson']),
      data: widget.sampleData,
      format: InvitationCardFormat.portrait,
      status: 'ACTIVE',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = widget.template['isPremium'] == true;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.selected ? AhadiColors.primary : AhadiColors.border,
          width: widget.selected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: FutureBuilder<Uint8List>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(snapshot.data!, fit: BoxFit.cover),
                    if (isPremium)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AhadiColors.primaryStrong,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.t('templateGallery.premium'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  stringFrom(widget.template, 'name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  stringFrom(widget.template, 'category'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AhadiColors.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: widget.onUse,
                  child: Text(
                    context.t('templateGallery.useTemplate'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardContext {
  _CardContext({
    required this.detail,
    required this.settings,
    required this.templates,
  });

  final Map<String, dynamic> detail;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> templates;
}

/// Invitation Detail gains [ Preview Card ]: template picker, format
/// switcher (Portrait/Square/Story), live preview, and Download PNG / Copy
/// Link / Copy Invitation Text. Always re-fetches invitation detail (and
/// therefore `shareUrl`) fresh on open -- this screen never keeps its own
/// copy of a token across a Rotate Link, so there is no stale-QR risk from
/// this screen's own state; the "old cards still have the old link"
/// warning after rotation is shown on Invitation Detail instead, since a
/// PNG the organizer already downloaded/shared can't be reached from here.
/// Same shape as [renderInvitationCardPng] -- overridable in tests (mirrors
/// the existing `shareImage`/`receiptImageBytes` injection points on
/// `ReceiptDetailScreen`) so a test can observe exactly what data/QR
/// payload reached the renderer without needing to decode PNG pixels.
typedef InvitationCardRenderer = Future<Uint8List> Function({
  required Map<String, dynamic> templateConfig,
  required InvitationCardData data,
  required InvitationCardFormat format,
  required String status,
});

class InvitationCardPreviewScreen extends StatefulWidget {
  const InvitationCardPreviewScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.invitationId,
    this.renderCard = renderInvitationCardPng,
  });

  final SessionController controller;
  final EventSummary event;
  final String invitationId;
  final InvitationCardRenderer renderCard;

  @override
  State<InvitationCardPreviewScreen> createState() =>
      _InvitationCardPreviewScreenState();
}

class _InvitationCardPreviewScreenState
    extends State<InvitationCardPreviewScreen> {
  late Future<_CardContext> future;
  String? templateId;
  InvitationCardFormat format = InvitationCardFormat.portrait;
  bool exporting = false;

  // Render-future memoization: rebuilding this every widget rebuild (e.g.
  // while `exporting` toggles during a download) would re-run the Canvas
  // painter needlessly and flash the preview back to a spinner. Recomputed
  // only when the inputs that actually affect pixels change.
  String? _renderKey;
  Future<Uint8List>? _renderFuture;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_CardContext> _load() async {
    final results = await Future.wait([
      widget.controller.eventInvitationDetail(
        widget.event.id,
        widget.invitationId,
      ),
      widget.controller.eventInvitationSettings(widget.event.id),
      widget.controller.invitationTemplates(),
    ]);
    final detail = results[0] as Map<String, dynamic>;
    final settingsResponse = results[1] as Map<String, dynamic>;
    final templates = results[2] as List<Map<String, dynamic>>;
    final settings = objectMap(settingsResponse['settings']);
    if (templateId == null) {
      final invitationTemplateId =
          (detail['template'] as Map<String, dynamic>?)?['id']?.toString();
      final settingsTemplateId = stringFrom(settings, 'templateId');
      templateId =
          invitationTemplateId ??
          (settingsTemplateId.isNotEmpty ? settingsTemplateId : null) ??
          (templates.isNotEmpty ? stringFrom(templates.first, 'id') : null);
    }
    return _CardContext(
      detail: detail,
      settings: settings,
      templates: templates,
    );
  }

  void _refresh() => setState(() => future = _load());

  InvitationCardData _dataFrom(
    BuildContext context,
    Map<String, dynamic> detail,
    Map<String, dynamic> settings,
  ) {
    final invitationTitle = stringFrom(settings, 'invitationTitle');
    final venueOverride = stringFrom(settings, 'venueNameOverride');
    final addressOverride = stringFrom(settings, 'venueAddressOverride');
    final deadlineText = stringFrom(settings, 'rsvpDeadline');
    return InvitationCardData(
      leadInText: context.t('cardPreview.leadIn'),
      connectorText: context.t('cardPreview.connector'),
      hostDisplayName: stringFrom(settings, 'hostDisplayName'),
      guestDisplayName: stringFrom(detail, 'displayName'),
      eventName: invitationTitle.isNotEmpty
          ? invitationTitle
          : widget.event.name,
      dateText: dateText(widget.event.eventDate),
      timeText: stringFrom(settings, 'eventTimeDisplay'),
      venueName: venueOverride.isNotEmpty
          ? venueOverride
          : (widget.event.venue ?? ''),
      venueAddress: addressOverride,
      rsvpDeadlineText: deadlineText.isEmpty
          ? ''
          : context
                .t('cardPreview.rsvpBy')
                .replaceFirst('{date}', dateText(deadlineText)),
      // The public invitation URL is the only thing that ever reaches the
      // QR encoder -- see InvitationCardData.qrPayload.
      shareUrl: stringFrom(detail, 'shareUrl'),
    );
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('invitationDetail.linkCopied'))),
    );
  }

  Future<void> _copyInvitationText(
    Map<String, dynamic> detail,
    String url,
  ) async {
    final text = _shareText(context, widget.event, detail, url);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t('invitationDetail.linkCopied'))),
    );
  }

  Future<void> _downloadPng(
    Map<String, dynamic> templateConfig,
    InvitationCardData data,
    String status,
  ) async {
    setState(() => exporting = true);
    try {
      final bytes = await widget.renderCard(
        templateConfig: templateConfig,
        data: data,
        format: format,
        status: status,
      );
      final filename = invitationCardFilename(data.guestDisplayName, format);
      final payload = await invitationCardSharePayload(bytes, filename);
      await _cardShareChannel.invokeMethod<void>('shareImage', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('cardPreview.downloadReady'))),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorText(err))));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _useTemplate(String newTemplateId) async {
    try {
      await widget.controller.updateEventInvitation(
        widget.event.id,
        widget.invitationId,
        {'templateId': newTemplateId},
      );
      if (!mounted) return;
      setState(() => templateId = newTemplateId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('cardPreview.templateApplied'))),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorText(err))));
    }
  }

  Future<void> _browseTemplates(InvitationCardData sampleData) async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TemplateGalleryScreen(
          controller: widget.controller,
          sampleData: sampleData,
          selectedTemplateId: templateId,
        ),
      ),
    );
    if (selected != null) setState(() => templateId = selected);
  }

  @override
  Widget build(BuildContext context) {
    // invitation.view -> preview card; invitation.edit -> persist a
    // template change. Never a role-name/isOwner shortcut.
    final canView = _hasPermission(widget.controller, 'invitation.view');
    final canEdit = _hasPermission(widget.controller, 'invitation.edit');
    return Scaffold(
      appBar: AppBar(title: Text(context.t('cardPreview.title'))),
      body: !canView
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.t('cardPreview.noAccess'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
            )
          : FutureBuilder<_CardContext>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: ErrorPanel(
                      message: friendlyErrorText(
                        snapshot.error,
                        context.t('invitationDetail.loadError'),
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
                final cardContext = snapshot.data!;
                final status = stringFrom(
                  cardContext.detail,
                  'status',
                  'DRAFT',
                );

                if (status == 'CANCELLED') {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: AhadiSectionCard(
                      title: context.t('cardPreview.title'),
                      children: [
                        Text(
                          context.t('cardPreview.cancelledNotice'),
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                      ],
                    ),
                  );
                }

                final templates = cardContext.templates;
                final template = templates.firstWhere(
                  (t) => stringFrom(t, 'id') == templateId,
                  orElse: () => templates.isNotEmpty
                      ? templates.first
                      : <String, dynamic>{},
                );
                final templateConfig = objectMap(template['configJson']);
                final data = _dataFrom(
                  context,
                  cardContext.detail,
                  cardContext.settings,
                );
                final shareUrl = data.shareUrl;
                final currentTemplateId =
                    (cardContext.detail['template']
                            as Map<String, dynamic>?)?['id']
                        ?.toString();
                final selectedTemplateId = template.isEmpty
                    ? null
                    : stringFrom(template, 'id');

                final renderKey =
                    '$selectedTemplateId|${format.name}|$shareUrl|$status';
                if (_renderKey != renderKey && template.isNotEmpty) {
                  _renderKey = renderKey;
                  _renderFuture = widget.renderCard(
                    templateConfig: templateConfig,
                    data: data,
                    format: format,
                    status: status,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (status == 'DRAFT')
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          context.t('cardPreview.draftNotice'),
                          style: const TextStyle(
                            color: AhadiColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedTemplateId,
                            // Without isExpanded, DropdownButton's internal
                            // Row sizes to its content's intrinsic width
                            // (MainAxisSize.min) rather than the width this
                            // Expanded actually allocates -- a long
                            // template name (e.g. "Traditional Kitenge")
                            // then overflows on a narrow screen instead of
                            // being ellipsized.
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: context.t('cardPreview.template'),
                            ),
                            items: templates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: stringFrom(t, 'id'),
                                    child: Text(
                                      stringFrom(t, 'name'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => templateId = value);
                              }
                            },
                          ),
                        ),
                        IconButton(
                          tooltip: context.t('cardPreview.browseTemplates'),
                          icon: const Icon(Icons.grid_view_outlined),
                          onPressed: () => _browseTemplates(data),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: SegmentedButton<InvitationCardFormat>(
                        segments: InvitationCardFormat.values
                            .map(
                              (f) =>
                                  ButtonSegment(value: f, label: Text(f.label)),
                            )
                            .toList(),
                        selected: {format},
                        onSelectionChanged: (selection) =>
                            setState(() => format = selection.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: AspectRatio(
                          aspectRatio: format.width / format.height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: AhadiColors.border),
                            ),
                            child: template.isEmpty || _renderFuture == null
                                ? const Center(child: Text('—'))
                                : FutureBuilder<Uint8List>(
                                    future: _renderFuture,
                                    builder: (context, snapshot) {
                                      if (!snapshot.hasData) {
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      return Image.memory(
                                        snapshot.data!,
                                        fit: BoxFit.contain,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (status == 'ACTIVE')
                          FilledButton.icon(
                            onPressed: exporting || template.isEmpty
                                ? null
                                : () => _downloadPng(
                                    templateConfig,
                                    data,
                                    status,
                                  ),
                            icon: const Icon(Icons.download_outlined),
                            label: Text(context.t('cardPreview.downloadPng')),
                          ),
                        if (status == 'ACTIVE' && shareUrl.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _copyLink(shareUrl),
                            icon: const Icon(Icons.copy),
                            label: Text(context.t('invitationDetail.copyLink')),
                          ),
                        if (status == 'ACTIVE' && shareUrl.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () => _copyInvitationText(
                              cardContext.detail,
                              shareUrl,
                            ),
                            icon: const Icon(Icons.content_copy_outlined),
                            label: Text(
                              context.t('invitationDetail.copyInvitationText'),
                            ),
                          ),
                        if (canEdit &&
                            selectedTemplateId != null &&
                            selectedTemplateId != currentTemplateId)
                          FilledButton.icon(
                            onPressed: () => _useTemplate(selectedTemplateId),
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(
                              context.t('cardPreview.useThisTemplate'),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

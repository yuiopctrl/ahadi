import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../contacts/presentation/contacts_screen.dart';
import '../../financial/presentation/financial_screens.dart' hide objectList;
import '../../invitations/presentation/invitations_screen.dart';
import '../../invitations/presentation/rsvp_dashboard_screen.dart';
import '../../pledges/presentation/pledge_form.dart';
import '../../pledges/presentation/pledges_screen.dart';

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  int tabIndex = 0;
  late Future<_EventDetailData> future;
  late EventSummary event;

  @override
  void initState() {
    super.initState();
    event = widget.event;
    future = _load();
  }

  Future<_EventDetailData> _load() async {
    final results = await Future.wait([
      widget.controller
          .eventFinancialSummary(event.id)
          .catchError((_) => <String, dynamic>{}),
      widget.controller
          .eventMembers(event.id)
          .catchError((_) => <Map<String, dynamic>>[]),
      widget.controller
          .eventPledges(event.id)
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return _EventDetailData(
      summary: results[0] as Map<String, dynamic>,
      members: results[1] as List<Map<String, dynamic>>,
      pledges: results[2] as List<Map<String, dynamic>>,
    );
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  Future<void> _editEvent() async {
    final updated = await Navigator.of(context).push<EventSummary>(
      MaterialPageRoute(
        builder: (_) =>
            EditEventScreen(controller: widget.controller, event: event),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      event = updated;
      future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'events.update',
            ) ==
            true;
    // No `isOwner` bypass here: `isOwner` is just a denormalized restatement
    // of "role == TENANT_OWNER", not an independent authorization concept,
    // and the tenant context's effective `permissions` list already
    // includes every invitation.*/rsvp.* permission that role currently
    // grants -- checking it directly is both behavior-identical today and
    // correct if a permission is ever overridden per-user in the future.
    final canViewInvitations =
        widget.controller.selectedTenantContext?.permissions.contains(
          'invitation.view',
        ) ==
        true;
    final canViewRsvp =
        widget.controller.selectedTenantContext?.permissions.contains(
          'rsvp.view',
        ) ==
        true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('eventDetail.title')),
        actions: [
          if (canEdit)
            TextButton(
              onPressed: _editEvent,
              child: Text(context.t('common.edit')),
            ),
        ],
      ),
      body: FutureBuilder<_EventDetailData>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 4),
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _EventHeader(event: event, summary: data.summary),
                const SizedBox(height: 12),
                FilterTabs<int>(
                  items: [
                    FilterTabItem(
                      value: 0,
                      label: context.t('eventDetail.overview'),
                    ),
                    FilterTabItem(
                      value: 1,
                      label: context.t('dashboard.members'),
                    ),
                    FilterTabItem(
                      value: 2,
                      label: context.t('shell.more.pledges'),
                    ),
                    FilterTabItem(
                      value: 3,
                      label: context.t('shell.nav.payments'),
                    ),
                    if (canViewInvitations)
                      FilterTabItem(
                        value: 4,
                        label: context.t('eventDetail.invitations'),
                      ),
                    if (canViewRsvp)
                      FilterTabItem(
                        value: 5,
                        label: context.t('eventDetail.rsvp'),
                      ),
                  ],
                  selected: tabIndex,
                  onChanged: (value) => setState(() => tabIndex = value),
                ),
                const SizedBox(height: 12),
                if (tabIndex == 0) _OverviewTab(event: event, data: data),
                if (tabIndex == 1)
                  _MembersTab(
                    controller: widget.controller,
                    event: event,
                    onChanged: _refresh,
                  ),
                if (tabIndex == 2)
                  _PledgesTab(
                    controller: widget.controller,
                    event: event,
                    members: data.members,
                    pledges: data.pledges,
                    onChanged: _refresh,
                  ),
                if (tabIndex == 3)
                  _PaymentsTab(controller: widget.controller, event: event),
                if (tabIndex == 4 && canViewInvitations)
                  InvitationsTab(
                    controller: widget.controller,
                    event: event,
                    onChanged: _refresh,
                  ),
                if (tabIndex == 5 && canViewRsvp)
                  RsvpDashboardTab(controller: widget.controller, event: event),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EventDetailData {
  const _EventDetailData({
    required this.summary,
    required this.members,
    required this.pledges,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> pledges;
}

class EditEventScreen extends StatefulWidget {
  const EditEventScreen({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final name = TextEditingController();
  final customType = TextEditingController();
  final eventDate = TextEditingController();
  final venue = TextEditingController();
  final targetAmount = TextEditingController();
  final pledgeDeadline = TextEditingController();
  late String eventType;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    eventType = widget.event.eventType.isEmpty
        ? 'WEDDING'
        : widget.event.eventType;
    name.text = widget.event.name;
    customType.text = widget.event.customEventType ?? '';
    eventDate.text = widget.event.eventDate ?? '';
    venue.text = widget.event.venue ?? '';
    targetAmount.text = moneyInputText(widget.event.targetAmount);
    pledgeDeadline.text = widget.event.pledgeDeadline ?? '';
  }

  @override
  void dispose() {
    name.dispose();
    customType.dispose();
    eventDate.dispose();
    venue.dispose();
    targetAmount.dispose();
    pledgeDeadline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.t('eventDetail.editEvent'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: context.t('events.eventName'),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: eventType,
            items: _eventTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(context.t('events.type.$type')),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => eventType = value ?? 'WEDDING'),
            decoration: InputDecoration(
              labelText: context.t('events.eventType'),
            ),
          ),
          if (eventType == 'OTHER') ...[
            const SizedBox(height: 12),
            TextField(
              controller: customType,
              decoration: InputDecoration(
                labelText: context.t('events.customEventType'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: eventDate,
            decoration: InputDecoration(
              labelText: context.t('events.eventDate'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: venue,
            decoration: InputDecoration(labelText: context.t('events.venue')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: targetAmount,
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInputFormatter()],
            decoration: InputDecoration(
              labelText: context.t('events.targetAmount'),
              prefixText: 'TZS ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pledgeDeadline,
            decoration: InputDecoration(
              labelText: context.t('events.pledgeDeadline'),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: Text(context.t('common.cancel')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(
                    saving
                        ? context.t('auth.saving')
                        : context.t('eventDetail.saveChanges'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final updated = await widget.controller.updateEvent(widget.event.id, {
        'name': name.text.trim(),
        'eventType': eventType,
        'customEventType': eventType == 'OTHER' ? customType.text.trim() : null,
        'eventDate': eventDate.text.trim().isEmpty
            ? null
            : eventDate.text.trim(),
        'venue': venue.text.trim().isEmpty ? null : venue.text.trim(),
        'targetAmount': targetAmount.text.trim().isEmpty
            ? null
            : moneyInputValue(targetAmount.text),
        'pledgeDeadline': pledgeDeadline.text.trim().isEmpty
            ? null
            : pledgeDeadline.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

const _eventTypes = [
  'WEDDING',
  'SENDOFF',
  'FUNERAL',
  'FUNDRAISER',
  'BIRTHDAY',
  'GRADUATION',
  'RELIGIOUS',
  'OTHER',
];

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event, required this.summary});

  final EventSummary event;
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                StatusPill(status: event.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${context.t('events.type.${event.eventType}')} · ${dateText(event.eventDate)}',
              style: const TextStyle(color: AhadiColors.muted),
            ),
            if (event.venue != null && event.venue!.isNotEmpty)
              Text(event.venue!),
            const SizedBox(height: 12),
            FinancialSummary(
              pledged: summary['totalPledged'] ?? event.totalPledged,
              received:
                  summary['totalAllocated'] ??
                  summary['totalAllocatedToPledges'] ??
                  event.totalCollected,
              outstanding:
                  summary['totalOutstanding'] ?? event.totalOutstanding,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.event, required this.data});

  final EventSummary event;
  final _EventDetailData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(context.t('eventDetail.status')),
                trailing: StatusPill(status: event.status),
              ),
              ListTile(
                title: Text(context.t('events.pledgeDeadlineShort')),
                trailing: Text(dateText(event.pledgeDeadline)),
              ),
              ListTile(
                title: Text(context.t('events.targetAmount')),
                trailing: Text(moneyText(event.targetAmount)),
              ),
              ListTile(
                title: Text(context.t('dashboard.members')),
                trailing: Text(data.members.length.toString()),
              ),
              ListTile(
                title: Text(context.t('shell.more.pledges')),
                trailing: Text(data.pledges.length.toString()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _memberSortOptions = <(String, String, String)>[
  ('NAME', 'ASC', 'eventDetail.sort.nameAsc'),
  ('NAME', 'DESC', 'eventDetail.sort.nameDesc'),
  ('CREATED', 'DESC', 'eventDetail.sort.newest'),
  ('CREATED', 'ASC', 'eventDetail.sort.oldest'),
  ('PLEDGE_AMOUNT', 'DESC', 'eventDetail.sort.pledgeHighLow'),
  ('PLEDGE_AMOUNT', 'ASC', 'eventDetail.sort.pledgeLowHigh'),
  ('OUTSTANDING', 'DESC', 'eventDetail.sort.outstandingHighLow'),
  ('OUTSTANDING', 'ASC', 'eventDetail.sort.outstandingLowHigh'),
];

const _pledgeFilterOptions = <(String, String)>[
  ('ALL', 'eventDetail.filter.all'),
  ('HAS_PLEDGE', 'eventDetail.filter.hasPledge'),
  ('NO_PLEDGE', 'eventDetail.filter.noPledge'),
  ('FULLY_PAID', 'eventDetail.filter.fullyPaid'),
  ('PARTIALLY_PAID', 'eventDetail.filter.partiallyPaid'),
  ('UNPAID', 'eventDetail.filter.unpaid'),
];

const _phoneFilterOptions = <(String, String)>[
  ('ALL', 'eventDetail.filter.all'),
  ('HAS_PHONE', 'eventDetail.filter.hasPhone'),
  ('NO_PHONE', 'eventDetail.filter.noPhone'),
];

class _MembersTab extends StatefulWidget {
  const _MembersTab({
    required this.controller,
    required this.event,
    required this.onChanged,
  });

  final SessionController controller;
  final EventSummary event;
  final VoidCallback onChanged;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  static const pageSize = 10;

  bool pickerOpen = false;
  String query = '';
  String pledgeFilter = 'ALL';
  String phoneFilter = 'ALL';
  String sort = 'NAME';
  String direction = 'ASC';
  int page = 0;
  Timer? debounce;
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.listEventMembers(
      widget.event.id,
      search: query,
      pledgeStatus: pledgeFilter,
      phoneStatus: phoneFilter,
      sort: sort,
      direction: direction,
      limit: pageSize,
      offset: page * pageSize,
    );
  }

  void _refresh() => setState(() => future = _load());

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

  @override
  Widget build(BuildContext context) {
    final canAssign =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'members.assign_event',
            ) ==
            true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canAssign)
          FilledButton.icon(
            onPressed: () => setState(() => pickerOpen = !pickerOpen),
            icon: const Icon(Icons.add),
            label: Text(context.t('eventDetail.addMember')),
          ),
        if (pickerOpen)
          _AvailableContactPicker(
            controller: widget.controller,
            event: widget.event,
            onDone: () {
              setState(() => pickerOpen = false);
              _refresh();
              widget.onChanged();
            },
          ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            labelText: context.t('eventDetail.searchMembers'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: _onSearch,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SortDropdown(
              sort: sort,
              direction: direction,
              onChanged: (nextSort, nextDirection) => setState(() {
                sort = nextSort;
                direction = nextDirection;
                page = 0;
                future = _load();
              }),
            ),
            _FilterDropdown(
              value: pledgeFilter,
              options: _pledgeFilterOptions,
              label: context.t('eventDetail.filter.pledgeHint'),
              onChanged: (value) => setState(() {
                pledgeFilter = value;
                page = 0;
                future = _load();
              }),
            ),
            _FilterDropdown(
              value: phoneFilter,
              options: _phoneFilterOptions,
              label: context.t('eventDetail.filter.phoneHint'),
              onChanged: (value) => setState(() {
                phoneFilter = value;
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
              return ErrorPanel(
                message: friendlyErrorText(
                  snapshot.error,
                  context.t('eventDetail.membersLoadError'),
                ),
                onRetry: _refresh,
              );
            }
            if (!snapshot.hasData) {
              return const LoadingCards(count: 3);
            }
            final response = snapshot.data!;
            final rows =
                (response['data'] is List
                        ? (response['data'] as List)
                        : const [])
                    .whereType<Map<String, dynamic>>()
                    .toList();
            final pagination = response['pagination'] is Map
                ? Map<String, dynamic>.from(response['pagination'] as Map)
                : const <String, dynamic>{};
            final totalRows =
                numberFrom(pagination['totalRows'])?.round() ?? rows.length;
            final totalPages = totalRows == 0
                ? 1
                : ((totalRows - 1) ~/ pageSize) + 1;
            if (rows.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.t('eventDetail.noMembersFound')),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...rows.map(
                  (member) => AhadiListRow(
                    title: titleCaseName(member['full_name']),
                    subtitle: stringFrom(
                      member,
                      'phone_e164',
                      context.t('contacts.noPhone'),
                    ),
                    status: stringFrom(member, 'pledge_status', 'NO PLEDGE'),
                    financialSummary: FinancialSummary(
                      pledged: member['pledged_amount'],
                      received: member['total_allocated'],
                      outstanding: member['outstanding_amount'],
                    ),
                    meta: (numberFrom(member['pledged_amount']) ?? 0) <= 0
                        ? context.t('eventDetail.noPledge')
                        : null,
                    onTap: () => Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => EventMemberDetailScreen(
                              controller: widget.controller,
                              event: widget.event,
                              eventMemberId: stringFrom(
                                member,
                                'event_member_id',
                              ),
                            ),
                          ),
                        )
                        .then((_) => _refresh()),
                  ),
                ),
                _EventListPaginationControls(
                  page: page,
                  totalPages: totalPages,
                  totalRows: totalRows,
                  label: context.t('dashboard.members').toLowerCase(),
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

// Chip-triggered popup menus, not DropdownButtonFormField: a fixed-width
// dropdown field overflows once the selected option's translated text
// (e.g. "Outstanding: High to Low") is long, on narrower screens. A Chip
// sizes to its own content and never has that failure mode.
class _SortDropdown extends StatelessWidget {
  const _SortDropdown({
    required this.sort,
    required this.direction,
    required this.onChanged,
  });

  final String sort;
  final String direction;
  final void Function(String sort, String direction) onChanged;

  @override
  Widget build(BuildContext context) {
    final current = _memberSortOptions.firstWhere(
      (option) => option.$1 == sort && option.$2 == direction,
      orElse: () => _memberSortOptions.first,
    );
    return PopupMenuButton<String>(
      initialValue: '${current.$1}|${current.$2}',
      onSelected: (value) {
        final parts = value.split('|');
        onChanged(parts[0], parts[1]);
      },
      itemBuilder: (context) => _memberSortOptions
          .map(
            (option) => PopupMenuItem(
              value: '${option.$1}|${option.$2}',
              child: Text(context.t(option.$3)),
            ),
          )
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.sort, size: 16),
        label: Text(
          '${context.t('eventDetail.sort.label')}: ${context.t(current.$3)}',
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
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

class EventMemberDetailScreen extends StatefulWidget {
  const EventMemberDetailScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.eventMemberId,
  });

  final SessionController controller;
  final EventSummary event;
  final String eventMemberId;

  @override
  State<EventMemberDetailScreen> createState() =>
      _EventMemberDetailScreenState();
}

class _EventMemberDetailScreenState extends State<EventMemberDetailScreen> {
  late Future<Map<String, dynamic>> future;
  String? error;

  @override
  void initState() {
    super.initState();
    future = widget.controller.eventMemberDetail(
      widget.event.id,
      widget.eventMemberId,
    );
  }

  void _refresh() {
    final next = widget.controller.eventMemberDetail(
      widget.event.id,
      widget.eventMemberId,
    );
    // Block body, not `() => future = next` -- an assignment expression
    // evaluates to the assigned Future, which trips Flutter's "setState
    // callback returned a Future" guard.
    setState(() {
      future = next;
    });
  }

  bool _hasPermission(String permission) =>
      widget.controller.selectedTenantContext?.isOwner == true ||
      widget.controller.selectedTenantContext?.permissions.contains(
            permission,
          ) ==
          true;

  Future<void> _openRecordPledge(Map<String, dynamic> member) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: PledgeForm(
            controller: widget.controller,
            event: widget.event,
            members: [member],
            initialEventMemberId: widget.eventMemberId,
            startOpen: true,
            onDone: () => Navigator.of(sheetContext).pop(true),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    _refresh();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t('pledges.pledgeSaved'))));
  }

  Future<void> _openEditPledge(Map<String, dynamic> member) async {
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => EditPledgeScreen(
          controller: widget.controller,
          event: widget.event,
          pledge: member,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    _refresh();
  }

  Future<void> _openRecordPayment(Map<String, dynamic> member) async {
    // Note: RecordPaymentScreen navigates to a success screen via
    // pushReplacement, which resolves *this* push's future with null at
    // the moment of replacement (well before the user taps "Done") -- so
    // the return value here can't reliably signal "a payment was saved".
    // Refresh unconditionally instead; it's a cheap refetch and guarantees
    // Member Details never shows a stale outstanding balance.
    await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(
          controller: widget.controller,
          initialMember: {
            'eventMemberId': widget.eventMemberId,
            'pledgeId': stringFrom(member, 'pledge_id'),
            'member': member['full_name'],
            'phone': stringFrom(member, 'phone_e164'),
            'pledged': member['pledged_amount'],
            'paid': member['total_allocated'],
            'outstanding': member['outstanding_amount'],
            'effectiveDueDate': stringFrom(member, 'effective_due_date'),
          },
          suggestedAmount: numberFrom(member['outstanding_amount']),
        ),
      ),
    );
    if (!mounted) return;
    await widget.controller.refreshTenantContext();
    if (!mounted) return;
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canRemove = _hasPermission('members.assign_event');
    final canCreatePledge = _hasPermission('pledges.create');
    final canEditPledge = _hasPermission('pledges.update');
    final canRecordPayment = _hasPermission('payments.create');
    return Scaffold(
      appBar: AppBar(title: Text(context.t('eventDetail.memberDetails'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 3),
            );
          }
          final detail = snapshot.data!;
          final member = detail['member'] is Map<String, dynamic>
              ? detail['member'] as Map<String, dynamic>
              : detail;
          final memberId = stringFrom(
            member,
            'member_id',
            stringFrom(member, 'id'),
          );
          // The event-member-detail view already excludes CANCELLED pledges
          // (see v_event_members_list), so an empty pledge_id here reliably
          // means "no active pledge" -- a cancelled pledge is never treated
          // as active.
          final pledgeId = stringFrom(member, 'pledge_id');
          final hasActivePledge = pledgeId.isNotEmpty;
          final outstandingAmount =
              numberFrom(member['outstanding_amount']) ?? 0;
          final isFullyPaid = hasActivePledge && outstandingAmount <= 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                titleCaseName(member['full_name']),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                stringFrom(member, 'phone_e164', context.t('contacts.noPhone')),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 16),
              AhadiSectionCard(
                title: context.t('eventDetail.pledge'),
                children: [
                  if (!hasActivePledge) ...[
                    Text(
                      context.t('eventDetail.noPledgeForMember'),
                      style: const TextStyle(color: AhadiColors.muted),
                    ),
                    if (canCreatePledge) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _openRecordPledge(member),
                        icon: const Icon(Icons.add),
                        label: Text(context.t('pledges.recordPledge')),
                      ),
                    ],
                  ] else ...[
                    FinancialSummary(
                      pledged: member['pledged_amount'],
                      received: member['total_allocated'],
                      outstanding: member['outstanding_amount'],
                    ),
                    const SizedBox(height: 12),
                    AhadiInfoRow(
                      label: context.t('eventDetail.dueDate'),
                      value: dateText(stringFrom(member, 'due_date')),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.t('eventDetail.status'),
                            style: const TextStyle(color: AhadiColors.muted),
                          ),
                        ),
                        StatusPill(
                          status: isFullyPaid
                              ? 'PAID'
                              : stringFrom(member, 'pledge_status', 'PENDING'),
                        ),
                      ],
                    ),
                    if (canEditPledge ||
                        (!isFullyPaid && canRecordPayment)) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (canEditPledge)
                            OutlinedButton.icon(
                              onPressed: () => _openEditPledge(member),
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(context.t('pledges.editPledge')),
                            ),
                          if (!isFullyPaid && canRecordPayment)
                            FilledButton.icon(
                              onPressed: () => _openRecordPayment(member),
                              icon: const Icon(Icons.payments_outlined),
                              label: Text(
                                context.t('eventDetail.recordPayment'),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (isFullyPaid) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.t('eventDetail.paidInFull'),
                        style: const TextStyle(
                          color: AhadiColors.success,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              EventMemberInvitationSection(
                controller: widget.controller,
                event: widget.event,
                eventMemberId: widget.eventMemberId,
                memberName: stringFrom(member, 'full_name'),
              ),
              AhadiSectionCard(
                title: context.t('shell.nav.events'),
                children: [
                  Text(
                    widget.event.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${context.t('events.type.${widget.event.eventType}')} · ${dateText(widget.event.eventDate)}',
                    style: const TextStyle(color: AhadiColors.muted),
                  ),
                ],
              ),
              AhadiSectionCard(
                title: context.t('eventDetail.actions'),
                children: [
                  if (memberId.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ContactDetailScreen(
                            controller: widget.controller,
                            contact: member,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.person_outline),
                      label: Text(context.t('eventDetail.viewContact')),
                    ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: const TextStyle(color: AhadiColors.danger),
                    ),
                  ],
                  if (canRemove) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _confirmRemove(titleCaseName(member['full_name'])),
                      icon: const Icon(Icons.person_remove_outlined),
                      label: Text(context.t('eventDetail.removeFromEvent')),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmRemove(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          context
              .t('eventDetail.removeConfirmTitle')
              .replaceFirst('{name}', name)
              .replaceFirst('{event}', widget.event.name),
        ),
        content: Text(context.t('eventDetail.removeConfirmBody')),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.t('eventDetail.remove')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeEventMember(
        widget.event.id,
        widget.eventMemberId,
        reason: 'Removed from mobile',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      setState(() => error = err.toString());
    }
  }
}

class _AvailableContactPicker extends StatefulWidget {
  const _AvailableContactPicker({
    required this.controller,
    required this.event,
    required this.onDone,
  });

  final SessionController controller;
  final EventSummary event;
  final VoidCallback onDone;

  @override
  State<_AvailableContactPicker> createState() =>
      _AvailableContactPickerState();
}

class _AvailableContactPickerState extends State<_AvailableContactPicker> {
  late Future<List<Map<String, dynamic>>> future;
  String query = '';
  String? error;

  @override
  void initState() {
    super.initState();
    future = widget.controller.availableContactsForEvent(widget.event.id);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows = snapshot.data!
                .where(
                  (row) =>
                      '${row['full_name'] ?? ''} ${row['phone_e164'] ?? ''}'
                          .toLowerCase()
                          .contains(query.toLowerCase()),
                )
                .toList();
            return Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    labelText: context.t('eventDetail.searchExistingContact'),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AhadiColors.danger),
                  ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(context.t('eventDetail.noAvailableContacts')),
                  )
                else
                  ...rows
                      .take(8)
                      .map(
                        (row) => ListTile(
                          title: Text(titleCaseName(row['full_name'])),
                          subtitle: Text(
                            stringFrom(
                              row,
                              'phone_e164',
                              context.t('contacts.noPhone'),
                            ),
                          ),
                          trailing: const Icon(Icons.add),
                          onTap: () async {
                            try {
                              await widget.controller.attachEventMember(
                                widget.event.id,
                                stringFrom(row, 'member_id'),
                              );
                              widget.onDone();
                            } catch (err) {
                              setState(() => error = err.toString());
                            }
                          },
                        ),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PledgesTab extends StatefulWidget {
  const _PledgesTab({
    required this.controller,
    required this.event,
    required this.members,
    required this.pledges,
    required this.onChanged,
  });

  final SessionController controller;
  final EventSummary event;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> pledges;
  final VoidCallback onChanged;

  @override
  State<_PledgesTab> createState() => _PledgesTabState();
}

class _PledgesTabState extends State<_PledgesTab> {
  static const pageSize = 10;

  String query = '';
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.pledges.where((pledge) {
      final haystack =
          '${pledge['member_name'] ?? ''} ${pledge['full_name'] ?? ''}'
              .toLowerCase();
      return haystack.contains(query.toLowerCase());
    }).toList();
    final totalPages = filtered.isEmpty
        ? 1
        : ((filtered.length - 1) ~/ pageSize) + 1;
    final effectivePage = page >= totalPages ? totalPages - 1 : page;
    final visible = filtered.skip(effectivePage * pageSize).take(pageSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.controller.selectedTenantContext?.isOwner == true ||
            widget.controller.selectedTenantContext?.permissions.contains(
                  'pledges.create',
                ) ==
                true)
          PledgeForm(
            controller: widget.controller,
            event: widget.event,
            members: widget.members,
            onDone: widget.onChanged,
          ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            labelText: context.t('eventDetail.searchPledges'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            query = value;
            page = 0;
          }),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.t('eventDetail.noPledgesFound')),
            ),
          )
        else ...[
          ...visible.map(
            (pledge) => AhadiListRow(
              title: titleCaseName(
                pledge['member_name'] ?? pledge['full_name'],
              ),
              subtitle: stringFrom(
                pledge,
                'phone_e164',
                context.t('contacts.noPhone'),
              ),
              status: stringFrom(pledge, 'status', 'PENDING'),
              financialSummary: FinancialSummary(
                pledged: pledge['pledged_amount'],
                received: pledge['total_allocated'] ?? pledge['paid_amount'],
                outstanding: pledge['outstanding_amount'],
              ),
              meta:
                  '${context.t('eventDetail.due')} ${dateText(stringFrom(pledge, 'due_date'))}',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PledgeDetailScreen(
                    controller: widget.controller,
                    event: widget.event,
                    pledge: pledge,
                    onChanged: widget.onChanged,
                  ),
                ),
              ),
            ),
          ),
          _EventListPaginationControls(
            page: effectivePage,
            totalPages: totalPages,
            totalRows: filtered.length,
            label: context.t('shell.more.pledges').toLowerCase(),
            onPrevious: effectivePage == 0
                ? null
                : () => setState(() => page = effectivePage - 1),
            onNext: effectivePage >= totalPages - 1
                ? null
                : () => setState(() => page = effectivePage + 1),
          ),
        ],
      ],
    );
  }
}

class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab({required this.controller, required this.event});

  final SessionController controller;
  final EventSummary event;

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  static const pageSize = 10;

  final search = TextEditingController();
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  int page = 1;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.eventReport(widget.event.id, 'payments', {
      'page': page,
      'pageSize': pageSize,
      'search': search.text.trim(),
      'sort': 'DATE',
      'direction': 'DESC',
    });
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  void _searchChanged(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        page = 1;
        future = _load();
      });
    });
  }

  Future<void> _record() async {
    final recorded = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(controller: widget.controller),
      ),
    );
    if (recorded != null && mounted) await _refresh();
  }

  String _methodLabel(BuildContext context, Map<String, dynamic> payment) {
    final raw = stringFrom(
      payment,
      'paymentMethod',
      stringFrom(payment, 'payment_method'),
    );
    if (raw.isEmpty) return context.t('eventDetail.payment');
    return raw
        .replaceAll('_', ' ')
        .toLowerCase()
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final canRecord =
        widget.controller.selectedEventId == widget.event.id &&
        (widget.controller.selectedTenantContext?.isOwner == true ||
            widget.controller.selectedTenantContext?.permissions.contains(
                  'payments.create',
                ) ==
                true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canRecord)
          FilledButton.icon(
            onPressed: _record,
            icon: const Icon(Icons.add),
            label: Text(context.t('eventDetail.recordPayment')),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: search,
          decoration: InputDecoration(
            labelText: context.t('eventDetail.searchPayments'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: _searchChanged,
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LoadingCards(count: 3);
            final report = snapshot.data!;
            final rows = objectList(report['data']);
            if (rows.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.t('eventDetail.noPaymentsFound')),
                ),
              );
            }
            final pagination = objectMap(report['pagination']);
            final totalPages =
                numberFrom(pagination['totalPages'])?.round() ?? 1;
            final totalRows =
                numberFrom(pagination['totalRows'])?.round() ?? rows.length;
            return Column(
              children: [
                ...rows.map(
                  (payment) => AhadiListRow(
                    title: titleCaseName(
                      stringFrom(
                        payment,
                        'member',
                        context.t('eventDetail.member'),
                      ),
                    ),
                    subtitle:
                        '${moneyText(payment['amount'])}\n${_methodLabel(context, payment)} • ${dateText(stringFrom(payment, 'date', stringFrom(payment, 'payment_date')))}',
                    status: stringFrom(payment, 'status', 'CONFIRMED'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PaymentDetailScreen(
                          controller: widget.controller,
                          payment: payment,
                        ),
                      ),
                    ),
                  ),
                ),
                _EventListPaginationControls(
                  page: page - 1,
                  totalPages: totalPages,
                  totalRows: totalRows,
                  label: context.t('shell.nav.payments').toLowerCase(),
                  onPrevious: page <= 1
                      ? null
                      : () => setState(() {
                          page -= 1;
                          future = _load();
                        }),
                  onNext: page >= totalPages
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

class _EventListPaginationControls extends StatelessWidget {
  const _EventListPaginationControls({
    required this.page,
    required this.totalPages,
    required this.totalRows,
    required this.label,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalRows;
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (totalRows <= 10) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: context.t('common.previousPage'),
          ),
          Expanded(
            child: Text(
              '${context.t('common.page')} ${page + 1} ${context.t('common.of')} $totalPages · $totalRows $label',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: context.t('common.nextPage'),
          ),
        ],
      ),
    );
  }
}

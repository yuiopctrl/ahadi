import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../contacts/presentation/contacts_screen.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Details'),
        actions: [
          if (canEdit)
            TextButton(onPressed: _editEvent, child: const Text('Edit')),
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
                  items: const [
                    FilterTabItem(value: 0, label: 'Overview'),
                    FilterTabItem(value: 1, label: 'Members'),
                    FilterTabItem(value: 2, label: 'Pledges'),
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
                    members: data.members,
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
    targetAmount.text = widget.event.targetAmount?.round().toString() ?? '';
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
      appBar: AppBar(title: const Text('Edit Event')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Event Name'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: eventType,
            items: _eventTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.replaceAll('_', ' ')),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => eventType = value ?? 'WEDDING'),
            decoration: const InputDecoration(labelText: 'Event Type'),
          ),
          if (eventType == 'OTHER') ...[
            const SizedBox(height: 12),
            TextField(
              controller: customType,
              decoration: const InputDecoration(labelText: 'Custom Event Type'),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: eventDate,
            decoration: const InputDecoration(
              labelText: 'Event Date YYYY-MM-DD',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: venue,
            decoration: const InputDecoration(labelText: 'Venue'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: targetAmount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Target Amount'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pledgeDeadline,
            decoration: const InputDecoration(
              labelText: 'Pledge Deadline YYYY-MM-DD',
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
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving...' : 'Save Changes'),
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
            : num.tryParse(targetAmount.text.trim()),
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
              '${event.eventType} · ${dateText(event.eventDate)}',
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
                title: const Text('Status'),
                trailing: StatusPill(status: event.status),
              ),
              ListTile(
                title: const Text('Pledge deadline'),
                trailing: Text(dateText(event.pledgeDeadline)),
              ),
              ListTile(
                title: const Text('Target amount'),
                trailing: Text(moneyText(event.targetAmount)),
              ),
              ListTile(
                title: const Text('Members'),
                trailing: Text(data.members.length.toString()),
              ),
              ListTile(
                title: const Text('Pledges'),
                trailing: Text(data.pledges.length.toString()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MembersTab extends StatefulWidget {
  const _MembersTab({
    required this.controller,
    required this.event,
    required this.members,
    required this.onChanged,
  });

  final SessionController controller;
  final EventSummary event;
  final List<Map<String, dynamic>> members;
  final VoidCallback onChanged;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends State<_MembersTab> {
  static const pageSize = 10;

  bool pickerOpen = false;
  String query = '';
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final filtered = widget.members.where((member) {
      final haystack =
          '${member['full_name'] ?? ''} ${member['phone_e164'] ?? ''}'
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
                  'members.assign_event',
                ) ==
                true)
          FilledButton.icon(
            onPressed: () => setState(() => pickerOpen = !pickerOpen),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add Member'),
          ),
        if (pickerOpen)
          _AvailableContactPicker(
            controller: widget.controller,
            event: widget.event,
            onDone: () {
              setState(() => pickerOpen = false);
              widget.onChanged();
            },
          ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search members',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            query = value;
            page = 0;
          }),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No event members found.'),
            ),
          )
        else ...[
          ...visible.map(
            (member) => AhadiListRow(
              title: titleCaseName(member['full_name']),
              subtitle: stringFrom(member, 'phone_e164', 'No phone'),
              status: stringFrom(member, 'pledge_status', 'NO PLEDGE'),
              financialSummary: FinancialSummary(
                pledged: member['pledged_amount'],
                received: member['total_allocated'] ?? member['paid_amount'],
                outstanding: member['outstanding_amount'],
              ),
              meta: (numberFrom(member['pledged_amount']) ?? 0) <= 0
                  ? 'No pledge'
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EventMemberDetailScreen(
                    controller: widget.controller,
                    event: widget.event,
                    eventMemberId: stringFrom(member, 'event_member_id'),
                  ),
                ),
              ),
            ),
          ),
          _EventListPaginationControls(
            page: effectivePage,
            totalPages: totalPages,
            totalRows: filtered.length,
            label: 'members',
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

  @override
  Widget build(BuildContext context) {
    final canRemove =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'members.assign_event',
            ) ==
            true;
    return Scaffold(
      appBar: AppBar(title: const Text('Member Details')),
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
          final pledge = detail['pledge'] is Map<String, dynamic>
              ? detail['pledge'] as Map<String, dynamic>
              : member;
          final memberId = stringFrom(
            member,
            'member_id',
            stringFrom(member, 'id'),
          );
          final pledgeId = stringFrom(pledge, 'pledge_id');
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
                stringFrom(member, 'phone_e164', 'No phone'),
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 16),
              AhadiSectionCard(
                title: 'Financial Summary',
                children: [
                  FinancialSummary(
                    pledged: member['pledged_amount'],
                    received:
                        member['total_allocated'] ?? member['paid_amount'],
                    outstanding: member['outstanding_amount'],
                  ),
                ],
              ),
              AhadiSectionCard(
                title: 'Pledge',
                children: [
                  AhadiInfoRow(
                    label: 'Amount',
                    value: moneyText(pledge['pledged_amount']),
                  ),
                  AhadiInfoRow(
                    label: 'Due Date',
                    value: dateText(stringFrom(pledge, 'due_date')),
                  ),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Status',
                          style: TextStyle(color: AhadiColors.muted),
                        ),
                      ),
                      StatusPill(
                        status: stringFrom(
                          pledge,
                          'status',
                          stringFrom(member, 'pledge_status', 'NO PLEDGE'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              AhadiSectionCard(
                title: 'Event',
                children: [
                  Text(
                    widget.event.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.event.eventType} · ${dateText(widget.event.eventDate)}',
                    style: const TextStyle(color: AhadiColors.muted),
                  ),
                ],
              ),
              AhadiSectionCard(
                title: 'Actions',
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
                      label: const Text('View Contact'),
                    ),
                  if (pledgeId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PledgeDetailScreen(
                            controller: widget.controller,
                            event: widget.event,
                            pledge: {
                              ...pledge,
                              'event_member_id': widget.eventMemberId,
                              'member_name': member['full_name'],
                              'phone_e164': member['phone_e164'],
                            },
                            onChanged: () => setState(
                              () =>
                                  future = widget.controller.eventMemberDetail(
                                    widget.event.id,
                                    widget.eventMemberId,
                                  ),
                            ),
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('View / Edit Pledge'),
                    ),
                  ],
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
                      label: const Text('Remove from Event'),
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
        title: Text('Remove $name from ${widget.event.name}?'),
        content: const Text('This removes the contact from this event only.'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
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
                  decoration: const InputDecoration(
                    labelText: 'Search existing contact',
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: AhadiColors.danger),
                  ),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No available contacts found.'),
                  )
                else
                  ...rows
                      .take(8)
                      .map(
                        (row) => ListTile(
                          title: Text(titleCaseName(row['full_name'])),
                          subtitle: Text(
                            stringFrom(row, 'phone_e164', 'No phone'),
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
          decoration: const InputDecoration(
            labelText: 'Search pledges',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() {
            query = value;
            page = 0;
          }),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No pledges found for this event.'),
            ),
          )
        else ...[
          ...visible.map(
            (pledge) => AhadiListRow(
              title: titleCaseName(
                pledge['member_name'] ?? pledge['full_name'],
              ),
              subtitle: stringFrom(pledge, 'phone_e164', 'No phone'),
              status: stringFrom(pledge, 'status', 'PENDING'),
              financialSummary: FinancialSummary(
                pledged: pledge['pledged_amount'],
                received: pledge['total_allocated'] ?? pledge['paid_amount'],
                outstanding: pledge['outstanding_amount'],
              ),
              meta: 'Due ${dateText(stringFrom(pledge, 'due_date'))}',
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
            label: 'pledges',
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
            tooltip: 'Previous page',
          ),
          Expanded(
            child: Text(
              'Page ${page + 1} of $totalPages · $totalRows $label',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import 'pledge_form.dart';

class PledgesScreen extends StatefulWidget {
  const PledgesScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PledgesScreen> createState() => _PledgesScreenState();
}

class _PledgesScreenState extends State<PledgesScreen> {
  static const pageSize = 20;

  late Future<_PledgeScreenData> future;
  String? loadedEventId;
  String filter = 'ALL';
  String query = '';
  int page = 0;

  @override
  void initState() {
    super.initState();
    loadedEventId = widget.controller.selectedEventId;
    future = _load();
  }

  Future<_PledgeScreenData> _load() async {
    final event = widget.controller.selectedEvent;
    if (event == null) {
      return const _PledgeScreenData(members: [], pledges: []);
    }
    final results = await Future.wait([
      widget.controller
          .eventMembers(event.id)
          .catchError((_) => <Map<String, dynamic>>[]),
      widget.controller
          .eventPledges(
            event.id,
            search: query,
            status: filter,
            limit: pageSize + 1,
            offset: page * pageSize,
          )
          .catchError((_) => <Map<String, dynamic>>[]),
    ]);
    return _PledgeScreenData(members: results[0], pledges: results[1]);
  }

  void _reload() {
    setState(() => future = _load());
  }

  @override
  Widget build(BuildContext context) {
    if (loadedEventId != widget.controller.selectedEventId) {
      loadedEventId = widget.controller.selectedEventId;
      future = _load();
    }
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: Text(context.t('shell.more.pledges'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.controller.selectedEvent?.name ?? context.t('common.noEventSelected'),
            style: const TextStyle(color: AhadiColors.muted),
          ),
          const SizedBox(height: 12),
          FilterTabs<String>(
            items: [
              FilterTabItem(value: 'ALL', label: context.t('common.all')),
              FilterTabItem(value: 'PENDING', label: context.t('pledges.unpaid')),
              FilterTabItem(value: 'PARTIALLY_PAID', label: context.t('pledges.partial')),
              FilterTabItem(value: 'PAID', label: context.t('pledges.done')),
            ],
            selected: filter,
            onChanged: (value) => setState(() {
              filter = value;
              page = 0;
              future = _load();
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              labelText: context.t('eventDetail.searchPledges'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() {
              query = value;
              page = 0;
              future = _load();
            }),
          ),
          const SizedBox(height: 12),
          FutureBuilder<_PledgeScreenData>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LoadingCards(count: 3);
              final data = snapshot.data!;
              final event = widget.controller.selectedEvent;
              final filtered = data.pledges
                  .where(_matchesCurrentFilter)
                  .toList();
              final visible = filtered.take(pageSize).toList();
              final hasNext = filtered.length > pageSize;
              if (event == null) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(context.t('pledges.noEventAvailable')),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.controller.selectedTenantContext?.isOwner ==
                          true ||
                      widget.controller.selectedTenantContext?.permissions
                              .contains('pledges.create') ==
                          true)
                    PledgeForm(
                      controller: widget.controller,
                      event: event,
                      members: data.members,
                      onDone: _reload,
                    ),
                  const SizedBox(height: 12),
                  if (visible.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.t('pledges.noneForFilter'),
                        ),
                      ),
                    )
                  else ...[
                    ...visible.map(
                      (pledge) => AhadiListRow(
                        title: titleCaseName(
                          pledge['member_name'] ?? pledge['full_name'],
                        ),
                        subtitle: stringFrom(pledge, 'phone_e164', context.t('contacts.noPhone')),
                        status: stringFrom(pledge, 'status', 'PENDING'),
                        financialSummary: FinancialSummary(
                          pledged: pledge['pledged_amount'],
                          received:
                              pledge['total_allocated'] ??
                              pledge['paid_amount'],
                          outstanding: pledge['outstanding_amount'],
                        ),
                        meta: '${context.t('eventDetail.due')} ${dateText(stringFrom(pledge, 'due_date'))}',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PledgeDetailScreen(
                              controller: widget.controller,
                              event: event,
                              pledge: pledge,
                              onChanged: _reload,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _PledgePaginationControls(
                      page: page,
                      hasNext: hasNext,
                      onPrevious: page == 0
                          ? null
                          : () => setState(() {
                              page -= 1;
                              future = _load();
                            }),
                      onNext: !hasNext
                          ? null
                          : () => setState(() {
                              page += 1;
                              future = _load();
                            }),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool _matchesCurrentFilter(Map<String, dynamic> pledge) {
    final status = _normalizedPledgeStatus(
      stringFrom(
        pledge,
        'status',
        stringFrom(pledge, 'pledge_status', stringFrom(pledge, 'pledgeStatus')),
      ),
    );
    final statusMatches = filter == 'ALL' || status == filter;
    if (!statusMatches) return false;
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    final haystack =
        '${pledge['member_name'] ?? ''} ${pledge['full_name'] ?? ''} ${pledge['phone_e164'] ?? ''}'
            .toLowerCase();
    return haystack.contains(normalizedQuery);
  }
}

String _normalizedPledgeStatus(String value) {
  final status = value.trim().toUpperCase();
  if (status == 'UNPAID') return 'PENDING';
  if (status == 'PARTIAL') return 'PARTIALLY_PAID';
  if (status == 'DONE') return 'PAID';
  return status;
}

class _PledgePaginationControls extends StatelessWidget {
  const _PledgePaginationControls({
    required this.page,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (page == 0 && !hasNext) return const SizedBox();
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
              '${context.t('common.page')} ${page + 1}',
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

class PledgeDetailScreen extends StatefulWidget {
  const PledgeDetailScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.pledge,
    required this.onChanged,
  });

  final SessionController controller;
  final dynamic event;
  final Map<String, dynamic> pledge;
  final VoidCallback onChanged;

  @override
  State<PledgeDetailScreen> createState() => _PledgeDetailScreenState();
}

class _PledgeDetailScreenState extends State<PledgeDetailScreen> {
  late Map<String, dynamic> pledge;

  @override
  void initState() {
    super.initState();
    pledge = Map<String, dynamic>.from(widget.pledge);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'pledges.update',
            ) ==
            true;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        title: Text(context.t('pledges.pledgeDetails')),
        actions: [
          if (canEdit)
            TextButton(onPressed: _openEdit, child: Text(context.t('common.edit'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            titleCaseName(pledge['member_name'] ?? pledge['full_name']),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            widget.event.name,
            style: const TextStyle(color: AhadiColors.muted),
          ),
          const SizedBox(height: 16),
          AhadiSectionCard(
            title: context.t('eventDetail.financialSummary'),
            children: [
              FinancialSummary(
                pledged: pledge['pledged_amount'],
                received: pledge['total_allocated'] ?? pledge['paid_amount'],
                outstanding: pledge['outstanding_amount'],
              ),
            ],
          ),
          AhadiSectionCard(
            title: context.t('pledges.pledgeDetails'),
            children: [
              AhadiInfoRow(
                label: context.t('eventDetail.dueDate'),
                value: dateText(stringFrom(pledge, 'due_date')),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t('eventDetail.status'),
                      style: const TextStyle(color: AhadiColors.muted),
                    ),
                  ),
                  StatusPill(status: stringFrom(pledge, 'status', 'PENDING')),
                ],
              ),
              AhadiInfoRow(
                label: context.t('pledges.created'),
                value: dateText(
                  stringFrom(
                    pledge,
                    'created_at',
                    stringFrom(pledge, 'createdAt'),
                  ),
                ),
              ),
            ],
          ),
          if (canEdit)
            AhadiSectionCard(
              title: context.t('eventDetail.actions'),
              children: [
                OutlinedButton.icon(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(context.t('pledges.editPledge')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => EditPledgeScreen(
          controller: widget.controller,
          event: widget.event,
          pledge: pledge,
        ),
      ),
    );
    if (updated == null) return;
    setState(() => pledge = updated);
    widget.onChanged();
  }
}

class EditPledgeScreen extends StatefulWidget {
  const EditPledgeScreen({
    super.key,
    required this.controller,
    required this.event,
    required this.pledge,
  });

  final SessionController controller;
  final dynamic event;
  final Map<String, dynamic> pledge;

  @override
  State<EditPledgeScreen> createState() => _EditPledgeScreenState();
}

class _EditPledgeScreenState extends State<EditPledgeScreen> {
  late final TextEditingController amount;
  late final TextEditingController dueDate;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
      text: moneyInputText(widget.pledge['pledged_amount']),
    );
    dueDate = TextEditingController(
      text: stringFrom(widget.pledge, 'due_date'),
    );
  }

  @override
  void dispose() {
    amount.dispose();
    dueDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: Text(context.t('pledges.editPledge'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: const [MoneyInputFormatter()],
            decoration: InputDecoration(
              labelText: context.t('pledges.pledgeAmount'),
              prefixText: 'TZS ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: dueDate,
            decoration: InputDecoration(labelText: context.t('pledges.dueDateFormat')),
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
                  child: Text(saving ? context.t('auth.saving') : context.t('common.save')),
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
      final updatedAmount = moneyInputValue(amount.text) ?? 0;
      await widget.controller.upsertPledge(widget.event.id, {
        'eventMemberId': stringFrom(widget.pledge, 'event_member_id'),
        'amount': updatedAmount,
        'dueDate': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
        'notes': null,
        'changeReason': 'Updated from mobile',
      }, pledgeId: stringFrom(widget.pledge, 'pledge_id'));
      if (mounted) {
        Navigator.of(context).pop({
          ...widget.pledge,
          'pledged_amount': updatedAmount,
          'due_date': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
        });
      }
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _PledgeScreenData {
  const _PledgeScreenData({required this.members, required this.pledges});

  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> pledges;
}

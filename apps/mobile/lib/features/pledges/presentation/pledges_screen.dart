import 'package:flutter/material.dart';

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
  static const pageSize = 10;

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
          .eventPledges(event.id)
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Pledges',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          widget.controller.selectedEvent?.name ?? 'No event selected',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        FilterTabs<String>(
          items: const [
            FilterTabItem(value: 'ALL', label: 'All'),
            FilterTabItem(value: 'PENDING', label: 'Unpaid'),
            FilterTabItem(value: 'PARTIALLY_PAID', label: 'Partial'),
            FilterTabItem(value: 'PAID', label: 'Done'),
          ],
          selected: filter,
          onChanged: (value) => setState(() {
            filter = value;
            page = 0;
          }),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        FutureBuilder<_PledgeScreenData>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LoadingCards(count: 3);
            final data = snapshot.data!;
            final event = widget.controller.selectedEvent;
            final pledges = data.pledges
                .where(
                  (pledge) =>
                      filter == 'ALL' || stringFrom(pledge, 'status') == filter,
                )
                .where((pledge) {
                  final haystack =
                      '${pledge['member_name'] ?? ''} ${pledge['full_name'] ?? ''}'
                          .toLowerCase();
                  return haystack.contains(query.toLowerCase());
                })
                .toList();
            final totalPages = pledges.isEmpty
                ? 1
                : ((pledges.length - 1) ~/ pageSize) + 1;
            final effectivePage = page >= totalPages ? totalPages - 1 : page;
            final visible = pledges
                .skip(effectivePage * pageSize)
                .take(pageSize)
                .toList();
            if (event == null) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No event is available for pledges.'),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.controller.selectedTenantContext?.isOwner == true ||
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
                if (pledges.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No pledges found for this event and filter.',
                      ),
                    ),
                  )
                else ...[
                  ...visible.map(
                    (pledge) => Card(
                      child: ListTile(
                        title: Text(
                          titleCaseName(
                            pledge['member_name'] ?? pledge['full_name'],
                          ),
                        ),
                        subtitle: Text(
                          '${moneyText(pledge['pledged_amount'])} pledged · ${moneyText(pledge['total_allocated'])} paid\n${moneyText(pledge['outstanding_amount'])} outstanding',
                        ),
                        isThreeLine: true,
                        trailing: StatusPill(
                          status: stringFrom(pledge, 'status', 'PENDING'),
                        ),
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
                  ),
                  _PledgePaginationControls(
                    page: effectivePage,
                    totalPages: totalPages,
                    totalRows: pledges.length,
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
          },
        ),
      ],
    );
  }
}

class _PledgePaginationControls extends StatelessWidget {
  const _PledgePaginationControls({
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
    if (totalRows <= _PledgesScreenState.pageSize) return const SizedBox();
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
              'Page ${page + 1} of $totalPages · $totalRows pledges',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
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
  bool editing = false;
  late final TextEditingController amount;
  late final TextEditingController dueDate;
  String? error;

  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
      text: '${numberFrom(widget.pledge['pledged_amount'])?.round() ?? ''}',
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
    final canEdit =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'pledges.update',
            ) ==
            true;
    return Scaffold(
      appBar: AppBar(title: const Text('Pledge Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Member'),
                  subtitle: Text(
                    titleCaseName(
                      widget.pledge['member_name'] ??
                          widget.pledge['full_name'],
                    ),
                  ),
                ),
                ListTile(
                  title: const Text('Event'),
                  subtitle: Text(widget.event.name),
                ),
                ListTile(
                  title: const Text('Pledged'),
                  trailing: Text(moneyText(widget.pledge['pledged_amount'])),
                ),
                ListTile(
                  title: const Text('Paid'),
                  trailing: Text(moneyText(widget.pledge['total_allocated'])),
                ),
                ListTile(
                  title: const Text('Outstanding'),
                  trailing: Text(
                    moneyText(widget.pledge['outstanding_amount']),
                  ),
                ),
                ListTile(
                  title: const Text('Due date'),
                  trailing: Text(
                    dateText(stringFrom(widget.pledge, 'due_date')),
                  ),
                ),
                ListTile(
                  title: const Text('Status'),
                  trailing: StatusPill(
                    status: stringFrom(widget.pledge, 'status', 'PENDING'),
                  ),
                ),
              ],
            ),
          ),
          if (canEdit && !editing) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => setState(() => editing = true),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          ],
          if (editing) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Amount'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dueDate,
                      decoration: const InputDecoration(
                        labelText: 'Due Date YYYY-MM-DD',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => editing = false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _save,
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    try {
      await widget.controller.upsertPledge(widget.event.id, {
        'eventMemberId': stringFrom(widget.pledge, 'event_member_id'),
        'amount': num.tryParse(amount.text.trim()) ?? 0,
        'dueDate': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
        'notes': null,
        'changeReason': 'Updated from mobile',
      }, pledgeId: stringFrom(widget.pledge, 'pledge_id'));
      widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      setState(() => error = err.toString());
    }
  }
}

class _PledgeScreenData {
  const _PledgeScreenData({required this.members, required this.pledges});

  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> pledges;
}

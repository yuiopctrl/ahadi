import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../financial/presentation/financial_screens.dart';

const _reportPageSize = 20;

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final event = controller.selectedEvent;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ReportsHeader(event: event),
          const SizedBox(height: 16),
          _ReportSection(
            title: 'Event Reports',
            children: [
              _ReportTile(
                icon: Icons.query_stats_outlined,
                title: 'Financial Summary',
                subtitle: 'Pledged, received, outstanding and collection rate',
                enabled: event != null,
                onTap: () => _open(
                  context,
                  FinancialSummaryReportScreen(controller: controller),
                ),
              ),
              _ReportTile(
                icon: Icons.volunteer_activism_outlined,
                title: 'Pledges',
                subtitle: 'Member pledge rows with paid and outstanding totals',
                enabled: event != null,
                onTap: () =>
                    _open(context, PledgeReportScreen(controller: controller)),
              ),
              _ReportTile(
                icon: Icons.payments_outlined,
                title: 'Payments',
                subtitle: 'Recorded payments and receipt references',
                enabled: event != null,
                onTap: () => _open(
                  context,
                  PaymentsScreen(
                    controller: controller,
                    appBar: AppBar(title: const Text('Payments Report')),
                  ),
                ),
              ),
              _ReportTile(
                icon: Icons.trending_down_outlined,
                title: 'Outstanding',
                subtitle: 'Members with unpaid balances',
                enabled: event != null,
                onTap: () =>
                    _open(context, OutstandingScreen(controller: controller)),
              ),
              _ReportTile(
                icon: Icons.receipt_long_outlined,
                title: 'Receipts',
                subtitle: 'Receipt history including reversed receipts',
                enabled: event != null,
                onTap: () =>
                    _open(context, ReceiptsScreen(controller: controller)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ReportSection(
            title: 'Organization Reports',
            children: [
              _ReportTile(
                icon: Icons.event_note_outlined,
                title: 'Events Summary',
                subtitle:
                    'Server-provided event totals across this organization',
                enabled: controller.selectedTenantContext != null,
                onTap: () => _open(
                  context,
                  EventsSummaryReportScreen(controller: controller),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class FinancialSummaryReportScreen extends StatefulWidget {
  const FinancialSummaryReportScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<FinancialSummaryReportScreen> createState() =>
      _FinancialSummaryReportScreenState();
}

class _FinancialSummaryReportScreenState
    extends State<FinancialSummaryReportScreen> {
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;

  @override
  void initState() {
    super.initState();
    loadedEventId = widget.controller.selectedEventId;
    widget.controller.addListener(_controllerChanged);
    future = _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted || loadedEventId == widget.controller.selectedEventId) return;
    setState(() {
      loadedEventId = widget.controller.selectedEventId;
      future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() {
    final event = widget.controller.selectedEvent;
    if (event == null) return Future.value(<String, dynamic>{});
    return widget.controller.eventFinancialSummary(event.id);
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.selectedEvent;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Financial Summary')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EventHeader(title: 'Financial Summary', event: event),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _LoadingCard();
                }
                if (snapshot.hasError) {
                  return _ErrorCard(
                    message: friendlyErrorText(snapshot.error),
                    onRetry: _refresh,
                  );
                }
                final summary = snapshot.data ?? const <String, dynamic>{};
                final pledged =
                    numberFrom(
                      summary['totalPledged'] ?? event?.totalPledged,
                    ) ??
                    0;
                final received =
                    numberFrom(
                      summary['totalReceived'] ??
                          summary['totalAllocated'] ??
                          summary['totalAllocatedToPledges'] ??
                          event?.totalCollected,
                    ) ??
                    0;
                final outstanding =
                    numberFrom(
                      summary['totalOutstanding'] ?? event?.totalOutstanding,
                    ) ??
                    0;
                final rate = pledged > 0 ? (received / pledged) * 100 : 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _EventMetaCard(event: event),
                    const SizedBox(height: 12),
                    _MetricGrid(
                      metrics: [
                        _Metric('Total Pledged', moneyText(pledged)),
                        _Metric('Received', moneyText(received)),
                        _Metric('Outstanding', moneyText(outstanding)),
                        _Metric('Collection Rate', '${rate.round()}%'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _MetricGrid(
                      metrics: [
                        _Metric(
                          'Members',
                          '${numberFrom(summary['memberCount'] ?? event?.memberCount)?.round() ?? 0}',
                        ),
                        _Metric(
                          'With Pledge',
                          '${numberFrom(summary['membersWithPledges'])?.round() ?? 0}',
                        ),
                        _Metric(
                          'Without Pledge',
                          '${numberFrom(summary['membersWithoutPledges'])?.round() ?? 0}',
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class PledgeReportScreen extends StatefulWidget {
  const PledgeReportScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PledgeReportScreen> createState() => _PledgeReportScreenState();
}

class _PledgeReportScreenState extends State<PledgeReportScreen> {
  final search = TextEditingController();
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;
  int page = 1;
  String sort = 'MEMBER';
  String direction = 'ASC';

  @override
  void initState() {
    super.initState();
    loadedEventId = widget.controller.selectedEventId;
    widget.controller.addListener(_controllerChanged);
    future = _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted || loadedEventId == widget.controller.selectedEventId) return;
    setState(() {
      loadedEventId = widget.controller.selectedEventId;
      page = 1;
      search.clear();
      future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() {
    final event = widget.controller.selectedEvent;
    if (event == null) return Future.value(_emptyReport());
    return widget.controller.eventReport(event.id, 'pledges', {
      'page': page,
      'pageSize': _reportPageSize,
      'search': search.text.trim(),
      'sort': sort,
      'direction': direction,
      'status': 'ALL',
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

  Future<void> _chooseSort() async {
    final choice = await showModalBottomSheet<List<String>>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SortOption('Member A-Z', 'MEMBER', 'ASC'),
            _SortOption('Highest Pledged', 'PLEDGED', 'DESC'),
            _SortOption('Highest Outstanding', 'OUTSTANDING', 'DESC'),
            _SortOption('Due Date', 'DUE_DATE', 'ASC'),
          ],
        ),
      ),
    );
    if (choice == null) return;
    setState(() {
      sort = choice[0];
      direction = choice[1];
      page = 1;
      future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.selectedEvent;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Pledges Report')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EventHeader(title: 'Pledges', event: event),
            const SizedBox(height: 12),
            TextField(
              key: const Key('reports-pledges-search'),
              controller: search,
              onChanged: _searchChanged,
              decoration: const InputDecoration(
                labelText: 'Search name or phone',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _chooseSort,
              icon: const Icon(Icons.sort),
              label: Text(_sortLabel(sort, direction)),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _LoadingCard();
                }
                if (snapshot.hasError) {
                  return _ErrorCard(
                    message: friendlyErrorText(snapshot.error),
                    onRetry: _refresh,
                  );
                }
                final report = snapshot.data ?? _emptyReport();
                final summary = _jsonMap(report['summary']);
                final rows = _objectList(report['data']);
                if (rows.isEmpty) return const _EmptyCard('No pledges found.');
                return Column(
                  children: [
                    _MetricGrid(
                      metrics: [
                        _Metric(
                          'Pledges',
                          '${numberFrom(summary['pledgeCount'])?.round() ?? rows.length}',
                        ),
                        _Metric('Pledged', moneyText(summary['totalPledged'])),
                        _Metric('Paid', moneyText(summary['totalPaid'])),
                        _Metric(
                          'Outstanding',
                          moneyText(summary['totalOutstanding']),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final pledge in rows) ...[
                      _PledgeReportCard(pledge: pledge),
                      const SizedBox(height: 8),
                    ],
                    _PaginationControls(
                      page: page,
                      pagination: _jsonMap(report['pagination']),
                      onPrevious: page > 1
                          ? () {
                              setState(() {
                                page -= 1;
                                future = _load();
                              });
                            }
                          : null,
                      onNext: _hasNext(report)
                          ? () {
                              setState(() {
                                page += 1;
                                future = _load();
                              });
                            }
                          : null,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class EventsSummaryReportScreen extends StatelessWidget {
  const EventsSummaryReportScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final events = controller.selectedTenantContext?.events ?? const [];
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Events Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Events Summary',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            controller.selectedTenantContext?.tenantName ?? 'Organization',
            style: const TextStyle(color: AhadiColors.muted),
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            const _EmptyCard('No events available for this organization.')
          else
            for (final event in events) ...[
              _EventSummaryReportCard(event: event),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _ReportsHeader extends StatelessWidget {
  const _ReportsHeader({required this.event});

  final EventSummary? event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reports',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          event == null
              ? 'Select an event to open event reports.'
              : 'Selected event: ${event!.name}',
          style: const TextStyle(color: AhadiColors.muted),
        ),
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(title.toUpperCase(), style: AhadiTypography.label),
            ),
            for (var i = 0; i < children.length; i += 1) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: _ReportIcon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: enabled ? onTap : null,
    );
  }
}

class _ReportIcon extends StatelessWidget {
  const _ReportIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AhadiColors.border),
      ),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 20, color: AhadiColors.primary),
      ),
    );
  }
}

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.title, required this.event});

  final String title;
  final EventSummary? event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          event?.name ?? 'No event selected',
          style: const TextStyle(color: AhadiColors.muted),
        ),
      ],
    );
  }
}

class _EventMetaCard extends StatelessWidget {
  const _EventMetaCard({required this.event});

  final EventSummary? event;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _InfoLine(label: 'Event Name', value: event?.name ?? 'Not set'),
            _InfoLine(label: 'Status', value: event?.status ?? 'Not set'),
            _InfoLine(label: 'Event Date', value: dateText(event?.eventDate)),
            _InfoLine(
              label: 'Pledge Deadline',
              value: dateText(event?.pledgeDeadline),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value);

  final String label;
  final String value;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.65,
      children: metrics
          .map(
            (metric) => _MetricCard(label: metric.label, value: metric.value),
          )
          .toList(),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AhadiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(color: AhadiColors.muted)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PledgeReportCard extends StatelessWidget {
  const _PledgeReportCard({required this.pledge});

  final Map<String, dynamic> pledge;

  @override
  Widget build(BuildContext context) {
    final status = _text(pledge, ['status', 'pledgeStatus'], 'PENDING');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    titleCaseName(_text(pledge, ['member', 'memberName'])),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _text(pledge, ['phone'], 'No phone'),
              style: const TextStyle(color: AhadiColors.muted),
            ),
            const SizedBox(height: 10),
            _ThreeAmounts(
              pledged: pledge['pledged'],
              paid: pledge['paid'],
              outstanding: pledge['outstanding'],
            ),
            const SizedBox(height: 8),
            Text(
              'Due ${dateText(_text(pledge, ['effectiveDueDate', 'dueDate']))}',
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventSummaryReportCard extends StatelessWidget {
  const _EventSummaryReportCard({required this.event});

  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final pledged = event.totalPledged ?? 0;
    final received = event.totalCollected ?? 0;
    final outstanding = event.totalOutstanding ?? 0;
    final rate = pledged > 0 ? ((received / pledged) * 100).round() : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(status: event.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${event.memberCount ?? 0} members • Collection $rate%',
              style: const TextStyle(color: AhadiColors.muted),
            ),
            const SizedBox(height: 10),
            _ThreeAmounts(
              pledged: pledged,
              paid: received,
              outstanding: outstanding,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreeAmounts extends StatelessWidget {
  const _ThreeAmounts({
    required this.pledged,
    required this.paid,
    required this.outstanding,
  });

  final Object? pledged;
  final Object? paid;
  final Object? outstanding;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TinyAmount(label: 'Pledged', value: pledged),
        ),
        Expanded(
          child: _TinyAmount(label: 'Paid', value: paid),
        ),
        Expanded(
          child: _TinyAmount(label: 'Outstanding', value: outstanding),
        ),
      ],
    );
  }
}

class _TinyAmount extends StatelessWidget {
  const _TinyAmount({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AhadiColors.muted, fontSize: 12),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            moneyText(value),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.page,
    required this.pagination,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final Map<String, dynamic> pagination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (onPrevious == null && onNext == null) return const SizedBox();
    final totalPages = numberFrom(pagination['totalPages']);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: onPrevious,
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              totalPages == null
                  ? 'Page $page'
                  : 'Page $page of ${totalPages.round()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            onPressed: onNext,
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption(this.label, this.sort, this.direction);

  final String label;
  final String sort;
  final String direction;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.of(context).pop([sort, direction]),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message, style: const TextStyle(color: AhadiColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

Map<String, dynamic> _emptyReport() => {
  'data': <Map<String, dynamic>>[],
  'summary': <String, dynamic>{},
  'pagination': {
    'page': 1,
    'pageSize': _reportPageSize,
    'totalRows': 0,
    'totalPages': 0,
  },
};

bool _hasNext(Map<String, dynamic> report) {
  final pagination = _jsonMap(report['pagination']);
  final currentPage = numberFrom(pagination['page']) ?? 1;
  final totalPages = numberFrom(pagination['totalPages']);
  if (totalPages != null) return currentPage < totalPages;
  return _objectList(report['data']).length >= _reportPageSize;
}

String _sortLabel(String sort, String direction) {
  if (sort == 'PLEDGED') return 'Highest Pledged';
  if (sort == 'OUTSTANDING') return 'Highest Outstanding';
  if (sort == 'DUE_DATE') return 'Due Date';
  return direction == 'DESC' ? 'Member Z-A' : 'Member A-Z';
}

String _text(
  Map<String, dynamic> row,
  List<String> keys, [
  String fallback = '',
]) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return fallback;
}

List<Map<String, dynamic>> _objectList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> _jsonMap(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

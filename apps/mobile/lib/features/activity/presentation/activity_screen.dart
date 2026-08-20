import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';

const _actionLabels = <String, String>{
  'contact.created': 'Contact added',
  'contact.updated': 'Contact edited',
  'contact.archived': 'Contact archived',
  'contact.reactivated': 'Contact reactivated',
  'member.created': 'Member added',
  'event_member.attached': 'Contact added to event',
  'event_member.removed': 'Member removed from event',
  'pledge.upserted': 'Pledge updated',
  'pledge.cancelled': 'Pledge cancelled',
  'payment.recorded': 'Payment recorded',
  'payment.reversed': 'Payment reversed',
  'event.created': 'Event created',
  'user.invited': 'User invited',
  'user.role_changed': 'User role changed',
};

String activityActionLabel(String action) {
  return _actionLabels[action] ??
      action
          .replaceAll('.', ' ')
          .replaceAll('_', ' ')
          .split(' ')
          .where((part) => part.isNotEmpty)
          .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
}

const _fieldLabels = <String, String>{
  'full_name': 'Full Name',
  'phone_e164': 'Phone',
  'alternative_phone_e164': 'Alternative Phone',
  'email': 'Email',
  'location': 'Location',
  'notes': 'Notes',
  'status': 'Status',
  'sms_enabled': 'SMS Enabled',
  'preferred_language': 'Preferred Language',
  'pledged_amount': 'Pledge Amount',
  'payment_method': 'Payment Method',
};

String activityFieldLabel(String key) {
  final mapped = _fieldLabels[key];
  if (mapped != null) return mapped;
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _activityValueText(Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Yes' : 'No';
  final text = value.toString().trim();
  return text.isEmpty ? '—' : text;
}

String activityDateTimeText(String? value) {
  if (value == null || value.isEmpty) return 'Not set';
  final parsed = DateTime.tryParse(value)?.toLocal();
  if (parsed == null) return value;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = parsed.hour.toString().padLeft(2, '0');
  final minute = parsed.minute.toString().padLeft(2, '0');
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}, $hour:$minute';
}

class _EntityTypeFilter {
  static const all = '';
  static const member = 'member';
  static const payment = 'payment';
  static const pledge = 'pledge';
  static const event = 'event';
  static const tenantUser = 'tenant_user';
}

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const pageSize = 20;

  late Future<Map<String, dynamic>> future;
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  String entityType = _EntityTypeFilter.all;
  int offset = 0;

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
    return widget.controller.activity(
      search: query,
      entityType: entityType.isEmpty ? null : entityType,
      limit: pageSize,
      offset: offset,
    );
  }

  void _onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          query = value;
          offset = 0;
          future = _load();
        });
      }
    });
  }

  void _onEntityTypeChanged(String value) {
    setState(() {
      entityType = value;
      offset = 0;
      future = _load();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      offset = 0;
      future = _load();
    });
    await future;
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ActivityDetailScreen(row: row)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Activity')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            final envelope = snapshot.data;
            final rows = envelope != null && envelope['data'] is List
                ? (envelope['data'] as List)
                      .whereType<Map<String, dynamic>>()
                      .toList()
                : <Map<String, dynamic>>[];
            final pagination = envelope != null && envelope['pagination'] is Map
                ? Map<String, dynamic>.from(envelope['pagination'] as Map)
                : const <String, dynamic>{};
            final hasMore = pagination['hasMore'] == true;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AhadiSearchField(
                  controller: search,
                  onChanged: _onSearch,
                  label: 'Search activity',
                ),
                const SizedBox(height: 12),
                FilterTabs<String>(
                  selected: entityType,
                  onChanged: _onEntityTypeChanged,
                  items: const [
                    FilterTabItem(value: _EntityTypeFilter.all, label: 'All'),
                    FilterTabItem(
                      value: _EntityTypeFilter.member,
                      label: 'Contacts',
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.payment,
                      label: 'Payments',
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.pledge,
                      label: 'Pledges',
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.event,
                      label: 'Events',
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.tenantUser,
                      label: 'Users',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData)
                  const LoadingCards(count: 4)
                else if (snapshot.hasError)
                  ErrorPanel(
                    message: friendlyErrorText(
                      snapshot.error,
                      'Unable to load activity. Please try again.',
                    ),
                    onRetry: () => setState(() => future = _load()),
                  )
                else if (rows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No activity yet.'),
                    ),
                  )
                else ...[
                  ...rows.map(
                    (row) =>
                        _ActivityRow(row: row, onTap: () => _openDetail(row)),
                  ),
                  _ActivityPaginationControls(
                    page: offset ~/ pageSize,
                    hasNext: hasMore,
                    onPrevious: offset == 0
                        ? null
                        : () => setState(() {
                            offset = (offset - pageSize).clamp(0, offset);
                            future = _load();
                          }),
                    onNext: !hasMore
                        ? null
                        : () => setState(() {
                            offset += pageSize;
                            future = _load();
                          }),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final action = stringFrom(row, 'action');
    final actorName = stringFrom(row, 'actor_name', 'Unknown user');
    final entityLabel = _subjectLabel(row);
    return AhadiListRow(
      title: actorName,
      subtitle: entityLabel.isEmpty
          ? activityActionLabel(action)
          : '${activityActionLabel(action)}: $entityLabel',
      meta: activityDateTimeText(stringFrom(row, 'created_at')),
      onTap: onTap,
    );
  }
}

String _subjectLabel(Map<String, dynamic> row) {
  final newValues = row['new_values'] is Map
      ? Map<String, dynamic>.from(row['new_values'] as Map)
      : const <String, dynamic>{};
  final oldValues = row['old_values'] is Map
      ? Map<String, dynamic>.from(row['old_values'] as Map)
      : const <String, dynamic>{};
  final name = newValues['full_name'] ?? oldValues['full_name'];
  if (name is String && name.trim().isNotEmpty) return titleCaseName(name);
  final eventName = stringFrom(row, 'event_name');
  return eventName;
}

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final action = stringFrom(row, 'action');
    final newValues = row['new_values'] is Map
        ? Map<String, dynamic>.from(row['new_values'] as Map)
        : const <String, dynamic>{};
    final oldValues = row['old_values'] is Map
        ? Map<String, dynamic>.from(row['old_values'] as Map)
        : const <String, dynamic>{};
    final changedKeys = <String>{...oldValues.keys, ...newValues.keys}.toList()
      ..sort();
    final reason = stringFrom(row, 'reason');
    final eventName = stringFrom(row, 'event_name');

    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Activity Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            activityActionLabel(action),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          AhadiSectionCard(
            title: 'Details',
            children: [
              AhadiInfoRow(
                label: 'Actor',
                value: stringFrom(row, 'actor_name', 'Unknown user'),
              ),
              AhadiInfoRow(
                label: 'Date & Time',
                value: activityDateTimeText(stringFrom(row, 'created_at')),
              ),
              AhadiInfoRow(label: 'Action', value: activityActionLabel(action)),
              AhadiInfoRow(
                label: 'Entity',
                value: activityFieldLabel(stringFrom(row, 'entity_type')),
              ),
              if (eventName.isNotEmpty)
                AhadiInfoRow(label: 'Event', value: eventName),
              if (reason.isNotEmpty)
                AhadiInfoRow(label: 'Reason', value: reason),
            ],
          ),
          if (changedKeys.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Changes',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            AhadiSectionCard(
              children: [
                for (final key in changedKeys) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activityFieldLabel(key),
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(_activityValueText(oldValues[key])),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 16,
                                color: AhadiColors.muted,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _activityValueText(newValues[key]),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (key != changedKeys.last) const Divider(height: 1),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActivityPaginationControls extends StatelessWidget {
  const _ActivityPaginationControls({
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
            key: const Key('activity-previous-page'),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
          ),
          Expanded(
            child: Text(
              'Page ${page + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            key: const Key('activity-next-page'),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

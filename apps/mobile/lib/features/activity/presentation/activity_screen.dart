import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';

const _actionKeys = <String, String>{
  'contact.created': 'activity.action.contactCreated',
  'contact.updated': 'activity.action.contactUpdated',
  'contact.archived': 'activity.action.contactArchived',
  'contact.reactivated': 'activity.action.contactReactivated',
  'member.created': 'activity.action.memberCreated',
  'event_member.attached': 'activity.action.eventMemberAttached',
  'event_member.removed': 'activity.action.eventMemberRemoved',
  'pledge.upserted': 'activity.action.pledgeUpserted',
  'pledge.cancelled': 'activity.action.pledgeCancelled',
  'payment.recorded': 'activity.action.paymentRecorded',
  'payment.reversed': 'activity.action.paymentReversed',
  'event.created': 'activity.action.eventCreated',
  'user.invited': 'activity.action.userInvited',
  'user.role_changed': 'activity.action.userRoleChanged',
};

String activityActionLabel(BuildContext context, String action) {
  final key = _actionKeys[action];
  if (key != null) return context.t(key);
  return action
      .replaceAll('.', ' ')
      .replaceAll('_', ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

const _fieldKeys = <String, String>{
  'full_name': 'auth.fullName',
  'phone_e164': 'contacts.phone',
  'alternative_phone_e164': 'contacts.alternativePhone',
  'email': 'auth.email',
  'location': 'contacts.location',
  'notes': 'activity.field.notes',
  'status': 'eventDetail.status',
  'sms_enabled': 'activity.field.smsEnabled',
  'preferred_language': 'activity.field.preferredLanguage',
  'pledged_amount': 'pledges.pledgeAmount',
  'payment_method': 'activity.field.paymentMethod',
};

String activityFieldLabel(BuildContext context, String key) {
  final mapped = _fieldKeys[key];
  if (mapped != null) return context.t(mapped);
  return key
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _activityValueText(BuildContext context, Object? value) {
  if (value == null) return '—';
  if (value is bool) return value ? context.t('common.yes') : context.t('common.no');
  final text = value.toString().trim();
  return text.isEmpty ? '—' : text;
}

String activityDateTimeText(BuildContext context, String? value) {
  if (value == null || value.isEmpty) return context.t('activity.notSet');
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
      appBar: AppBar(title: Text(context.t('shell.more.activity'))),
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
                  label: context.t('activity.searchActivity'),
                ),
                const SizedBox(height: 12),
                FilterTabs<String>(
                  selected: entityType,
                  onChanged: _onEntityTypeChanged,
                  items: [
                    FilterTabItem(value: _EntityTypeFilter.all, label: context.t('common.all')),
                    FilterTabItem(
                      value: _EntityTypeFilter.member,
                      label: context.t('shell.more.contacts'),
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.payment,
                      label: context.t('shell.nav.payments'),
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.pledge,
                      label: context.t('shell.more.pledges'),
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.event,
                      label: context.t('shell.nav.events'),
                    ),
                    FilterTabItem(
                      value: _EntityTypeFilter.tenantUser,
                      label: context.t('activity.users'),
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
                      context.t('activity.loadError'),
                    ),
                    onRetry: () => setState(() => future = _load()),
                  )
                else if (rows.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.t('activity.noActivityYet')),
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
    final actorName = stringFrom(row, 'actor_name', context.t('activity.unknownUser'));
    final entityLabel = _subjectLabel(row);
    return AhadiListRow(
      title: actorName,
      subtitle: entityLabel.isEmpty
          ? activityActionLabel(context, action)
          : '${activityActionLabel(context, action)}: $entityLabel',
      meta: activityDateTimeText(context, stringFrom(row, 'created_at')),
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
      appBar: AppBar(title: Text(context.t('activity.activityDetail'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            activityActionLabel(context, action),
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          AhadiSectionCard(
            title: context.t('activity.details'),
            children: [
              AhadiInfoRow(
                label: context.t('activity.actor'),
                value: stringFrom(row, 'actor_name', context.t('activity.unknownUser')),
              ),
              AhadiInfoRow(
                label: context.t('activity.dateAndTime'),
                value: activityDateTimeText(context, stringFrom(row, 'created_at')),
              ),
              AhadiInfoRow(label: context.t('activity.action'), value: activityActionLabel(context, action)),
              AhadiInfoRow(
                label: context.t('activity.entity'),
                value: activityFieldLabel(context, stringFrom(row, 'entity_type')),
              ),
              if (eventName.isNotEmpty)
                AhadiInfoRow(label: context.t('activity.event'), value: eventName),
              if (reason.isNotEmpty)
                AhadiInfoRow(label: context.t('activity.reason'), value: reason),
            ],
          ),
          if (changedKeys.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.t('activity.changes'),
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
                          activityFieldLabel(context, key),
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(_activityValueText(context, oldValues[key])),
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
                                _activityValueText(context, newValues[key]),
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
            key: const Key('activity-next-page'),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: context.t('common.nextPage'),
          ),
        ],
      ),
    );
  }
}

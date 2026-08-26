import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';

const _manualTypes = ['PLEDGE_REQUEST', 'BALANCE_REMINDER'];
const _pageSize = 15;

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  String tab = 'compose';
  String? loadedEventId;

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.selectedEvent;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Messages')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EventHeader(event: event),
          const SizedBox(height: 12),
          FilterTabs<String>(
            items: const [
              FilterTabItem(value: 'compose', label: 'Compose'),
              FilterTabItem(value: 'history', label: 'History'),
            ],
            selected: tab,
            onChanged: (value) => setState(() => tab = value),
          ),
          const SizedBox(height: 12),
          if (event == null)
            const ErrorPanel(message: 'Select an event to use messaging.')
          else if (tab == 'compose')
            MessageComposer(
              controller: widget.controller,
              event: event,
              onSent: () => setState(() => tab = 'history'),
            )
          else
            MessageHistory(controller: widget.controller, event: event),
        ],
      ),
    );
  }
}

class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.event,
    this.onSent,
  });

  final SessionController controller;
  final EventSummary event;
  final VoidCallback? onSent;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  String messageType = 'BALANCE_REMINDER';
  String recipientGroup = 'eligible';
  late Future<_ComposerData> future;
  final selected = <String>{};
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  String? error;
  List<Map<String, dynamic>> customTemplates = [];
  List<String> senderOptions = [];
  String? senderId;

  bool get _isCustomType => !_manualTypes.contains(messageType);

  Map<String, dynamic>? get _selectedCustomTemplate {
    for (final template in customTemplates) {
      if (_text(template, ['code', 'templateCode']) == messageType) {
        return template;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    future = _load();
    _loadMeta();
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id) {
      selected.clear();
      query = '';
      search.clear();
      future = _load();
      _loadMeta();
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        widget.controller.customSmsTemplates(),
        widget.controller.smsProviderOptions(),
        widget.controller.smsSettings(),
      ]);
      if (!mounted) return;
      final templates = results[0] as List<Map<String, dynamic>>;
      final providers = _providerOptions(results[1] as Map<String, dynamic>);
      final settings = results[2] as Map<String, dynamic>;
      final provider = _text(settings, ['provider', 'smsProvider'], 'NEXTSMS');
      final defaultSender = _text(
        settings,
        ['senderId', 'sender_id'],
        'MICHANGO',
      );
      final senders = _resolveSenderIds(
        providers: providers,
        provider: provider,
        settings: settings,
      );
      setState(() {
        customTemplates = templates;
        senderOptions = senders;
        senderId ??= senders.contains(defaultSender)
            ? defaultSender
            : senders.firstOrNull;
      });
    } catch (_) {
      // Custom templates are optional; the built-in flow stays usable if this fails.
    }
  }

  Future<_ComposerData> _load() async {
    final recipients = await _eligibleRecipients();
    return _ComposerData(recipients: recipients);
  }

  Future<List<Map<String, dynamic>>> _eligibleRecipients() async {
    if (messageType == 'PLEDGE_REQUEST') {
      return widget.controller.noPledgeMessageRecipients(widget.event.id);
    }
    if (_isCustomType && recipientGroup != 'outstanding') {
      return widget.controller.allEventMembers(widget.event.id);
    }
    final report = await widget.controller.eventReport(
      widget.event.id,
      'outstanding',
      {
        'page': 1,
        'pageSize': 100,
        'filter': 'ALL',
        'sort': 'MEMBER',
        'direction': 'ASC',
        'search': query,
      },
    );
    return _list(report['data']);
  }

  List<String> _targetIds(List<Map<String, dynamic>> recipients) {
    final rows = _visibleRecipients(recipients);
    if (recipientGroup == 'selected') {
      return selected.where((id) => rows.any((row) => _id(row) == id)).toList();
    }
    return rows.map(_id).where((id) => id.isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _visibleRecipients(
    List<Map<String, dynamic>> rows,
  ) {
    final filtered = rows.where((row) {
      final reason = _text(row, ['ineligibleReason']);
      if (reason.isNotEmpty && reason != 'null') return false;
      if (query.isEmpty ||
          messageType == 'BALANCE_REMINDER' ||
          (_isCustomType && recipientGroup == 'outstanding')) {
        return true;
      }
      final haystack =
          '${_name(row)} ${_text(row, ['phone', 'phone_e164', 'phoneE164'])}'
              .toLowerCase();
      return haystack.contains(query.toLowerCase()) ||
          compactPhoneSearch(haystack).contains(compactPhoneSearch(query));
    }).toList();
    if (recipientGroup == 'selected') return filtered.take(25).toList();
    return filtered;
  }

  void _reload() {
    setState(() {
      error = null;
      future = _load();
    });
  }

  void _onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          query = value.trim();
          future = _load();
        });
      }
    });
  }

  Future<void> _openPreview(_ComposerData data) async {
    final ids = _targetIds(data.recipients);
    if (ids.isEmpty) {
      setState(() => error = 'No eligible members found.');
      return;
    }
    if (_isCustomType && (senderId == null || senderId!.isEmpty)) {
      setState(() => error = 'Select a sender ID.');
      return;
    }
    setState(() => error = null);
    final queued = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _MessagePreviewScreen(
          controller: widget.controller,
          event: widget.event,
          messageType: messageType,
          targetIds: ids,
          isCustom: _isCustomType,
          senderId: _isCustomType ? senderId : null,
          customTemplateName: _isCustomType
              ? _text(_selectedCustomTemplate ?? const {}, ['name'])
              : null,
        ),
      ),
    );
    if (queued == null) return;
    selected.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Messages queued successfully. $queued recipients.'),
        ),
      );
    }
    widget.onSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _can(widget.controller, 'messages.send');
    return FutureBuilder<_ComposerData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(
            message: friendlyErrorText(
              snapshot.error,
              'Unable to load messaging data.',
            ),
            onRetry: _reload,
          );
        }
        if (!snapshot.hasData) return const LoadingCards(count: 3);
        final data = snapshot.data!;
        final recipients = _visibleRecipients(data.recipients);
        final ids = _targetIds(data.recipients);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AhadiSectionCard(
              title: 'Send Message',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: messageType,
                  decoration: const InputDecoration(labelText: 'Message Type'),
                  items: [
                    ..._manualTypes.map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(_messageTypeLabel(type)),
                      ),
                    ),
                    ...customTemplates.map((template) {
                      final code = _text(template, ['code', 'templateCode']);
                      return DropdownMenuItem(
                        value: code,
                        child: Text(_text(template, ['name'], 'Custom template')),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      messageType = value ?? 'BALANCE_REMINDER';
                      recipientGroup = _manualTypes.contains(messageType)
                          ? 'eligible'
                          : 'outstanding';
                      selected.clear();
                      future = _load();
                    });
                  },
                ),
                if (_isCustomType) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: senderOptions.contains(senderId)
                        ? senderId
                        : senderOptions.firstOrNull,
                    decoration: const InputDecoration(labelText: 'Sender ID'),
                    items: senderOptions
                        .map(
                          (value) =>
                              DropdownMenuItem(value: value, child: Text(value)),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => senderId = value),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: recipientGroup,
                  decoration: const InputDecoration(labelText: 'Recipients'),
                  items: _isCustomType
                      ? const [
                          DropdownMenuItem(
                            value: 'outstanding',
                            child: Text('Members With Outstanding Balance'),
                          ),
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('All Members'),
                          ),
                          DropdownMenuItem(
                            value: 'selected',
                            child: Text('Selected Members'),
                          ),
                        ]
                      : [
                          DropdownMenuItem(
                            value: 'eligible',
                            child: Text(
                              messageType == 'PLEDGE_REQUEST'
                                  ? 'Members Without Pledge'
                                  : 'Members With Outstanding Balance',
                            ),
                          ),
                          const DropdownMenuItem(
                            value: 'selected',
                            child: Text('Selected Members'),
                          ),
                        ],
                  onChanged: (value) {
                    setState(() {
                      recipientGroup =
                          value ?? (_isCustomType ? 'outstanding' : 'eligible');
                      selected.clear();
                      future = _load();
                    });
                  },
                ),
                const SizedBox(height: 12),
                AhadiInfoRow(
                  label: 'Eligible Members',
                  value: '${recipients.length}',
                ),
                if (recipientGroup == 'selected') ...[
                  const SizedBox(height: 12),
                  AhadiSearchField(
                    controller: search,
                    label: 'Search name or phone',
                    onChanged: _onSearch,
                  ),
                  const SizedBox(height: 8),
                  ...recipients.map((row) {
                    final id = _id(row);
                    return CheckboxListTile(
                      value: selected.contains(id),
                      onChanged: id.isEmpty
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                                future = Future.value(data);
                              });
                            },
                      title: Text(_name(row)),
                      subtitle: Text(_phone(row)),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                ],
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  error!,
                  style: const TextStyle(color: AhadiColors.danger),
                ),
              ),
            FilledButton.icon(
              key: const Key('send-message-button'),
              onPressed: !canSend || ids.isEmpty
                  ? null
                  : () => _openPreview(data),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview Messages'),
            ),
            if (!canSend)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Your role does not include permission to send messages.',
                  style: TextStyle(color: AhadiColors.muted),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MessagePreviewScreen extends StatefulWidget {
  const _MessagePreviewScreen({
    required this.controller,
    required this.event,
    required this.messageType,
    required this.targetIds,
    this.isCustom = false,
    this.senderId,
    this.customTemplateName,
  });

  final SessionController controller;
  final EventSummary event;
  final String messageType;
  final List<String> targetIds;
  final bool isCustom;
  final String? senderId;
  final String? customTemplateName;

  @override
  State<_MessagePreviewScreen> createState() => _MessagePreviewScreenState();
}

class _MessagePreviewScreenState extends State<_MessagePreviewScreen> {
  late Future<Map<String, dynamic>> future;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    if (widget.isCustom) {
      return widget.controller.customSmsBulkPreview(widget.event.id, {
        'code': widget.messageType,
        'eventMemberIds': widget.targetIds,
        'senderId': widget.senderId,
      });
    }
    return widget.controller.smsBulkPreview(widget.event.id, {
      'templateCode': widget.messageType,
      'eventMemberIds': widget.targetIds,
    });
  }

  Future<void> _send(int recipientCount) async {
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final response = widget.isCustom
          ? await widget.controller.sendCustomSmsBulk(
              widget.event.id,
              widget.messageType,
              widget.targetIds,
              widget.senderId ?? '',
            )
          : widget.messageType == 'PLEDGE_REQUEST'
          ? await widget.controller.sendPledgeRequestBulk(
              widget.event.id,
              widget.targetIds,
            )
          : await widget.controller.sendBalanceReminderBulk(
              widget.event.id,
              widget.targetIds,
            );
      final queued =
          numberFrom(
            response['queued'] ?? response['queuedCount'] ?? response['count'],
          )?.round() ??
          recipientCount;
      if (mounted) Navigator.of(context).pop(queued);
    } catch (err) {
      setState(
        () => error = friendlyErrorText(
          err,
          'Unable to send messages. Please try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Preview Messages')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(
                message: friendlyErrorText(
                  snapshot.error,
                  'Unable to load message previews.',
                ),
                onRetry: () => setState(() => future = _load()),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 4),
            );
          }
          final data = snapshot.data!;
          final previews = _list(data['previews']);
          final maxCharacters =
              numberFrom(data['maxCharacters'])?.round() ?? 159;
          final skipped = <String>[
            for (final entry in {
              'No phone': data['noPhone'],
              'SMS disabled': data['smsDisabled'],
              'Recently sent': data['recentlySent'],
              'Already pledged': data['hasPledge'],
            }.entries)
              if ((numberFrom(entry.value)?.round() ?? 0) > 0)
                '${entry.key}: ${numberFrom(entry.value)!.round()}',
          ];
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AhadiSectionCard(
                      title: 'Ready to Send',
                      children: [
                        AhadiInfoRow(label: 'Event', value: widget.event.name),
                        AhadiInfoRow(
                          label: 'Type',
                          value:
                              (widget.customTemplateName?.isNotEmpty ?? false)
                              ? widget.customTemplateName!
                              : _messageTypeLabel(widget.messageType),
                        ),
                        if (widget.isCustom)
                          AhadiInfoRow(
                            label: 'Sender ID',
                            value: widget.senderId ?? '-',
                          ),
                        AhadiInfoRow(
                          label: 'Recipients',
                          value: '${previews.length}',
                        ),
                        if (skipped.isNotEmpty)
                          AhadiInfoRow(
                            label: 'Skipped',
                            value: skipped.join(' • '),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (previews.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No eligible members to preview for this selection.',
                          ),
                        ),
                      )
                    else
                      ...previews.map((raw) {
                        final preview = _map(raw);
                        final member = _map(preview['member']);
                        final characters =
                            numberFrom(preview['characters'])?.round() ?? 0;
                        final valid = preview['valid'] != false;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        titleCaseName(
                                          _text(member, ['name'], 'Member'),
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _text(member, [
                                        'phoneMasked',
                                      ], 'No phone'),
                                      style: const TextStyle(
                                        color: AhadiColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(_text(preview, ['message'])),
                                const SizedBox(height: 6),
                                Text(
                                  '$characters / $maxCharacters',
                                  style: TextStyle(
                                    color: valid
                                        ? AhadiColors.muted
                                        : AhadiColors.danger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (error != null) ...[
                        Text(
                          error!,
                          style: const TextStyle(color: AhadiColors.danger),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton.icon(
                        key: const Key('confirm-send-messages-button'),
                        onPressed: sending || previews.isEmpty
                            ? null
                            : () => _send(previews.length),
                        icon: const Icon(Icons.send_outlined),
                        label: Text(
                          sending
                              ? 'Sending...'
                              : 'Send ${previews.length} Messages',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class MessageHistory extends StatefulWidget {
  const MessageHistory({
    super.key,
    required this.controller,
    required this.event,
  });

  final SessionController controller;
  final EventSummary event;

  @override
  State<MessageHistory> createState() => _MessageHistoryState();
}

class _MessageHistoryState extends State<MessageHistory> {
  late Future<List<_MessageCampaign>> future;
  int page = 0;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  @override
  void didUpdateWidget(covariant MessageHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id) {
      page = 0;
      future = _load();
    }
  }

  Future<List<_MessageCampaign>> _load() async {
    final rows = await widget.controller.messageHistory();
    final scoped = rows.where(
      (row) => _text(row, ['event_id', 'eventId']) == widget.event.id,
    );
    return _groupCampaigns(scoped.toList());
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_MessageCampaign>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(
            message: friendlyErrorText(
              snapshot.error,
              'Unable to load message history.',
            ),
            onRetry: () => setState(() => future = _load()),
          );
        }
        if (!snapshot.hasData) return const LoadingCards(count: 4);
        final rows = snapshot.data!;
        final visible = rows.skip(page * _pageSize).take(_pageSize).toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              if (rows.isEmpty)
                const AhadiSectionCard(
                  children: [Text('No messages found for this event.')],
                )
              else ...[
                ...visible.map(
                  (campaign) => AhadiListRow(
                    title: campaign.displayLabel,
                    subtitle: '${campaign.total} recipients',
                    status: campaign.primaryStatus,
                    meta:
                        '${dateText(campaign.createdAt)} • ${campaign.summaryText}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _MessageDetailScreen(
                          controller: widget.controller,
                          campaign: campaign,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: page == 0
                            ? null
                            : () => setState(() => page -= 1),
                        child: const Text('Previous'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (page + 1) * _pageSize >= rows.length
                            ? null
                            : () => setState(() => page += 1),
                        child: const Text('Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MessageDetailScreen extends StatefulWidget {
  const _MessageDetailScreen({
    required this.controller,
    required this.campaign,
  });

  final SessionController controller;
  final _MessageCampaign campaign;

  @override
  State<_MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<_MessageDetailScreen> {
  bool retrying = false;
  String? message;

  Future<void> _retry(_MessageRecipient recipient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retry Failed Message'),
        content: Text('Retry message to ${recipient.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      retrying = true;
      message = null;
    });
    try {
      await widget.controller.retrySms(recipient.id);
      setState(() => message = 'Message queued for retry.');
    } catch (err) {
      setState(
        () => message = friendlyErrorText(err, 'Unable to retry message.'),
      );
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campaign;
    final canRetry = _can(widget.controller, 'messages.send');
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Message Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            title: 'Message',
            children: [
              AhadiInfoRow(label: 'Type', value: c.displayLabel),
              AhadiInfoRow(label: 'Event', value: c.eventName),
              AhadiInfoRow(label: 'Created', value: dateText(c.createdAt)),
              AhadiInfoRow(label: 'Sender', value: c.senderId),
            ],
          ),
          AhadiSectionCard(
            title: 'Recipient Summary',
            children: [
              AhadiInfoRow(label: 'Total', value: '${c.total}'),
              ...c.statusCounts.entries.map(
                (entry) => AhadiInfoRow(
                  label: _statusLabel(entry.key),
                  value: '${entry.value}',
                ),
              ),
            ],
          ),
          AhadiSectionCard(title: 'Message Text', children: [Text(c.body)]),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(message!),
            ),
          AhadiSectionCard(
            title: 'Recipients',
            children: c.recipients
                .map(
                  (recipient) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(recipient.name),
                    subtitle: Text(
                      [
                        recipient.phone,
                        if (recipient.lastError.isNotEmpty) recipient.lastError,
                      ].where((value) => value.isNotEmpty).join('\n'),
                    ),
                    trailing: recipient.status == 'FAILED' && canRetry
                        ? TextButton(
                            onPressed: retrying
                                ? null
                                : () => _retry(recipient),
                            child: const Text('Retry'),
                          )
                        : Text(_statusLabel(recipient.status)),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class MessagingSettingsScreen extends StatefulWidget {
  const MessagingSettingsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<MessagingSettingsScreen> createState() =>
      _MessagingSettingsScreenState();
}

class _MessagingSettingsScreenState extends State<MessagingSettingsScreen> {
  late Future<_SettingsData> future;
  bool saving = false;
  String? provider;
  String? senderId;
  bool smsEnabled = true;
  String language = 'sw';
  String? message;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<_SettingsData> _load() async {
    final results = await Future.wait([
      widget.controller.smsSettings(),
      widget.controller.smsProviderOptions(),
      widget.controller.smsTemplates(),
      widget.controller.customSmsTemplates(),
    ]);
    final settings = results[0] as Map<String, dynamic>;
    provider = _text(settings, ['provider', 'smsProvider'], 'NEXTSMS');
    senderId = _text(settings, ['senderId', 'sender_id'], 'MICHANGO');
    smsEnabled = settings['smsEnabled'] != false;
    language = _text(settings, ['defaultLanguage'], 'sw');
    return _SettingsData(
      settings: settings,
      providers: _providerOptions(results[1] as Map<String, dynamic>),
      templates: (results[2] as List<Map<String, dynamic>>),
      customTemplates: (results[3] as List<Map<String, dynamic>>),
    );
  }

  Future<void> _openCustomTemplateEditor([
    Map<String, dynamic>? template,
  ]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomTemplateEditorScreen(
          controller: widget.controller,
          template: template,
        ),
      ),
    );
    if (changed == true) {
      setState(() => future = _load());
    }
  }

  Future<void> _deleteCustomTemplate(Map<String, dynamic> template) async {
    final code = _text(template, ['code', 'templateCode']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text(
          'Delete "${_text(template, ['name'], code)}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.deleteCustomSmsTemplate(code);
      if (mounted) setState(() => future = _load());
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorText(err, 'Template could not be deleted.'),
          ),
        ),
      );
    }
  }

  List<String> _senders(_SettingsData data) {
    return _resolveSenderIds(
      providers: data.providers,
      provider: provider,
      settings: data.settings,
    );
  }

  Future<void> _save() async {
    if (provider == null || senderId == null) return;
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await widget.controller.updateSmsSettings({
        'smsEnabled': smsEnabled,
        'provider': provider,
        'senderId': senderId,
        'defaultLanguage': language,
      });
      setState(() {
        message = 'Messaging settings saved.';
        future = _load();
      });
    } catch (err) {
      setState(
        () => message = friendlyErrorText(
          err,
          'Messaging settings could not be saved.',
        ),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _can(widget.controller, 'messages.manage_settings');
    final canManageTemplates = _can(
      widget.controller,
      'messages.manage_templates',
    );
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Messaging')),
      body: FutureBuilder<_SettingsData>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ErrorPanel(
                message: friendlyErrorText(
                  snapshot.error,
                  'Unable to load messaging settings.',
                ),
                onRetry: () => setState(() => future = _load()),
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
          final senders = _senders(data);
          if (senderId != null && !senders.contains(senderId)) {
            senders.add(senderId!);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AhadiSectionCard(
                title: 'SMS Settings',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: smsEnabled,
                    onChanged: canManage && !saving
                        ? (value) => setState(() => smsEnabled = value)
                        : null,
                    title: const Text('SMS enabled'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: senders.contains(senderId)
                        ? senderId
                        : senders.firstOrNull,
                    decoration: const InputDecoration(labelText: 'Sender ID'),
                    items: senders
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: canManage && !saving
                        ? (value) => setState(() => senderId = value)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: canManage && !saving ? _save : null,
                    child: Text(saving ? 'Saving...' : 'Save Settings'),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(message!),
                  ],
                ],
              ),
              AhadiSectionCard(
                title: 'Templates',
                children: data.templates
                    .map(
                      (template) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: AhadiColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: AhadiColors.border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            title: Text(
                              _messageTypeLabel(
                                _text(template, ['code', 'templateCode']),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              _text(template, ['body']).isEmpty
                                  ? 'Template managed by backend'
                                  : _text(template, ['body']),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => SmsTemplateScreen(
                                  controller: widget.controller,
                                  template: template,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              AhadiSectionCard(
                title: 'Custom Templates',
                children: [
                  if (data.customTemplates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        'No custom templates yet.',
                        style: TextStyle(color: AhadiColors.muted),
                      ),
                    ),
                  ...data.customTemplates.map(
                    (template) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: AhadiColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: AhadiColors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          title: Text(
                            _text(template, ['name'], 'Custom template'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(_text(template, ['body'])),
                          trailing: canManageTemplates
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      _deleteCustomTemplate(template),
                                )
                              : null,
                          onTap: () => _openCustomTemplateEditor(template),
                        ),
                      ),
                    ),
                  ),
                  if (canManageTemplates)
                    OutlinedButton.icon(
                      onPressed: () => _openCustomTemplateEditor(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Template'),
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

class SmsTemplateScreen extends StatefulWidget {
  const SmsTemplateScreen({
    super.key,
    required this.controller,
    required this.template,
  });

  final SessionController controller;
  final Map<String, dynamic> template;

  @override
  State<SmsTemplateScreen> createState() => _SmsTemplateScreenState();
}

class _SmsTemplateScreenState extends State<SmsTemplateScreen> {
  late final TextEditingController body;
  bool saving = false;
  String? message;

  @override
  void initState() {
    super.initState();
    body = TextEditingController(text: _text(widget.template, ['body']));
  }

  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final code = _text(widget.template, ['code', 'templateCode']);
    setState(() {
      saving = true;
      message = null;
    });
    try {
      await widget.controller.updateSmsTemplate(code, {
        'body': body.text,
        'language': _text(widget.template, ['language'], 'sw'),
      });
      setState(() => message = 'Template saved.');
    } catch (err) {
      setState(
        () => message = friendlyErrorText(err, 'Template could not be saved.'),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _reset() async {
    final code = _text(widget.template, ['code', 'templateCode']);
    setState(() {
      saving = true;
      message = null;
    });
    try {
      final reset = await widget.controller.resetSmsTemplate(code);
      body.text = _text(reset, ['body', 'systemBody'], body.text);
      setState(() => message = 'Template reset.');
    } catch (err) {
      setState(
        () => message = friendlyErrorText(err, 'Template could not be reset.'),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _text(widget.template, ['code', 'templateCode']);
    final variables = _list(widget.template['variables'])
        .map((row) => row.values.isEmpty ? '' : row.values.first.toString())
        .where((value) => value.isNotEmpty)
        .join(', ');
    final sample = _text(widget.template, ['samplePreview']);
    final count =
        numberFrom(
          widget.template['samplePreviewCharacters'] ?? body.text.length,
        )?.round() ??
        body.text.length;
    final max = numberFrom(widget.template['maxCharacters'])?.round() ?? 159;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Edit Template')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            title: _messageTypeLabel(code),
            children: [
              TextField(
                controller: body,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Message'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                '${body.text.length} / $max template characters',
                style: const TextStyle(color: AhadiColors.muted),
              ),
              if (variables.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Available Variables', style: AhadiTypography.label),
                const SizedBox(height: 4),
                Text(variables),
              ],
            ],
          ),
          if (sample.isNotEmpty)
            AhadiSectionCard(
              title: 'Preview',
              children: [
                Text(sample),
                const SizedBox(height: 8),
                Text(
                  '$count / $max',
                  style: const TextStyle(color: AhadiColors.muted),
                ),
              ],
            ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(message!),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : _reset,
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CustomTemplateEditorScreen extends StatefulWidget {
  const CustomTemplateEditorScreen({
    super.key,
    required this.controller,
    this.template,
  });

  final SessionController controller;
  final Map<String, dynamic>? template;

  @override
  State<CustomTemplateEditorScreen> createState() =>
      _CustomTemplateEditorScreenState();
}

class _CustomTemplateEditorScreenState
    extends State<CustomTemplateEditorScreen> {
  late final TextEditingController name;
  late final TextEditingController body;
  bool saving = false;
  String? error;

  bool get isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: _text(widget.template ?? {}, ['name']));
    body = TextEditingController(text: _text(widget.template ?? {}, ['body']));
  }

  @override
  void dispose() {
    name.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty || body.text.trim().isEmpty) {
      setState(() => error = 'Title and message are required.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final payload = {'name': name.text.trim(), 'body': body.text.trim()};
      if (isEditing) {
        final code = _text(widget.template!, ['code', 'templateCode']);
        await widget.controller.updateCustomSmsTemplate(code, payload);
      } else {
        await widget.controller.createCustomSmsTemplate(payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(
        () => error = friendlyErrorText(err, 'Template could not be saved.'),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Custom Template' : 'New Custom Template'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            title: 'Template',
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: body,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Message'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                '${body.text.length} characters',
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 12),
              Text(
                'Use {{member_name}} to insert the recipient\'s name.',
                style: AhadiTypography.label,
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                style: const TextStyle(color: AhadiColors.danger),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event});

  final EventSummary? event;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Messages',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
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

class _ComposerData {
  const _ComposerData({required this.recipients});

  final List<Map<String, dynamic>> recipients;
}

class _SettingsData {
  const _SettingsData({
    required this.settings,
    required this.providers,
    required this.templates,
    required this.customTemplates,
  });

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> providers;
  final List<Map<String, dynamic>> templates;
  final List<Map<String, dynamic>> customTemplates;
}

class _MessageCampaign {
  const _MessageCampaign({
    required this.id,
    required this.templateCode,
    required this.templateName,
    required this.eventName,
    required this.createdAt,
    required this.provider,
    required this.senderId,
    required this.body,
    required this.recipients,
    required this.statusCounts,
  });

  final String id;
  final String templateCode;
  final String templateName;
  final String eventName;
  final String createdAt;
  final String provider;
  final String senderId;
  final String body;
  final List<_MessageRecipient> recipients;
  final Map<String, int> statusCounts;

  int get total => recipients.length;

  String get displayLabel =>
      templateName.isNotEmpty ? templateName : _messageTypeLabel(templateCode);

  String get primaryStatus {
    if (statusCounts.containsKey('FAILED')) return 'FAILED';
    if (statusCounts.containsKey('QUEUED')) return 'QUEUED';
    if (statusCounts.containsKey('PROCESSING')) return 'PROCESSING';
    if (statusCounts.containsKey('DELIVERED')) return 'DELIVERED';
    if (statusCounts.containsKey('SENT')) return 'SENT';
    return statusCounts.keys.firstOrNull ?? 'UNKNOWN';
  }

  String get summaryText => statusCounts.entries
      .map((entry) => '${_statusLabel(entry.key)}: ${entry.value}')
      .join(' • ');
}

class _MessageRecipient {
  const _MessageRecipient({
    required this.id,
    required this.name,
    required this.phone,
    required this.status,
    required this.lastError,
  });

  final String id;
  final String name;
  final String phone;
  final String status;
  final String lastError;
}

List<_MessageCampaign> _groupCampaigns(List<Map<String, dynamic>> rows) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final key = _text(row, ['batch_id', 'batchId']);
    final id = key.isEmpty || key == 'null' ? _text(row, ['id']) : key;
    grouped.putIfAbsent(id, () => []).add(row);
  }
  final campaigns = grouped.entries.map((entry) {
    final first = entry.value.first;
    final counts = <String, int>{};
    final recipients = entry.value.map((row) {
      final status = _text(row, ['status'], 'UNKNOWN').toUpperCase();
      counts[status] = (counts[status] ?? 0) + 1;
      return _MessageRecipient(
        id: _text(row, ['id']),
        name: _text(row, ['member_name', 'memberName'], 'Member'),
        phone: _text(row, ['phone_e164', 'phone', 'maskedPhone']),
        status: status,
        lastError: _text(row, ['last_error_message', 'lastErrorMessage']),
      );
    }).toList();
    return _MessageCampaign(
      id: entry.key,
      templateCode: _text(first, ['template_code', 'templateCode']),
      templateName: _text(first, ['template_name', 'templateName']),
      eventName: _text(first, ['event_name', 'eventName'], '-'),
      createdAt: _text(first, ['created_at', 'createdAt']),
      provider: _text(first, ['provider'], '-'),
      senderId: _text(first, ['sender_id', 'senderId'], '-'),
      body: _text(first, ['message_body', 'messageBody'], ''),
      recipients: recipients,
      statusCounts: counts,
    );
  }).toList();
  campaigns.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return campaigns;
}

List<Map<String, dynamic>> _providerOptions(Map<String, dynamic> data) {
  final direct = _list(data['providers']);
  if (direct.isNotEmpty) return direct;
  final options = _list(data['options']);
  if (options.isNotEmpty) return options;
  return data.isEmpty ? const [] : [data];
}

List<String> _resolveSenderIds({
  required List<Map<String, dynamic>> providers,
  required String? provider,
  required Map<String, dynamic> settings,
}) {
  final fromProvider = providers
      .where(
        (row) => _text(row, ['provider', 'providerCode', 'code']) == provider,
      )
      .expand(
        (row) => _list(row['senderIds'])
            .map((sender) => _text(sender, ['senderId', 'id', 'code'])),
      )
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  if (fromProvider.isNotEmpty) return fromProvider;
  return _list(settings['allowedSenderIds'])
      .map((row) => row.values.first.toString())
      .toList();
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is List) {
    return value.map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) {
        return item.map((key, value) => MapEntry('$key', value));
      }
      return {'value': item};
    }).toList();
  }
  return const [];
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  return const {};
}

String _text(
  Map<String, dynamic> row,
  List<String> keys, [
  String fallback = '',
]) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && '$value'.trim().isNotEmpty) return '$value';
  }
  return fallback;
}

String _id(Map<String, dynamic> row) =>
    _text(row, ['eventMemberId', 'event_member_id']);

String _name(Map<String, dynamic> row) => titleCaseName(
  _text(row, ['fullName', 'full_name', 'member', 'member_name'], 'Member'),
);

String _phone(Map<String, dynamic> row) =>
    _text(row, ['maskedPhone', 'phone', 'phone_e164'], 'No phone');

String _messageTypeLabel(String value) {
  switch (value) {
    case 'PLEDGE_REQUEST':
      return 'Pledge Request';
    case 'PLEDGE_REGISTRATION':
      return 'Pledge Registration';
    case 'PAYMENT_CONFIRMATION':
      return 'Payment Confirmation';
    case 'BALANCE_REMINDER':
      return 'Balance Reminder';
    case 'PLEDGE_COMPLETED':
      return 'Pledge Completed';
    default:
      return titleCaseName(value.replaceAll('_', ' '));
  }
}

String _statusLabel(String value) => titleCaseName(value.replaceAll('_', ' '));

bool _can(SessionController controller, String permission) {
  final context = controller.selectedTenantContext;
  return context?.isOwner == true ||
      context?.permissions.contains(permission) == true;
}

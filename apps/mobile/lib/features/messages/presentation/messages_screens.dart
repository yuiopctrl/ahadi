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
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  @override
  void didUpdateWidget(covariant MessageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.id != widget.event.id) {
      selected.clear();
      query = '';
      search.clear();
      future = _load();
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<_ComposerData> _load() async {
    final recipients = await _eligibleRecipients();
    final ids = _targetIds(recipients);
    final preview = ids.isEmpty
        ? <String, dynamic>{}
        : await widget.controller.smsBulkPreview(widget.event.id, {
            'templateCode': messageType,
            'eventMemberIds': ids.take(25).toList(),
          });
    return _ComposerData(recipients: recipients, preview: preview);
  }

  Future<List<Map<String, dynamic>>> _eligibleRecipients() async {
    if (messageType == 'PLEDGE_REQUEST') {
      return widget.controller.noPledgeMessageRecipients(widget.event.id);
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
      if (query.isEmpty || messageType == 'BALANCE_REMINDER') return true;
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

  Future<void> _confirmSend(_ComposerData data) async {
    final ids = _targetIds(data.recipients);
    if (ids.isEmpty) {
      setState(() => error = 'No eligible members found.');
      return;
    }
    final settings = await widget.controller.smsSettings().catchError(
      (_) => <String, dynamic>{},
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Message'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AhadiInfoRow(label: 'Event', value: widget.event.name),
            AhadiInfoRow(label: 'Type', value: _messageTypeLabel(messageType)),
            AhadiInfoRow(label: 'Recipients', value: '${ids.length}'),
            AhadiInfoRow(
              label: 'Provider',
              value: _text(settings, ['provider', 'smsProvider'], '-'),
            ),
            AhadiInfoRow(
              label: 'Sender',
              value: _text(settings, ['senderId', 'sender_id'], '-'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Send ${ids.length} Messages'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final response = messageType == 'PLEDGE_REQUEST'
          ? await widget.controller.sendPledgeRequestBulk(widget.event.id, ids)
          : await widget.controller.sendBalanceReminderBulk(
              widget.event.id,
              ids,
            );
      final queued =
          numberFrom(
            response['queued'] ?? response['queuedCount'] ?? response['count'],
          )?.round() ??
          ids.length;
      selected.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Messages queued successfully. $queued recipients.'),
          ),
        );
        widget.onSent?.call();
      }
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
        final preview = data.preview;
        final previewText = _text(preview, [
          'samplePreview',
          'message',
          'preview',
        ]);
        final characters = numberFrom(
          preview['samplePreviewCharacters'] ?? preview['characters'],
        )?.round();
        final maxCharacters =
            numberFrom(preview['maxCharacters'])?.round() ?? 159;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AhadiSectionCard(
              title: 'Send Message',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: messageType,
                  decoration: const InputDecoration(labelText: 'Message Type'),
                  items: _manualTypes
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(_messageTypeLabel(type)),
                        ),
                      )
                      .toList(),
                  onChanged: sending
                      ? null
                      : (value) {
                          setState(() {
                            messageType = value ?? 'BALANCE_REMINDER';
                            recipientGroup = 'eligible';
                            selected.clear();
                            future = _load();
                          });
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: recipientGroup,
                  decoration: const InputDecoration(labelText: 'Recipients'),
                  items: [
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
                  onChanged: sending
                      ? null
                      : (value) {
                          setState(() {
                            recipientGroup = value ?? 'eligible';
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
            if (previewText.isNotEmpty)
              AhadiSectionCard(
                title: 'Preview using sample recipient',
                children: [
                  Text(previewText),
                  const SizedBox(height: 8),
                  Text(
                    characters == null
                        ? 'SMS length validated by server'
                        : '$characters / $maxCharacters',
                    style: TextStyle(
                      color: (characters ?? 0) > maxCharacters
                          ? AhadiColors.danger
                          : AhadiColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
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
            FilledButton.icon(
              key: const Key('send-message-button'),
              onPressed: !canSend || sending || ids.isEmpty
                  ? null
                  : () => _confirmSend(data),
              icon: const Icon(Icons.send_outlined),
              label: Text(sending ? 'Sending...' : 'Continue'),
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
                    title: _messageTypeLabel(campaign.templateCode),
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
              AhadiInfoRow(
                label: 'Type',
                value: _messageTypeLabel(c.templateCode),
              ),
              AhadiInfoRow(label: 'Event', value: c.eventName),
              AhadiInfoRow(label: 'Created', value: dateText(c.createdAt)),
              AhadiInfoRow(label: 'Provider', value: c.provider),
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
    );
  }

  List<String> _senders(_SettingsData data) {
    final selectedProvider = provider;
    final fromProvider = data.providers
        .where(
          (row) =>
              _text(row, ['provider', 'providerCode', 'code']) ==
              selectedProvider,
        )
        .expand(
          (row) =>
              _list(row['senderIds'])
                  .map((sender) => _text(sender, ['senderId', 'id', 'code'])),
        )
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (fromProvider.isNotEmpty) return fromProvider;
    return _list(data.settings['allowedSenderIds'])
        .map((row) => row.values.first.toString())
        .toList();
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
  const _ComposerData({required this.recipients, required this.preview});

  final List<Map<String, dynamic>> recipients;
  final Map<String, dynamic> preview;
}

class _SettingsData {
  const _SettingsData({
    required this.settings,
    required this.providers,
    required this.templates,
  });

  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> providers;
  final List<Map<String, dynamic>> templates;
}

class _MessageCampaign {
  const _MessageCampaign({
    required this.id,
    required this.templateCode,
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
  final String eventName;
  final String createdAt;
  final String provider;
  final String senderId;
  final String body;
  final List<_MessageRecipient> recipients;
  final Map<String, int> statusCounts;

  int get total => recipients.length;

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

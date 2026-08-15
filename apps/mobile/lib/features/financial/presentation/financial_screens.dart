import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import '../../events/presentation/event_detail_screen.dart';

const _pageSize = 20;
const _shareChannel = MethodChannel('work.yuiop.ahadi/share');

Future<Map<String, Object?>> receiptImageSharePayload(
  List<int> bytes, {
  DateTime? now,
  Directory? directory,
}) async {
  final file = File(
    '${(directory ?? Directory.systemTemp).path}/ahadi-receipt-${(now ?? DateTime.now()).microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes);
  return {'path': file.path, 'mimeType': 'image/png', 'title': 'Ahadi Receipt'};
}

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.controller, this.appBar});

  final SessionController controller;
  final PreferredSizeWidget? appBar;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final search = TextEditingController();
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;
  int page = 1;

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
    return widget.controller.eventReport(event.id, 'payments', {
      'page': page,
      'pageSize': _pageSize,
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

  Future<void> _record([Map<String, dynamic>? member]) async {
    final recorded = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => RecordPaymentScreen(
          controller: widget.controller,
          initialMember: member,
        ),
      ),
    );
    if (recorded != null && mounted) {
      await widget.controller.refreshTenantContext();
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loadedEventId != widget.controller.selectedEventId) {
      loadedEventId = widget.controller.selectedEventId;
      page = 1;
      search.clear();
      future = _load();
    }
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: widget.appBar,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EventContextHeader(
              title: 'Payments',
              event: widget.controller.selectedEvent,
            ),
            const SizedBox(height: 12),
            if (_can(widget.controller, 'payments.create'))
              FilledButton.icon(
                key: const Key('record-payment-action'),
                onPressed: () => _record(),
                icon: const Icon(Icons.add),
                label: const Text('Record Payment'),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('payments-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Search payments',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _searchChanged,
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LoadingCards(count: 4);
                final report = snapshot.data!;
                final rows = objectList(report['data']);
                if (rows.isEmpty) {
                  return const _EmptyCard('No payments found for this event.');
                }
                return Column(
                  children: [
                    ...rows.map(
                      (payment) => AhadiListRow(
                        title: titleCaseName(_text(payment, ['member'])),
                        subtitle:
                            '${moneyText(payment['amount'])}\n${_method(payment)} • ${dateText(_text(payment, ['date', 'payment_date']))}',
                        status: _text(payment, ['status'], 'CONFIRMED'),
                        meta: _receiptMeta(payment),
                        onTap: () async {
                          final changed = await Navigator.of(context)
                              .push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => PaymentDetailScreen(
                                    controller: widget.controller,
                                    payment: payment,
                                  ),
                                ),
                              );
                          if (changed == true && mounted) await _refresh();
                        },
                      ),
                    ),
                    _PaginationControls(
                      page: page,
                      pagination: jsonMap(report['pagination']),
                      onPrevious: page <= 1
                          ? null
                          : () => setState(() {
                              page -= 1;
                              future = _load();
                            }),
                      onNext: _hasNext(report)
                          ? () => setState(() {
                              page += 1;
                              future = _load();
                            })
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

class RecordPaymentScreen extends StatefulWidget {
  const RecordPaymentScreen({
    super.key,
    required this.controller,
    this.initialMember,
  });

  final SessionController controller;
  final Map<String, dynamic>? initialMember;

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  final search = TextEditingController();
  final amount = TextEditingController();
  final reference = TextEditingController();
  final notes = TextEditingController();
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  Map<String, dynamic>? selectedMember;
  String method = 'CASH';
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    selectedMember = widget.initialMember;
    future = _loadMembers();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    amount.dispose();
    reference.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadMembers() {
    final event = widget.controller.selectedEvent;
    if (event == null) return Future.value(_emptyReport());
    return widget.controller.eventReport(event.id, 'outstanding', {
      'page': 1,
      'pageSize': _pageSize,
      'search': search.text.trim(),
      'sort': 'OUTSTANDING',
      'direction': 'DESC',
    });
  }

  void _searchChanged(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => future = _loadMembers());
    });
  }

  Future<void> _confirm() async {
    final event = widget.controller.selectedEvent;
    final member = selectedMember;
    final parsed = moneyInputValue(amount.text);
    if (event == null || member == null) return;
    if (parsed == null || parsed <= 0) {
      setState(() => error = 'Enter a valid payment amount.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titleCaseName(_memberName(member))),
            const SizedBox(height: 12),
            AhadiInfoRow(label: 'Amount', value: moneyText(parsed)),
            AhadiInfoRow(label: 'Method', value: _methodName(method)),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );
    if (ok != true || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.controller.recordPayment(event.id, {
        'eventMemberId': _text(member, ['eventMemberId', 'event_member_id']),
        'pledgeId': _text(member, ['pledgeId', 'pledge_id']),
        'amount': parsed,
        'paymentMethod': method,
        'paymentDate': DateTime.now().toUtc().toIso8601String(),
        'transactionReference': reference.text.trim().isEmpty
            ? null
            : reference.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
      });
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            controller: widget.controller,
            payment: result,
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => error = 'Payment could not be recorded.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.controller.selectedEvent;
    final selected = selectedMember;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Record Payment')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EventContextHeader(title: 'Record Payment', event: event),
          const SizedBox(height: 12),
          if (selected == null) ...[
            TextField(
              key: const Key('record-payment-member-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Search name or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _searchChanged,
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LoadingCards(count: 3);
                final rows = objectList(snapshot.data!['data']);
                if (rows.isEmpty) {
                  return const _EmptyCard('No outstanding members found.');
                }
                return Column(
                  children: rows.map((member) {
                    return AhadiListRow(
                      title: titleCaseName(_memberName(member)),
                      subtitle: _text(member, ['phone']),
                      financialSummary: FinancialSummary(
                        pledged: member['pledged'],
                        received: member['paid'],
                        outstanding: member['outstanding'],
                      ),
                      meta:
                          'Due ${dateText(_text(member, ['effectiveDueDate', 'due_date']))}',
                      onTap: () => setState(() => selectedMember = member),
                    );
                  }).toList(),
                );
              },
            ),
          ] else ...[
            _SelectedMemberCard(
              member: selected,
              onChange: () => setState(() => selectedMember = null),
            ),
            const SizedBox(height: 12),
            AhadiSectionCard(
              title: 'Payment',
              children: [
                TextField(
                  key: const Key('payment-amount-input'),
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [MoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'TZS ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                  ),
                  items: _paymentMethods
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_methodName(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => method = value ?? 'CASH'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reference,
                  decoration: const InputDecoration(
                    labelText: 'Reference Number',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  minLines: 2,
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _PaymentPreview(member: selected, amount: amount.text),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AhadiColors.danger)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('record-payment-submit'),
              onPressed: saving ? null : _confirm,
              child: saving
                  ? const Text('Recording...')
                  : const Text('Record Payment'),
            ),
          ],
        ],
      ),
    );
  }
}

class PaymentSuccessScreen extends StatelessWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.controller,
    required this.payment,
  });

  final SessionController controller;
  final Map<String, dynamic> payment;

  @override
  Widget build(BuildContext context) {
    final receiptId = _text(payment, ['receipt_id', 'receiptId']);
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Payment Recorded')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            children: [
              const Text(
                'Payment recorded successfully',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AhadiMoneyValue(
                      label: 'Paid',
                      value: payment['payment_amount'],
                      accent: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AhadiMoneyValue(
                      label: 'Allocated',
                      value: payment['allocated_amount'],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AhadiMoneyValue(
                label: 'Unallocated',
                value: payment['unallocated_amount'],
              ),
              const SizedBox(height: 8),
              AhadiInfoRow(
                label: 'Outstanding',
                value: moneyText(payment['outstanding_amount']),
              ),
              AhadiInfoRow(
                label: 'Receipt',
                value: _text(payment, ['receipt_number', 'receiptNumber'], '-'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (receiptId.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReceiptDetailScreen(
                    controller: controller,
                    receiptId: receiptId,
                  ),
                ),
              ),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View Receipt'),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => RecordPaymentScreen(controller: controller),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Record Another Payment'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(payment),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class PaymentDetailScreen extends StatefulWidget {
  const PaymentDetailScreen({
    super.key,
    required this.controller,
    required this.payment,
  });

  final SessionController controller;
  final Map<String, dynamic> payment;

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    final event = widget.controller.selectedEvent;
    final paymentId = _text(widget.payment, ['paymentId', 'payment_id']);
    if (event == null || paymentId.isEmpty) {
      return Future.value(widget.payment);
    }
    return widget.controller
        .paymentDetail(event.id, paymentId)
        .catchError((_) => widget.payment);
  }

  Future<void> _reverse(Map<String, dynamic> payment) async {
    final reason = TextEditingController();
    final event = widget.controller.selectedEvent;
    final paymentId = _text(payment, ['payment_id', 'paymentId']);
    if (event == null || paymentId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse Payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AhadiInfoRow(label: 'Amount', value: moneyText(payment['amount'])),
            AhadiInfoRow(
              label: 'Member',
              value: titleCaseName(_text(payment, ['member_name', 'member'])),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              minLines: 2,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reverse Payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().isEmpty) return;
    await widget.controller.reversePayment(event.id, paymentId, reason.text);
    await widget.controller.refreshTenantContext();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Payment Details')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 2),
            );
          }
          final payment = snapshot.data!;
          final receiptId = _text(payment, ['receipt_id', 'receiptId']);
          final status = _text(payment, ['status'], 'CONFIRMED');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AhadiSectionCard(
                title: 'Payment',
                children: [
                  AhadiInfoRow(
                    label: 'Member',
                    value: titleCaseName(
                      _text(payment, ['member_name', 'member']),
                    ),
                  ),
                  AhadiInfoRow(
                    label: 'Event',
                    value: widget.controller.selectedEvent?.name ?? '-',
                  ),
                  AhadiInfoRow(
                    label: 'Amount',
                    value: moneyText(payment['amount']),
                  ),
                  AhadiInfoRow(label: 'Method', value: _method(payment)),
                  AhadiInfoRow(
                    label: 'Reference',
                    value: _text(payment, [
                      'transaction_reference',
                      'transactionReference',
                    ], '-'),
                  ),
                  AhadiInfoRow(
                    label: 'Date',
                    value: dateText(_text(payment, ['payment_date', 'date'])),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AhadiStatusLabel(status: status),
                  ),
                ],
              ),
              AhadiSectionCard(
                title: 'Allocation',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AhadiMoneyValue(
                          label: 'Allocated',
                          value:
                              payment['allocated_amount'] ??
                              payment['allocatedAmount'],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AhadiMoneyValue(
                          label: 'Unallocated',
                          value:
                              payment['unallocated_amount'] ??
                              payment['unallocatedAmount'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (receiptId.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReceiptDetailScreen(
                        controller: widget.controller,
                        receiptId: receiptId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View Receipt'),
                ),
              if (_can(widget.controller, 'payments.reverse') &&
                  status.toUpperCase() != 'REVERSED')
                OutlinedButton.icon(
                  onPressed: () => _reverse(payment),
                  icon: const Icon(Icons.undo),
                  label: const Text('Reverse Payment'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;
  int page = 1;

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
      page = 1;
      future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() {
    final event = widget.controller.selectedEvent;
    if (event == null) return Future.value(_emptyReport());
    return widget.controller.eventReport(event.id, 'payments', {
      'page': page,
      'pageSize': _pageSize,
      'sort': 'DATE',
      'direction': 'DESC',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Receipts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EventContextHeader(
            title: 'Receipts',
            event: widget.controller.selectedEvent,
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LoadingCards(count: 4);
              final rows = objectList(snapshot.data!['data'])
                  .where(
                    (row) => _text(row, [
                      'receiptNumber',
                      'receipt_number',
                    ]).isNotEmpty,
                  )
                  .toList();
              if (rows.isEmpty) return const _EmptyCard('No receipts found.');
              return Column(
                children: [
                  ...rows.map(
                    (payment) => AhadiListRow(
                      title: _text(payment, [
                        'receiptNumber',
                        'receipt_number',
                      ]),
                      subtitle:
                          '${titleCaseName(_text(payment, ['member', 'member_name']))}\n${moneyText(payment['amount'])}',
                      status: _text(payment, ['status']) == 'REVERSED'
                          ? 'REVERSED'
                          : 'ISSUED',
                      meta:
                          '${_method(payment)} • ${dateText(_text(payment, ['date', 'payment_date']))}',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ReceiptDetailScreen(
                            controller: widget.controller,
                            receiptId: _text(payment, [
                              'receiptId',
                              'receipt_id',
                            ]),
                            fallback: payment,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _PaginationControls(
                    page: page,
                    pagination: jsonMap(snapshot.data!['pagination']),
                    onPrevious: page <= 1
                        ? null
                        : () => setState(() {
                            page -= 1;
                            future = _load();
                          }),
                    onNext: _hasNext(snapshot.data!)
                        ? () => setState(() {
                            page += 1;
                            future = _load();
                          })
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ReceiptDetailScreen extends StatefulWidget {
  const ReceiptDetailScreen({
    super.key,
    required this.controller,
    required this.receiptId,
    this.fallback,
    this.shareImage,
    this.receiptImageBytes,
  });

  final SessionController controller;
  final String receiptId;
  final Map<String, dynamic>? fallback;
  final Future<void> Function(Map<String, Object?> payload)? shareImage;
  final Future<List<int>> Function(Map<String, dynamic> receipt)?
  receiptImageBytes;

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late Future<Map<String, dynamic>> future;

  @override
  void initState() {
    super.initState();
    future = widget.receiptId.isEmpty
        ? Future.value(widget.fallback ?? <String, dynamic>{})
        : widget.controller
              .receiptDetail(widget.receiptId)
              .catchError((_) => widget.fallback ?? <String, dynamic>{});
  }

  Future<void> _shareReceipt(Map<String, dynamic> receipt) async {
    final bytes =
        await (widget.receiptImageBytes?.call(receipt) ??
            _receiptImageBytes(
              receipt,
              organization:
                  widget.controller.selectedTenantContext?.tenantName ?? '-',
              event:
                  widget.controller.selectedEvent?.name ??
                  _text(receipt, ['event_name', 'eventName'], '-'),
              receiptId: widget.receiptId,
            ));
    final payload = await receiptImageSharePayload(bytes);
    final shareImage = widget.shareImage;
    if (shareImage != null) {
      await shareImage(payload);
    } else {
      await _shareChannel.invokeMethod<void>('shareImage', payload);
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt ready to share')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Receipt Details')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingCards(count: 2),
            );
          }
          final receipt = snapshot.data!;
          final paymentStatus = _text(receipt, [
            'payment_status',
            'status',
          ], 'CONFIRMED');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AhadiSectionCard(
                children: [
                  const Center(
                    child: Text(
                      'AHADI',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AhadiInfoRow(
                    label: 'Receipt No',
                    value: _text(receipt, [
                      'receipt_number',
                      'receiptNumber',
                    ], widget.receiptId),
                  ),
                  AhadiInfoRow(
                    label: 'Organization',
                    value:
                        widget.controller.selectedTenantContext?.tenantName ??
                        '-',
                  ),
                  AhadiInfoRow(
                    label: 'Event',
                    value: widget.controller.selectedEvent?.name ?? '-',
                  ),
                  AhadiInfoRow(
                    label: 'Received From',
                    value: titleCaseName(
                      _text(receipt, ['member_name', 'member']),
                    ),
                  ),
                  AhadiInfoRow(
                    label: 'Amount',
                    value: moneyText(
                      receipt['payment_amount'] ?? receipt['amount'],
                    ),
                  ),
                  AhadiInfoRow(label: 'Method', value: _method(receipt)),
                  AhadiInfoRow(
                    label: 'Date',
                    value: dateText(
                      _text(receipt, ['payment_date', 'date', 'issued_at']),
                    ),
                  ),
                  AhadiInfoRow(
                    label: 'Recorded By',
                    value: _text(receipt, [
                      'received_by_name',
                      'receivedBy',
                    ], '-'),
                  ),
                  AhadiInfoRow(label: 'Payment Status', value: paymentStatus),
                  AhadiInfoRow(
                    label: 'Receipt Status',
                    value: paymentStatus == 'REVERSED' ? 'REVERSED' : 'ISSUED',
                  ),
                ],
              ),
              AhadiSectionCard(
                title: 'Financial Details',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AhadiMoneyValue(
                          label: 'Payment',
                          value: receipt['payment_amount'] ?? receipt['amount'],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AhadiMoneyValue(
                          label: 'Allocated',
                          value:
                              receipt['allocated_amount'] ??
                              receipt['allocatedAmount'],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AhadiMoneyValue(
                    label: 'Unallocated',
                    value:
                        receipt['unallocated_excess'] ??
                        receipt['unallocated_amount'] ??
                        receipt['unallocatedAmount'],
                  ),
                ],
              ),
              FilledButton.icon(
                key: const Key('share-receipt-button'),
                onPressed: () => _shareReceipt(receipt),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share Receipt'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class OutstandingScreen extends StatefulWidget {
  const OutstandingScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<OutstandingScreen> createState() => _OutstandingScreenState();
}

class _OutstandingScreenState extends State<OutstandingScreen> {
  final search = TextEditingController();
  Timer? debounce;
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;
  int page = 1;
  String sort = 'OUTSTANDING';
  String direction = 'DESC';

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
      sort = 'OUTSTANDING';
      direction = 'DESC';
      future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() {
    final event = widget.controller.selectedEvent;
    if (event == null) return Future.value(_emptyReport());
    return widget.controller.eventReport(event.id, 'outstanding', {
      'page': page,
      'pageSize': _pageSize,
      'search': search.text.trim(),
      'sort': sort,
      'direction': direction,
    });
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
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SortTile('Highest Outstanding', 'OUTSTANDING', 'DESC'),
            _SortTile('Lowest Outstanding', 'OUTSTANDING', 'ASC'),
            _SortTile('Due Date', 'DUE_DATE', 'ASC'),
            _SortTile('Name', 'MEMBER', 'ASC'),
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
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        title: const Text('Outstanding'),
        actions: [
          IconButton(
            tooltip: 'Sort',
            onPressed: _chooseSort,
            icon: const Icon(Icons.sort),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => future = _load());
          await future;
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _EventContextHeader(
              title: 'Outstanding',
              event: widget.controller.selectedEvent,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('outstanding-search'),
              controller: search,
              decoration: const InputDecoration(
                labelText: 'Search name or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _searchChanged,
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LoadingCards(count: 4);
                final report = snapshot.data!;
                final summary = jsonMap(report['summary']);
                final rows = objectList(report['data']);
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AhadiMoneyValue(
                            label: 'Total Outstanding',
                            value: summary['totalOutstanding'],
                            accent: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CountBox(
                            label: 'Members',
                            value:
                                '${summary['outstandingMembers'] ?? rows.length}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (rows.isEmpty)
                      const _EmptyCard('No outstanding balances found.')
                    else
                      ...rows.map(
                        (member) => AhadiListRow(
                          title: titleCaseName(_memberName(member)),
                          subtitle: _text(member, ['phone']),
                          financialSummary: FinancialSummary(
                            pledged: member['pledged'],
                            received: member['paid'],
                            outstanding: member['outstanding'],
                          ),
                          meta:
                              'Due ${dateText(_text(member, ['effectiveDueDate']))}',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => EventMemberDetailScreen(
                                controller: widget.controller,
                                event: widget.controller.selectedEvent!,
                                eventMemberId: _text(member, ['eventMemberId']),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (rows.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _can(widget.controller, 'payments.create')
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecordPaymentScreen(
                                    controller: widget.controller,
                                  ),
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Record Payment'),
                      ),
                    _PaginationControls(
                      page: page,
                      pagination: jsonMap(report['pagination']),
                      onPrevious: page <= 1
                          ? null
                          : () => setState(() {
                              page -= 1;
                              future = _load();
                            }),
                      onNext: _hasNext(report)
                          ? () => setState(() {
                              page += 1;
                              future = _load();
                            })
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

class ShareListScreen extends StatefulWidget {
  const ShareListScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ShareListScreen> createState() => _ShareListScreenState();
}

class _ShareListScreenState extends State<ShareListScreen> {
  late Future<Map<String, dynamic>> future;
  String? loadedEventId;
  String format = 'DETAILED';
  bool includeSummary = true;

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
      format = 'DETAILED';
      includeSummary = true;
      future = _load();
    });
  }

  Future<Map<String, dynamic>> _load() async {
    final event = widget.controller.selectedEvent;
    if (event == null) return <String, dynamic>{};
    final settings = await widget.controller.whatsappShareSettings(event.id);
    final preview = await widget.controller.whatsappSharePreview(event.id, {
      'format': format,
      'includeSummary': includeSummary,
      'includeWithoutPledges': true,
      'showPaymentInstructions': settings['showPaymentInstructions'],
      'paymentInstructions': settings['paymentInstructions'],
      'showAlama': settings['showAlama'],
      'alamaLabels': settings['alamaLabels'],
    });
    return {'settings': settings, 'preview': preview};
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('List copied')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        title: const Text('Share List'),
        actions: [
          if (_can(widget.controller, 'shares.whatsapp.financial'))
            IconButton(
              tooltip: 'Edit Share Settings',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ShareSettingsScreen(controller: widget.controller),
                  ),
                );
                if (changed == true && mounted) {
                  setState(() => future = _load());
                }
              },
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EventContextHeader(
            title: 'Share List',
            event: widget.controller.selectedEvent,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: const [
              DropdownMenuItem(value: 'DETAILED', child: Text('Detailed')),
              DropdownMenuItem(
                value: 'PRIVACY',
                child: Text('Privacy Friendly'),
              ),
              DropdownMenuItem(
                value: 'PAYMENT_PROGRESS',
                child: Text('Payment Progress'),
              ),
              DropdownMenuItem(
                value: 'OUTSTANDING_FOLLOW_UP',
                child: Text('Outstanding Follow-up'),
              ),
            ],
            onChanged: (value) => setState(() {
              format = value ?? 'DETAILED';
              includeSummary = format == 'PRIVACY' ? false : includeSummary;
              future = _load();
            }),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: includeSummary,
            onChanged: format == 'PRIVACY'
                ? null
                : (value) => setState(() {
                    includeSummary = value ?? true;
                    future = _load();
                  }),
            title: const Text('Include summary'),
          ),
          FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LoadingCards(count: 2);
              final preview = jsonMap(snapshot.data!['preview']);
              final text = _text(preview, [
                'text',
                'message',
                'previewText',
                'body',
              ]);
              if (text.isEmpty) {
                return const _EmptyCard('Share list preview is unavailable.');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AhadiSectionCard(
                    title: 'Preview',
                    children: [
                      SelectableText(
                        text,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('share-list-copy-button'),
                          onPressed: () => _copy(text),
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _copy(text),
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ShareSettingsScreen extends StatefulWidget {
  const ShareSettingsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ShareSettingsScreen> createState() => _ShareSettingsScreenState();
}

class _ShareSettingsScreenState extends State<ShareSettingsScreen> {
  final paymentInstructions = TextEditingController();
  final completed = TextEditingController(text: 'Amemaliza');
  final partial = TextEditingController(text: 'Amepunguza');
  final noPledge = TextEditingController(text: 'Hajatoa Ahadi');
  bool showPaymentInstructions = true;
  bool showAlama = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    paymentInstructions.dispose();
    completed.dispose();
    partial.dispose();
    noPledge.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final event = widget.controller.selectedEvent;
    if (event == null) return;
    final settings = await widget.controller.whatsappShareSettings(event.id);
    if (!mounted) return;
    final labels = jsonMap(settings['alamaLabels']);
    setState(() {
      paymentInstructions.text = _text(settings, ['paymentInstructions']);
      showPaymentInstructions = settings['showPaymentInstructions'] != false;
      showAlama = settings['showAlama'] != false;
      completed.text = _text(labels, ['completed'], completed.text);
      partial.text = _text(labels, ['partial'], partial.text);
      noPledge.text = _text(labels, ['noPledge'], noPledge.text);
    });
  }

  Future<void> _save() async {
    final event = widget.controller.selectedEvent;
    if (event == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final existing = await widget.controller.whatsappShareSettings(event.id);
      await widget.controller.updateWhatsappShareSettings(event.id, {
        'headerText': existing['headerText'],
        'footerText': existing['footerText'],
        'includeEventName': existing['includeEventName'] ?? true,
        'includeEventDate': existing['includeEventDate'] ?? false,
        'includeEventPaymentInstructions':
            existing['includeEventPaymentInstructions'] ?? false,
        'includeMobileMoneyInstructions':
            existing['includeMobileMoneyInstructions'] ?? false,
        'includeBankInstructions': existing['includeBankInstructions'] ?? false,
        'defaultListFormat': existing['defaultListFormat'] ?? 'DETAILED',
        'defaultSort': existing['defaultSort'] ?? 'ORIGINAL',
        'defaultIncludeSummary': existing['defaultIncludeSummary'] ?? true,
        'summaryRows': existing['summaryRows'],
        'showPaymentInstructions': showPaymentInstructions,
        'paymentInstructions': paymentInstructions.text.trim().isEmpty
            ? null
            : paymentInstructions.text.trim(),
        'showAlama': showAlama,
        'alamaLabels': {
          'completed': completed.text.trim(),
          'partial': partial.text.trim(),
          'noPledge': noPledge.text.trim(),
        },
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => error = 'Settings could not be saved.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Share Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: showPaymentInstructions,
            onChanged: (value) =>
                setState(() => showPaymentInstructions = value),
            title: const Text('Payment Instructions'),
          ),
          TextField(
            controller: paymentInstructions,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Payment Instructions',
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: showAlama,
            onChanged: (value) => setState(() => showAlama = value),
            title: const Text('Alama'),
          ),
          TextField(
            controller: completed,
            decoration: const InputDecoration(labelText: 'Completed label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: partial,
            decoration: const InputDecoration(labelText: 'Partial label'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noPledge,
            decoration: const InputDecoration(labelText: 'No pledge label'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Saving...' : 'Save Settings'),
          ),
        ],
      ),
    );
  }
}

class _SelectedMemberCard extends StatelessWidget {
  const _SelectedMemberCard({required this.member, required this.onChange});

  final Map<String, dynamic> member;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return AhadiSectionCard(
      title: 'Member',
      children: [
        Text(
          titleCaseName(_memberName(member)),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          _text(member, ['phone']),
          style: const TextStyle(color: AhadiColors.muted),
        ),
        const SizedBox(height: 10),
        FinancialSummary(
          pledged: member['pledged'],
          received: member['paid'],
          outstanding: member['outstanding'],
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onChange, child: const Text('Change Member')),
      ],
    );
  }
}

Future<List<int>> _receiptImageBytes(
  Map<String, dynamic> receipt, {
  required String organization,
  required String event,
  required String receiptId,
}) async {
  const width = 900.0;
  const margin = 72.0;
  var y = 64.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = Colors.white;
  final dividerPaint = Paint()
    ..color = AhadiColors.border
    ..strokeWidth = 2;
  canvas.drawRect(const Rect.fromLTWH(0, 0, width, 1320), paint);

  void text(
    String value, {
    double size = 28,
    FontWeight weight = FontWeight.w500,
    Color color = AhadiColors.text,
    TextAlign align = TextAlign.left,
    String family = AhadiTypography.sans,
    double gap = 18,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.25,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 4,
    )..layout(maxWidth: width - (margin * 2));
    final dx = switch (align) {
      TextAlign.center => (width - painter.width) / 2,
      TextAlign.right => width - margin - painter.width,
      _ => margin,
    };
    painter.paint(canvas, Offset(dx, y));
    y += painter.height + gap;
  }

  void row(String label, String value, {bool mono = false}) {
    text(
      label,
      size: 22,
      weight: FontWeight.w700,
      color: AhadiColors.muted,
      gap: 4,
    );
    text(
      value,
      size: mono ? 26 : 30,
      weight: FontWeight.w800,
      family: mono ? AhadiTypography.mono : AhadiTypography.sans,
      gap: 18,
    );
  }

  text(
    'AHADI',
    size: 46,
    weight: FontWeight.w900,
    align: TextAlign.center,
    gap: 6,
  );
  text(
    'PAYMENT RECEIPT',
    size: 24,
    weight: FontWeight.w800,
    color: AhadiColors.primary,
    align: TextAlign.center,
    gap: 36,
  );
  canvas.drawLine(Offset(margin, y), Offset(width - margin, y), dividerPaint);
  y += 34;
  row(
    'Receipt No',
    _text(receipt, ['receipt_number', 'receiptNumber'], receiptId),
    mono: true,
  );
  row('Organization', organization);
  row('Event', event);
  row(
    'Received From',
    titleCaseName(_text(receipt, ['member_name', 'member'])),
  );
  row('Amount', moneyText(receipt['payment_amount'] ?? receipt['amount']));
  row('Method', _method(receipt));
  row('Date', dateText(_text(receipt, ['payment_date', 'date', 'issued_at'])));
  row('Status', _text(receipt, ['payment_status', 'status'], 'CONFIRMED'));
  y += 10;
  canvas.drawLine(Offset(margin, y), Offset(width - margin, y), dividerPaint);
  y += 36;
  text(
    'Thank you',
    size: 28,
    weight: FontWeight.w800,
    align: TextAlign.center,
    gap: 8,
  );
  text(
    'Powered by Changisha App',
    size: 22,
    weight: FontWeight.w700,
    color: AhadiColors.muted,
    align: TextAlign.center,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.round(), (y + 72).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

class _PaymentPreview extends StatelessWidget {
  const _PaymentPreview({required this.member, required this.amount});

  final Map<String, dynamic> member;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final payment = moneyInputValue(amount) ?? 0;
    final outstanding = numberFrom(member['outstanding']) ?? 0;
    final remaining = outstanding - payment;
    final overpay = payment > outstanding && outstanding > 0;
    return AhadiSectionCard(
      title: 'Preview',
      children: [
        AhadiInfoRow(
          label: 'Current Outstanding',
          value: moneyText(outstanding),
        ),
        AhadiInfoRow(label: 'Payment', value: moneyText(payment)),
        if (!overpay)
          AhadiInfoRow(
            label: 'Expected Remaining',
            value: moneyText(remaining < 0 ? 0 : remaining),
          )
        else
          const Text(
            'This payment exceeds the current outstanding amount. The server will allocate the amount according to Ahadi payment rules.',
            style: TextStyle(color: AhadiColors.muted),
          ),
      ],
    );
  }
}

class _EventContextHeader extends StatelessWidget {
  const _EventContextHeader({required this.title, required this.event});

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
    final totalPages = pagination['totalPages'];
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
              totalPages is num
                  ? 'Page $page of ${totalPages.round()}'
                  : 'Page $page',
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

class _SortTile extends StatelessWidget {
  const _SortTile(this.label, this.sort, this.direction);

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

class _CountBox extends StatelessWidget {
  const _CountBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AhadiColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AhadiColors.muted)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
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
    'pageSize': _pageSize,
    'totalRows': 0,
    'totalPages': 0,
  },
};

bool _hasNext(Map<String, dynamic> report) {
  final pagination = jsonMap(report['pagination']);
  final page = numberFrom(pagination['page']) ?? 1;
  final totalPages = numberFrom(pagination['totalPages']);
  if (totalPages != null) return page < totalPages;
  return objectList(report['data']).length >= _pageSize;
}

bool _can(SessionController controller, String permission) {
  final context = controller.selectedTenantContext;
  return context?.isOwner == true ||
      context?.permissions.contains(permission) == true;
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

String _memberName(Map<String, dynamic> row) =>
    _text(row, ['member', 'member_name', 'full_name'], 'Member');

String _method(Map<String, dynamic> row) =>
    _methodName(_text(row, ['paymentMethod', 'payment_method']));

String _methodName(String value) {
  return value
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

String _receiptMeta(Map<String, dynamic> row) {
  final receipt = _text(row, ['receiptNumber', 'receipt_number']);
  final recordedBy = _text(row, ['receivedBy', 'received_by_name']);
  return [
    if (receipt.isNotEmpty) 'Receipt $receipt',
    if (recordedBy.isNotEmpty) 'Recorded by $recordedBy',
  ].join(' • ');
}

List<Map<String, dynamic>> objectList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
  return <Map<String, dynamic>>[];
}

Map<String, dynamic> jsonMap(Object? value) {
  return value is Map<String, dynamic> ? value : <String, dynamic>{};
}

const _paymentMethods = [
  'CASH',
  'M_PESA',
  'AIRTEL_MONEY',
  'MIX_BY_YAS',
  'HALOPESA',
  'BANK_TRANSFER',
  'CHEQUE',
  'OTHER',
];

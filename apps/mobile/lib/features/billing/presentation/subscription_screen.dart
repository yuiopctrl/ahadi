import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'subscription_plan_card.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late Future<Map<String, dynamic>> billingFuture;

  @override
  void initState() {
    super.initState();
    billingFuture = widget.controller.billingSummary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: Text(context.t('shell.more.subscription'))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: billingFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return _StateCard(
              title: context.t('billing.unableToLoadSubscription'),
              message: snapshot.error.toString(),
            );
          }

          final data = snapshot.data ?? const <String, dynamic>{};
          final subscription = _subscriptionFrom(data);
          final invoices = objectList(data['invoices']);
          final payments = objectList(data['payments']);
          final pendingIntents = objectList(data['pendingIntents']);
          final payableInvoices = invoices.where(_invoicePayable).toList();
          final openBalance = payableInvoices.fold<num>(
            0,
            (sum, invoice) =>
                sum +
                (numberFrom(invoice['amount_due']) ??
                    numberFrom(invoice['amountDue']) ??
                    0),
          );

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                billingFuture = widget.controller.billingSummary();
              });
              await billingFuture;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _CurrentSubscriptionCard(
                  subscription: subscription,
                  tenantName:
                      widget.controller.selectedTenantContext?.tenantName ??
                      context.t('billing.organization'),
                ),
                const SizedBox(height: 12),
                _UsageCard(subscription: subscription),
                const SizedBox(height: 12),
                _BillingStatsCard(
                  openBalance: openBalance,
                  payableInvoiceCount: payableInvoices.length,
                  paymentCount: payments.length,
                  pendingIntentCount: pendingIntents.length,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('subscription-change-plan-button'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlanComparisonScreen(
                          controller: widget.controller,
                          currentPlanCode: subscription.planCode,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.compare_arrows_outlined),
                  label: Text(context.t('billing.changePlan')),
                ),
                const SizedBox(height: 18),
                Text(context.t('billing.invoices'), style: AhadiTypography.sectionTitle),
                const SizedBox(height: 8),
                if (invoices.isEmpty)
                  _StateCard(
                    title: context.t('billing.noInvoicesYet'),
                    message: context.t('billing.noInvoicesHint'),
                  )
                else
                  ...invoices.map(
                    (invoice) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _InvoiceCard(invoice: invoice),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  SubscriptionSummary _subscriptionFrom(Map<String, dynamic> data) {
    final raw = data['subscription'];
    if (raw is Map<String, dynamic>) {
      return SubscriptionSummary.fromJson(raw);
    }
    return widget.controller.selectedTenantContext?.subscription ??
        const SubscriptionSummary(status: 'EXPIRED', planName: 'Not set');
  }
}

class PlanComparisonScreen extends StatefulWidget {
  const PlanComparisonScreen({
    super.key,
    required this.controller,
    required this.currentPlanCode,
  });

  final SessionController controller;
  final String? currentPlanCode;

  @override
  State<PlanComparisonScreen> createState() => _PlanComparisonScreenState();
}

class _PlanComparisonScreenState extends State<PlanComparisonScreen> {
  late Future<List<SubscriptionPlan>> plansFuture;

  @override
  void initState() {
    super.initState();
    plansFuture = widget.controller.plans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: Text(context.t('billing.changePlan'))),
      body: FutureBuilder<List<SubscriptionPlan>>(
        future: plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return _StateCard(
              title: context.t('billing.unableToLoadPackages'),
              message: snapshot.error.toString(),
            );
          }
          final plans = snapshot.data ?? const <SubscriptionPlan>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StateCard(
                title: context.t('billing.packageChanges'),
                message: context.t('billing.packageChangesHint'),
              ),
              const SizedBox(height: 12),
              if (plans.isEmpty)
                _StateCard(
                  title: context.t('billing.noPackagesAvailable'),
                  message: context.t('billing.noPackagesHint'),
                )
              else
                ...plans.map(
                  (plan) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SubscriptionPlanCard(
                      plan: plan,
                      current: plan.code == widget.currentPlanCode,
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

class _CurrentSubscriptionCard extends StatelessWidget {
  const _CurrentSubscriptionCard({
    required this.subscription,
    required this.tenantName,
  });

  final SubscriptionSummary subscription;
  final String tenantName;

  @override
  Widget build(BuildContext context) {
    final status = subscription.status.isEmpty
        ? 'UNKNOWN'
        : subscription.status;
    final renewalLabel = status == 'TRIAL'
        ? context.t('billing.trialEnds')
        : status == 'ACTIVE'
        ? context.t('billing.renews')
        : context.t('billing.accessThrough');
    final renewalDate = status == 'TRIAL'
        ? subscription.trialEndsAt
        : subscription.currentPeriodEnd;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tenantName, style: AhadiTypography.sectionTitle),
          const SizedBox(height: 8),
          Text(
            subscription.planName.isEmpty
                ? context.t('billing.noPackageSelected')
                : subscription.planName,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(status: status),
              _LimitPill(label: renewalLabel, value: dateText(renewalDate)),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.subscription});

  final SubscriptionSummary subscription;

  @override
  Widget build(BuildContext context) {
    final usage = subscription.eventUsage.isNotEmpty
        ? subscription.eventUsage
        : subscription.limits;
    final used = _number(usage, ['used', 'usedEventSlots', 'used_event_slots']);
    final limit = _number(usage, ['limit', 'maxEventSlots', 'max_event_slots']);
    final available = _number(usage, [
      'available',
      'availableEventSlots',
      'available_event_slots',
    ]);
    final progress = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('billing.usageAndLimits'), style: AhadiTypography.sectionTitle),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LimitPill(label: context.t('billing.usedEventSlots'), value: used.toString()),
              _LimitPill(label: context.t('billing.maxEventSlots'), value: limit.toString()),
              _LimitPill(label: context.t('billing.availableSlots'), value: available.toString()),
              _LimitPill(
                label: context.t('billing.includedSms'),
                value: _number(subscription.limits, [
                  'includedSms',
                  'included_sms',
                ]).toString(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillingStatsCard extends StatelessWidget {
  const _BillingStatsCard({
    required this.openBalance,
    required this.payableInvoiceCount,
    required this.paymentCount,
    required this.pendingIntentCount,
  });

  final num openBalance;
  final int payableInvoiceCount;
  final int paymentCount;
  final int pendingIntentCount;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('billing.billing'), style: AhadiTypography.sectionTitle),
          const SizedBox(height: 10),
          _InfoRow(label: context.t('billing.openBalance'), value: moneyText(openBalance)),
          _InfoRow(
            label: context.t('billing.payableInvoices'),
            value: payableInvoiceCount.toString(),
          ),
          _InfoRow(label: context.t('billing.verifiedPayments'), value: paymentCount.toString()),
          _InfoRow(
            label: context.t('billing.pendingAttempts'),
            value: pendingIntentCount.toString(),
          ),
        ],
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _text(invoice, [
                    'invoice_number',
                    'invoiceNumber',
                  ], context.t('billing.invoice')),
                  style: AhadiTypography.cardTitle,
                ),
              ),
              _StatusPill(status: _text(invoice, ['status'], 'ISSUED')),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(
            label: context.t('billing.total'),
            value: moneyText(invoice['total_amount'] ?? invoice['totalAmount']),
          ),
          _InfoRow(
            label: context.t('billing.paid'),
            value: moneyText(invoice['amount_paid'] ?? invoice['amountPaid']),
          ),
          _InfoRow(
            label: context.t('billing.balance'),
            value: moneyText(invoice['amount_due'] ?? invoice['amountDue']),
          ),
          _InfoRow(
            label: context.t('eventDetail.due'),
            value: dateText(_text(invoice, ['due_date', 'dueDate'], '')),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AhadiColors.surface,
        border: Border.all(color: AhadiColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AhadiTypography.cardTitle),
          const SizedBox(height: 6),
          Text(message, style: AhadiTypography.secondary),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toUpperCase();
    final color = switch (normalized) {
      'ACTIVE' || 'TRIAL' => AhadiColors.success,
      'PAST_DUE' || 'EXPIRED' => AhadiColors.warning,
      'SUSPENDED' || 'CANCELLED' => AhadiColors.danger,
      _ => AhadiColors.muted,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          normalized,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _LimitPill extends StatelessWidget {
  const _LimitPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AhadiTypography.label),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AhadiTypography.secondary)),
          const SizedBox(width: 12),
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

bool _invoicePayable(Map<String, dynamic> invoice) {
  final status = _text(invoice, ['status'], '').toUpperCase();
  final amountDue =
      numberFrom(invoice['amount_due']) ??
      numberFrom(invoice['amountDue']) ??
      0;
  return !['PAID', 'VOID'].contains(status) && amountDue > 0;
}

int _number(Map<String, dynamic> value, List<String> keys) {
  for (final key in keys) {
    final parsed = numberFrom(value[key]);
    if (parsed != null) return parsed.toInt();
  }
  return 0;
}

String _text(
  Map<String, dynamic> value,
  List<String> keys, [
  String fallback = 'Not set',
]) {
  for (final key in keys) {
    final raw = value[key];
    if (raw is String && raw.isNotEmpty) return raw;
  }
  return fallback;
}

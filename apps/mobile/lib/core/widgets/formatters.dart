import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors/api_failure.dart';
import '../theme/ahadi_theme.dart';

String moneyText(Object? value) {
  final amount = numberFrom(value);
  if (amount == null) return 'TZS -';
  final rounded = amount.round();
  final digits = rounded.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i += 1) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return 'TZS ${buffer.toString()}';
}

String compactPhoneSearch(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('255')) return digits.substring(3);
  if (digits.startsWith('0')) return digits.substring(1);
  return digits;
}

num? moneyInputValue(String value) {
  final cleaned = value.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return num.tryParse(cleaned);
}

String moneyInputText(Object? value) {
  final amount = numberFrom(value);
  if (amount == null) return '';
  return moneyText(amount).replaceFirst('TZS ', '');
}

class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }
    final formatted = _commaDigits(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String _commaDigits(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i += 1) {
    final remaining = digits.length - i;
    buffer.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

String dateText(String? value) {
  if (value == null || value.isEmpty) return 'Not set';
  final parsed = DateTime.tryParse(value);
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
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

num? numberFrom(Object? value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value);
  return null;
}

String stringFrom(
  Map<String, dynamic> row,
  String key, [
  String fallback = '',
]) {
  final value = row[key];
  if (value == null) return fallback;
  return value is String ? value : value.toString();
}

String titleCaseName(Object? value, [String fallback = 'Contact']) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return fallback;
  return raw
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String friendlyErrorText(
  Object? error, [
  String fallback = 'Unable to load data. Please try again.',
]) {
  if (error is ApiFailure) return error.friendlyMessage;
  final message = error?.toString() ?? '';
  if (message.contains('SocketException') ||
      message.contains('Failed host lookup') ||
      message.contains('OS Error') ||
      message.contains('errno')) {
    return 'No internet connection. Check your connection and try again.';
  }
  if (message.trim().isEmpty) return fallback;
  return fallback;
}

Color statusColor(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
    case 'PAID':
    case 'COMPLETED':
    case 'CONFIRMED':
      return AhadiColors.success;
    case 'DRAFT':
    case 'PENDING':
    case 'PARTIALLY_PAID':
    case 'TRIAL':
      return AhadiColors.warning;
    case 'CANCELLED':
    case 'ARCHIVED':
    case 'OVERDUE':
    case 'SUSPENDED':
      return AhadiColors.danger;
    default:
      return AhadiColors.muted;
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class AhadiStatusLabel extends StatelessWidget {
  const AhadiStatusLabel({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) => StatusPill(status: status);
}

class AhadiSectionCard extends StatelessWidget {
  const AhadiSectionCard({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.all(14),
  });

  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AhadiColors.muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

class AhadiInfoRow extends StatelessWidget {
  const AhadiInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class AhadiSearchField extends StatelessWidget {
  const AhadiSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = 'Search',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }
}

class AhadiMoneyField extends StatelessWidget {
  const AhadiMoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: const [MoneyInputFormatter()],
      decoration: InputDecoration(labelText: label, prefixText: 'TZS '),
      onChanged: onChanged,
    );
  }
}

class FinancialSummary extends StatelessWidget {
  const FinancialSummary({
    super.key,
    required this.pledged,
    required this.received,
    required this.outstanding,
  });

  final Object? pledged;
  final Object? received;
  final Object? outstanding;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _FinancialValue(label: 'Pledged', value: pledged),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FinancialValue(label: 'Received', value: received),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _FinancialValue(label: 'Outstanding', value: outstanding),
        ),
      ],
    );
  }
}

class AhadiMoneyValue extends StatelessWidget {
  const AhadiMoneyValue({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final Object? value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent ? AhadiColors.primarySoft : AhadiColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent ? AhadiColors.primary : AhadiColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AhadiColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              moneyText(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent ? AhadiColors.primary : AhadiColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialValue extends StatelessWidget {
  const _FinancialValue({required this.label, required this.value});

  final String label;
  final Object? value;

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
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AhadiColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              moneyText(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class AhadiListRow extends StatelessWidget {
  const AhadiListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.financialSummary,
    this.meta,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? status;
  final Widget? financialSummary;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: const TextStyle(color: AhadiColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (status != null) StatusPill(status: status!),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: AhadiColors.muted),
                  ],
                ],
              ),
              if (financialSummary != null) ...[
                const SizedBox(height: 10),
                financialSummary!,
              ],
              if (meta != null) ...[
                const SizedBox(height: 8),
                Text(meta!, style: const TextStyle(color: AhadiColors.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FilterTabs<T> extends StatelessWidget {
  const FilterTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<FilterTabItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((item) {
          final active = item.value == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton(
              onPressed: () => onChanged(item.value),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(74, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                backgroundColor: active ? AhadiColors.primarySoft : null,
                foregroundColor: active
                    ? AhadiColors.primary
                    : AhadiColors.text,
                side: BorderSide(
                  color: active ? AhadiColors.primary : AhadiColors.border,
                ),
              ),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class FilterTabItem<T> {
  const FilterTabItem({required this.value, required this.label});

  final T value;
  final String label;
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.wifi_off_outlined, color: AhadiColors.danger),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class LoadingCards extends StatelessWidget {
  const LoadingCards({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (index) => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(minHeight: 6),
          ),
        ),
      ),
    );
  }
}

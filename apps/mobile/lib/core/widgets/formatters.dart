import 'package:flutter/material.dart';

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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) {
        final active = item.value == selected;
        return OutlinedButton(
          onPressed: () => onChanged(item.value),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            backgroundColor: active ? AhadiColors.primarySoft : null,
            foregroundColor: active ? AhadiColors.primary : AhadiColors.text,
            side: BorderSide(
              color: active ? AhadiColors.primary : AhadiColors.border,
            ),
          ),
          child: Text(item.label),
        );
      }).toList(),
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

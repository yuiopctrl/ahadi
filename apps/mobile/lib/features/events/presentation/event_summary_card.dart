import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/domain/auth_models.dart';

class EventSummaryCard extends StatelessWidget {
  const EventSummaryCard({
    super.key,
    required this.event,
    this.selected = false,
    this.onTap,
    this.onSelect,
  });

  final EventSummary event;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                          event.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${context.t('events.type.${event.eventType}')} · ${dateText(event.eventDate)}',
                          style: const TextStyle(color: AhadiColors.muted),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(status: event.status),
                ],
              ),
              const SizedBox(height: 12),
              FinancialSummary(
                pledged: event.totalPledged,
                received: event.totalCollected,
                outstanding: event.totalOutstanding,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (selected)
                    Text(
                      context.t('events.currentEvent'),
                      style: const TextStyle(
                        color: AhadiColors.success,
                        fontWeight: FontWeight.w800,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: onSelect,
                      child: Text(context.t('events.setCurrent')),
                    ),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(Icons.chevron_right, color: AhadiColors.muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

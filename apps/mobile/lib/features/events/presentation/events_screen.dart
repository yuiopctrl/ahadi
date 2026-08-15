import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';
import 'event_detail_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String filter = 'ALL';
  bool formOpen = false;

  @override
  Widget build(BuildContext context) {
    final tenant = widget.controller.selectedTenantContext;
    final events = (tenant?.events ?? const <EventSummary>[])
        .where((event) => filter == 'ALL' || event.status == filter)
        .toList();
    final canCreate =
        tenant?.isOwner == true ||
        tenant?.permissions.contains('events.create') == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Events',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.filled(
              onPressed: canCreate
                  ? () => setState(() => formOpen = !formOpen)
                  : null,
              icon: const Icon(Icons.add),
              tooltip: 'New Event',
            ),
          ],
        ),
        if (!canCreate)
          const Text(
            'Your role does not include permission to create events.',
            style: TextStyle(color: AhadiColors.muted),
          ),
        const SizedBox(height: 12),
        FilterTabs<String>(
          items: const [
            FilterTabItem(value: 'ALL', label: 'All'),
            FilterTabItem(value: 'ACTIVE', label: 'Active'),
            FilterTabItem(value: 'DRAFT', label: 'Draft'),
            FilterTabItem(value: 'CLOSED', label: 'Closed'),
          ],
          selected: filter,
          onChanged: (value) => setState(() => filter = value),
        ),
        if (formOpen) ...[
          const SizedBox(height: 12),
          _CreateEventForm(
            controller: widget.controller,
            onDone: () => setState(() => formOpen = false),
          ),
        ],
        const SizedBox(height: 12),
        if (events.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No events match this filter.'),
            ),
          )
        else
          ...events.map(
            (event) => _EventCard(
              controller: widget.controller,
              event: event,
              onSelected: () => setState(() {}),
            ),
          ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.controller,
    required this.event,
    required this.onSelected,
  });

  final SessionController controller;
  final EventSummary event;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () async {
          await controller.selectEvent(event.id);
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    EventDetailScreen(controller: controller, event: event),
              ),
            );
          }
        },
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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  StatusPill(status: event.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${event.eventType} · ${dateText(event.eventDate)}',
                style: const TextStyle(color: AhadiColors.muted),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text('Pledged\n${moneyText(event.totalPledged)}'),
                  ),
                  Expanded(
                    child: Text('Received\n${moneyText(event.totalCollected)}'),
                  ),
                  TextButton(
                    onPressed: () async {
                      await controller.selectEvent(event.id);
                      onSelected();
                    },
                    child: Text(
                      event.id == controller.selectedEventId
                          ? 'Current'
                          : 'Set current',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateEventForm extends StatefulWidget {
  const _CreateEventForm({required this.controller, required this.onDone});

  final SessionController controller;
  final VoidCallback onDone;

  @override
  State<_CreateEventForm> createState() => _CreateEventFormState();
}

class _CreateEventFormState extends State<_CreateEventForm> {
  final name = TextEditingController();
  final customType = TextEditingController();
  final eventDate = TextEditingController();
  final venue = TextEditingController();
  final targetAmount = TextEditingController();
  final pledgeDeadline = TextEditingController();
  String eventType = 'WEDDING';
  bool saving = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    customType.dispose();
    eventDate.dispose();
    venue.dispose();
    targetAmount.dispose();
    pledgeDeadline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New Event',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Event Name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: eventType,
              items:
                  const [
                        'WEDDING',
                        'SENDOFF',
                        'FUNERAL',
                        'FUNDRAISER',
                        'BIRTHDAY',
                        'GRADUATION',
                        'RELIGIOUS',
                        'OTHER',
                      ]
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.replaceAll('_', ' ')),
                        ),
                      )
                      .toList(),
              onChanged: (value) =>
                  setState(() => eventType = value ?? 'WEDDING'),
              decoration: const InputDecoration(labelText: 'Event Type'),
            ),
            if (eventType == 'OTHER') ...[
              const SizedBox(height: 12),
              TextField(
                controller: customType,
                decoration: const InputDecoration(
                  labelText: 'Custom Event Type',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: eventDate,
              decoration: const InputDecoration(
                labelText: 'Event Date YYYY-MM-DD',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: venue,
              decoration: const InputDecoration(labelText: 'Venue'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetAmount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pledgeDeadline,
              decoration: const InputDecoration(
                labelText: 'Pledge Deadline YYYY-MM-DD',
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AhadiColors.danger)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : _submit,
              child: Text(saving ? 'Creating...' : 'Create Event'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.createEvent({
        'name': name.text,
        'eventType': eventType,
        'customEventType': eventType == 'OTHER' ? customType.text : null,
        'eventDate': eventDate.text.trim().isEmpty
            ? null
            : eventDate.text.trim(),
        'venue': venue.text.trim().isEmpty ? null : venue.text.trim(),
        'targetAmount': targetAmount.text.trim().isEmpty
            ? null
            : num.tryParse(targetAmount.text.trim()),
        'pledgeDeadline': pledgeDeadline.text.trim().isEmpty
            ? null
            : pledgeDeadline.text.trim(),
      });
      widget.onDone();
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

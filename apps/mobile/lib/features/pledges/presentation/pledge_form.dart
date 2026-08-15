import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';
import '../../auth/domain/auth_models.dart';

class PledgeForm extends StatefulWidget {
  const PledgeForm({
    super.key,
    required this.controller,
    required this.event,
    required this.members,
    required this.onDone,
  });

  final SessionController controller;
  final EventSummary event;
  final List<Map<String, dynamic>> members;
  final VoidCallback onDone;

  @override
  State<PledgeForm> createState() => _PledgeFormState();
}

class _PledgeFormState extends State<PledgeForm> {
  String? eventMemberId;
  final memberSearch = TextEditingController();
  final amount = TextEditingController();
  final dueDate = TextEditingController();
  final notes = TextEditingController();
  bool open = false;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    memberSearch.dispose();
    amount.dispose();
    dueDate.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMember = widget.members
        .where(
          (member) => stringFrom(member, 'event_member_id') == eventMemberId,
        )
        .firstOrNull;
    final memberQuery = memberSearch.text.trim().toLowerCase();
    final matchingMembers = widget.members
        .where((member) {
          final haystack =
              '${member['full_name'] ?? ''} ${member['phone_e164'] ?? ''}'
                  .toLowerCase();
          return memberQuery.isEmpty || haystack.contains(memberQuery);
        })
        .take(6)
        .toList();
    if (!open) {
      return FilledButton.icon(
        onPressed: widget.members.isEmpty
            ? null
            : () => setState(() => open = true),
        icon: const Icon(Icons.add),
        label: const Text('Record Pledge'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Record Pledge',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (selectedMember == null) ...[
              TextField(
                controller: memberSearch,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Search name or phone',
                  prefixIcon: Icon(Icons.search),
                  helperText: 'Choose a member from this event.',
                ),
              ),
              const SizedBox(height: 8),
              if (matchingMembers.isEmpty)
                const Text(
                  'No event members match your search.',
                  style: TextStyle(color: AhadiColors.muted),
                )
              else
                ...matchingMembers.map((member) {
                  final id = stringFrom(member, 'event_member_id');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(titleCaseName(member['full_name'])),
                    subtitle: Text(
                      stringFrom(member, 'phone_e164', 'No phone'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => eventMemberId = id),
                  );
                }),
            ] else
              AhadiSectionCard(
                title: 'Selected Member',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleCaseName(selectedMember['full_name']),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              stringFrom(
                                selectedMember,
                                'phone_e164',
                                'No phone',
                              ),
                              style: const TextStyle(color: AhadiColors.muted),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          eventMemberId = null;
                          memberSearch.clear();
                        }),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pledge Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dueDate,
              decoration: const InputDecoration(
                labelText: 'Due Date YYYY-MM-DD (optional)',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Default due date: ${dateText(widget.event.pledgeDeadline)}',
              style: const TextStyle(color: AhadiColors.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error!, style: const TextStyle(color: AhadiColors.danger)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => open = false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: saving ? null : _submit,
                    child: Text(saving ? 'Saving...' : 'Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final selected = eventMemberId;
    if (selected == null || selected.isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.upsertPledge(widget.event.id, {
        'eventMemberId': selected,
        'amount': num.tryParse(amount.text.trim()) ?? 0,
        'dueDate': dueDate.text.trim().isEmpty ? null : dueDate.text.trim(),
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'changeReason': null,
      });
      setState(() => open = false);
      widget.onDone();
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

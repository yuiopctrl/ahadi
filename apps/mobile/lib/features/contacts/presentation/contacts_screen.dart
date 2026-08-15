import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/phone_normalization.dart';
import '../../auth/data/session_controller.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  static const pageSize = 10;

  late Future<List<Map<String, dynamic>>> future;
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  int page = 0;

  @override
  void initState() {
    super.initState();
    future = widget.controller.contacts();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          query = value;
          page = 0;
        });
      }
    });
  }

  Future<void> _refresh() async {
    setState(() => future = widget.controller.contacts());
    await future;
  }

  Future<void> _openAddContact() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ContactFormScreen(controller: widget.controller),
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _openContact(Map<String, dynamic> contact) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ContactDetailScreen(
          controller: widget.controller,
          contact: contact,
        ),
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <Map<String, dynamic>>[];
        final canCreate =
            widget.controller.selectedTenantContext?.isOwner == true ||
            widget.controller.selectedTenantContext?.permissions.contains(
                  'members.create',
                ) ==
                true;
        final filtered = rows.where((row) {
          final haystack =
              '${row['full_name'] ?? ''} ${row['phone_e164'] ?? ''}'
                  .toLowerCase();
          return haystack.contains(query.toLowerCase());
        }).toList();
        final totalPages = filtered.isEmpty
            ? 1
            : ((filtered.length - 1) ~/ pageSize) + 1;
        final effectivePage = page >= totalPages ? totalPages - 1 : page;
        final visible = filtered
            .skip(effectivePage * pageSize)
            .take(pageSize)
            .toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Contacts',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton.filled(
                    onPressed: canCreate ? _openAddContact : null,
                    icon: const Icon(Icons.person_add_alt),
                    tooltip: 'Add Contact',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  labelText: 'Search name or phone',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              if (!canCreate)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Your role does not include permission to add contacts.',
                    style: TextStyle(color: AhadiColors.muted),
                  ),
                ),
              const SizedBox(height: 12),
              if (!snapshot.hasData)
                const LoadingCards(count: 4)
              else if (filtered.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No contacts found.'),
                  ),
                )
              else ...[
                ...visible.map(
                  (contact) => Card(
                    child: ListTile(
                      title: Text(
                        titleCaseName(contact['full_name']),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${stringFrom(contact, 'phone_e164', 'No phone')} · ${numberFrom(contact['event_count'])?.round() ?? 0} events',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openContact(contact),
                    ),
                  ),
                ),
                _PaginationControls(
                  page: effectivePage,
                  totalPages: totalPages,
                  totalRows: filtered.length,
                  onPrevious: effectivePage == 0
                      ? null
                      : () => setState(() => page = effectivePage - 1),
                  onNext: effectivePage >= totalPages - 1
                      ? null
                      : () => setState(() => page = effectivePage + 1),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ContactFormScreen extends StatefulWidget {
  const ContactFormScreen({super.key, required this.controller, this.contact});

  final SessionController controller;
  final Map<String, dynamic>? contact;

  @override
  State<ContactFormScreen> createState() => _ContactFormScreenState();
}

class _ContactFormScreenState extends State<ContactFormScreen> {
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final alternativePhone = TextEditingController();
  final email = TextEditingController();
  final location = TextEditingController();
  bool saving = false;
  String? error;

  bool get editing => widget.contact != null;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    if (contact != null) {
      fullName.text = stringFrom(contact, 'full_name');
      phone.text = stringFrom(contact, 'phone_e164');
      alternativePhone.text = stringFrom(contact, 'alternative_phone_e164');
      email.text = stringFrom(contact, 'email');
      location.text = stringFrom(contact, 'location');
    }
  }

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    alternativePhone.dispose();
    email.dispose();
    location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Contact' : 'Add Contact')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: fullName,
            decoration: const InputDecoration(labelText: 'Full Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone Number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: alternativePhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Alternative Phone'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: location,
            decoration: const InputDecoration(labelText: 'Location'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: AhadiColors.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _submit,
            child: Text(saving ? 'Saving...' : 'Save Contact'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (editing) {
        final memberId = stringFrom(
          widget.contact!,
          'member_id',
          stringFrom(widget.contact!, 'id'),
        );
        await widget.controller.updateContact(memberId, {
          'fullName': fullName.text,
          'phoneE164': phone.text.trim().isEmpty
              ? null
              : normalizeTanzaniaPhone(phone.text),
          'alternativePhoneE164': alternativePhone.text.trim().isEmpty
              ? null
              : normalizeTanzaniaPhone(alternativePhone.text),
          'email': email.text.trim().isEmpty ? null : email.text.trim(),
          'location': location.text.trim().isEmpty
              ? null
              : location.text.trim(),
          'smsEnabled': phone.text.trim().isNotEmpty,
        });
      } else {
        await widget.controller.createContact({
          'fullName': fullName.text,
          'phone': phone.text.trim().isEmpty
              ? null
              : normalizeTanzaniaPhone(phone.text),
          'alternativePhone': alternativePhone.text.trim().isEmpty
              ? null
              : normalizeTanzaniaPhone(alternativePhone.text),
          'email': email.text.trim().isEmpty ? null : email.text.trim(),
          'location': location.text.trim().isEmpty
              ? null
              : location.text.trim(),
          'notes': null,
          'smsEnabled': phone.text.trim().isNotEmpty,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => error = err.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class ContactDetailScreen extends StatefulWidget {
  const ContactDetailScreen({
    super.key,
    required this.controller,
    required this.contact,
  });

  final SessionController controller;
  final Map<String, dynamic> contact;

  @override
  State<ContactDetailScreen> createState() => _ContactDetailScreenState();
}

class _ContactDetailScreenState extends State<ContactDetailScreen> {
  late Future<Map<String, dynamic>> future;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    return widget.controller.contactDetail(
      stringFrom(widget.contact, 'member_id', stringFrom(widget.contact, 'id')),
    );
  }

  Future<void> _edit(Map<String, dynamic> contact) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ContactFormScreen(controller: widget.controller, contact: contact),
      ),
    );
    if (saved == true) {
      changed = true;
      setState(() => future = _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'members.update',
            ) ==
            true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(titleCaseName(widget.contact['full_name']))),
        body: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingCards(count: 3),
              );
            }
            final detail = snapshot.data!;
            final contact = detail['contact'] is Map<String, dynamic>
                ? detail['contact'] as Map<String, dynamic>
                : widget.contact;
            final events = detail['events'] is List
                ? (detail['events'] as List)
                      .whereType<Map<String, dynamic>>()
                      .toList()
                : <Map<String, dynamic>>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Name'),
                        subtitle: Text(titleCaseName(contact['full_name'])),
                      ),
                      ListTile(
                        title: const Text('Phone'),
                        subtitle: Text(
                          stringFrom(contact, 'phone_e164', 'No phone'),
                        ),
                      ),
                      ListTile(
                        title: const Text('Email'),
                        subtitle: Text(stringFrom(contact, 'email', 'Not set')),
                      ),
                      ListTile(
                        title: const Text('Location'),
                        subtitle: Text(
                          stringFrom(contact, 'location', 'Not set'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canEdit) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _edit(contact),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Contact'),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Events',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (events.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'This contact is not attached to any event yet.',
                      ),
                    ),
                  )
                else
                  ...events.map(
                    (event) => Card(
                      child: ListTile(
                        title: Text(stringFrom(event, 'event_name')),
                        subtitle: Text(
                          '${moneyText(event['pledged_amount'])} pledged · ${moneyText(event['outstanding_amount'])} outstanding',
                        ),
                        trailing: StatusPill(
                          status: stringFrom(
                            event,
                            'participation_status',
                            'ACTIVE',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PaginationControls extends StatelessWidget {
  const _PaginationControls({
    required this.page,
    required this.totalPages,
    required this.totalRows,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int totalPages;
  final int totalRows;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (totalRows <= _ContactsScreenState.pageSize) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.outlined(
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
          ),
          Expanded(
            child: Text(
              'Page ${page + 1} of $totalPages · $totalRows contacts',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

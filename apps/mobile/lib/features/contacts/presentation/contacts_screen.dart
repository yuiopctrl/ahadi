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
  static const pageSize = 20;

  late Future<List<Map<String, dynamic>>> future;
  final search = TextEditingController();
  Timer? debounce;
  String query = '';
  int page = 0;

  @override
  void initState() {
    super.initState();
    future = _load();
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
          future = _load();
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> _load() {
    return widget.controller.contacts(
      search: query,
      limit: pageSize + 1,
      offset: page * pageSize,
    );
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
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
    final canCreate =
        widget.controller.selectedTenantContext?.isOwner == true ||
        widget.controller.selectedTenantContext?.permissions.contains(
              'members.create',
            ) ==
            true;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton.filled(
            onPressed: canCreate ? _openAddContact : null,
            style: IconButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.add),
            tooltip: 'Add Contact',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final visible = rows.take(pageSize).toList();
          final hasNext = rows.length > pageSize;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                else if (visible.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No contacts found.'),
                    ),
                  )
                else ...[
                  ...visible.map(
                    (contact) => AhadiListRow(
                      title: titleCaseName(contact['full_name']),
                      subtitle: stringFrom(contact, 'phone_e164', 'No phone'),
                      meta:
                          '${numberFrom(contact['event_count'])?.round() ?? 0} events',
                      onTap: () => _openContact(contact),
                    ),
                  ),
                  _PaginationControls(
                    page: page,
                    hasNext: hasNext,
                    onPrevious: page == 0
                        ? null
                        : () => setState(() {
                            page -= 1;
                            future = _load();
                          }),
                    onNext: !hasNext
                        ? null
                        : () => setState(() {
                            page += 1;
                            future = _load();
                          }),
                  ),
                ],
              ],
            ),
          );
        },
      ),
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
      backgroundColor: AhadiColors.background,
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
    } on FormatException {
      setState(
        () => error = 'Enter a valid Tanzanian phone number, e.g. 0712345678.',
      );
    } catch (err) {
      setState(
        () => error = friendlyErrorText(
          err,
          'Unable to save contact. Please try again.',
        ),
      );
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
        backgroundColor: AhadiColors.background,
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
                Text(
                  titleCaseName(contact['full_name']),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  stringFrom(contact, 'phone_e164', 'No phone'),
                  style: const TextStyle(color: AhadiColors.muted),
                ),
                const SizedBox(height: 16),
                AhadiSectionCard(
                  title: 'Contact Information',
                  children: [
                    AhadiInfoRow(
                      label: 'Phone',
                      value: stringFrom(contact, 'phone_e164', 'No phone'),
                    ),
                    AhadiInfoRow(
                      label: 'Email',
                      value: stringFrom(contact, 'email', 'Not set'),
                    ),
                    AhadiInfoRow(
                      label: 'Location',
                      value: stringFrom(contact, 'location', 'Not set'),
                    ),
                  ],
                ),
                if (canEdit) ...[
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
                    (event) => AhadiListRow(
                      title: stringFrom(event, 'event_name'),
                      subtitle: stringFrom(event, 'event_type'),
                      status: stringFrom(
                        event,
                        'participation_status',
                        'ACTIVE',
                      ),
                      financialSummary: FinancialSummary(
                        pledged: event['pledged_amount'],
                        received: event['total_allocated'],
                        outstanding: event['outstanding_amount'],
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
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (page == 0 && !hasNext) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          IconButton.outlined(
            key: const Key('contacts-previous-page'),
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous page',
          ),
          Expanded(
            child: Text(
              'Page ${page + 1}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
          IconButton.outlined(
            key: const Key('contacts-next-page'),
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }
}

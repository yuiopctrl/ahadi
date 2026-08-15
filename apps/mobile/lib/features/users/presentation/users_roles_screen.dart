import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../auth/data/session_controller.dart';

const _roles = ['EVENT_ADMIN', 'TREASURER', 'COLLECTOR', 'VIEWER'];
const _ownerRole = 'TENANT_OWNER';
const _pageSize = 20;

class UsersRolesScreen extends StatefulWidget {
  const UsersRolesScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends State<UsersRolesScreen> {
  late Future<List<Map<String, dynamic>>> future;
  final search = TextEditingController();
  Timer? debounce;
  int page = 0;
  String query = '';

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

  Future<List<Map<String, dynamic>>> _load() {
    return widget.controller.tenantUsers(
      search: query,
      limit: _pageSize + 1,
      offset: page * _pageSize,
    );
  }

  Future<void> _refresh() async {
    setState(() => future = _load());
    await future;
  }

  void _onSearch(String value) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        query = value.trim();
        page = 0;
        future = _load();
      });
    });
  }

  Future<void> _openInvite() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => InviteUserScreen(controller: widget.controller),
      ),
    );
    if (changed == true) await _refresh();
  }

  Future<void> _openDetails(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            UserRoleDetailsScreen(controller: widget.controller, row: row),
      ),
    );
    if (changed == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = widget.controller.selectedTenantContext;
    final canInvite = _can(widget.controller, 'users.invite');
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Users & Roles')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <Map<String, dynamic>>[];
          final visible = rows.take(_pageSize).toList();
          final hasNext = rows.length > _pageSize;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tenant?.tenantName ?? 'Organization',
                  style: const TextStyle(color: AhadiColors.muted),
                ),
                const SizedBox(height: 12),
                if (canInvite)
                  FilledButton.icon(
                    onPressed: _openInvite,
                    icon: const Icon(Icons.add),
                    label: const Text('Invite User'),
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
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  ErrorPanel(
                    message: friendlyErrorText(
                      snapshot.error,
                      'Unable to load users.',
                    ),
                    onRetry: _refresh,
                  )
                else if (!snapshot.hasData)
                  const LoadingCards(count: 4)
                else if (visible.isEmpty)
                  const AhadiSectionCard(
                    children: [Text('No users match this search.')],
                  )
                else ...[
                  ...visible.map(
                    (row) => AhadiListRow(
                      title: _name(row),
                      subtitle: [
                        _phone(row),
                        _roleLabel(_primaryRole(row)),
                      ].where((value) => value.isNotEmpty).join('\n'),
                      status: _statusLabel(_status(row)),
                      meta: _rowType(row) == 'INVITATION'
                          ? 'Invited ${dateText(_text(row, ['created_at', 'createdAt']))}'
                          : 'Joined ${dateText(_text(row, ['joined_at', 'joinedAt']))}',
                      onTap: () => _openDetails(row),
                    ),
                  ),
                  _Pager(
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

class InviteUserScreen extends StatefulWidget {
  const InviteUserScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<InviteUserScreen> createState() => _InviteUserScreenState();
}

class _InviteUserScreenState extends State<InviteUserScreen> {
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  String role = 'TREASURER';
  bool saving = false;
  String? error;

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.inviteTenantUser({
        'fullName': fullName.text.trim(),
        'phone': phone.text.trim(),
        'email': email.text.trim().isEmpty ? null : email.text.trim(),
        'role': role,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (err) {
      setState(() => error = friendlyErrorText(err, 'Unable to invite user.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Invite User')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            title: 'User',
            children: [
              TextField(
                controller: fullName,
                textCapitalization: TextCapitalization.words,
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
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _allowedRoles(widget.controller)
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_roleLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() => role = value ?? 'TREASURER'),
              ),
            ],
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
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Sending...' : 'Send Invitation'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class UserRoleDetailsScreen extends StatefulWidget {
  const UserRoleDetailsScreen({
    super.key,
    required this.controller,
    required this.row,
  });

  final SessionController controller;
  final Map<String, dynamic> row;

  @override
  State<UserRoleDetailsScreen> createState() => _UserRoleDetailsScreenState();
}

class _UserRoleDetailsScreenState extends State<UserRoleDetailsScreen> {
  late Map<String, dynamic> row = widget.row;
  bool saving = false;
  String? message;
  String? error;

  Future<void> _changeRole() async {
    final tenantUserId = _tenantUserId(row);
    if (tenantUserId.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            Text(
              'Change Role',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._allowedRoles(widget.controller).map(
              (role) => ListTile(
                title: Text(_roleLabel(role)),
                trailing: _primaryRole(row) == role
                    ? const Icon(Icons.check, color: AhadiColors.primary)
                    : null,
                onTap: () => Navigator.of(context).pop(role),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null || selected == _primaryRole(row)) return;
    await _run(() async {
      final updated = await widget.controller.updateTenantUserRole(
        tenantUserId,
        selected,
      );
      row = {
        ...row,
        ...updated,
        'roles': [selected],
      };
      message = 'Role updated.';
    });
  }

  Future<void> _statusAction(String action, String label) async {
    final tenantUserId = _tenantUserId(row);
    if (tenantUserId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(label),
        content: Text(
          action == 'remove'
              ? 'Remove ${_name(row)} from ${widget.controller.selectedTenantContext?.tenantName ?? 'this organization'}?\n\nTheir Ahadi account and access to other organizations will not be affected.'
              : '$label for ${_name(row)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      if (action == 'suspend') {
        row = {
          ...row,
          ...await widget.controller.suspendTenantUser(tenantUserId),
          'status': 'SUSPENDED',
        };
      } else if (action == 'reactivate') {
        row = {
          ...row,
          ...await widget.controller.reactivateTenantUser(tenantUserId),
          'status': 'ACTIVE',
        };
      } else {
        await widget.controller.removeTenantUser(tenantUserId);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      message = '$label complete.';
    });
  }

  Future<void> _resend() async {
    final invitationId = _invitationId(row);
    if (invitationId.isEmpty) return;
    await _run(() async {
      await widget.controller.resendTenantInvitation(invitationId);
      message = 'Invitation resent.';
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    if (saving) return;
    setState(() {
      saving = true;
      error = null;
      message = null;
    });
    try {
      await work();
      final tenantId = widget.controller.selectedTenantId;
      if (tenantId != null) await widget.controller.selectTenant(tenantId);
    } catch (err) {
      setState(() => error = friendlyErrorText(err, 'Unable to update user.'));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInvitation = _rowType(row) == 'INVITATION';
    final canManage = _can(widget.controller, 'users.manage_roles');
    final canSuspend =
        _can(widget.controller, 'users.suspend') ||
        _can(widget.controller, 'users.manage_roles');
    final canInvite = _can(widget.controller, 'users.invite');
    final status = _status(row);
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('User Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            children: [
              Text(
                _name(row),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                _phone(row),
                style: const TextStyle(color: AhadiColors.muted),
              ),
            ],
          ),
          AhadiSectionCard(
            title: 'Access',
            children: [
              AhadiInfoRow(label: 'Role', value: _roleLabel(_primaryRole(row))),
              AhadiInfoRow(label: 'Status', value: _statusLabel(status)),
              AhadiInfoRow(
                label: 'Organization',
                value:
                    widget.controller.selectedTenantContext?.tenantName ??
                    'Organization',
              ),
              AhadiInfoRow(
                label: isInvitation ? 'Invited' : 'Joined',
                value: dateText(
                  _text(row, [
                    isInvitation ? 'created_at' : 'joined_at',
                    isInvitation ? 'createdAt' : 'joinedAt',
                  ]),
                ),
              ),
            ],
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(message!),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                style: const TextStyle(color: AhadiColors.danger),
              ),
            ),
          if (isInvitation && canInvite)
            FilledButton(
              onPressed: saving ? null : _resend,
              child: Text(saving ? 'Sending...' : 'Resend Invitation'),
            ),
          if (!isInvitation && canManage) ...[
            FilledButton(
              onPressed: saving ? null : _changeRole,
              child: const Text('Change Role'),
            ),
            const SizedBox(height: 8),
          ],
          if (!isInvitation && canSuspend) ...[
            if (status == 'SUSPENDED')
              OutlinedButton(
                onPressed: saving
                    ? null
                    : () => _statusAction('reactivate', 'Reactivate'),
                child: const Text('Reactivate'),
              )
            else
              OutlinedButton(
                onPressed: saving
                    ? null
                    : () => _statusAction('suspend', 'Suspend Access'),
                child: const Text('Suspend Access'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: saving
                  ? null
                  : () => _statusAction('remove', 'Remove'),
              child: const Text('Remove From Organization'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
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
    return Row(
      children: [
        IconButton.outlined(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Center(
            child: Text(
              'Page ${page + 1}',
              style: const TextStyle(color: AhadiColors.muted),
            ),
          ),
        ),
        IconButton.outlined(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

List<String> _allowedRoles(SessionController controller) {
  final canManageOwners =
      controller.selectedTenantContext?.isOwner == true ||
      controller.selectedTenantContext?.permissions.contains(
            'users.manage_owner',
          ) ==
          true;
  return canManageOwners ? [_ownerRole, ..._roles] : _roles;
}

bool _can(SessionController controller, String permission) {
  final context = controller.selectedTenantContext;
  return context?.isOwner == true ||
      context?.permissions.contains(permission) == true;
}

String _name(Map<String, dynamic> row) {
  return titleCaseName(
    _text(row, ['full_name', 'fullName', 'name']),
    'Ahadi user',
  );
}

String _phone(Map<String, dynamic> row) {
  return _text(row, ['phone_e164', 'phoneE164', 'phone']);
}

String _status(Map<String, dynamic> row) {
  return _text(row, ['status'], 'ACTIVE').toUpperCase();
}

String _rowType(Map<String, dynamic> row) {
  return _text(row, ['row_type', 'rowType'], 'USER').toUpperCase();
}

String _tenantUserId(Map<String, dynamic> row) {
  return _text(row, ['tenant_user_id', 'tenantUserId']);
}

String _invitationId(Map<String, dynamic> row) {
  return _text(row, ['invitation_id', 'invitationId']);
}

String _primaryRole(Map<String, dynamic> row) {
  final roles = row['roles'];
  if (roles is List && roles.isNotEmpty) return roles.first.toString();
  return row['role']?.toString() ?? 'VIEWER';
}

String _roleLabel(String role) {
  switch (role) {
    case 'TENANT_OWNER':
      return 'Owner';
    case 'EVENT_ADMIN':
      return 'Event Admin';
    case 'TREASURER':
      return 'Treasurer';
    case 'COLLECTOR':
      return 'Collector';
    case 'VIEWER':
      return 'Viewer';
    default:
      return titleCaseName(role.replaceAll('_', ' '), role);
  }
}

String _statusLabel(String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return 'Active';
    case 'SUSPENDED':
      return 'Suspended';
    case 'INVITED':
      return 'Invitation Pending';
    case 'REMOVED':
      return 'Removed';
    default:
      return titleCaseName(status.replaceAll('_', ' '), status);
  }
}

String _text(
  Map<String, dynamic> row,
  List<String> keys, [
  String fallback = '',
]) {
  for (final key in keys) {
    final value = row[key];
    if (value != null && value.toString().isNotEmpty) return value.toString();
  }
  return fallback;
}

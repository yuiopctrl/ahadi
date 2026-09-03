import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/app_locale.dart';
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
      appBar: AppBar(title: Text(context.t('shell.more.usersRoles'))),
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
                  tenant?.tenantName ?? context.t('billing.organization'),
                  style: const TextStyle(color: AhadiColors.muted),
                ),
                const SizedBox(height: 12),
                if (canInvite)
                  FilledButton.icon(
                    onPressed: _openInvite,
                    icon: const Icon(Icons.add),
                    label: Text(context.t('users.inviteUser')),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: search,
                  onChanged: _onSearch,
                  decoration: InputDecoration(
                    labelText: context.t('contacts.searchHint'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  ErrorPanel(
                    message: friendlyErrorText(
                      snapshot.error,
                      context.t('users.loadError'),
                    ),
                    onRetry: _refresh,
                  )
                else if (!snapshot.hasData)
                  const LoadingCards(count: 4)
                else if (visible.isEmpty)
                  AhadiSectionCard(
                    children: [Text(context.t('users.noneMatchSearch'))],
                  )
                else ...[
                  ...visible.map(
                    (row) => AhadiListRow(
                      title: _name(context, row),
                      subtitle: [
                        _phone(row),
                        _roleLabel(context, _primaryRole(row)),
                      ].where((value) => value.isNotEmpty).join('\n'),
                      status: _statusLabel(context, _status(row)),
                      meta: _rowType(row) == 'INVITATION'
                          ? '${context.t('users.invited')} ${dateText(_text(row, ['created_at', 'createdAt']))}'
                          : '${context.t('users.joined')} ${dateText(_text(row, ['joined_at', 'joinedAt']))}',
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
      if (!mounted) return;
      setState(() => error = friendlyErrorText(err, context.t('users.inviteError')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: Text(context.t('users.inviteUser'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            title: context.t('users.user'),
            children: [
              TextField(
                controller: fullName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: context.t('auth.fullName')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: context.t('auth.phoneNumber')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: context.t('auth.email')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: InputDecoration(labelText: context.t('users.role')),
                items: _allowedRoles(widget.controller)
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_roleLabel(context, value)),
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
                  child: Text(context.t('common.cancel')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? context.t('users.sending') : context.t('users.sendInvitation')),
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
              context.t('users.changeRole'),
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._allowedRoles(widget.controller).map(
              (role) => ListTile(
                title: Text(_roleLabel(context, role)),
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
      if (mounted) message = context.t('users.roleUpdated');
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
              ? context
                    .t('users.removeConfirmBody')
                    .replaceFirst('{name}', _name(context, row))
                    .replaceFirst(
                      '{organization}',
                      widget.controller.selectedTenantContext?.tenantName ??
                          context.t('users.thisOrganization'),
                    )
              : '$label ${context.t('users.forSomeone')} ${_name(context, row)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.t('common.cancel')),
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
      if (mounted) {
        message = context.t('users.actionComplete').replaceFirst('{action}', label);
      }
    });
  }

  Future<void> _resend() async {
    final invitationId = _invitationId(row);
    if (invitationId.isEmpty) return;
    await _run(() async {
      await widget.controller.resendTenantInvitation(invitationId);
      if (mounted) message = context.t('users.invitationResent');
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
      if (!mounted) return;
      setState(() => error = friendlyErrorText(err, context.t('users.updateError')));
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
      appBar: AppBar(title: Text(context.t('users.userDetails'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AhadiSectionCard(
            children: [
              Text(
                _name(context, row),
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
            title: context.t('users.access'),
            children: [
              AhadiInfoRow(label: context.t('users.role'), value: _roleLabel(context, _primaryRole(row))),
              AhadiInfoRow(label: context.t('eventDetail.status'), value: _statusLabel(context, status)),
              AhadiInfoRow(
                label: context.t('billing.organization'),
                value:
                    widget.controller.selectedTenantContext?.tenantName ??
                    context.t('billing.organization'),
              ),
              AhadiInfoRow(
                label: isInvitation ? context.t('users.invited') : context.t('users.joined'),
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
              child: Text(saving ? context.t('users.sending') : context.t('users.resendInvitation')),
            ),
          if (!isInvitation && canManage) ...[
            FilledButton(
              onPressed: saving ? null : _changeRole,
              child: Text(context.t('users.changeRole')),
            ),
            const SizedBox(height: 8),
          ],
          if (!isInvitation && canSuspend) ...[
            if (status == 'SUSPENDED')
              OutlinedButton(
                onPressed: saving
                    ? null
                    : () => _statusAction('reactivate', context.t('users.reactivate')),
                child: Text(context.t('users.reactivate')),
              )
            else
              OutlinedButton(
                onPressed: saving
                    ? null
                    : () => _statusAction('suspend', context.t('users.suspendAccess')),
                child: Text(context.t('users.suspendAccess')),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: saving
                  ? null
                  : () => _statusAction('remove', context.t('users.remove')),
              child: Text(context.t('users.removeFromOrganization')),
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
              '${context.t('common.page')} ${page + 1}',
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

String _name(BuildContext context, Map<String, dynamic> row) {
  return titleCaseName(
    _text(row, ['full_name', 'fullName', 'name']),
    context.t('shell.ahadiUser'),
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

String _roleLabel(BuildContext context, String role) {
  switch (role) {
    case 'TENANT_OWNER':
      return context.t('users.role.owner');
    case 'EVENT_ADMIN':
      return context.t('users.role.eventAdmin');
    case 'TREASURER':
      return context.t('users.role.treasurer');
    case 'COLLECTOR':
      return context.t('users.role.collector');
    case 'VIEWER':
      return context.t('users.role.viewer');
    default:
      return titleCaseName(role.replaceAll('_', ' '), role);
  }
}

String _statusLabel(BuildContext context, String status) {
  switch (status.toUpperCase()) {
    case 'ACTIVE':
      return context.t('users.status.active');
    case 'SUSPENDED':
      return context.t('users.status.suspended');
    case 'INVITED':
      return context.t('users.status.invitationPending');
    case 'REMOVED':
      return context.t('users.status.removed');
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

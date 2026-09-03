import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

const _roles = [
  'PLATFORM_OWNER',
  'PLATFORM_ADMIN',
  'PLATFORM_SUPPORT',
  'PLATFORM_AUDITOR',
];

class PlatformUsersScreen extends StatefulWidget {
  const PlatformUsersScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PlatformUsersScreen> createState() => _PlatformUsersScreenState();
}

class _PlatformUsersScreenState extends State<PlatformUsersScreen> {
  Key _reloadKey = UniqueKey();
  void _reload() => setState(() => _reloadKey = UniqueKey());

  void _showError(Object error) {
    final message = error is ApiFailure
        ? error.friendlyMessage
        : 'Something went wrong.';
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final phoneController = TextEditingController();
    var role = 'PLATFORM_SUPPORT';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add platform user'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (+2557XXXXXXXX)',
                  helperText:
                      'The person must already have a Changisha account.',
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roles
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (value) => setState(() => role = value ?? role),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != true || phoneController.text.trim().isEmpty) return;
    try {
      await widget.controller.api.addPlatformUser(
        phoneE164: phoneController.text.trim(),
        role: role,
      );
      _reload();
    } on ApiFailure catch (failure) {
      _showError(failure);
    }
  }

  Future<void> _changeRole(Map<String, dynamic> user) async {
    var role = user['role'] as String;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Change role for ${user['full_name']}'),
          content: DropdownButtonFormField<String>(
            initialValue: role,
            items: _roles
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (value) => setState(() => role = value ?? role),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      await widget.controller.api.setPlatformUserRole(
        platformUserId: user['platform_user_id'] as String,
        role: role,
      );
      _reload();
    } on ApiFailure catch (failure) {
      _showError(failure);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> user, String status) async {
    try {
      await widget.controller.api.setPlatformUserStatus(
        platformUserId: user['platform_user_id'] as String,
        status: status,
      );
      _reload();
    } on ApiFailure catch (failure) {
      _showError(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.controller.hasPermission(
      PlatformPermission.usersManage,
    );
    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add user'),
            )
          : null,
      body: AsyncStateView<List<Map<String, dynamic>>>(
        key: _reloadKey,
        future: widget.controller.api.listPlatformUsers,
        isEmpty: (data) => data.isEmpty,
        emptyMessage: 'No platform staff yet.',
        builder: (context, users) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: PlatformColors.border),
            itemBuilder: (context, index) {
              final user = users[index];
              final status = user['status'] as String? ?? 'ACTIVE';
              return ListTile(
                title: Text('${user['full_name']}'),
                subtitle: Text('${user['phone_e164']}  •  ${user['role']}'),
                trailing: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(label: Text(status)),
                    if (canManage)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'role') {
                            _changeRole(user);
                          } else {
                            _setStatus(user, value);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'role',
                            child: Text('Change role'),
                          ),
                          if (status != 'ACTIVE')
                            const PopupMenuItem(
                              value: 'ACTIVE',
                              child: Text('Reactivate'),
                            ),
                          if (status != 'SUSPENDED')
                            const PopupMenuItem(
                              value: 'SUSPENDED',
                              child: Text('Suspend'),
                            ),
                          if (status != 'DISABLED')
                            const PopupMenuItem(
                              value: 'DISABLED',
                              child: Text('Disable'),
                            ),
                        ],
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

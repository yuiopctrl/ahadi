import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

const _statuses = [
  'OPEN',
  'IN_PROGRESS',
  'WAITING_CUSTOMER',
  'RESOLVED',
  'CLOSED',
];

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  Key _reloadKey = UniqueKey();
  String _statusFilter = 'ALL';
  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _openDetail(Map<String, dynamic> request) async {
    final canManage = widget.controller.hasPermission(
      PlatformPermission.supportManage,
    );
    var status = request['status'] as String;
    final noteController = TextEditingController();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${request['ticket_number']} — ${request['subject']}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization: ${request['tenant_name']}',
                  style: PlatformTypography.secondary,
                ),
                Text(
                  'Reporter: ${request['reporter_name'] ?? '-'} (${request['reporter_phone'] ?? '-'})',
                  style: PlatformTypography.secondary,
                ),
                Text(
                  'Category: ${request['category']}  •  Priority: ${request['priority']}',
                  style: PlatformTypography.secondary,
                ),
                const SizedBox(height: 16),
                if (canManage) ...[
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: _statuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => status = value ?? status),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Internal note (optional)',
                    ),
                    maxLines: 3,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (canManage)
              FilledButton(
                onPressed: () => Navigator.of(context).pop({
                  'status': status,
                  if (noteController.text.trim().isNotEmpty)
                    'note': noteController.text.trim(),
                }),
                child: const Text('Save'),
              ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await widget.controller.api.updateSupportRequest(
        request['id'] as String,
        result,
      );
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Filter by status:', style: PlatformTypography.label),
              const SizedBox(width: 12),
              DropdownMenu<String>(
                initialSelection: _statusFilter,
                onSelected: (value) =>
                    setState(() => _statusFilter = value ?? 'ALL'),
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: 'ALL', label: 'All'),
                  ..._statuses.map(
                    (s) => DropdownMenuEntry(value: s, label: s),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncStateView<List<Map<String, dynamic>>>(
            key: _reloadKey,
            future: widget.controller.api.listSupportRequests,
            isEmpty: (data) => data.isEmpty,
            emptyMessage: 'No support requests yet.',
            builder: (context, requests) {
              final filtered = _statusFilter == 'ALL'
                  ? requests
                  : requests
                        .where((r) => r['status'] == _statusFilter)
                        .toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No requests match this filter.',
                    style: PlatformTypography.secondary,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: PlatformColors.border),
                itemBuilder: (context, index) {
                  final request = filtered[index];
                  return ListTile(
                    title: Text(
                      '${request['ticket_number']} — ${request['subject']}',
                    ),
                    subtitle: Text(
                      '${request['tenant_name']}  •  ${request['category']}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(label: Text('${request['priority']}')),
                        Chip(label: Text('${request['status']}')),
                      ],
                    ),
                    onTap: () => _openDetail(request),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

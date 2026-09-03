import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _actionController = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  int? _nextCursor;
  bool _loading = false;
  bool _initialLoaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.api.listAuditLog(
        action: _actionController.text.trim().isEmpty
            ? null
            : _actionController.text.trim(),
        beforeId: reset ? null : _nextCursor,
      );
      final items =
          (result['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      setState(() {
        if (reset) _items.clear();
        _items.addAll(items);
        _nextCursor = result['nextCursor'] as int?;
        _loading = false;
        _initialLoaded = true;
      });
    } catch (error) {
      setState(() {
        _error = error;
        _loading = false;
        _initialLoaded = true;
      });
    }
  }

  void _showDetail(Map<String, dynamic> entry) {
    const encoder = JsonEncoder.withIndent('  ');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${entry['action']}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Organization: ${entry['tenant_name'] ?? '-'}',
                  style: PlatformTypography.secondary,
                ),
                Text(
                  'Actor: ${entry['actor_name'] ?? 'System'}',
                  style: PlatformTypography.secondary,
                ),
                Text(
                  'Entity: ${entry['entity_type']} (${entry['entity_id'] ?? '-'})',
                  style: PlatformTypography.secondary,
                ),
                if (entry['reason'] != null)
                  Text(
                    'Reason: ${entry['reason']}',
                    style: PlatformTypography.secondary,
                  ),
                Text(
                  'At: ${entry['created_at']}',
                  style: PlatformTypography.secondary,
                ),
                const SizedBox(height: 12),
                if (entry['old_values'] != null) ...[
                  const Text('Old values', style: PlatformTypography.label),
                  Text(
                    encoder.convert(entry['old_values']),
                    style: PlatformTypography.mono13,
                  ),
                  const SizedBox(height: 8),
                ],
                if (entry['new_values'] != null) ...[
                  const Text('New values', style: PlatformTypography.label),
                  Text(
                    encoder.convert(entry['new_values']),
                    style: PlatformTypography.mono13,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _actionController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText:
                        'Filter by exact action (e.g. TENANT_STATUS_CHANGED)',
                  ),
                  onSubmitted: (_) => _load(reset: true),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _load(reset: true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
        if (!_initialLoaded)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
            child: ErrorStateView(
              error: _error,
              onRetry: () => _load(reset: true),
            ),
          )
        else if (_items.isEmpty)
          const Expanded(
            child: EmptyStateView(message: 'No audit entries yet.'),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length + 1,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: PlatformColors.border),
              itemBuilder: (context, index) {
                if (index == _items.length) {
                  if (_nextCursor == null) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          'End of log',
                          style: PlatformTypography.secondary,
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : OutlinedButton(
                              onPressed: _load,
                              child: const Text('Load more'),
                            ),
                    ),
                  );
                }
                final entry = _items[index];
                return ListTile(
                  title: Text('${entry['action']}'),
                  subtitle: Text(
                    '${entry['tenant_name'] ?? 'Platform'}  •  ${entry['actor_name'] ?? 'System'}  •  ${entry['created_at']}',
                  ),
                  onTap: () => _showDetail(entry),
                );
              },
            ),
          ),
      ],
    );
  }
}

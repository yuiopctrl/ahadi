import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/errors/api_failure.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  Key _reloadKey = UniqueKey();
  void _reload() => setState(() => _reloadKey = UniqueKey());

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _reload();
    } on ApiFailure catch (failure) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.friendlyMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = widget.controller.hasPermission(
      PlatformPermission.smsManage,
    );
    return AsyncStateView<List<Map<String, dynamic>>>(
      key: _reloadKey,
      future: widget.controller.api.listSmsProviders,
      isEmpty: (data) => data.isEmpty,
      emptyMessage: 'No SMS providers configured.',
      builder: (context, providers) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: providers.map((provider) {
            final senderIds =
                (provider['senderIds'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                const [];
            final providerCode = provider['code'] as String;
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${provider['name']} ($providerCode)',
                            style: PlatformTypography.cardTitle,
                          ),
                        ),
                        if (provider['isDefault'] == true)
                          const Chip(label: Text('Default')),
                        const SizedBox(width: 8),
                        Chip(label: Text('${provider['status']}')),
                        if (canManage) ...[
                          const SizedBox(width: 8),
                          Switch(
                            value: provider['status'] == 'ACTIVE',
                            onChanged: (value) => _run(
                              () => widget.controller.api.updateSmsProvider(
                                providerCode,
                                {'status': value ? 'ACTIVE' : 'DISABLED'},
                              ),
                            ),
                          ),
                          if (provider['isDefault'] != true)
                            TextButton(
                              onPressed: () => _run(
                                () => widget.controller.api.updateSmsProvider(
                                  providerCode,
                                  {'isDefault': true},
                                ),
                              ),
                              child: const Text('Set default'),
                            ),
                        ],
                      ],
                    ),
                    const Divider(),
                    const Text('Sender IDs', style: PlatformTypography.label),
                    ...senderIds.map((sender) {
                      final senderId = sender['senderId'] as String;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(senderId),
                        trailing: Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (sender['isDefault'] == true)
                              const Chip(label: Text('Default')),
                            Chip(label: Text('${sender['status']}')),
                            if (canManage) ...[
                              Switch(
                                value: sender['status'] == 'ACTIVE',
                                onChanged: (value) => _run(
                                  () => widget.controller.api.updateSmsSenderId(
                                    providerCode,
                                    senderId,
                                    {'status': value ? 'ACTIVE' : 'DISABLED'},
                                  ),
                                ),
                              ),
                              if (sender['isDefault'] != true)
                                TextButton(
                                  onPressed: () => _run(
                                    () =>
                                        widget.controller.api.updateSmsSenderId(
                                          providerCode,
                                          senderId,
                                          {'isDefault': true},
                                        ),
                                  ),
                                  child: const Text('Set default'),
                                ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

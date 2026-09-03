import 'package:flutter/material.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';
import '../../../core/widgets/async_state_view.dart';
import 'organization_detail_screen.dart';

class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key, required this.controller});

  final SessionController controller;

  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'ALL';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, code or owner phone',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              DropdownMenu<String>(
                initialSelection: _statusFilter,
                onSelected: (value) =>
                    setState(() => _statusFilter = value ?? 'ALL'),
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 'ALL', label: 'All statuses'),
                  DropdownMenuEntry(value: 'TRIAL', label: 'Trial'),
                  DropdownMenuEntry(value: 'ACTIVE', label: 'Active'),
                  DropdownMenuEntry(value: 'SUSPENDED', label: 'Suspended'),
                  DropdownMenuEntry(value: 'EXPIRED', label: 'Expired'),
                  DropdownMenuEntry(value: 'CANCELLED', label: 'Cancelled'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncStateView<List<Map<String, dynamic>>>(
            future: widget.controller.api.listOrganizations,
            emptyMessage: 'No organizations yet.',
            isEmpty: (data) => data.isEmpty,
            builder: (context, organizations) {
              final query = _searchController.text.trim().toLowerCase();
              final filtered = organizations.where((org) {
                final matchesStatus =
                    _statusFilter == 'ALL' || org['status'] == _statusFilter;
                if (!matchesStatus) return false;
                if (query.isEmpty) return true;
                final haystack = [
                  org['name'],
                  org['code'],
                  org['owner_name'],
                  org['owner_phone'],
                ].map((v) => '$v'.toLowerCase()).join(' ');
                return haystack.contains(query);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'No organizations match your filters.',
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
                  final org = filtered[index];
                  return ListTile(
                    title: Text('${org['name']}'),
                    subtitle: Text(
                      '${org['code']}  •  Owner: ${org['owner_name'] ?? '-'} (${org['owner_phone'] ?? '-'})',
                    ),
                    trailing: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${org['plan_name'] ?? 'No plan'}',
                          style: PlatformTypography.secondary,
                        ),
                        Chip(label: Text('${org['status']}')),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrganizationDetailScreen(
                          controller: widget.controller,
                          tenantId: org['id'] as String,
                        ),
                      ),
                    ),
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

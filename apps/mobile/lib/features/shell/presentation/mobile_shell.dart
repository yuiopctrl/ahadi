import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../organizations/presentation/create_organization_screen.dart';
import '../../profile/presentation/profile_screen.dart';

class MobileShell extends StatefulWidget {
  const MobileShell({super.key, required this.controller});

  final SessionController controller;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final tenantName =
        widget.controller.selectedTenantContext?.tenantName ?? 'Organizations';
    final pages = [
      DashboardScreen(controller: widget.controller),
      const _PlaceholderPage(title: 'Events', icon: Icons.event_outlined),
      const _PlaceholderPage(title: 'Payments', icon: Icons.payments_outlined),
      ProfileScreen(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: TextButton.icon(
          key: const Key('top-organization-switcher'),
          onPressed: () => _showOrganizationSheet(context),
          icon: const Icon(Icons.business_outlined, color: AhadiColors.primary),
          label: Text(
            tenantName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AhadiColors.text,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Account',
            onPressed: () => setState(() => index = 3),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            icon: Icon(Icons.payments_outlined),
            selectedIcon: Icon(Icons.payments),
            label: 'Payments',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'More',
          ),
        ],
      ),
    );
  }

  void _showOrganizationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text(
                'Organizations',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...widget.controller.activeMemberships.map((membership) {
                final selected =
                    membership.tenantId == widget.controller.selectedTenantId;
                return ListTile(
                  key: Key('switch-${membership.tenantId}'),
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.business_outlined,
                    color: selected ? AhadiColors.success : null,
                  ),
                  title: Text(membership.tenantName),
                  onTap: selected
                      ? () => Navigator.of(context).pop()
                      : () async {
                          Navigator.of(context).pop();
                          await widget.controller.switchTenant(
                            membership.tenantId,
                          );
                        },
                );
              }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add_business_outlined),
                title: const Text('Create another organization'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CreateOrganizationScreen(
                        controller: widget.controller,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AhadiColors.primary),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'This mobile area will be expanded after the auth and organization foundation.',
            ),
          ],
        ),
      ),
    );
  }
}

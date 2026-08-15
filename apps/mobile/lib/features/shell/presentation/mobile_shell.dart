import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../auth/data/session_controller.dart';
import '../../contacts/presentation/contacts_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../events/presentation/events_screen.dart';
import '../../organizations/presentation/create_organization_screen.dart';
import '../../pledges/presentation/pledges_screen.dart';
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
    final eventName =
        widget.controller.selectedEvent?.name ?? 'No event selected';
    final pages = [
      DashboardScreen(controller: widget.controller),
      EventsScreen(controller: widget.controller),
      const _PlaceholderPage(title: 'Payments', icon: Icons.payments_outlined),
      _MorePage(controller: widget.controller),
    ];
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: const Key('top-organization-switcher'),
              onTap: () => _showOrganizationSheet(context),
              child: Text(
                tenantName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AhadiColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
            InkWell(
              key: const Key('top-event-switcher'),
              onTap: () => _showEventSheet(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      eventName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AhadiColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AhadiColors.muted,
                  ),
                ],
              ),
            ),
          ],
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

  void _showEventSheet(BuildContext context) {
    final events = widget.controller.selectedTenantContext?.events ?? const [];
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
                'Events',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (events.isEmpty)
                const ListTile(
                  title: Text('No event selected'),
                  subtitle: Text('Create an event to begin operations.'),
                )
              else
                ...events.map((event) {
                  final selected =
                      event.id == widget.controller.selectedEventId;
                  return ListTile(
                    leading: Icon(
                      selected ? Icons.check : Icons.event_outlined,
                      color: selected ? AhadiColors.success : null,
                    ),
                    title: Text(event.name),
                    subtitle: Text(event.status),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await widget.controller.selectEvent(event.id);
                    },
                  );
                }),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create Event'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => index = 1);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'More',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.contacts_outlined),
                title: const Text('Contacts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ContactsScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('Pledges'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PledgesScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: const Text('Profile'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Profile')),
                      body: ProfileScreen(controller: controller),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () async {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  await controller.signOut();
                },
              ),
            ],
          ),
        ),
      ],
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

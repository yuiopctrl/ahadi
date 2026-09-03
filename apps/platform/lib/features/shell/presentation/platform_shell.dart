import 'package:flutter/material.dart';

import '../../../core/auth/platform_permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/theme/platform_theme.dart';
import '../../account/presentation/account_screen.dart';
import '../../audit/presentation/audit_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../messaging/presentation/messaging_screen.dart';
import '../../organizations/presentation/organizations_screen.dart';
import '../../plans/presentation/plans_screen.dart';
import '../../platform_users/presentation/platform_users_screen.dart';
import '../../subscriptions/presentation/subscriptions_screen.dart';
import '../../support/presentation/support_screen.dart';
import '../../system/presentation/system_screen.dart';

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.permission,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final String permission;
  final Widget Function(SessionController controller) builder;
}

class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key, required this.controller});

  final SessionController controller;

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int _selected = 0;

  List<_NavItem> get _items => [
    _NavItem(
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      permission: PlatformPermission.dashboardView,
      builder: (c) => DashboardScreen(controller: c),
    ),
    _NavItem(
      label: 'Organizations',
      icon: Icons.apartment_outlined,
      permission: PlatformPermission.tenantsView,
      builder: (c) => OrganizationsScreen(controller: c),
    ),
    _NavItem(
      label: 'Subscriptions',
      icon: Icons.receipt_long_outlined,
      permission: PlatformPermission.tenantsView,
      builder: (c) => SubscriptionsScreen(controller: c),
    ),
    _NavItem(
      label: 'Packages',
      icon: Icons.inventory_2_outlined,
      permission: PlatformPermission.plansView,
      builder: (c) => PlansScreen(controller: c),
    ),
    _NavItem(
      label: 'Platform Users',
      icon: Icons.admin_panel_settings_outlined,
      permission: PlatformPermission.usersView,
      builder: (c) => PlatformUsersScreen(controller: c),
    ),
    _NavItem(
      label: 'Support',
      icon: Icons.support_agent_outlined,
      permission: PlatformPermission.supportView,
      builder: (c) => SupportScreen(controller: c),
    ),
    _NavItem(
      label: 'Audit Logs',
      icon: Icons.fact_check_outlined,
      permission: PlatformPermission.auditView,
      builder: (c) => AuditScreen(controller: c),
    ),
    _NavItem(
      label: 'Messaging',
      icon: Icons.sms_outlined,
      permission: PlatformPermission.smsView,
      builder: (c) => MessagingScreen(controller: c),
    ),
    _NavItem(
      label: 'System',
      icon: Icons.monitor_heart_outlined,
      permission: PlatformPermission.systemErrorsView,
      builder: (c) => SystemScreen(controller: c),
    ),
    _NavItem(
      label: 'Account',
      icon: Icons.person_outline,
      permission: '',
      builder: (c) => AccountScreen(controller: c),
    ),
  ];

  List<_NavItem> get _visibleItems => _items
      .where(
        (item) =>
            item.permission.isEmpty ||
            widget.controller.hasPermission(item.permission),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    final selected = _selected.clamp(0, items.length - 1);
    final wide = MediaQuery.of(context).size.width >= 900;

    final destinations = items
        .map(
          (item) => NavigationRailDestination(
            icon: Icon(item.icon),
            label: Text(item.label),
          ),
        )
        .toList();

    final body = items.isEmpty
        ? const Center(
            child: Text('No platform modules are available for your role.'),
          )
        : items[selected].builder(widget.controller);

    if (wide) {
      return Scaffold(
        appBar: _buildAppBar(items, selected),
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: items.isEmpty ? null : selected,
              onDestinationSelected: (index) =>
                  setState(() => _selected = index),
              labelType: NavigationRailLabelType.all,
              destinations: destinations,
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      onPressed: widget.controller.logout,
                      icon: const Icon(Icons.logout),
                      tooltip: 'Logout',
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: PlatformColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(items, selected),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              for (var i = 0; i < items.length; i++)
                ListTile(
                  leading: Icon(items[i].icon),
                  title: Text(items[i].label),
                  selected: i == selected,
                  onTap: () {
                    setState(() => _selected = i);
                    Navigator.of(context).pop();
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: widget.controller.logout,
              ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }

  PreferredSizeWidget _buildAppBar(List<_NavItem> items, int selected) {
    final role = widget.controller.session?.platformRole ?? '';
    return AppBar(
      title: Text(items.isEmpty ? 'Changisha Platform' : items[selected].label),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(child: Text(role, style: PlatformTypography.label)),
        ),
      ],
    );
  }
}

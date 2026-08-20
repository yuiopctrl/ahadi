import 'package:flutter/material.dart';

import '../../../core/theme/ahadi_theme.dart';
import '../../../core/widgets/formatters.dart';
import '../../activity/presentation/activity_screen.dart';
import '../../auth/data/session_controller.dart';
import '../../billing/presentation/subscription_screen.dart';
import '../../contacts/presentation/contacts_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../events/presentation/events_screen.dart';
import '../../financial/presentation/financial_screens.dart';
import '../../messages/presentation/messages_screens.dart';
import '../../organizations/presentation/create_organization_screen.dart';
import '../../organizations/presentation/organization_selection_screen.dart';
import '../../pledges/presentation/pledges_screen.dart';
import '../../profile/presentation/change_pin_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../users/presentation/users_roles_screen.dart';

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
      PaymentsScreen(controller: widget.controller),
      _MorePage(controller: widget.controller),
    ];
    final hasEvent = widget.controller.selectedEvent != null;
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            border: const Border(bottom: BorderSide(color: AhadiColors.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          key: const Key('top-organization-switcher'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _showOrganizationSheet(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: AhadiColors.primarySoft,
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: const Icon(
                                    Icons.apartment_rounded,
                                    size: 14,
                                    color: AhadiColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    tenantName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AhadiColors.text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.unfold_more_rounded,
                                  size: 16,
                                  color: AhadiColors.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          key: const Key('top-event-switcher'),
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _showEventSheet(context),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(9, 5, 6, 5),
                            decoration: BoxDecoration(
                              color: AhadiColors.background,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AhadiColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasEvent)
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: statusColor(
                                        widget.controller.selectedEvent!.status,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.event_outlined,
                                    size: 13,
                                    color: AhadiColors.muted,
                                  ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    eventName,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasEvent
                                          ? AhadiColors.text
                                          : AhadiColors.muted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 15,
                                  color: AhadiColors.muted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    key: const Key('top-account-avatar'),
                    customBorder: const CircleBorder(),
                    onTap: () => _showAccountSheet(context),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: AhadiColors.border),
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 17,
                        backgroundColor: AhadiColors.primary,
                        child: Text(
                          _initials(
                            widget.controller.userContext?.profile?.fullName,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if ((widget.controller.userContext?.pendingInvitations.length ?? 0) >
              0)
            Material(
              color: AhadiColors.primary.withValues(alpha: 0.08),
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AhadiColors.primary,
                ),
                title: Text(
                  widget.controller.userContext!.pendingInvitations.length == 1
                      ? 'Organization invitation available'
                      : '${widget.controller.userContext!.pendingInvitations.length} organization invitations',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        InvitationsReviewScreen(controller: widget.controller),
                  ),
                ),
              ),
            ),
          Expanded(child: pages[index]),
        ],
      ),
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
                          if (mounted) setState(() {});
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

  String _initials(String? fullName) {
    final trimmed = fullName?.trim() ?? '';
    if (trimmed.isEmpty) return 'A';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  void _showAccountSheet(BuildContext context) {
    final profile = widget.controller.userContext?.profile;
    final name = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : 'Ahadi user';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AhadiColors.primary,
                  child: Text(
                    _initials(profile?.fullName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: profile != null ? Text(profile.phoneE164) : null,
              ),
              const Divider(),
              ListTile(
                leading: const _MenuIcon(Icons.pin_outlined),
                title: const Text('Change PIN'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ChangePinScreen(controller: widget.controller),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.logout_outlined),
                title: const Text('Sign out'),
                onTap: () async {
                  final navigator = Navigator.of(context, rootNavigator: true);
                  Navigator.of(context).pop();
                  await widget.controller.signOut();
                  navigator.popUntil((route) => route.isFirst);
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
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusPill(status: event.status),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await widget.controller.selectEvent(event.id);
                      if (mounted) setState(() {});
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
    final canViewUsers =
        controller.selectedTenantContext?.isOwner == true ||
        controller.selectedTenantContext?.permissions.contains('users.view') ==
            true;
    final canViewActivity =
        controller.selectedTenantContext?.isOwner == true ||
        controller.selectedTenantContext?.permissions.contains('audit.view') ==
            true;
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
                leading: const _MenuIcon(Icons.sms_outlined),
                title: const Text('Messages'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MessagesScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.contacts_outlined),
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
                leading: const _MenuIcon(Icons.volunteer_activism_outlined),
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
                leading: const _MenuIcon(Icons.receipt_long_outlined),
                title: const Text('Receipts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReceiptsScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.trending_down_outlined),
                title: const Text('Outstanding'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OutstandingScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.share_outlined),
                title: const Text('Share List'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ShareListScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (canViewUsers) ...[
                ListTile(
                  leading: const _MenuIcon(Icons.group_outlined),
                  title: const Text('Users & Roles'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UsersRolesScreen(controller: controller),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const _MenuIcon(Icons.analytics_outlined),
                title: const Text('Reports'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportsScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (canViewActivity) ...[
                ListTile(
                  leading: const _MenuIcon(Icons.history_outlined),
                  title: const Text('Activity'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityScreen(controller: controller),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
              ListTile(
                leading: const _MenuIcon(Icons.credit_card_outlined),
                title: const Text('Subscription'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubscriptionScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.settings_outlined),
                title: const Text('Settings'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _SettingsScreen(controller: controller),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const _MenuIcon(Icons.person_outline, round: true),
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
                leading: const _MenuIcon(Icons.logout_outlined),
                title: const Text('Sign out'),
                onTap: () async {
                  await controller.signOut();
                  if (context.mounted) {
                    Navigator.of(
                      context,
                      rootNavigator: true,
                    ).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon(this.icon, {this.round = false});

  final IconData icon;
  final bool round;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AhadiColors.primarySoft,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(8),
        border: Border.all(color: AhadiColors.border),
      ),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: 20, color: AhadiColors.primary),
      ),
    );
  }
}

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AhadiColors.background,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const _MenuIcon(Icons.sms_outlined),
                  title: const Text('Messaging'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          MessagingSettingsScreen(controller: controller),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

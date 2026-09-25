import 'package:ahadi_mobile/core/errors/api_failure.dart';
import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/events/presentation/event_detail_screen.dart';
import 'package:ahadi_mobile/features/invitations/presentation/invitations_screen.dart';
import 'package:ahadi_mobile/features/invitations/presentation/rsvp_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

// A realistic TENANT_OWNER effective-permission set for these tests --
// invitation.*/rsvp.* are listed explicitly here (matching what the
// TENANT_OWNER role actually has granted via role_permissions in
// production) rather than relying on `isOwner` as a bypass. The
// permission-gating code under test deliberately does NOT special-case
// `isOwner`, so a default fixture that omitted these and depended on an
// isOwner shortcut would silently stop testing anything.
const _tenantOwnerPermissions = [
  'events.view',
  'events.create',
  'events.update',
  'members.create',
  'members.update',
  'members.assign_event',
  'pledges.create',
  'pledges.update',
  'messages.view',
  'messages.send',
  'messages.manage_settings',
  'users.view',
  'users.invite',
  'users.manage_roles',
  'users.suspend',
  'invitation.view',
  'invitation.create',
  'invitation.edit',
  'invitation.cancel',
  'invitation.send',
  'rsvp.view',
  'rsvp.manage',
];

SessionController _buildController(
  FakeAhadiApi api, {
  TenantContext? tenantContext,
}) {
  final controller = SessionController(
    api: api,
    storage: MemorySessionStorage(),
  );
  controller.credentials = const SessionCredentials(
    accessToken: 'a',
    refreshToken: 'r',
  );
  controller.userContext = api.userContext;
  controller.selectedTenantId = 'tenant-a';
  controller.selectedTenantContext =
      tenantContext ??
      TenantContext(
        tenantId: 'tenant-a',
        tenantName: 'Herosimini Committee',
        events: defaultTestEvents,
        permissions: _tenantOwnerPermissions,
        isOwner: true,
        accessState: 'ACTIVE',
      );
  return controller;
}

TenantContext _restrictedContext(List<String> permissions) {
  return TenantContext(
    tenantId: 'tenant-a',
    tenantName: 'Herosimini Committee',
    events: const [
      EventSummary(
        id: 'event-1',
        name: 'Main Event',
        status: 'ACTIVE',
        eventType: 'WEDDING',
        eventDate: '2026-08-24',
        totalPledged: 100000,
        totalCollected: 40000,
        totalOutstanding: 60000,
      ),
    ],
    permissions: permissions,
    isOwner: false,
    accessState: 'ACTIVE',
  );
}

Map<String, dynamic> _invitation({
  required String id,
  required String eventMemberId,
  required String status,
  Map<String, dynamic>? rsvp,
  int maxGuests = 4,
  int publicTokenVersion = 1,
}) {
  return {
    'id': id,
    'eventId': 'event-1',
    'eventMemberId': eventMemberId,
    'memberId': 'member-$eventMemberId',
    'memberName': 'Victor Prever Kinabo',
    'phone': '+255712345678',
    'displayName': 'Victor Prever Kinabo & Family',
    'maxGuests': maxGuests,
    'status': status,
    'publicTokenVersion': publicTokenVersion,
    'template': null,
    'rsvp': rsvp,
    'deliveries': <Map<String, dynamic>>[],
    'viewCount': 0,
    'firstViewedAt': null,
    'lastViewedAt': null,
    'activatedAt': status != 'DRAFT' ? '2026-08-01T00:00:00Z' : null,
    'cancelledAt': status == 'CANCELLED' ? '2026-08-02T00:00:00Z' : null,
    'createdAt': '2026-07-01T00:00:00Z',
    'updatedAt': '2026-07-01T00:00:00Z',
  };
}

void main() {
  testWidgets(
    '1. Invitations and RSVP tabs are hidden without invitation.view/rsvp.view',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(
        api,
        tenantContext: _restrictedContext(const ['events.view']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invitations'), findsNothing);
      expect(find.text('RSVP'), findsNothing);
    },
  );

  testWidgets(
    'Invitations and RSVP tabs are visible with invitation.view/rsvp.view',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(
        api,
        tenantContext: _restrictedContext(const [
          'events.view',
          'invitation.view',
          'rsvp.view',
        ]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Invitations'), findsOneWidget);
      expect(find.text('RSVP'), findsOneWidget);
    },
  );

  testWidgets(
    '2. empty Invitations state shows the create-invitations action',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationsTab(
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No invitations have been created for this event.'),
        findsOneWidget,
      );
      expect(find.text('Create Invitations'), findsWidgets);
    },
  );

  testWidgets(
    '3. invitation list rows render with name, status and RSVP summary',
    (tester) async {
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(
          id: 'inv-1',
          eventMemberId: 'em-1',
          status: 'ACTIVE',
          rsvp: {
            'response': 'ATTENDING',
            'attendingCount': 3,
            'note': null,
            'submittedByType': 'PUBLIC_GUEST',
            'respondedAt': '2026-08-01T00:00:00Z',
            'guestNames': ['Victor Kinabo', 'Mary Kinabo'],
          },
        ),
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationsTab(
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Victor Prever Kinabo'), findsOneWidget);
      expect(find.textContaining('Attending'), findsWidgets);
      expect(find.textContaining('3 of 4'), findsOneWidget);
    },
  );

  testWidgets(
    '4/5/6. status filter, RSVP filter and search all reach the server-side list API',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InvitationsTab(
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.lastListInvitationsArgs?['status'], 'ALL');
      expect(api.lastListInvitationsArgs?['rsvpStatus'], 'ALL');

      await tester.enterText(find.byType(TextField).first, 'Victor');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(api.lastListInvitationsArgs?['search'], 'Victor');

      await tester.tap(find.textContaining('Status:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();
      expect(api.lastListInvitationsArgs?['status'], 'ACTIVE');

      await tester.tap(find.textContaining('RSVP:'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Attending').last);
      await tester.pumpAndSettle();
      expect(api.lastListInvitationsArgs?['rsvpStatus'], 'ATTENDING');
    },
  );

  testWidgets(
    '7/8. bulk creation lets eligible members be selected and already-invited members are shown but not selectable',
    (tester) async {
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(
          id: 'inv-existing',
          eventMemberId: 'em-a',
          status: 'ACTIVE',
        ),
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: BulkCreateInvitationsScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // fake eventMembers() always returns a single row with event_member_id 'em-a'.
      expect(find.text('Invitation already exists'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Nothing was selectable (the only member already has an
      // invitation) -> tapping Next surfaces the guard message and keeps
      // the user on step 1 instead of silently advancing.
      expect(find.text('Select at least one member.'), findsOneWidget);
      // Still on step 1's content (the step indicator itself always shows
      // all three step labels, so this checks for step-1-specific content
      // rather than the indicator label).
      expect(find.text('Select all eligible members'), findsOneWidget);
    },
  );

  testWidgets(
    '9. Create Invitation from Member Detail preselects the member name',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: SingleCreateInvitationScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            eventMemberId: 'em-a',
            memberName: 'Jane Contact',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'Jane Contact');
      // The member is never asked to be re-selected: no member picker exists
      // on this screen.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    },
  );

  testWidgets(
    '10/11/12. invitation detail shows Activate for DRAFT, public-link actions for ACTIVE, and none for CANCELLED',
    (tester) async {
      // A tall viewport so the whole ListView (Guest/Invitation/RSVP/Public
      // Link/Actions) is materialized -- Flutter's sliver-backed ListView
      // only mounts children within the viewport, so a short default test
      // window would hide the bottom action buttons from finders entirely.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-draft', eventMemberId: 'em-a', status: 'DRAFT'),
      );
      var controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            key: const ValueKey('inv-draft'),
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-draft',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Activate'), findsOneWidget);
      expect(find.text('Copy Link'), findsNothing);

      final api2 = FakeAhadiApi();
      api2.invitationRecords.add(
        _invitation(id: 'inv-active', eventMemberId: 'em-a', status: 'ACTIVE'),
      );
      controller = _buildController(api2);
      // A fresh Key forces a new State (and therefore a fresh initState/
      // future) -- without it, pumpWidget would reuse the previous
      // InvitationDetailScreen's State object since it's the same widget
      // type at the same tree position, exactly as real Navigator.push
      // instances never would (each push always mounts a brand new route).
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            key: const ValueKey('inv-active'),
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-active',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Rotate Link'), findsOneWidget);
      expect(find.text('Cancel Invitation'), findsOneWidget);

      final api3 = FakeAhadiApi();
      api3.invitationRecords.add(
        _invitation(
          id: 'inv-cancelled',
          eventMemberId: 'em-a',
          status: 'CANCELLED',
        ),
      );
      controller = _buildController(api3);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            key: const ValueKey('inv-cancelled'),
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-cancelled',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Copy Link'), findsNothing);
      expect(find.text('Rotate Link'), findsNothing);
      expect(find.text('Cancel Invitation'), findsNothing);
      expect(
        find.text(
          'This invitation is cancelled. Its public link no longer works.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '13. reducing max guests below the current RSVP count shows a friendly error',
    (tester) async {
      final api = FakeAhadiApi();
      api.updateInvitationError = const ApiFailure(
        kind: ApiFailureKind.conflict,
        message: 'Guest limit below RSVP count',
        code: 'INVITATION_GUEST_LIMIT_BELOW_RSVP_COUNT',
        statusCode: 409,
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: EditInvitationScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitation: _invitation(
              id: 'inv-1',
              eventMemberId: 'em-a',
              status: 'ACTIVE',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Maximum guests cannot be lower than the current RSVP guest count.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '14/15/16. manual RSVP: ATTENDING and MAYBE send a guest count, NOT_ATTENDING forces zero and hides guest fields',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(api);
      final invitation = _invitation(
        id: 'inv-1',
        eventMemberId: 'em-a',
        status: 'ACTIVE',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ManualRsvpForm(
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              invitation: invitation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Defaults to ATTENDING with guest fields visible.
      expect(find.text('Guest Names'), findsOneWidget);
      await tester.tap(find.text('Save RSVP'));
      await tester.pumpAndSettle();
      expect(api.lastManualRsvpPayload?['response'], 'ATTENDING');
      expect(api.lastManualRsvpPayload?['attendingCount'], 1);

      await tester.tap(find.text('Maybe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save RSVP'));
      await tester.pumpAndSettle();
      expect(api.lastManualRsvpPayload?['response'], 'MAYBE');

      await tester.tap(find.text('Not Attending'));
      await tester.pumpAndSettle();
      expect(find.text('Guest Names'), findsNothing);
      await tester.tap(find.text('Save RSVP'));
      await tester.pumpAndSettle();
      expect(api.lastManualRsvpPayload?['response'], 'NOT_ATTENDING');
      expect(api.lastManualRsvpPayload?['attendingCount'], 0);
      expect(api.lastManualRsvpPayload?['guestNames'], isEmpty);
    },
  );

  testWidgets(
    '17/18. RSVP dashboard keeps invitation counts and guest counts visually distinct, and shows No Response',
    (tester) async {
      final api = FakeAhadiApi();
      api.invitationRecords.addAll([
        _invitation(
          id: 'inv-1',
          eventMemberId: 'em-1',
          status: 'ACTIVE',
          rsvp: {
            'response': 'ATTENDING',
            'attendingCount': 3,
            'guestNames': [],
          },
        ),
        _invitation(id: 'inv-2', eventMemberId: 'em-2', status: 'ACTIVE'),
      ]);
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RsvpDashboardTab(
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AhadiSectionCard renders its title uppercased.
      expect(find.text('RSVP RESPONSES'), findsOneWidget);
      expect(find.text('GUEST COUNT'), findsOneWidget);
      expect(find.text('Confirmed Guests'), findsOneWidget);
      expect(find.text('No Response'), findsOneWidget);
      // 1 attending invitation vs 3 confirmed guests -- must both be visible,
      // distinctly, not conflated into a single number.
      expect(find.text('1'), findsWidgets);
      expect(find.text('3'), findsWidgets);
    },
  );

  testWidgets('19. Rotate Link updates the displayed share URL', (
    tester,
  ) async {
    // Tall viewport so the action buttons are actually materialized and
    // hit-testable (Flutter's sliver-backed ListView only mounts/positions
    // children within the viewport).
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = FakeAhadiApi();
    api.invitationRecords.add(
      _invitation(
        id: 'inv-1',
        eventMemberId: 'em-a',
        status: 'ACTIVE',
        publicTokenVersion: 1,
      ),
    );
    final controller = _buildController(api);
    await tester.pumpWidget(
      MaterialApp(
        home: InvitationDetailScreen(
          controller: controller,
          event: controller.selectedTenantContext!.events.first,
          invitationId: 'inv-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('-v1'), findsOneWidget);

    await tester.tap(find.text('Rotate Link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rotate Link').last);
    await tester.pumpAndSettle();

    expect(api.rotateLinkCalls, 1);
    expect(find.textContaining('-v2'), findsOneWidget);
    expect(find.textContaining('-v1'), findsNothing);
  });

  testWidgets(
    '20. a mutation (activate) refreshes the invitation detail state without leaving the screen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-1', eventMemberId: 'em-a', status: 'DRAFT'),
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Draft'), findsOneWidget);

      await tester.ensureVisible(find.text('Activate'));
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate').last);
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Draft'), findsNothing);
    },
  );

  testWidgets('21. a user without rsvp.manage cannot record an RSVP', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    api.invitationRecords.add(
      _invitation(id: 'inv-1', eventMemberId: 'em-a', status: 'ACTIVE'),
    );
    final controller = _buildController(
      api,
      tenantContext: _restrictedContext(const [
        'events.view',
        'invitation.view',
      ]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InvitationDetailScreen(
          controller: controller,
          event: controller.selectedTenantContext!.events.first,
          invitationId: 'inv-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Record RSVP'), findsNothing);
    expect(find.text('Edit RSVP'), findsNothing);
  });

  testWidgets(
    '22. the invitations tab does not overflow on a narrow phone-sized viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(
          id: 'inv-1',
          eventMemberId: 'em-1',
          status: 'ACTIVE',
          rsvp: {
            'response': 'ATTENDING',
            'attendingCount': 3,
            'guestNames': ['Victor Kinabo', 'Mary Kinabo'],
          },
        ),
      );
      final controller = _buildController(api);
      // Matches real usage: EventDetailScreen always hosts InvitationsTab
      // inside its own scrollable ListView, exactly like the pre-existing
      // _MembersTab -- it is not meant to be self-scrolling standalone.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InvitationsTab(
                controller: controller,
                event: controller.selectedTenantContext!.events.first,
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate-name regression: two event members named "JULIAS KINABO" (event_member A and B) must never be confused -- only B has an invitation',
    (tester) async {
      final api = FakeAhadiApi();
      // Only event member B gets an invitation record. Both share the
      // exact same full_name/memberName on purpose.
      api.invitationRecords.add(
        _invitation(
          id: 'inv-b',
          eventMemberId: 'event-member-B',
          status: 'ACTIVE',
        )..['memberName'] = 'JULIAS KINABO',
      );
      final controller = _buildController(api);

      // Open A's Member Detail section first -- must show "no invitation",
      // never B's, despite the identical name.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventMemberInvitationSection(
              key: const ValueKey('event-member-A'),
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              eventMemberId: 'event-member-A',
              memberName: 'JULIAS KINABO',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No invitation created'), findsOneWidget);
      expect(find.text('Active'), findsNothing);

      // Now open B's Member Detail section -- must show B's own
      // invitation.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventMemberInvitationSection(
              key: const ValueKey('event-member-B'),
              controller: controller,
              event: controller.selectedTenantContext!.events.first,
              eventMemberId: 'event-member-B',
              memberName: 'JULIAS KINABO',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No invitation created'), findsNothing);
      expect(find.text('Active'), findsOneWidget);
    },
  );

  testWidgets(
    'permission override: TENANT_OWNER role with invitation.cancel explicitly absent from effective permissions must not show Cancel, while other invitation actions still work',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-1', eventMemberId: 'em-a', status: 'ACTIVE'),
      );
      // isOwner: true (as a real TENANT_OWNER row would report), but the
      // effective permissions list does NOT include invitation.cancel --
      // proving the UI defers to permissions, not the isOwner flag, for
      // this action. invitation.edit and rsvp.manage remain granted, so
      // Edit/Record RSVP must still work normally.
      final controller = _buildController(
        api,
        tenantContext: TenantContext(
          tenantId: 'tenant-a',
          tenantName: 'Herosimini Committee',
          events: defaultTestEvents,
          permissions: const [
            'invitation.view',
            'invitation.edit',
            'rsvp.manage',
          ],
          isOwner: true,
          accessState: 'ACTIVE',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Cancel Invitation'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Record RSVP'), findsOneWidget);
    },
  );

  testWidgets(
    'permission override: rsvp.manage explicitly absent hides Record/Edit RSVP even with isOwner true and invitation.edit/cancel granted',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-1', eventMemberId: 'em-a', status: 'ACTIVE'),
      );
      final controller = _buildController(
        api,
        tenantContext: TenantContext(
          tenantId: 'tenant-a',
          tenantName: 'Herosimini Committee',
          events: defaultTestEvents,
          permissions: const [
            'invitation.view',
            'invitation.edit',
            'invitation.cancel',
          ],
          isOwner: true,
          accessState: 'ACTIVE',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationDetailScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Record RSVP'), findsNothing);
      expect(find.text('Edit RSVP'), findsNothing);
      expect(find.text('Cancel Invitation'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
    },
  );
}

const defaultTestEvents = [
  EventSummary(
    id: 'event-1',
    name: 'Main Event',
    status: 'ACTIVE',
    eventType: 'WEDDING',
    eventDate: '2026-08-24',
    totalPledged: 100000,
    totalCollected: 40000,
    totalOutstanding: 60000,
  ),
];

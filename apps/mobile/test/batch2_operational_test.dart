import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/core/errors/api_failure.dart';
import 'package:ahadi_mobile/core/widgets/formatters.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/auth/presentation/login_screen.dart';
import 'package:ahadi_mobile/features/contacts/presentation/contacts_screen.dart';
import 'package:ahadi_mobile/features/dashboard/presentation/dashboard_screen.dart';
import 'package:ahadi_mobile/features/events/presentation/events_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  test('dashboard/event JSON parsing supports server financial fields', () {
    final event = EventSummary.fromJson({
      'id': 'event-a',
      'name': 'Wedding',
      'eventType': 'WEDDING',
      'eventDate': '2026-08-14',
      'status': 'ACTIVE',
      'totalPledged': 1250000,
      'totalCollected': 500000,
      'totalOutstanding': 750000,
    });
    expect(event.eventType, 'WEDDING');
    expect(event.totalPledged, 1250000);
    expect(event.totalCollected, 500000);
  });

  test('money and date formatting are mobile friendly', () {
    expect(moneyText(1250000), 'TZS 1,250,000');
    expect(moneyText('500000'), 'TZS 500,000');
    expect(dateText('2026-08-14T10:30:00.000Z'), '14 Aug 2026');
  });

  test('network failures expose friendly message only', () {
    const failure = ApiFailure(
      kind: ApiFailureKind.networkUnavailable,
      message: "Failed host lookup: 'api.yuiop.work'",
    );
    expect(failure.friendlyMessage, contains('No internet connection'));
    expect(failure.friendlyMessage, isNot(contains('api.yuiop.work')));
    expect(failure.friendlyMessage, isNot(contains('Failed host lookup')));
  });

  testWidgets('login includes create organization signup action', (
    tester,
  ) async {
    final controller = SessionController(
      api: FakeAhadiApi(),
      storage: MemorySessionStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(controller: controller)),
    );
    expect(find.byKey(const Key('create-organization-signup')), findsOneWidget);
    expect(find.text('Create Organization'), findsOneWidget);
  });

  testWidgets('event status is rendered from backend value', (tester) async {
    final api = FakeAhadiApi();
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
    controller.selectedTenantContext = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventsScreen(controller: controller)),
      ),
    );
    expect(find.text('ACTIVE'), findsOneWidget);
    expect(find.text('Main Event'), findsOneWidget);
  });

  testWidgets('contact search debounce filters list', (tester) async {
    final api = FakeAhadiApi();
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
    controller.selectedTenantContext = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ContactsScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Jane Contact'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'missing');
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Jane Contact'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    expect(find.text('No contacts found.'), findsOneWidget);
  });

  testWidgets('permission-controlled create event action is disabled', (
    tester,
  ) async {
    final api = FakeAhadiApi();
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
    controller.selectedTenantContext = const TenantContext(
      tenantId: 'tenant-a',
      tenantName: 'Read Only',
      events: [
        EventSummary(
          id: 'event-1',
          name: 'Main Event',
          status: 'ACTIVE',
          eventType: 'WEDDING',
        ),
      ],
      permissions: ['events.view'],
      isOwner: false,
      accessState: 'ACTIVE',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EventsScreen(controller: controller)),
      ),
    );
    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.add).first,
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  test('organization switch clears tenant-scoped context before loading next tenant', () async {
    final api = FakeAhadiApi()
      ..userContext = userWithMemberships([
        membership('tenant-a', 'Herosimini Committee'),
        membership('tenant-b', 'Valentino Group'),
      ]);
    final controller = SessionController(
      api: api,
      storage: MemorySessionStorage(),
    );
    controller.credentials = const SessionCredentials(
      accessToken: 'a',
      refreshToken: 'r',
    );
    controller.userContext = api.userContext;
    await controller.selectTenant('tenant-a');
    var cleared = false;
    controller.addListener(() {
      if (controller.selectedTenantContext == null) cleared = true;
    });
    await controller.switchTenant('tenant-b');
    expect(cleared, isTrue);
    expect(controller.selectedTenantId, 'tenant-b');
  });

  test(
    'single active event is auto-selected and logout clears selected event',
    () async {
      final storage = MemorySessionStorage()
        ..session = const SessionCredentials(
          accessToken: 'a',
          refreshToken: 'r',
        );
      final api = FakeAhadiApi();
      final controller = SessionController(api: api, storage: storage);
      await controller.initialize();
      expect(controller.selectedEventId, 'event-1');
      await controller.signOut();
      expect(controller.selectedEventId, isNull);
      expect(storage.selectedEventIds, isEmpty);
    },
  );

  test('selected event is restored per tenant', () async {
    final storage = MemorySessionStorage();
    final api = FakeAhadiApi()
      ..userContext = userWithMemberships([
        membership('tenant-a', 'Herosimini Committee'),
        membership('tenant-b', 'Valentino Group'),
      ]);
    api.tenantContexts['tenant-a'] = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
      events: const [
        EventSummary(
          id: 'event-a1',
          name: 'A One',
          status: 'ACTIVE',
          eventType: 'WEDDING',
        ),
        EventSummary(
          id: 'event-a2',
          name: 'A Two',
          status: 'ACTIVE',
          eventType: 'SENDOFF',
        ),
      ],
    );
    api.tenantContexts['tenant-b'] = makeTenantContext(
      'tenant-b',
      'Valentino Group',
      events: const [
        EventSummary(
          id: 'event-b1',
          name: 'B One',
          status: 'ACTIVE',
          eventType: 'WEDDING',
        ),
      ],
    );
    final controller = SessionController(api: api, storage: storage)
      ..credentials = const SessionCredentials(
        accessToken: 'a',
        refreshToken: 'r',
      )
      ..userContext = api.userContext;
    await controller.selectTenant('tenant-a');
    expect(controller.selectedEventId, isNull);
    await controller.selectEvent('event-a2');
    await controller.switchTenant('tenant-b');
    expect(controller.selectedEventId, 'event-b1');
    await controller.switchTenant('tenant-a');
    expect(controller.selectedEventId, 'event-a2');
  });

  testWidgets('dashboard KPIs use selected event summary', (tester) async {
    final api = FakeAhadiApi()
      ..eventSummaries['event-1'] = {
        'totalPledged': 222000,
        'totalAllocated': 111000,
        'totalOutstanding': 111000,
        'memberCount': 5,
      };
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
    controller.selectedTenantContext = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
    );
    controller.selectedEventId = 'event-1';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DashboardScreen(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('TZS 222,000'), findsOneWidget);
    expect(find.text('TZS 111,000'), findsWidgets);
    expect(find.text('5'), findsOneWidget);
  });

  test(
    'pledge creation payload uses selected tenant and event member',
    () async {
      final api = FakeAhadiApi();
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
      controller.selectedTenantContext = makeTenantContext(
        'tenant-a',
        'Herosimini Committee',
      );
      await controller.upsertPledge('event-1', {
        'eventMemberId': 'em-a',
        'amount': 100000,
        'dueDate': null,
        'notes': null,
        'changeReason': null,
      });
      expect(api.lastTenantId, 'tenant-a');
      expect(api.lastPledgePayload?['eventMemberId'], 'em-a');
    },
  );

  test('create contact normalizes phone before API call', () async {
    final api = FakeAhadiApi();
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
    controller.selectedTenantContext = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
    );
    await controller.createContact({
      'fullName': 'Jane Contact',
      'phone': '+255712345678',
    });
    expect(api.lastCreatedContact?['phone'], '+255712345678');
  });

  test(
    'update contact uses member patch payload and normalizes phone',
    () async {
      final api = FakeAhadiApi();
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
      controller.selectedTenantContext = makeTenantContext(
        'tenant-a',
        'Herosimini Committee',
      );
      await controller.updateContact('member-a', {
        'fullName': 'Jane Contact',
        'phoneE164': '0712345678',
        'alternativePhoneE164': '',
      });
      expect(api.lastTenantId, 'tenant-a');
      expect(api.lastUpdatedContact?['phoneE164'], '+255712345678');
      expect(api.lastUpdatedContact?['alternativePhoneE164'], '');
    },
  );

  test('duplicate event-member attach error is surfaced', () async {
    final api = FakeAhadiApi()
      ..attachError = const ApiFailure(
        kind: ApiFailureKind.conflict,
        message: 'This contact is already part of this event.',
        code: 'MEMBER_ALREADY_IN_EVENT',
        statusCode: 409,
      );
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
    controller.selectedTenantContext = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
    );
    expect(
      controller.attachEventMember('event-1', 'member-a'),
      throwsA(isA<ApiFailure>()),
    );
  });
}

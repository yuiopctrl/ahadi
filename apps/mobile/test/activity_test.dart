import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/activity/presentation/activity_screen.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets('organization owner can open Activity from the More menu', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: MobileShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);

    await tester.ensureVisible(find.text('Activity'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();

    expect(api.activityCalls, greaterThanOrEqualTo(1));
    expect(find.text('Fred Mushi'), findsWidgets);
    expect(find.textContaining('Contact edited'), findsOneWidget);
    expect(find.textContaining('Payment recorded'), findsOneWidget);
  });

  testWidgets('unauthorized role does not see Activity in the More menu', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(
      api,
      isOwner: false,
      permissions: const ['events.view', 'members.view'],
    );
    await tester.pumpWidget(
      MaterialApp(home: MobileShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Activity'), findsNothing);
  });

  testWidgets('activity search filters rows through the API call', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ActivityScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'payment');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(api.lastActivitySearch, 'payment');
    expect(find.textContaining('Payment recorded'), findsOneWidget);
    expect(find.textContaining('Contact edited'), findsNothing);
  });

  testWidgets('activity filter tab scopes to contacts entity type', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ActivityScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Contacts'));
    await tester.pumpAndSettle();

    expect(api.lastActivityEntityType, 'member');
    expect(find.textContaining('Contact edited'), findsOneWidget);
    expect(find.textContaining('Payment recorded'), findsNothing);
  });

  testWidgets('tapping an activity row opens the detail with changed fields', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ActivityScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Contact edited').first);
    await tester.pumpAndSettle();

    expect(find.text('Activity Detail'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('+255712345678'), findsOneWidget);
  });

  testWidgets('activity empty state renders when there is no activity', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    api.activityRows = [];
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ActivityScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('No activity yet.'), findsOneWidget);
  });
}

SessionController _readyController(
  FakeAhadiApi api, {
  bool isOwner = true,
  List<String>? permissions,
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
  final base = makeTenantContext('tenant-a', 'Herosimini Committee');
  controller.selectedTenantContext = TenantContext(
    tenantId: base.tenantId,
    tenantName: base.tenantName,
    events: base.events,
    permissions: permissions ?? base.permissions,
    isOwner: isOwner,
    accessState: base.accessState,
    subscription: base.subscription,
  );
  controller.selectedEventId = 'event-1';
  return controller;
}

import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/organizations/presentation/create_organization_screen.dart';
import 'package:ahadi_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets('more menu opens tenant subscription with usage and billing', (
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
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription'));
    await tester.pumpAndSettle();

    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('TRIAL'), findsOneWidget);
    expect(find.text('Used event slots'), findsOneWidget);
    expect(find.text('Open balance'), findsOneWidget);
    expect(find.text('TZS 15,000'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('INV-0001'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('subscription-change-plan-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('subscription-change-plan-button')));
    await tester.pumpAndSettle();

    expect(find.text('Change Plan'), findsOneWidget);
    expect(find.text('Basic · Current'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.textContaining('Plan switching is handled'), findsOneWidget);
  });

  testWidgets('organization onboarding shows package price trial and limits', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);

    await tester.pumpWidget(
      MaterialApp(home: CreateOrganizationScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan-card-BASIC')), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);
    expect(find.text('TZS 20,000 / monthly'), findsOneWidget);
    expect(find.text('monthly billing · 14 trial days'), findsWidgets);
    expect(find.text('2 active events'), findsOneWidget);
    expect(find.text('100 SMS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-card-GROWTH')));
    await tester.pumpAndSettle();
    expect(find.text('Growth'), findsOneWidget);
  });
}

SessionController _readyController(FakeAhadiApi api) {
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
  controller.selectedEventId =
      controller.selectedTenantContext!.events.first.id;
  return controller;
}

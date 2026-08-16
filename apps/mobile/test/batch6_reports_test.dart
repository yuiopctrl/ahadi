import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/reports/presentation/reports_screen.dart';
import 'package:ahadi_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets(
    'more menu opens reports and financial summary uses server totals',
    (tester) async {
      final api = FakeAhadiApi()
        ..eventSummaries['event-1'] = {
          'memberCount': 3,
          'membersWithPledges': 2,
          'membersWithoutPledges': 1,
          'totalPledged': 12500000,
          'totalAllocatedToPledges': 8750000,
          'totalOutstanding': 3750000,
        };
      final controller = _readyController(api);

      await tester.pumpWidget(
        MaterialApp(home: MobileShell(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -280));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();

      expect(find.text('EVENT REPORTS'), findsOneWidget);
      expect(find.text('Financial Summary'), findsOneWidget);
      expect(find.text('Events Summary'), findsOneWidget);

      await tester.tap(find.text('Financial Summary'));
      await tester.pumpAndSettle();

      expect(api.lastTenantId, 'tenant-a');
      expect(find.text('TZS 12,500,000'), findsOneWidget);
      expect(find.text('TZS 8,750,000'), findsOneWidget);
      expect(find.text('TZS 3,750,000'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
    },
  );

  testWidgets('pledges report is selected-event scoped and server searched', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);

    await tester.pumpWidget(
      MaterialApp(home: PledgeReportScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jane Contact'), findsOneWidget);
    expect(api.lastTenantId, 'tenant-a');
    expect(api.lastEventId, 'event-1');
    expect(api.lastReportType, 'pledges');
    expect(api.lastReportPayload?['pageSize'], 20);

    final initialCalls = api.eventReportCalls;
    await tester.enterText(
      find.byKey(const Key('reports-pledges-search')),
      '071',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.eventReportCalls, initialCalls);
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.lastReportPayload?['search'], '071');
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

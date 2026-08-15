import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/messages/presentation/messages_screens.dart';
import 'package:ahadi_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets('more menu opens event-scoped messages screen', (tester) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: MobileShell(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();

    expect(find.text('Messages'), findsWidgets);
    expect(find.text('Main Event'), findsOneWidget);
    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });

  testWidgets(
    'composer previews and queues balance reminders with confirmation',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _readyController(api);
      await tester.pumpWidget(
        MaterialApp(home: MessagesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Balance Reminder'), findsWidgets);
      expect(find.textContaining('salio lako'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-message-button')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm Message'), findsOneWidget);
      await tester.tap(find.textContaining('Send ').last);
      await tester.pumpAndSettle();

      expect(api.sendBalanceReminderCalls, 1);
      expect(api.lastSmsSendPayload?['eventMemberIds'], ['em-a']);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('2 recipients'), findsOneWidget);
      expect(
        find.textContaining('Messages queued successfully'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'history shows selected event messages and supports failed retry',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _readyController(api);
      await tester.pumpWidget(
        MaterialApp(home: MessagesScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('Balance Reminder'), findsOneWidget);
      expect(find.text('2 recipients'), findsOneWidget);

      await tester.tap(find.text('Balance Reminder'));
      await tester.pumpAndSettle();
      expect(find.text('Message Details'), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -260));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry').last);
      await tester.pumpAndSettle();

      expect(api.retrySmsCalls, 1);
      expect(find.text('Message queued for retry.'), findsOneWidget);
    },
  );

  testWidgets('messaging settings load provider sender and templates', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: MessagingSettingsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('SMS SETTINGS'), findsOneWidget);
    expect(find.text('NEXTSMS'), findsNothing);
    expect(find.text('MICHANGO'), findsWidgets);
    expect(find.text('Pledge Request'), findsOneWidget);
    expect(find.text('Balance Reminder'), findsOneWidget);
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
    events: const [
      EventSummary(
        id: 'event-1',
        name: 'Main Event',
        status: 'ACTIVE',
        eventType: 'WEDDING',
      ),
    ],
  );
  controller.selectedEventId = 'event-1';
  return controller;
}

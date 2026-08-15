import 'dart:io';

import 'package:ahadi_mobile/core/theme/ahadi_theme.dart';
import 'package:ahadi_mobile/core/widgets/formatters.dart';
import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/financial/presentation/financial_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var clipboardText = '';

  setUp(() {
    clipboardText = '';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments;
            if (args is Map && args['text'] is String) {
              clipboardText = args['text'] as String;
            }
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('Ubuntu fonts and money formatter are configured', () {
    final theme = ahadiTheme();
    expect(theme.textTheme.bodyMedium?.fontFamily, AhadiTypography.sans);
    expect(AhadiTypography.mono, 'Ubuntu Mono');
    expect(
      const MoneyInputFormatter()
          .formatEditUpdate(
            const TextEditingValue(),
            const TextEditingValue(text: '50000'),
          )
          .text,
      '50,000',
    );
    expect(moneyInputValue('50,000'), 50000);
  });

  testWidgets('payments screen uses selected event report and pagination', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: PaymentsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Jane Contact'), findsOneWidget);
    expect(find.textContaining('TZS 150,000'), findsOneWidget);
    expect(find.textContaining('Receipt AHADI-0001'), findsOneWidget);
    expect(api.lastTenantId, 'tenant-a');
    expect(api.lastEventId, 'event-1');
    expect(api.lastReportType, 'payments');
    expect(api.lastReportPayload?['pageSize'], 20);
  });

  testWidgets('payment search is debounced and server scoped', (tester) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: PaymentsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    final initialCalls = api.eventReportCalls;

    await tester.enterText(find.byKey(const Key('payments-search')), 'Jane');
    await tester.pump(const Duration(milliseconds: 299));
    expect(api.eventReportCalls, initialCalls);
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(api.lastReportPayload?['search'], 'Jane');
    expect(api.lastEventId, 'event-1');
  });

  testWidgets(
    'record payment validates amount and renders overpayment preview',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _readyController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: RecordPaymentScreen(
            controller: controller,
            initialMember: const {
              'pledgeId': 'pledge-a',
              'eventMemberId': 'em-a',
              'member': 'Jane Contact',
              'phone': '+255712345678',
              'pledged': 100000,
              'paid': 40000,
              'outstanding': 60000,
              'effectiveDueDate': '2026-08-24',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      await tester.tap(find.byKey(const Key('record-payment-submit')).last);
      await tester.pump();
      expect(find.text('Enter a valid payment amount.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('payment-amount-input')),
        '150000',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('server will allocate the amount'),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pump();
      await tester.tap(find.byKey(const Key('record-payment-submit')).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Payment').last);
      await tester.pumpAndSettle();

      expect(api.recordPaymentCalls, 1);
      expect(api.lastPaymentPayload?['eventMemberId'], 'em-a');
      expect(api.lastPaymentPayload?['pledgeId'], 'pledge-a');
      expect(api.lastPaymentPayload?['amount'], 150000);
      expect(api.lastPaymentPayload?['idempotencyKey'], isNotNull);
      expect(find.text('Payment recorded successfully'), findsOneWidget);
    },
  );

  testWidgets('payment details hide reversal for users without permission', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(
      api,
      context: const TenantContext(
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
        permissions: ['payments.view'],
        isOwner: false,
        accessState: 'ACTIVE',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PaymentDetailScreen(
          controller: controller,
          payment: const {'paymentId': 'payment-a'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment Details'), findsOneWidget);
    expect(find.text('Reverse Payment'), findsNothing);
  });

  test('receipt image share payload writes png metadata', () async {
    final temp = await Directory.systemTemp.createTemp('ahadi-receipt-test-');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final payload = await receiptImageSharePayload(
      [137, 80, 78, 71],
      directory: temp,
      now: DateTime.fromMicrosecondsSinceEpoch(123456),
    );
    expect(payload['mimeType'], 'image/png');
    expect(payload['path'], contains('ahadi-receipt-123456.png'));
    expect(await File(payload['path']! as String).exists(), isTrue);
  });

  testWidgets('outstanding supports search, sort and record-payment reuse', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: OutstandingScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Total Outstanding'), findsOneWidget);
    expect(find.text('Jane Contact'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('outstanding-search')), 'Jane');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    expect(api.lastReportPayload?['search'], 'Jane');

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Due Date'));
    await tester.pumpAndSettle();
    expect(api.lastReportPayload?['sort'], 'DUE_DATE');
    expect(api.lastReportPayload?['direction'], 'ASC');

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    await tester.tap(find.text('Record Payment').last);
    await tester.pumpAndSettle();
    expect(find.text('Record Payment'), findsWidgets);
  });

  testWidgets('share list renders server preview and copies final text', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ShareListScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Share List'), findsWidgets);
    expect(find.textContaining('MUHTASARI'), findsOneWidget);
    await tester.tap(find.text('Detailed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Privacy Friendly').last);
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.whatsappPreviewCalls, greaterThanOrEqualTo(2));
    expect(api.lastEventId, 'event-1');

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-list-copy-button')));
    await tester.pump(const Duration(milliseconds: 350));
    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, contains('© AHADI APP'));
  });

  testWidgets('event switch reloads financial screens with new event scope', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final context = makeTenantContext(
      'tenant-a',
      'Herosimini Committee',
      events: const [
        EventSummary(
          id: 'event-1',
          name: 'Main Event',
          status: 'ACTIVE',
          eventType: 'WEDDING',
        ),
        EventSummary(
          id: 'event-2',
          name: 'Second Event',
          status: 'ACTIVE',
          eventType: 'SENDOFF',
        ),
      ],
    );
    final controller = _readyController(api, context: context);
    await tester.pumpWidget(
      MaterialApp(home: PaymentsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(api.lastEventId, 'event-1');

    await tester.enterText(find.byKey(const Key('payments-search')), 'Jane');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();
    await controller.selectEvent('event-2');
    await tester.pumpAndSettle();

    expect(find.text('Second Event'), findsOneWidget);
    expect(api.lastEventId, 'event-2');
    expect(api.lastReportPayload?['search'], '');
  });
}

SessionController _readyController(FakeAhadiApi api, {TenantContext? context}) {
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
      context ?? makeTenantContext('tenant-a', 'Herosimini Committee');
  controller.selectedEventId =
      controller.selectedTenantContext!.events.first.id;
  return controller;
}

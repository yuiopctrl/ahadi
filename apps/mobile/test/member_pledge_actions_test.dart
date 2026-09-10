import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/events/presentation/event_detail_screen.dart';
import 'package:ahadi_mobile/features/financial/presentation/financial_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

/// A stateful pledge fixture: eventMemberDetail reflects whatever
/// upsertPledge/recordPayment were last called with, so tests can assert
/// that Member Details actually refreshes with server-authoritative data
/// after a mutation instead of showing stale numbers.
class _StatefulPledgeApi extends FakeAhadiApi {
  Map<String, dynamic> memberState = {
    'event_member_id': 'em-a',
    'member_id': 'member-a',
    'full_name': 'Jane Contact',
    'phone_e164': '+255712345678',
    'pledge_id': null,
    'pledged_amount': 0,
    'total_allocated': 0,
    'outstanding_amount': 0,
    'pledge_status': null,
    'due_date': null,
  };

  @override
  Future<Map<String, dynamic>> eventMemberDetail(
    String tenantId,
    String eventId,
    String eventMemberId,
  ) async {
    lastTenantId = tenantId;
    return {
      'member': Map<String, dynamic>.from(memberState),
      'payments': <Map<String, dynamic>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> upsertPledge(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload, {
    String? pledgeId,
  }) async {
    lastTenantId = tenantId;
    lastPledgePayload = payload;
    final amount = (payload['amount'] as num?) ?? 0;
    final paid = (memberState['total_allocated'] as num?) ?? 0;
    final id = pledgeId ?? 'pledge-a';
    memberState = {
      ...memberState,
      'pledge_id': id,
      'pledged_amount': amount,
      'outstanding_amount': (amount - paid) < 0 ? 0 : (amount - paid),
      'pledge_status': paid >= amount && amount > 0 ? 'PAID' : 'PENDING',
    };
    return {'pledge_id': id, ...payload};
  }

  @override
  Future<Map<String, dynamic>> recordPayment(
    String tenantId,
    String eventId,
    Map<String, dynamic> payload,
  ) async {
    recordPaymentCalls += 1;
    lastTenantId = tenantId;
    lastEventId = eventId;
    lastPaymentPayload = payload;
    final amount = (payload['amount'] as num?) ?? 0;
    final pledged = (memberState['pledged_amount'] as num?) ?? 0;
    final paid = ((memberState['total_allocated'] as num?) ?? 0) + amount;
    memberState = {
      ...memberState,
      'total_allocated': paid,
      'outstanding_amount': (pledged - paid) < 0 ? 0 : (pledged - paid),
      'pledge_status': paid >= pledged ? 'PAID' : 'PARTIALLY_PAID',
    };
    return {
      'payment_id': 'payment-new',
      'payment_number': 'PAY-0002',
      'receipt_id': 'receipt-new',
      'receipt_number': 'AHADI-0002',
      'payment_amount': amount,
      'allocated_amount': amount,
      'unallocated_amount': 0,
      'outstanding_amount': memberState['outstanding_amount'],
    };
  }
}

const _memberDetailsEvent = EventSummary(
  id: 'event-1',
  name: 'Main Event',
  status: 'ACTIVE',
  eventType: 'WEDDING',
  eventDate: '2026-08-24',
  totalPledged: 100000,
  totalCollected: 40000,
  totalOutstanding: 60000,
);

/// isOwner is deliberately false and permissions explicit, so tests exercise
/// the same permission-based gating a real non-owner staff member would see
/// (makeTenantContext hardcodes isOwner: true, which would mask that).
TenantContext _tenantContext(List<String> permissions) {
  return TenantContext(
    tenantId: 'tenant-a',
    tenantName: 'Herosimini Committee',
    events: const [_memberDetailsEvent],
    permissions: permissions,
    isOwner: false,
    accessState: 'ACTIVE',
  );
}

SessionController _readyController(
  FakeAhadiApi api, {
  List<String> permissions = const [
    'pledges.create',
    'pledges.update',
    'payments.create',
  ],
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
  controller.selectedTenantContext = _tenantContext(permissions);
  // RecordPaymentScreen reads controller.selectedEvent (a separate concept
  // from the `event` parameter passed directly to EventMemberDetailScreen),
  // matching the real app where an event is always selected before Member
  // Details is reachable.
  controller.selectedEventId = _memberDetailsEvent.id;
  return controller;
}

Widget _buildScreen(SessionController controller) {
  final event = controller.selectedTenantContext!.events.first;
  return MaterialApp(
    home: EventMemberDetailScreen(
      controller: controller,
      event: event,
      eventMemberId: 'em-a',
    ),
  );
}

void main() {
  // 1. member with no pledge -> Record Pledge shown
  testWidgets('shows Record Pledge when the member has no active pledge', (
    tester,
  ) async {
    final api = _StatefulPledgeApi();
    final controller = _readyController(api);
    await tester.pumpWidget(_buildScreen(controller));
    await tester.pumpAndSettle();

    expect(
      find.text('No pledge has been recorded for this member.'),
      findsOneWidget,
    );
    expect(find.text('Record Pledge'), findsOneWidget);
    expect(find.text('Edit Pledge'), findsNothing);
    expect(find.text('Record Payment'), findsNothing);
  });

  // 2. member with active unpaid pledge -> Edit Pledge + Record Payment
  testWidgets(
    'shows Edit Pledge and Record Payment for an unpaid active pledge',
    (tester) async {
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': 'pledge-a',
          'pledged_amount': 100000,
          'total_allocated': 0,
          'outstanding_amount': 100000,
          'pledge_status': 'PENDING',
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      expect(find.text('Edit Pledge'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    },
  );

  // 3. member with partial payment -> correct pledged/paid/outstanding and both actions
  testWidgets(
    'shows correct pledged/paid/outstanding for a partially paid pledge',
    (tester) async {
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': 'pledge-a',
          'pledged_amount': 100000,
          'total_allocated': 40000,
          'outstanding_amount': 60000,
          'pledge_status': 'PARTIALLY_PAID',
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      expect(find.text('TZS 100,000'), findsWidgets);
      expect(find.text('TZS 40,000'), findsOneWidget);
      expect(find.text('TZS 60,000'), findsOneWidget);
      expect(find.text('Edit Pledge'), findsOneWidget);
      expect(find.text('Record Payment'), findsOneWidget);
    },
  );

  // 4. fully paid pledge -> Edit Pledge shown, Record Payment unavailable
  testWidgets(
    'hides Record Payment and shows Paid in Full once the pledge is fully paid',
    (tester) async {
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': 'pledge-a',
          'pledged_amount': 100000,
          'total_allocated': 100000,
          'outstanding_amount': 0,
          'pledge_status': 'PAID',
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      expect(find.text('Edit Pledge'), findsOneWidget);
      expect(find.text('Record Payment'), findsNothing);
      expect(find.text('Paid in Full'), findsOneWidget);
    },
  );

  // 5. create pledge from Member Details -> refreshes detail
  // 11. member/event/pledge context is preselected correctly (no re-selection)
  testWidgets(
    'recording a pledge from Member Details preselects the member and refreshes the view',
    (tester) async {
      final api = _StatefulPledgeApi();
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record Pledge'));
      await tester.pumpAndSettle();

      // The member picker must not appear -- Member Details already knows
      // exactly who this pledge is for.
      expect(find.text('Choose a member from this event.'), findsNothing);
      // Appears both in the Member Details header and the sheet's
      // preselected-member card.
      expect(find.text('Jane Contact'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('pledge-amount-input')),
        '100000',
      );
      await tester.tap(find.byKey(const Key('pledge-form-save')));
      await tester.pumpAndSettle();

      expect(api.lastPledgePayload?['eventMemberId'], 'em-a');
      // Sheet closed and Member Details refreshed with the new pledge.
      expect(
        find.text('No pledge has been recorded for this member.'),
        findsNothing,
      );
      expect(find.text('TZS 100,000'), findsWidgets);
      expect(find.text('Pledge saved.'), findsOneWidget);
    },
  );

  // 6. edit pledge -> updates displayed amounts
  // 12. no stale UI after mutation
  testWidgets(
    'editing a pledge updates the displayed amounts and clears the old value',
    (tester) async {
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': 'pledge-a',
          'pledged_amount': 100000,
          'total_allocated': 40000,
          'outstanding_amount': 60000,
          'pledge_status': 'PARTIALLY_PAID',
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      expect(find.text('TZS 100,000'), findsWidgets);

      await tester.tap(find.text('Edit Pledge'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '150000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(api.lastPledgePayload?['amount'], 150000);
      expect(api.lastPledgePayload?['eventMemberId'], 'em-a');
      // Refreshed from the authoritative member-detail response, not the
      // stale value that was on screen before editing.
      expect(find.text('TZS 100,000'), findsNothing);
      expect(find.text('TZS 150,000'), findsWidgets);
    },
  );

  // 7. record payment -> refreshes paid/outstanding
  testWidgets(
    'recording a payment refreshes paid and outstanding without leaving the screen',
    (tester) async {
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': 'pledge-a',
          'pledged_amount': 100000,
          'total_allocated': 40000,
          'outstanding_amount': 60000,
          'pledge_status': 'PARTIALLY_PAID',
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Record Payment'));
      await tester.pumpAndSettle();

      // No member search picker -- context (member/event/pledge) is already known.
      expect(
        find.byKey(const Key('record-payment-member-search')),
        findsNothing,
      );
      // Confirms we actually navigated to RecordPaymentScreen with the amount
      // field pre-populated (not just Member Details' own outstanding text).
      expect(find.byKey(const Key('payment-amount-input')), findsOneWidget);
      final amountField = tester.widget<TextField>(
        find.byKey(const Key('payment-amount-input')),
      );
      expect(amountField.controller?.text, '60,000');

      // Member Details' own ListView is still mounted underneath (Navigator
      // keeps prior routes built), and ListView only builds children within
      // its cache extent even with a plain (non-.builder) child list -- so
      // the submit button doesn't exist in the tree until scrolled into
      // range. Scope the drag to RecordPaymentScreen's own ListView.
      final recordPaymentList = find.descendant(
        of: find.byType(RecordPaymentScreen),
        matching: find.byType(ListView),
      );
      await tester.drag(recordPaymentList, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('record-payment-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm Payment').last);
      await tester.pumpAndSettle();

      expect(api.lastPaymentPayload?['eventMemberId'], 'em-a');
      expect(api.lastPaymentPayload?['pledgeId'], 'pledge-a');
      expect(api.lastPaymentPayload?['amount'], 60000);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Back on Member Details, fully refreshed: no outstanding balance left.
      expect(find.text('Paid in Full'), findsOneWidget);
      expect(find.text('Record Payment'), findsNothing);
    },
  );

  // 8. permission without pledge create -> no Record Pledge
  testWidgets('hides Record Pledge when the user lacks pledges.create', (
    tester,
  ) async {
    final api = _StatefulPledgeApi();
    final controller = _readyController(api, permissions: const []);
    await tester.pumpWidget(_buildScreen(controller));
    await tester.pumpAndSettle();

    expect(
      find.text('No pledge has been recorded for this member.'),
      findsOneWidget,
    );
    expect(find.text('Record Pledge'), findsNothing);
  });

  // 9. permission without payment create -> no Record Payment
  testWidgets('hides Record Payment when the user lacks payments.create', (
    tester,
  ) async {
    final api = _StatefulPledgeApi()
      ..memberState = {
        ..._StatefulPledgeApi().memberState,
        'pledge_id': 'pledge-a',
        'pledged_amount': 100000,
        'total_allocated': 40000,
        'outstanding_amount': 60000,
        'pledge_status': 'PARTIALLY_PAID',
      };
    final controller = _readyController(
      api,
      permissions: const ['pledges.update'],
    );
    await tester.pumpWidget(_buildScreen(controller));
    await tester.pumpAndSettle();

    expect(find.text('Edit Pledge'), findsOneWidget);
    expect(find.text('Record Payment'), findsNothing);
  });

  // 10. cancelled/non-active pledge does not get treated as active
  testWidgets(
    'a cancelled pledge (excluded server-side) is treated as no active pledge',
    (tester) async {
      // v_event_members_list already excludes CANCELLED pledges from its join,
      // so the authoritative member-detail response for a member whose only
      // pledge was cancelled looks identical to "never had a pledge": no
      // pledge_id, zeroed amounts. The UI must not invent an "active" state.
      final api = _StatefulPledgeApi()
        ..memberState = {
          ..._StatefulPledgeApi().memberState,
          'pledge_id': null,
          'pledged_amount': 0,
          'total_allocated': 0,
          'outstanding_amount': 0,
          'pledge_status': null,
        };
      final controller = _readyController(api);
      await tester.pumpWidget(_buildScreen(controller));
      await tester.pumpAndSettle();

      expect(
        find.text('No pledge has been recorded for this member.'),
        findsOneWidget,
      );
      expect(find.text('Record Pledge'), findsOneWidget);
      expect(find.text('Edit Pledge'), findsNothing);
    },
  );
}

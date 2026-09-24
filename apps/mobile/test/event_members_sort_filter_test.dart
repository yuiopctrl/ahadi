import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/events/presentation/event_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

class _RecordingApi extends FakeAhadiApi {
  final List<Map<String, dynamic>> calls = [];

  @override
  Future<Map<String, dynamic>> listEventMembers(
    String tenantId,
    String eventId, {
    String? search,
    String pledgeStatus = 'ALL',
    String phoneStatus = 'ALL',
    String sort = 'NAME',
    String direction = 'ASC',
    int? limit,
    int? offset,
  }) async {
    calls.add({
      'search': search,
      'pledgeStatus': pledgeStatus,
      'phoneStatus': phoneStatus,
      'sort': sort,
      'direction': direction,
    });
    return {
      'data': [
        {
          'event_member_id': 'em-a',
          'full_name': 'Jane Contact',
          'phone_e164': '+255712345678',
          'pledged_amount': 100000,
          'total_allocated': 40000,
          'outstanding_amount': 60000,
          'pledge_status': 'PARTIALLY_PAID',
        },
      ],
      'pagination': {
        'limit': limit,
        'offset': offset ?? 0,
        'totalRows': 1,
        'hasMore': false,
      },
    };
  }
}

void main() {
  testWidgets(
    'Event Members tab loads via listEventMembers and re-fetches on sort/filter change',
    (tester) async {
      final api = _RecordingApi();
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
      final event = controller.selectedTenantContext!.events.first;

      await tester.pumpWidget(
        MaterialApp(
          home: EventDetailScreen(controller: controller, event: event),
        ),
      );
      await tester.pumpAndSettle();

      // Members tab.
      await tester.tap(find.text('Members').first);
      await tester.pumpAndSettle();

      expect(api.calls, isNotEmpty);
      expect(api.calls.last['sort'], 'NAME');
      expect(api.calls.last['direction'], 'ASC');
      expect(find.text('Jane Contact'), findsOneWidget);

      // Change sort -> should re-fetch with the new sort key.
      await tester.tap(find.text('Sort: Name A-Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Outstanding: High to Low').last);
      await tester.pumpAndSettle();

      expect(api.calls.last['sort'], 'OUTSTANDING');
      expect(api.calls.last['direction'], 'DESC');

      // Change pledge filter -> should re-fetch with the filter applied.
      await tester.tap(find.text('Pledge: All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fully Paid').last);
      await tester.pumpAndSettle();

      expect(api.calls.last['pledgeStatus'], 'FULLY_PAID');
    },
  );
}

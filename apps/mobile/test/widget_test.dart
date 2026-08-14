import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/auth/presentation/login_screen.dart';
import 'package:ahadi_mobile/features/auth/presentation/pin_input.dart';
import 'package:ahadi_mobile/features/organizations/presentation/organization_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets('fourth PIN digit auto-submits', (tester) async {
    var submittedPin = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinInput(onCompleted: (pin) => submittedPin = pin),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('pin-input')), '2468');
    expect(submittedPin, '2468');
  });

  testWidgets('login screen submits phone and PIN without OTP', (tester) async {
    final api = FakeAhadiApi();
    final controller = SessionController(
      api: api,
      storage: MemorySessionStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(controller: controller)),
    );
    await tester.enterText(find.byKey(const Key('phone-input')), '0712345678');
    await tester.enterText(find.byKey(const Key('pin-input')), '2468');
    await tester.pump();
    expect(api.loginPinCalls, 1);
    expect(api.requestOtpCalls, 0);
  });

  testWidgets('organization selection selects tapped organization', (
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
    controller.userContext = userWithMemberships([
      membership('tenant-a', 'Herosimini Committee'),
      membership('tenant-b', 'Valentino Group'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: OrganizationSelectionScreen(
          controller: controller,
          memberships: controller.activeMemberships,
        ),
      ),
    );
    await tester.tap(find.text('Valentino Group'));
    await tester.pumpAndSettle();
    expect(controller.selectedTenantId, 'tenant-b');
  });
}

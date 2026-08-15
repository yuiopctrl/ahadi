import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/profile/presentation/profile_screen.dart';
import 'package:ahadi_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:ahadi_mobile/features/users/presentation/users_roles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  testWidgets('more menu opens users and roles with friendly role labels', (
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
    expect(find.text('Users & Roles'), findsOneWidget);
    await tester.tap(find.text('Users & Roles'));
    await tester.pumpAndSettle();

    expect(find.text('Herosimini Committee'), findsOneWidget);
    expect(find.text('Godfrey Mrema'), findsOneWidget);
    expect(find.textContaining('Owner'), findsOneWidget);
    expect(find.textContaining('TENANT_OWNER'), findsNothing);
    expect(find.text('John Mushi'), findsOneWidget);
    expect(find.textContaining('Invitation Pending'), findsOneWidget);
  });

  testWidgets('users search is debounced and phone scoped', (tester) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: UsersRolesScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0713676401');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.pumpAndSettle();

    expect(api.tenantUsersCalls, greaterThanOrEqualTo(2));
    expect(find.text('Mary Joseph'), findsOneWidget);
    expect(find.text('Godfrey Mrema'), findsNothing);
  });

  testWidgets('invite user normalizes phone and creates invitation', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: InviteUserScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Anna Richard');
    await tester.enterText(find.byType(TextField).at(1), '0713000111');
    await tester.tap(find.text('Send Invitation'));
    await tester.pumpAndSettle();

    expect(api.inviteTenantUserCalls, 1);
    expect(api.lastInvitePayload?['phone'], '+255713000111');
    expect(api.lastInvitePayload?['role'], 'TREASURER');
  });

  testWidgets('user details support role change suspend and resend invite', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: UsersRolesScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mary Joseph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Role'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collector'));
    await tester.pumpAndSettle();
    expect(api.updateTenantUserRoleCalls, 1);
    expect(api.lastRolePayload?['role'], 'COLLECTOR');

    await tester.tap(find.text('Suspend Access'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend Access').last);
    await tester.pumpAndSettle();
    expect(api.suspendTenantUserCalls, 1);

    Navigator.of(tester.element(find.text('User Details'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('John Mushi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend Invitation'));
    await tester.pumpAndSettle();
    expect(api.resendTenantInvitationCalls, 1);
  });

  testWidgets('profile edit saves name and email without phone editing', (
    tester,
  ) async {
    final api = FakeAhadiApi();
    final controller = _readyController(api);
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Doctor'), findsOneWidget);
    await tester.tap(find.text('Edit Profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Godfrey Mrema');
    await tester.enterText(find.byType(TextField).at(1), 'godfrey@example.com');
    expect(find.text('+255712345678'), findsOneWidget);
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();

    expect(api.lastProfilePayload?['fullName'], 'Godfrey Mrema');
    expect(api.lastProfilePayload?['email'], 'godfrey@example.com');
    expect(controller.userContext?.profile?.fullName, 'Godfrey Mrema');
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
  controller.selectedEventId = 'event-1';
  return controller;
}

import 'package:changisha_platform/core/auth/auth_models.dart';
import 'package:changisha_platform/core/auth/session_controller.dart';
import 'package:changisha_platform/core/auth/session_storage.dart';
import 'package:changisha_platform/core/theme/platform_theme.dart';
import 'package:changisha_platform/features/auth/presentation/access_denied_screen.dart';
import 'package:changisha_platform/features/auth/presentation/login_screen.dart';
import 'package:changisha_platform/features/dashboard/presentation/dashboard_screen.dart';
import 'package:changisha_platform/features/organizations/presentation/organizations_screen.dart';
import 'package:changisha_platform/features/shell/presentation/platform_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform_api.dart';

Widget _wrap(Widget child) => MaterialApp(theme: platformTheme(), home: Scaffold(body: child));

void main() {
  group('Login screen', () {
    testWidgets('renders phone and PIN fields with a login button', (tester) async {
      final controller = SessionController(api: FakePlatformApi(), storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(LoginScreen(controller: controller)));

      expect(find.text('Changisha Platform'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'PIN'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Login'), findsOneWidget);
      expect(find.text('Forgot PIN?'), findsOneWidget);
    });

    testWidgets('shows an error message when login fails', (tester) async {
      final api = FakePlatformApi()..loginSucceeds = false;
      final controller = SessionController(api: api, storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(LoginScreen(controller: controller)));

      await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '+255712345678');
      await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Login'));
      await tester.pumpAndSettle();

      expect(find.text('Phone number or PIN is incorrect.'), findsOneWidget);
    });
  });

  group('Access denied screen', () {
    testWidgets('shows the required denial message and never platform data', (tester) async {
      final controller = SessionController(api: FakePlatformApi(), storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(AccessDeniedScreen(controller: controller)));

      expect(find.text('Your account does not have access to Changisha Platform.'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });
  });

  group('Dashboard screen', () {
    testWidgets('renders real dashboard metrics from the API', (tester) async {
      final api = FakePlatformApi()
        ..dashboardResult = {
          'totalTenants': 42,
          'activeTenants': 30,
          'trialTenants': 10,
          'suspendedTenants': 2,
          'openSupportRequests': 5,
        };
      final controller = SessionController(api: api, storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(DashboardScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('42'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);
      expect(find.text('Total Organizations'), findsOneWidget);
      expect(find.text('Open Support Requests'), findsOneWidget);
    });
  });

  group('Organizations screen', () {
    testWidgets('lists organizations and filters them by search text', (tester) async {
      final api = FakePlatformApi()
        ..organizations = [
          {'id': '1', 'name': 'Harusi ya Amani', 'code': 'AMANI01', 'status': 'ACTIVE', 'owner_name': 'Amani', 'owner_phone': '+255700000001'},
          {'id': '2', 'name': 'Msiba wa Familia', 'code': 'FAM02', 'status': 'TRIAL', 'owner_name': 'Familia', 'owner_phone': '+255700000002'},
        ];
      final controller = SessionController(api: api, storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(OrganizationsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Harusi ya Amani'), findsOneWidget);
      expect(find.text('Msiba wa Familia'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Amani');
      await tester.pumpAndSettle();

      expect(find.text('Harusi ya Amani'), findsOneWidget);
      expect(find.text('Msiba wa Familia'), findsNothing);
    });

    testWidgets('shows an empty state when there are no organizations', (tester) async {
      final controller = SessionController(api: FakePlatformApi(), storage: MemorySessionStorage());
      await tester.pumpWidget(_wrap(OrganizationsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('No organizations yet.'), findsOneWidget);
    });
  });

  group('Platform shell navigation', () {
    testWidgets('only shows nav destinations the session has permission for', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakePlatformApi()
        ..meResult = const PlatformSession(
          profile: PlatformProfile(fullName: 'Auditor Person', phoneE164: '+255700000009'),
          isPlatformUser: true,
          platformRole: 'PLATFORM_AUDITOR',
          platformStatus: 'ACTIVE',
          platformPermissions: ['platform.dashboard.view', 'platform.audit.view'],
        );
      final storage = MemorySessionStorage()..session = const SessionCredentials(accessToken: 'token', refreshToken: 'refresh');
      final controller = SessionController(api: api, storage: storage);
      await controller.bootstrap();

      await tester.pumpWidget(_wrap(PlatformShell(controller: controller)));
      await tester.pumpAndSettle();

      // "Overview" also appears in the AppBar title since it's the initially
      // selected destination, alongside its NavigationRail label.
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Audit Logs'), findsOneWidget);
      // An auditor with only dashboard/audit permissions must not see
      // management-oriented modules like Organizations or Platform Users.
      expect(find.text('Organizations'), findsNothing);
      expect(find.text('Platform Users'), findsNothing);
    });

    testWidgets('an owner sees every module', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = FakePlatformApi()
        ..meResult = const PlatformSession(
          profile: PlatformProfile(fullName: 'Owner Person', phoneE164: '+255700000001'),
          isPlatformUser: true,
          platformRole: 'PLATFORM_OWNER',
          platformStatus: 'ACTIVE',
          platformPermissions: [],
        );
      final storage = MemorySessionStorage()..session = const SessionCredentials(accessToken: 'token', refreshToken: 'refresh');
      final controller = SessionController(api: api, storage: storage);
      await controller.bootstrap();

      await tester.pumpWidget(_wrap(PlatformShell(controller: controller)));
      await tester.pumpAndSettle();

      for (final label in ['Overview', 'Organizations', 'Subscriptions', 'Packages', 'Platform Users', 'Support', 'Audit Logs', 'Messaging', 'System']) {
        expect(find.text(label), findsWidgets, reason: 'PLATFORM_OWNER should see $label');
      }
    });
  });
}

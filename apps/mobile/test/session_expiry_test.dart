import 'package:ahadi_mobile/core/errors/api_failure.dart';
import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

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
  controller.bootstrapState = BootstrapState.ready;
  return controller;
}

void main() {
  group('SessionController.handleSessionExpired', () {
    test('clears all session state, flags sessionExpired and goes to unauthenticated', () async {
      final controller = _readyController(FakeAhadiApi());
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.handleSessionExpired();

      expect(controller.credentials, isNull);
      expect(controller.userContext, isNull);
      expect(controller.selectedTenantContext, isNull);
      expect(controller.selectedTenantId, isNull);
      expect(controller.selectedEventId, isNull);
      expect(controller.sessionExpired, isTrue);
      expect(controller.bootstrapState, BootstrapState.unauthenticated);
      expect(notifications, 1);
    });

    test('is idempotent -- concurrent/repeated calls only clean up and notify once', () async {
      final controller = _readyController(FakeAhadiApi());
      var notifications = 0;
      controller.addListener(() => notifications++);

      // Several in-flight requests failing at once would all call this.
      await Future.wait([
        controller.handleSessionExpired(),
        controller.handleSessionExpired(),
        controller.handleSessionExpired(),
      ]);
      await controller.handleSessionExpired();

      expect(notifications, 1);
      expect(controller.bootstrapState, BootstrapState.unauthenticated);
    });

    test('a new login attempt clears the sessionExpired flag', () async {
      final api = FakeAhadiApi();
      final controller = _readyController(api);
      await controller.handleSessionExpired();
      expect(controller.sessionExpired, isTrue);

      await controller.loginWithPin(phone: '+255712345678', pin: '1234');

      expect(controller.sessionExpired, isFalse);
    });
  });

  group('SessionController.validateSessionOnResume', () {
    test(
      'an expired-session response triggers the same centralized cleanup',
      () async {
        final api = FakeAhadiApi()
          ..meError = const ApiFailure(
            kind: ApiFailureKind.unauthenticated,
            message: 'Session expired',
            code: 'SESSION_REQUIRED',
            statusCode: 401,
          );
        final controller = _readyController(api);

        await controller.validateSessionOnResume();

        expect(controller.bootstrapState, BootstrapState.unauthenticated);
        expect(controller.sessionExpired, isTrue);
      },
    );

    test('a network/server error on resume never logs the user out', () async {
      final api = FakeAhadiApi()
        ..meError = const ApiFailure(
          kind: ApiFailureKind.networkUnavailable,
          message:
              'No internet connection. Check your connection and try again.',
        );
      final controller = _readyController(api);

      await controller.validateSessionOnResume();

      expect(controller.bootstrapState, BootstrapState.ready);
      expect(controller.sessionExpired, isFalse);
      expect(controller.credentials, isNotNull);
    });

    test('does nothing when the app is not in the ready state', () async {
      final api = FakeAhadiApi();
      final controller = SessionController(
        api: api,
        storage: MemorySessionStorage(),
      );
      controller.bootstrapState = BootstrapState.unauthenticated;

      await controller.validateSessionOnResume();

      expect(api.meCalls, 0);
    });
  });

  group('Login screen session-expiry UX', () {
    testWidgets(
      'shows the expiry notice when the controller flags it, and not otherwise',
      (tester) async {
        final controller = _readyController(FakeAhadiApi());
        await controller.handleSessionExpired();

        await tester.pumpWidget(
          MaterialApp(home: LoginScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('session-expired-notice')), findsOneWidget);
        expect(
          find.text('Your session has expired. Please sign in again.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('does not show the expiry notice for an ordinary fresh login', (
      tester,
    ) async {
      final controller = SessionController(
        api: FakeAhadiApi(),
        storage: MemorySessionStorage(),
      );
      controller.bootstrapState = BootstrapState.unauthenticated;

      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('session-expired-notice')), findsNothing);
    });
  });
}

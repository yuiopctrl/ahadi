import 'dart:async';

import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/core/networking/ahadi_api.dart';
import 'package:ahadi_mobile/features/auth/data/phone_normalization.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

void main() {
  test('phone normalization accepts Tanzanian formats', () {
    expect(normalizeTanzaniaPhone('0712 345 678'), '+255712345678');
    expect(normalizeTanzaniaPhone('255 712 345 678'), '+255712345678');
    expect(normalizeTanzaniaPhone('+255 712 345 678'), '+255712345678');
    expect(() => normalizeTanzaniaPhone('123'), throwsFormatException);
  });

  test(
    'PIN validation requires four numeric digits and rejects weak reset PINs',
    () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isWeakPin('1234'), isTrue);
      expect(isWeakPin('2468'), isFalse);
    },
  );

  test('normal login does not request OTP', () async {
    final api = FakeAhadiApi();
    final controller = SessionController(
      api: api,
      storage: MemorySessionStorage(),
    );
    await controller.loginWithPin(phone: '0712345678', pin: '2468');
    expect(api.loginPinCalls, 1);
    expect(api.requestOtpCalls, 0);
  });

  test('no duplicate login request while pending', () async {
    final api = FakeAhadiApi()..loginCompleter = Completer<LoginResult>();
    final controller = SessionController(
      api: api,
      storage: MemorySessionStorage(),
    );
    final first = controller.loginWithPin(phone: '0712345678', pin: '2468');
    final second = controller.loginWithPin(phone: '0712345678', pin: '2468');
    expect(api.loginPinCalls, 1);
    api.loginCompleter!.complete(
      const LoginResult(
        credentials: SessionCredentials(accessToken: 'a', refreshToken: 'r'),
      ),
    );
    await Future.wait([first, second]);
  });

  test('forgot PIN requests OTP and can set a new authenticated PIN', () async {
    final api = FakeAhadiApi();
    final controller = SessionController(
      api: api,
      storage: MemorySessionStorage(),
    );
    await controller.requestForgotPinOtp('0712345678');
    await controller.verifyForgotPinOtp(phone: '0712345678', token: '123456');
    await controller.setForgottenPin(pin: '2468', confirmPin: '2468');
    expect(api.requestOtpCalls, 1);
    expect(api.verifyOtpCalls, 1);
    expect(api.setPinCalls, 1);
    expect(controller.isAuthenticated, isTrue);
  });

  test('session restoration clears expired sessions', () async {
    final storage = MemorySessionStorage()
      ..session = const SessionCredentials(
        accessToken: 'expired',
        refreshToken: 'refresh',
      )
      ..selectedTenantId = 'tenant-a';
    final api = FakeAhadiApi()..meError = expiredSessionFailure;
    final controller = SessionController(api: api, storage: storage);
    await controller.initialize();
    expect(controller.bootstrapState, BootstrapState.unauthenticated);
    expect(storage.session, isNull);
    expect(storage.selectedTenantId, isNull);
  });

  test('one organization auto-selection restores tenant context', () async {
    final storage = MemorySessionStorage()
      ..session = const SessionCredentials(accessToken: 'a', refreshToken: 'r');
    final api = FakeAhadiApi();
    final controller = SessionController(api: api, storage: storage);
    await controller.initialize();
    expect(controller.selectedTenantId, 'tenant-a');
    expect(
      controller.selectedTenantContext?.tenantName,
      'Herosimini Committee',
    );
  });

  test('multiple organizations require explicit selection', () async {
    final storage = MemorySessionStorage()
      ..session = const SessionCredentials(accessToken: 'a', refreshToken: 'r');
    final api = FakeAhadiApi()
      ..userContext = userWithMemberships([
        membership('tenant-a', 'Herosimini Committee'),
        membership('tenant-b', 'Valentino Group'),
      ]);
    final controller = SessionController(api: api, storage: storage);
    await controller.initialize();
    expect(controller.needsOrganizationSelection, isTrue);
    expect(controller.selectedTenantContext, isNull);
  });

  test(
    'organization switching resets tenant context and does not trigger OTP',
    () async {
      final api = FakeAhadiApi()
        ..userContext = userWithMemberships([
          membership('tenant-a', 'Herosimini Committee'),
          membership('tenant-b', 'Valentino Group'),
        ]);
      final controller = SessionController(
        api: api,
        storage: MemorySessionStorage(),
      );
      controller.credentials = const SessionCredentials(
        accessToken: 'a',
        refreshToken: 'r',
      );
      controller.userContext = api.userContext;
      await controller.selectTenant('tenant-a');
      var sawReset = false;
      controller.addListener(() {
        if (controller.selectedTenantContext == null) sawReset = true;
      });
      await controller.switchTenant('tenant-b');
      expect(sawReset, isTrue);
      expect(controller.selectedTenantId, 'tenant-b');
      expect(api.requestOtpCalls, 0);
    },
  );

  test(
    'create another organization uses authenticated onboarding without OTP',
    () async {
      final api = FakeAhadiApi();
      final controller = SessionController(
        api: api,
        storage: MemorySessionStorage(),
      );
      controller.credentials = const SessionCredentials(
        accessToken: 'a',
        refreshToken: 'r',
      );
      controller.userContext = api.userContext;
      await controller.createOrganization(
        planCode: 'BASIC',
        tenantName: 'New Committee',
        tenantPhone: '0712345678',
        tenantEmail: '',
        adminFullName: 'Test Doctor',
        adminEmail: '',
        firstEventName: 'Wedding',
        eventType: 'WEDDING',
        eventDate: '',
        venue: '',
        targetAmount: '',
        pledgeDeadline: '',
      );
      expect(
        api.lastOnboardingPayload?['onboardingIntent'],
        'CREATE_ADDITIONAL_TENANT',
      );
      expect(api.requestOtpCalls, 0);
      expect(controller.selectedTenantId, 'tenant-new');
    },
  );
}

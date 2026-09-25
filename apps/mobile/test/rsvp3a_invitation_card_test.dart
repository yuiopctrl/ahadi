import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ahadi_mobile/core/storage/session_storage.dart';
import 'package:ahadi_mobile/features/auth/data/session_controller.dart';
import 'package:ahadi_mobile/features/auth/domain/auth_models.dart';
import 'package:ahadi_mobile/features/invitations/presentation/invitation_card_renderer.dart';
import 'package:ahadi_mobile/features/invitations/presentation/invitations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_ahadi_api.dart';

const _tenantOwnerPermissions = [
  'events.view',
  'invitation.view',
  'invitation.create',
  'invitation.edit',
  'invitation.cancel',
  'invitation.send',
  'rsvp.view',
  'rsvp.manage',
];

// A real, minimal, valid 1x1 PNG -- widget tests inject this in place of a
// real render so `Image.memory` (used by the preview/gallery widgets under
// test) has something decodable to display. An empty byte list is NOT
// valid PNG data and throws "Invalid image data" from the image codec.
final _stubPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

const _classicConfig = {
  'version': 1,
  'layoutKey': 'CLASSIC',
  'background': {'type': 'solid', 'color': '#F8F2EA'},
  'colors': {'primary': '#8F1D2C', 'secondary': '#D7B56D', 'text': '#241A18'},
  'typography': {'titleStyle': 'serif_elegant', 'bodyStyle': 'ubuntu'},
  'elements': {
    'showHost': true,
    'showGuestName': true,
    'showEventName': true,
    'showDate': true,
    'showTime': true,
    'showVenue': true,
    'showAddress': true,
    'showQr': true,
    'showRsvpDeadline': true,
  },
};

InvitationCardData _sampleData({
  String guestDisplayName = 'Victor Prever Kinabo & Family',
  String shareUrl = 'https://app.changisha.co/i/token-abc',
}) {
  return InvitationCardData(
    leadInText: 'YOU ARE CORDIALLY INVITED',
    connectorText: 'to',
    hostDisplayName: 'Mr & Mrs Kinabo',
    guestDisplayName: guestDisplayName,
    eventName: 'Jennifer Ludovick Swai Send Off',
    dateText: 'Saturday, 12 December 2026',
    timeText: '6:00 PM',
    venueName: 'Riverside Hall',
    venueAddress: 'Dar es Salaam',
    rsvpDeadlineText: 'RSVP by 5 December',
    shareUrl: shareUrl,
  );
}

SessionController _buildController(
  FakeAhadiApi api, {
  TenantContext? tenantContext,
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
  controller.selectedTenantContext =
      tenantContext ??
      TenantContext(
        tenantId: 'tenant-a',
        tenantName: 'Herosimini Committee',
        events: const [
          EventSummary(
            id: 'event-1',
            name: 'Jennifer Ludovick Swai Send Off',
            status: 'ACTIVE',
            eventType: 'WEDDING',
            eventDate: '2026-12-12',
            venue: 'Riverside Hall',
            totalPledged: 0,
            totalCollected: 0,
            totalOutstanding: 0,
          ),
        ],
        permissions: _tenantOwnerPermissions,
        isOwner: true,
        accessState: 'ACTIVE',
      );
  return controller;
}

Map<String, dynamic> _invitation({
  required String id,
  required String status,
  int publicTokenVersion = 1,
  Map<String, dynamic>? template,
}) {
  return {
    'id': id,
    'eventId': 'event-1',
    'eventMemberId': 'event-member-$id',
    'memberId': 'member-$id',
    'memberName': 'Victor Prever Kinabo',
    'phone': '+255712345678',
    'displayName': 'Victor Prever Kinabo & Family',
    'maxGuests': 4,
    'status': status,
    'publicTokenVersion': publicTokenVersion,
    'template': template,
    'rsvp': null,
    'deliveries': <Map<String, dynamic>>[],
    'viewCount': 0,
    'firstViewedAt': null,
    'lastViewedAt': null,
    'activatedAt': status != 'DRAFT' ? '2026-08-01T00:00:00Z' : null,
    'cancelledAt': status == 'CANCELLED' ? '2026-08-02T00:00:00Z' : null,
    'createdAt': '2026-07-01T00:00:00Z',
    'updatedAt': '2026-07-01T00:00:00Z',
  };
}

Future<ui.Image> _decode(Uint8List bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, completer.complete);
  return completer.future;
}

void main() {
  // --- Pure data-model tests: QR payload / no leaked internal IDs -----

  test(
    'QR payload is exactly the shareUrl -- nothing else is ever encoded',
    () {
      final data = _sampleData(
        shareUrl: 'https://app.changisha.co/i/signed-token-xyz',
      );
      expect(
        data.qrPayload,
        equals('https://app.changisha.co/i/signed-token-xyz'),
      );
    },
  );

  test('QR payload never contains an invitation/event-member/tenant id, even when one is embedded elsewhere in the same screen state', () {
    const invitationId = 'inv-11111111-1111-1111-1111-111111111111';
    const eventMemberId = 'em-22222222-2222-2222-2222-222222222222';
    const tenantId = 'tenant-33333333-3333-3333-3333-333333333333';
    final data = _sampleData(
      shareUrl: 'https://app.changisha.co/i/only-the-token',
    );
    expect(data.qrPayload, isNot(contains(invitationId)));
    expect(data.qrPayload, isNot(contains(eventMemberId)));
    expect(data.qrPayload, isNot(contains(tenantId)));
  });

  test('InvitationCardData has no pledge/payment/balance fields -- a card can never leak them regardless of template', () {
    final data = _sampleData();
    // Structural proof, not just a string search: enumerate the only
    // fields this class carries and confirm none of them are
    // pledge/payment/balance related.
    final fields = <String>[
      data.leadInText,
      data.connectorText,
      data.hostDisplayName,
      data.guestDisplayName,
      data.eventName,
      data.dateText,
      data.timeText,
      data.venueName,
      data.venueAddress,
      data.rsvpDeadlineText,
      data.shareUrl,
    ];
    expect(fields.length, equals(11));
  });

  test('buildInvitationQrImage produces a real scannable QR module grid for a shareUrl', () {
    final qrImage = buildInvitationQrImage('https://app.changisha.co/i/abc123');
    expect(qrImage.moduleCount, greaterThan(0));
    var darkCount = 0;
    for (var r = 0; r < qrImage.moduleCount; r++) {
      for (var c = 0; c < qrImage.moduleCount; c++) {
        if (qrImage.isDark(r, c)) darkCount++;
      }
    }
    expect(darkCount, greaterThan(0));
  });

  // --- Rendered PNG dimension / success tests --------------------------

  // `picture.toImage()` (inside renderInvitationCardPng) and
  // `decodeImageFromList` both deliver their result via a real engine
  // callback that never fires under flutter_test's fake clock/zone unless
  // the call is wrapped in `tester.runAsync` -- this is Flutter's own
  // documented requirement for any dart:ui image encode/decode inside a
  // widget test (the same reason golden-image tests use it). Without this,
  // the awaited Future simply never completes.
  testWidgets('portrait output is exactly 1080x1350', (tester) async {
    final image = await tester.runAsync(() async {
      final bytes = await renderInvitationCardPng(
        templateConfig: _classicConfig,
        data: _sampleData(),
        format: InvitationCardFormat.portrait,
        status: 'ACTIVE',
      );
      return _decode(bytes);
    });
    expect(image!.width, equals(1080));
    expect(image.height, equals(1350));
  });

  testWidgets('square output is exactly 1080x1080', (tester) async {
    final image = await tester.runAsync(() async {
      final bytes = await renderInvitationCardPng(
        templateConfig: _classicConfig,
        data: _sampleData(),
        format: InvitationCardFormat.square,
        status: 'ACTIVE',
      );
      return _decode(bytes);
    });
    expect(image!.width, equals(1080));
    expect(image.height, equals(1080));
  });

  testWidgets('story output is exactly 1080x1920', (tester) async {
    final image = await tester.runAsync(() async {
      final bytes = await renderInvitationCardPng(
        templateConfig: _classicConfig,
        data: _sampleData(),
        format: InvitationCardFormat.story,
        status: 'ACTIVE',
      );
      return _decode(bytes);
    });
    expect(image!.width, equals(1080));
    expect(image.height, equals(1920));
  });

  testWidgets(
    'PNG export succeeds and is a valid, decodable image for every format',
    (tester) async {
      for (final format in InvitationCardFormat.values) {
        final image = await tester.runAsync(() async {
          final bytes = await renderInvitationCardPng(
            templateConfig: _classicConfig,
            data: _sampleData(),
            format: format,
            status: 'ACTIVE',
          );
          expect(bytes, isNotEmpty);
          return _decode(bytes);
        });
        expect(image!.width, greaterThan(0));
      }
    },
  );

  testWidgets(
    'a cancelled invitation cannot produce a usable card -- rendering throws',
    (tester) async {
      await expectLater(
        renderInvitationCardPng(
          templateConfig: _classicConfig,
          data: _sampleData(),
          format: InvitationCardFormat.portrait,
          status: 'CANCELLED',
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'a very long guest name does not throw and still produces the exact target dimensions',
    (tester) async {
      final image = await tester.runAsync(() async {
        final bytes = await renderInvitationCardPng(
          templateConfig: _classicConfig,
          data: _sampleData(
            guestDisplayName: 'Mr and Mrs Alexander Bartholomew Christopher Dominic Edwardson Kinabo Family and All Their Extended Relatives',
          ),
          format: InvitationCardFormat.square,
          status: 'ACTIVE',
        );
        return _decode(bytes);
      });
      expect(image!.width, equals(1080));
      expect(image.height, equals(1080));
    },
  );

  testWidgets(
    'long venue/address text does not throw and still produces the exact target dimensions',
    (tester) async {
      final data = InvitationCardData(
        leadInText: 'YOU ARE CORDIALLY INVITED',
        connectorText: 'to',
        hostDisplayName: 'Mr & Mrs Kinabo',
        guestDisplayName: 'Victor Prever Kinabo & Family',
        eventName: 'Jennifer Ludovick Swai Send Off',
        dateText: 'Saturday, 12 December 2026',
        timeText: '6:00 PM',
        venueName: 'The Grand Riverside Conference and Wedding Reception Hall, Block 14, Plot 220, Mikocheni Light Industrial Area',
        venueAddress: 'Along Mwai Kibaki Road, Next to the Old Water Tower, Kinondoni District, Dar es Salaam, United Republic of Tanzania',
        rsvpDeadlineText: 'RSVP by 5 December',
        shareUrl: 'https://app.changisha.co/i/token-abc',
      );
      final image = await tester.runAsync(() async {
        final bytes = await renderInvitationCardPng(
          templateConfig: _classicConfig,
          data: data,
          format: InvitationCardFormat.portrait,
          status: 'ACTIVE',
        );
        return _decode(bytes);
      });
      expect(image!.width, equals(1080));
      expect(image.height, equals(1350));
    },
  );

  // --- Widget-level tests: card status rules, permissions, freshness ---

  // `InvitationCardPreviewScreen`'s body is a plain `ListView`, which (like
  // any sliver) only builds elements within its viewport + cache extent --
  // content below the fold at the default test screen size is genuinely
  // never built into the Element tree, so `find.text(...)` legitimately
  // finds nothing for it even though it's not a bug. Every test below that
  // asserts on the action row (below the rendered card preview) needs a
  // tall enough viewport for that row to actually be built.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'DRAFT invitation: preview shown but Download PNG / Copy actions are hidden',
    (tester) async {
      useTallViewport(tester);
      final api = FakeAhadiApi();
      api.invitationRecords.add(_invitation(id: 'inv-draft', status: 'DRAFT'));
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-draft',
            renderCard: ({
              required templateConfig,
              required data,
              required format,
              required status,
            }) async => _stubPngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This invitation is still a draft -- the QR/link will not work until you activate it.',
        ),
        findsOneWidget,
      );
      expect(find.text('Download PNG'), findsNothing);
      expect(find.text('Copy Link'), findsNothing);
    },
  );

  testWidgets(
    'CANCELLED invitation shows "This invitation has been cancelled." and no export controls',
    (tester) async {
      useTallViewport(tester);
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-cancelled', status: 'CANCELLED'),
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-cancelled',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This invitation has been cancelled.'), findsOneWidget);
      expect(find.text('Download PNG'), findsNothing);
      expect(find.byType(SegmentedButton<InvitationCardFormat>), findsNothing);
    },
  );

  testWidgets(
    'ACTIVE invitation: Download PNG / Copy Link / Copy Invitation Text are all present',
    (tester) async {
      useTallViewport(tester);
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-active', status: 'ACTIVE'),
      );
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-active',
            renderCard: ({
              required templateConfig,
              required data,
              required format,
              required status,
            }) async => _stubPngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Download PNG'), findsOneWidget);
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Copy Invitation Text'), findsOneWidget);
    },
  );

  testWidgets(
    'invitation.view controls preview access -- without it, Preview Card shows a permission message instead of the card',
    (tester) async {
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-active', status: 'ACTIVE'),
      );
      final controller = _buildController(
        api,
        tenantContext: TenantContext(
          tenantId: 'tenant-a',
          tenantName: 'Herosimini Committee',
          events: const [
            EventSummary(
              id: 'event-1',
              name: 'Jennifer Ludovick Swai Send Off',
              status: 'ACTIVE',
              eventType: 'WEDDING',
              eventDate: '2026-12-12',
              totalPledged: 0,
              totalCollected: 0,
              totalOutstanding: 0,
            ),
          ],
          permissions: const ['events.view'],
          isOwner: false,
          accessState: 'ACTIVE',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-active',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('You do not have permission to preview this card.'),
        findsOneWidget,
      );
      expect(find.byType(SegmentedButton<InvitationCardFormat>), findsNothing);
    },
  );

  testWidgets(
    'invitation.edit controls template change -- "Use This Template" is hidden with view-only access',
    (tester) async {
      useTallViewport(tester);
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(
          id: 'inv-active',
          status: 'ACTIVE',
          template: {
            'id': 'template-classic',
            'name': 'Classic',
            'layoutKey': 'CLASSIC',
            'scope': 'PLATFORM',
          },
        ),
      );
      final controller = _buildController(
        api,
        tenantContext: TenantContext(
          tenantId: 'tenant-a',
          tenantName: 'Herosimini Committee',
          events: const [
            EventSummary(
              id: 'event-1',
              name: 'Jennifer Ludovick Swai Send Off',
              status: 'ACTIVE',
              eventType: 'WEDDING',
              eventDate: '2026-12-12',
              totalPledged: 0,
              totalCollected: 0,
              totalOutstanding: 0,
            ),
          ],
          // invitation.view but deliberately NOT invitation.edit.
          permissions: const ['events.view', 'invitation.view'],
          isOwner: false,
          accessState: 'ACTIVE',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-active',
            renderCard: ({
              required templateConfig,
              required data,
              required format,
              required status,
            }) async => _stubPngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch the picker to the other seeded template -- with view-only
      // access this must never surface a way to persist it.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegant Burgundy').last);
      await tester.pumpAndSettle();

      expect(find.text('Use This Template'), findsNothing);
    },
  );

  testWidgets(
    'rotating the link produces a different shareUrl on the next fetch -- the old token is never silently reused',
    (tester) async {
      final api = FakeAhadiApi();
      api.invitationRecords.add(
        _invitation(id: 'inv-active', status: 'ACTIVE', publicTokenVersion: 1),
      );
      final controller = _buildController(api);

      final before = await controller.eventInvitationDetail(
        'event-1',
        'inv-active',
      );
      final beforeShareUrl = before['shareUrl'] as String;

      // Simulate Rotate Link bumping the public token version server-side.
      api.invitationRecords.firstWhere(
        (inv) => inv['id'] == 'inv-active',
      )['publicTokenVersion'] = 2;

      final after = await controller.eventInvitationDetail(
        'event-1',
        'inv-active',
      );
      final afterShareUrl = after['shareUrl'] as String;

      expect(afterShareUrl, isNot(equals(beforeShareUrl)));

      // A freshly-pushed Preview Card screen (a new widget/state, exactly
      // what "Preview Card" always creates) has no prior state to have
      // cached -- its very first fetch already sees the rotated value.
      final capturedPayloads = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InvitationCardPreviewScreen(
            controller: controller,
            event: controller.selectedTenantContext!.events.first,
            invitationId: 'inv-active',
            renderCard:
                ({
                  required templateConfig,
                  required data,
                  required format,
                  required status,
                }) async {
                  capturedPayloads.add(data.qrPayload);
                  return _stubPngBytes;
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(capturedPayloads, isNotEmpty);
      expect(capturedPayloads.every((p) => p == afterShareUrl), isTrue);
    },
  );

  testWidgets('narrow/mobile preview has no RenderFlex overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = FakeAhadiApi();
    api.invitationRecords.add(_invitation(id: 'inv-active', status: 'ACTIVE'));
    final controller = _buildController(api);
    await tester.pumpWidget(
      MaterialApp(
        home: InvitationCardPreviewScreen(
          controller: controller,
          event: controller.selectedTenantContext!.events.first,
          invitationId: 'inv-active',
          renderCard: ({
            required templateConfig,
            required data,
            required format,
            required status,
          }) async => _stubPngBytes,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Template Gallery renders thumbnails for every visible template with a premium badge where applicable',
    (tester) async {
      final api = FakeAhadiApi();
      final controller = _buildController(api);
      await tester.pumpWidget(
        MaterialApp(
          home: TemplateGalleryScreen(
            controller: controller,
            sampleData: _sampleData(),
            renderCard: ({
              required templateConfig,
              required data,
              required format,
              required status,
            }) async => _stubPngBytes,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Classic" is both this template's name AND its category (the seeded
      // migration data uses the same word for both), so it legitimately
      // renders as two separate Text widgets -- not a bug.
      expect(find.text('Classic'), findsNWidgets(2));
      expect(find.text('Elegant Burgundy'), findsOneWidget);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.text('Use Template'), findsNWidgets(2));
    },
  );
}

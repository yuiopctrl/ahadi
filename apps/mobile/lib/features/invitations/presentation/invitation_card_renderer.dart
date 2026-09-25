import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../../../core/theme/ahadi_theme.dart';

/// RSVP-3A card output sizes. One logical layout algorithm below is reused
/// for all three -- these are not three separate templates, just three
/// canvas sizes the same layout distributes itself across.
enum InvitationCardFormat {
  portrait(1080, 1350, 'Portrait'),
  square(1080, 1080, 'Square'),
  story(1080, 1920, 'Story');

  const InvitationCardFormat(this.width, this.height, this.label);

  final int width;
  final int height;
  final String label;
}

/// Plain personalization data for one card. Deliberately contains nothing
/// about pledges/payments/balances/internal IDs -- those fields do not
/// exist here at all, so a card can never leak them regardless of template.
class InvitationCardData {
  const InvitationCardData({
    required this.leadInText,
    required this.connectorText,
    required this.hostDisplayName,
    required this.guestDisplayName,
    required this.eventName,
    required this.dateText,
    required this.timeText,
    required this.venueName,
    required this.venueAddress,
    required this.rsvpDeadlineText,
    required this.shareUrl,
  });

  /// e.g. "YOU ARE CORDIALLY INVITED" -- pre-localized by the caller so this
  /// renderer stays pure/testable and has no i18n dependency of its own.
  final String leadInText;

  /// e.g. "to" -- connects the guest line to the event name line.
  final String connectorText;

  final String hostDisplayName;
  final String guestDisplayName;
  final String eventName;
  final String dateText;
  final String timeText;
  final String venueName;
  final String venueAddress;
  final String rsvpDeadlineText;

  /// The public invitation URL. This is the ONLY thing ever encoded in the
  /// QR -- never memberId/eventMemberId/tenantId/invitationId/pledge data.
  /// Kept as its own field, and exposed unchanged as [qrPayload], so a test
  /// can assert directly on exactly what string reaches the QR encoder.
  final String shareUrl;

  String get qrPayload => shareUrl;
}

Color _hexColor(Object? value, Color fallback) {
  if (value is! String) return fallback;
  final match = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(value);
  if (match == null) return fallback;
  return Color(int.parse('FF${match.group(1)}', radix: 16));
}

String? _stringAt(Map<String, dynamic> config, List<String> path) {
  dynamic node = config;
  for (final key in path) {
    if (node is! Map) return null;
    node = node[key];
  }
  return node is String ? node : null;
}

/// Every element defaults to visible when the template config omits the
/// `elements` object entirely or omits a specific key -- a template only
/// ever narrows what's shown, it never silently hides data by omission.
bool _elementVisible(Map<String, dynamic> config, String key) {
  final elements = config['elements'];
  if (elements is! Map) return true;
  final value = elements[key];
  return value is bool ? value : true;
}

/// Only two real font families are bundled with the app (Ubuntu Sans,
/// Ubuntu Condensed) plus Ubuntu Mono -- there is no separate serif/script
/// font asset. Title "styles" are therefore weight/spacing/case variations
/// on those bundled families rather than distinct fonts, which is an
/// honest constraint given what's actually shipped in
/// apps/mobile/assets/fonts, not a placeholder left unfinished.
TextStyle _titleStyle(
  String? styleKey, {
  required double size,
  required Color color,
}) {
  switch (styleKey) {
    case 'sans_modern':
      return TextStyle(
        fontFamily: AhadiTypography.sans,
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: color,
        height: 1.15,
      );
    case 'condensed_bold':
      return TextStyle(
        fontFamily: AhadiTypography.condensed,
        fontSize: size * 1.05,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: color,
        height: 1.15,
      );
    case 'script_traditional':
      return TextStyle(
        fontFamily: AhadiTypography.condensed,
        fontSize: size * 0.95,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
        letterSpacing: 0.8,
        color: color,
        height: 1.2,
      );
    case 'minimal_light':
      return TextStyle(
        fontFamily: AhadiTypography.sans,
        fontSize: size * 0.9,
        fontWeight: FontWeight.w400,
        letterSpacing: 3,
        color: color,
        height: 1.2,
      );
    case 'serif_elegant':
    default:
      return TextStyle(
        fontFamily: AhadiTypography.condensed,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: color,
        height: 1.2,
      );
  }
}

TextStyle _bodyStyle(
  String? styleKey, {
  required double size,
  required FontWeight weight,
  required Color color,
}) {
  final family = switch (styleKey) {
    'condensed' => AhadiTypography.condensed,
    'mono' => AhadiTypography.mono,
    _ => AhadiTypography.sans,
  };
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.3,
  );
}

class _TextBlock {
  _TextBlock(this.painter, this.gapAfter);
  final TextPainter painter;
  final double gapAfter;
  double get height => painter.height + gapAfter;
}

TextPainter _layoutText(
  String text, {
  required TextStyle style,
  required double maxWidth,
  required TextAlign align,
  int maxLines = 3,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  return painter;
}

/// Builds the QR module grid for [data]. Kept separate from painting so a
/// test can inspect `moduleCount`/`isDark` without needing a canvas.
QrImage buildInvitationQrImage(String payload) {
  final qrCode = QrCode(
    payload: QrPayload.fromString(payload),
    errorCorrectLevel: QrErrorCorrectLevel.medium,
  );
  return QrImage(qrCode);
}

void _paintQr(Canvas canvas, QrImage qrImage, Rect box, Color darkColor) {
  // Quiet zone: >=4 modules of background on every side, per the QR spec's
  // minimum recommendation -- this is what keeps the code scannable after
  // the exported PNG is compressed/resized by a chat app or printer.
  const quietZoneModules = 4;
  final totalModules = qrImage.moduleCount + quietZoneModules * 2;
  final moduleSize = box.width / totalModules;
  final paint = Paint()..color = darkColor;
  for (var row = 0; row < qrImage.moduleCount; row++) {
    for (var col = 0; col < qrImage.moduleCount; col++) {
      if (!qrImage.isDark(row, col)) continue;
      final left = box.left + (quietZoneModules + col) * moduleSize;
      final top = box.top + (quietZoneModules + row) * moduleSize;
      canvas.drawRect(Rect.fromLTWH(left, top, moduleSize, moduleSize), paint);
    }
  }
}

/// Renders one invitation card as PNG bytes at the exact pixel dimensions
/// of [format] -- the same `dart:ui` PictureRecorder->Canvas->toImage path
/// already used for payment receipts (see `_receiptImageBytes` in
/// financial_screens.dart), not a widget screenshot. This is deterministic
/// (same input always produces the same pixels regardless of device/screen
/// density) and this exact function backs both the live preview
/// (`Image.memory`) and the exported/downloaded PNG, so there is only one
/// rendering engine, not two that could drift apart.
///
/// Throws [StateError] for a CANCELLED invitation -- callers must not
/// present a usable card for one (RSVP-3A card status rules).
Future<Uint8List> renderInvitationCardPng({
  required Map<String, dynamic> templateConfig,
  required InvitationCardData data,
  required InvitationCardFormat format,
  required String status,
}) async {
  if (status == 'CANCELLED') {
    throw StateError('Cannot render a card for a cancelled invitation');
  }

  final width = format.width.toDouble();
  final height = format.height.toDouble();
  final margin = width * 0.09;
  final contentWidth = width - margin * 2;

  final backgroundColor = _hexColor(
    _stringAt(templateConfig, ['background', 'color']),
    AhadiColors.background,
  );
  final primary = _hexColor(
    _stringAt(templateConfig, ['colors', 'primary']),
    AhadiColors.primary,
  );
  final secondary = _hexColor(
    _stringAt(templateConfig, ['colors', 'secondary']),
    AhadiColors.primarySoft,
  );
  final textColor = _hexColor(
    _stringAt(templateConfig, ['colors', 'text']),
    AhadiColors.text,
  );
  final titleStyleKey = _stringAt(templateConfig, ['typography', 'titleStyle']);
  final bodyStyleKey = _stringAt(templateConfig, ['typography', 'bodyStyle']);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Background.
  final backgroundType = _stringAt(templateConfig, ['background', 'type']);
  if (backgroundType == 'gradient') {
    final rawColors = (templateConfig['background'] as Map?)?['colors'];
    final stops = rawColors is List
        ? rawColors.map((c) => _hexColor(c, backgroundColor)).toList()
        : [backgroundColor, backgroundColor];
    final gradientPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, height),
        stops.length >= 2 ? stops : [backgroundColor, backgroundColor],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), gradientPaint);
  } else {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = backgroundColor,
    );
  }

  // Decorative top/bottom accent rules in the secondary color.
  final accentPaint = Paint()
    ..color = secondary
    ..strokeWidth = width * 0.004;
  canvas.drawLine(
    Offset(margin, margin * 0.7),
    Offset(width - margin, margin * 0.7),
    accentPaint,
  );

  // --- Block A: lead-in / host / guest / connector / event name ---
  final blocksA = <_TextBlock>[
    _TextBlock(
      _layoutText(
        data.leadInText,
        style: _bodyStyle(
          bodyStyleKey,
          size: width * 0.028,
          weight: FontWeight.w700,
          color: secondary,
        ),
        maxWidth: contentWidth,
        align: TextAlign.center,
        maxLines: 1,
      ),
      width * 0.03,
    ),
    if (_elementVisible(templateConfig, 'showHost') &&
        data.hostDisplayName.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.hostDisplayName,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.024,
            weight: FontWeight.w600,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 2,
        ),
        width * 0.02,
      ),
    if (_elementVisible(templateConfig, 'showGuestName'))
      _TextBlock(
        _layoutText(
          data.guestDisplayName,
          style: _titleStyle(
            titleStyleKey,
            size: width * 0.052,
            color: primary,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 2,
        ),
        width * 0.02,
      ),
    if (_elementVisible(templateConfig, 'showEventName') &&
        data.eventName.isNotEmpty) ...[
      _TextBlock(
        _layoutText(
          data.connectorText,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.022,
            weight: FontWeight.w500,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 1,
        ),
        width * 0.015,
      ),
      _TextBlock(
        _layoutText(
          data.eventName,
          style: _titleStyle(
            titleStyleKey,
            size: width * 0.04,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 2,
        ),
        0,
      ),
    ],
  ];

  // --- Block B: date / time / venue / address / rsvp deadline ---
  final blocksB = <_TextBlock>[
    if (_elementVisible(templateConfig, 'showDate') && data.dateText.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.dateText,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.028,
            weight: FontWeight.w700,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 1,
        ),
        width * 0.008,
      ),
    if (_elementVisible(templateConfig, 'showTime') && data.timeText.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.timeText,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.024,
            weight: FontWeight.w500,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 1,
        ),
        width * 0.025,
      ),
    if (_elementVisible(templateConfig, 'showVenue') &&
        data.venueName.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.venueName,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.026,
            weight: FontWeight.w700,
            color: primary,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 2,
        ),
        width * 0.006,
      ),
    if (_elementVisible(templateConfig, 'showAddress') &&
        data.venueAddress.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.venueAddress,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.02,
            weight: FontWeight.w400,
            color: textColor,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 2,
        ),
        width * 0.02,
      ),
    if (_elementVisible(templateConfig, 'showRsvpDeadline') &&
        data.rsvpDeadlineText.isNotEmpty)
      _TextBlock(
        _layoutText(
          data.rsvpDeadlineText,
          style: _bodyStyle(
            bodyStyleKey,
            size: width * 0.02,
            weight: FontWeight.w600,
            color: secondary,
          ),
          maxWidth: contentWidth,
          align: TextAlign.center,
          maxLines: 1,
        ),
        0,
      ),
  ];

  final showQr = _elementVisible(templateConfig, 'showQr');
  final qrSize = width * 0.32;

  final heightA = blocksA.fold(0.0, (sum, b) => sum + b.height);
  final heightB = blocksB.fold(0.0, (sum, b) => sum + b.height);
  final qrBlockHeight = showQr ? qrSize + width * 0.04 : 0.0;

  const gapAbMin = 0.0;
  const gapBQrMin = 0.0;
  final topMargin = margin * 1.4;
  final bottomMargin = margin;

  final fixedHeight =
      topMargin + heightA + heightB + qrBlockHeight + bottomMargin;
  final extra = (height - fixedHeight).clamp(0.0, double.infinity);
  final gapAB = gapAbMin + extra * 0.35;
  final gapBQr = gapBQrMin + extra * 0.45;

  var y = topMargin;
  for (final block in blocksA) {
    block.painter.paint(
      canvas,
      Offset(margin + (contentWidth - block.painter.width) / 2, y),
    );
    y += block.height;
  }
  y += gapAB;
  for (final block in blocksB) {
    block.painter.paint(
      canvas,
      Offset(margin + (contentWidth - block.painter.width) / 2, y),
    );
    y += block.height;
  }
  y += gapBQr;
  if (showQr) {
    final qrBox = Rect.fromLTWH((width - qrSize) / 2, y, qrSize, qrSize);
    canvas.drawRect(
      qrBox.inflate(width * 0.015),
      Paint()..color = Colors.white,
    );
    _paintQr(canvas, buildInvitationQrImage(data.qrPayload), qrBox, textColor);
  }

  canvas.drawLine(
    Offset(margin, height - bottomMargin * 0.6),
    Offset(width - margin, height - bottomMargin * 0.6),
    accentPaint,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(format.width, format.height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

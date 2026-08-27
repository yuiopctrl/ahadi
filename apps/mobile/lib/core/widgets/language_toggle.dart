import 'package:flutter/material.dart';

import '../localization/app_locale.dart';
import '../theme/ahadi_theme.dart';

/// A flat, rectangular sw/en switcher. No stadium/pill shapes anywhere in
/// this app — a bordered rounded-rect (matching the app's standard 8px
/// button radius) with a filled selected segment instead.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    super.key,
    this.swLabel = 'SW',
    this.enLabel = 'EN',
  });

  final String swLabel;
  final String enLabel;

  @override
  Widget build(BuildContext context) {
    final current = context.appLanguage;
    final controller = AppLocaleScope.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AhadiColors.primary),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              label: swLabel,
              selected: current == AppLanguage.sw,
              onTap: () => controller.setLanguage(AppLanguage.sw),
            ),
            const SizedBox(
              width: 1,
              height: 28,
              child: ColoredBox(color: AhadiColors.primary),
            ),
            _Segment(
              label: enLabel,
              selected: current == AppLanguage.en,
              onTap: () => controller.setLanguage(AppLanguage.en),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? AhadiColors.primary : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: selected ? Colors.white : AhadiColors.primary,
          ),
        ),
      ),
    );
  }
}

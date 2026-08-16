import 'package:flutter/material.dart';

import '../theme/ahadi_theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    this.subtitle = 'Changisha',
    this.iconSize = 80,
  });

  final String subtitle;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final radius = iconSize * 0.28;
    return Column(
      children: [
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: AhadiColors.primary.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.asset(
              'assets/brand/app_icon.png',
              width: iconSize,
              height: iconSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: iconSize,
                height: iconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AhadiColors.primary,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Text(
                  'C',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: iconSize * 0.42,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Image.asset(
          'assets/brand/wordmark.png',
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Text(
            'Changisha',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AhadiColors.muted),
        ),
      ],
    );
  }
}

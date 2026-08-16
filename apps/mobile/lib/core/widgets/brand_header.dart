import 'package:flutter/material.dart';

import '../theme/ahadi_theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle, this.iconSize = 132});

  final String? subtitle;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final radius = iconSize * 0.28;
    return Column(
      children: [
        ClipRRect(
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
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AhadiColors.muted),
          ),
        ],
      ],
    );
  }
}

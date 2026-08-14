import 'package:flutter/material.dart';

import '../theme/ahadi_theme.dart';

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle = 'Ahadi'});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AhadiColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'A',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ahadi',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AhadiColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

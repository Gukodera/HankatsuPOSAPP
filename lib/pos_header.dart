import 'package:flutter/material.dart';
import 'brand_logo.dart';

class PosHeader extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget? actions;
  const PosHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFF0DFE3)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 5, color: const Color(0xFFE32646)),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
          child: Row(
            children: [
              const BrandLogo(),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'HANKATSU',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    fontSize: 12,
                  ),
                ),
              ),
              if (actions != null)
                IconTheme(
                  data: const IconThemeData(color: Color(0xFF191519)),
                  child: actions!,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF191519),
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF82757B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE2E8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFFE32646), size: 28),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

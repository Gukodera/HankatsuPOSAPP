import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    padding: EdgeInsets.all(size * 0.04),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(size * 0.18)),
    clipBehavior: Clip.antiAlias,
    child: Image.asset(
      'assets/Logo.png',
      fit: BoxFit.contain,
      semanticLabel: 'Hankatsu logo',
    ),
  );
}

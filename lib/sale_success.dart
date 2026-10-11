import 'package:flutter/material.dart';

class SaleSuccess extends StatelessWidget {
  const SaleSuccess({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE2E8),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 550),
            curve: Curves.easeOutBack,
            builder: (_, value, child) =>
                Transform.scale(scale: value, child: child),
            child: const CircleAvatar(
              radius: 26,
              backgroundColor: Color(0xFFE32646),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 32),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sale complete!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF191519),
                  ),
                ),
                Text(
                  'Payment saved. Your receipt is ready.',
                  style: TextStyle(color: Color(0xFF82757B)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

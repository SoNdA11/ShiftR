import 'package:flutter/material.dart';

class GearDisplay extends StatelessWidget {
  final int gear;

  const GearDisplay({super.key, required this.gear});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Current gear $gear',
      liveRegion: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'GEAR',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.grey[500],
                  letterSpacing: 2,
                ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[700]!, width: 2),
            ),
            child: Text(
              '$gear',
              semanticsLabel: '$gear',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 72,
                    height: 1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

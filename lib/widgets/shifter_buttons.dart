import 'package:flutter/material.dart';

class ShifterButtons extends StatelessWidget {
  final VoidCallback onShiftUp;
  final VoidCallback onShiftDown;
  final bool enabled;

  const ShifterButtons({
    super.key,
    required this.onShiftUp,
    required this.onShiftDown,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: 'Shift down',
          child: _ShifterButton(
            icon: Icons.remove,
            label: 'SHIFT DOWN',
            color: Colors.redAccent,
            onPressed: enabled ? onShiftDown : null,
          ),
        ),
        const SizedBox(width: 24),
        Semantics(
          button: true,
          enabled: enabled,
          label: 'Shift up',
          child: _ShifterButton(
            icon: Icons.add,
            label: 'SHIFT UP',
            color: Colors.greenAccent,
            onPressed: enabled ? onShiftUp : null,
          ),
        ),
      ],
    );
  }
}

class _ShifterButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ShifterButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 80,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.85),
          foregroundColor: Colors.white,
          minimumSize: const Size(140, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
    );
  }
}

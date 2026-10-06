import 'package:flutter/material.dart';

/// An original layered paper-plane mark, drawn locally at any pixel density.
class TelegramMark extends StatelessWidget {
  const TelegramMark({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: const CustomPaint(painter: _TelegramMarkPainter()),
  );
}

class _TelegramMarkPainter extends CustomPainter {
  const _TelegramMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 28, size.height / 28);
    final outer = Path()
      ..moveTo(3, 12)
      ..lineTo(24, 3.5)
      ..quadraticBezierTo(26, 2.7, 25.5, 5)
      ..lineTo(21.8, 23.3)
      ..quadraticBezierTo(21.5, 25, 20, 24)
      ..lineTo(13.2, 18.7)
      ..lineTo(9.5, 21.6)
      ..lineTo(9, 15.4)
      ..lineTo(3, 13.8)
      ..quadraticBezierTo(1, 13.2, 3, 12)
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFF209CDE));
    final fold = Path()
      ..moveTo(9, 15.4)
      ..lineTo(22.4, 6.8)
      ..lineTo(12.3, 16.8)
      ..lineTo(9.5, 21.6)
      ..close();
    canvas.drawPath(fold, Paint()..color = const Color(0xFF126CB0));
    final wing = Path()
      ..moveTo(12.3, 16.8)
      ..lineTo(22.4, 6.8)
      ..lineTo(19.5, 20.8)
      ..lineTo(13.2, 18.7)
      ..close();
    canvas.drawPath(wing, Paint()..color = const Color(0xFF72CDF9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TelegramMarkPainter oldDelegate) => false;
}

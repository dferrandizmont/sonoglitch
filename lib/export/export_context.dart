import 'dart:math' as math;
import 'dart:ui';

import '../ambient/context_sensors.dart';
import 'export_layout.dart';

enum ContextItemKind { date, heading, pressure }

class ExportContextItem {
  const ExportContextItem(this.kind, this.text);
  final ContextItemKind kind;
  final String text;
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Local shutter time, never recomputed while a result is being exported.
List<ExportContextItem> contextItems(ExportContext? context) {
  if (context == null) return const [];
  final date = context.dateTime?.toLocal();
  final heading = context.validHeading;
  final pressure = context.validPressure;
  return [
    if (date != null)
      ExportContextItem(
        ContextItemKind.date,
        '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}',
      ),
    if (heading != null)
      ExportContextItem(
        ContextItemKind.heading,
        '${(heading.round() % 360).toString().padLeft(3, '0')}°',
      ),
    if (pressure != null)
      ExportContextItem(ContextItemKind.pressure, '${pressure.round()} hPa'),
  ];
}

/// One filled phase path; ring and fill use the same deterministic curves.
Path moonPhasePath(Offset center, double radius, double age) {
  final theta = 2 * math.pi * age / synodicMonth;
  final mirror = theta > math.pi ? -1 : 1;
  final path = Path();
  for (var i = 0; i < 24; i++) {
    final t = math.pi * i / 23;
    final point =
        center + Offset(mirror * radius * math.sin(t), -radius * math.cos(t));
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  for (var i = 0; i < 24; i++) {
    final t = math.pi * i / 23;
    final point =
        center +
        Offset(
          mirror * radius * math.cos(theta) * math.sin(t),
          radius * math.cos(t),
        );
    path.lineTo(point.dx, point.dy);
  }
  return path..close();
}

void paintMoon(
  Canvas canvas,
  Offset center,
  double u,
  DateTime date,
  Color color,
) {
  final radius = .008 * u;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..color = color.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.0015 * u, .1 * radius),
  );
  canvas.drawPath(
    moonPhasePath(center, radius, moonAge(date)),
    Paint()..color = color,
  );
}

void paintHeadingNeedle(
  Canvas canvas,
  Offset center,
  double capHeight,
  double heading,
  Color color,
) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(heading * math.pi / 180);
  final path = Path()
    ..moveTo(0, -.5 * capHeight)
    ..lineTo(.32 * capHeight, .5 * capHeight)
    ..lineTo(0, .28 * capHeight)
    ..lineTo(-.32 * capHeight, .5 * capHeight)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
  canvas.restore();
}

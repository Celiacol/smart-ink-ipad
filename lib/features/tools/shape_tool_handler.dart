import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, Rect;

import 'package:uuid/uuid.dart';

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/models/canvas_element.dart';
import 'canvas_tool_handler.dart';

/// Strumento per la creazione di forme geometriche (Rettangolo, Cerchio, Linea, Freccia).
class ShapeToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.shape;

  final Uuid _uuid = const Uuid();

  ShapeKind selectedShapeKind;
  int colorValue;
  double strokeWidth;

  int? _activePageIndex;
  Offset? _startPoint;
  Offset? _currentEndPoint;

  ShapeToolHandler({
    this.selectedShapeKind = ShapeKind.rectangle,
    this.colorValue = 0xFF1E293B,
    this.strokeWidth = 2.5,
  });

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    _activePageIndex = event.pageIndex;
    _startPoint = event.a4Position;
    _currentEndPoint = event.a4Position;
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex) return;
    _currentEndPoint = event.a4Position;
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != null &&
        _startPoint != null &&
        _currentEndPoint != null) {
      final distance = (_currentEndPoint! - _startPoint!).distance;
      if (distance > 4.0) {
        final shape = ShapeElement(
          id: _uuid.v4(),
          pageIndex: _activePageIndex!,
          colorValue: colorValue,
          kind: selectedShapeKind,
          startPoint: _startPoint!,
          endPoint: _currentEndPoint!,
          strokeWidth: strokeWidth,
        );
        commandManager.executeCommand(AddElementCommand(shape));
      }
    }

    _activePageIndex = null;
    _startPoint = null;
    _currentEndPoint = null;
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex ||
        _startPoint == null ||
        _currentEndPoint == null) {
      return;
    }

    drawShape(
      canvas: canvas,
      kind: selectedShapeKind,
      start: _startPoint!,
      end: _currentEndPoint!,
      color: Color(colorValue),
      strokeWidth: strokeWidth,
    );
  }

  @override
  void cancelActiveGesture() {
    _activePageIndex = null;
    _startPoint = null;
    _currentEndPoint = null;
  }

  /// Metodo statico riutilizzabile anche da `A4PagePainter` per disegnare una forma.
  static void drawShape({
    required Canvas canvas,
    required ShapeKind kind,
    required Offset start,
    required Offset end,
    required Color color,
    required double strokeWidth,
  }) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromPoints(start, end);

    switch (kind) {
      case ShapeKind.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case ShapeKind.circle:
        canvas.drawOval(rect, paint);
        break;
      case ShapeKind.line:
        canvas.drawLine(start, end, paint);
        break;
      case ShapeKind.arrow:
        canvas.drawLine(start, end, paint);
        final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
        const headLength = 14.0;
        const headAngle = 0.5;
        final path = Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            end.dx - headLength * math.cos(angle - headAngle),
            end.dy - headLength * math.sin(angle - headAngle),
          )
          ..moveTo(end.dx, end.dy)
          ..lineTo(
            end.dx - headLength * math.cos(angle + headAngle),
            end.dy - headLength * math.sin(angle + headAngle),
          );
        canvas.drawPath(path, paint);
        break;
    }
  }
}

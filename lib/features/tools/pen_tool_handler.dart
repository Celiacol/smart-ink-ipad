import 'dart:ui' show BlendMode, Canvas, Color, Offset, Paint, PaintingStyle, Path, StrokeCap, StrokeJoin;

import 'package:uuid/uuid.dart';

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/models/canvas_element.dart';
import '../handwriting_ocr/handwriting_ocr_service.dart';
import 'canvas_tool_handler.dart';

/// Strumento Penna ed Evidenziatore.
///
/// Cattura i punti a 120Hz, disegna l'anteprima fluida in tempo reale e
/// salva il tratto nel [CommandManager] (senza conversione automatica invasiva
/// mentre scrivi; la conversione avviene su richiesta tramite `LassoConvertToolHandler`).
class PenToolHandler implements CanvasToolHandler {
  @override
  final ToolType toolType;

  final HandwritingOcrService? ocrService;
  final Uuid _uuid = const Uuid();

  int colorValue;
  double strokeWidth;

  int? _activePageIndex;
  final List<InkPoint> _activePoints = [];

  PenToolHandler({
    this.ocrService,
    this.toolType = ToolType.pen,
    this.colorValue = 0xFF1E293B,
    this.strokeWidth = 2.5,
  });

  bool get isHighlighter => toolType == ToolType.highlighter;

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    _activePageIndex = event.pageIndex;
    _activePoints
      ..clear()
      ..add(
        InkPoint(
          x: event.a4Position.dx,
          y: event.a4Position.dy,
          pressure: event.pressure,
          timestampMs: event.timestampMs,
        ),
      );
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex) return;
    _activePoints.add(
      InkPoint(
        x: event.a4Position.dx,
        y: event.a4Position.dy,
        pressure: event.pressure,
        timestampMs: event.timestampMs,
      ),
    );
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex == null || _activePoints.isEmpty) return;

    final completedStroke = StrokeElement(
      id: _uuid.v4(),
      pageIndex: _activePageIndex!,
      colorValue: colorValue,
      strokeWidth: isHighlighter ? strokeWidth * 5.0 : strokeWidth,
      isHighlighter: isHighlighter,
      points: List<InkPoint>.from(_activePoints),
    );

    _activePoints.clear();
    _activePageIndex = null;

    // Aggiunge il tratto alla pagina tramite il Command Bus (niente timer automatici)
    commandManager.executeCommand(AddElementCommand(completedStroke));
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex || _activePoints.isEmpty) return;

    final effectiveWidth = isHighlighter ? strokeWidth * 5.0 : strokeWidth;
    final baseColor = Color(colorValue);
    final paint = Paint()
      ..color = isHighlighter ? baseColor.withOpacity(0.35) : baseColor
      ..strokeWidth = effectiveWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = isHighlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = isHighlighter ? BlendMode.multiply : BlendMode.srcOver;

    if (_activePoints.length == 1) {
      final pt = _activePoints.first;
      canvas.drawCircle(
        Offset(pt.x, pt.y),
        effectiveWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(_activePoints.first.x, _activePoints.first.y);
    for (int i = 1; i < _activePoints.length - 1; i++) {
      final p0 = _activePoints[i];
      final p1 = _activePoints[i + 1];
      final midX = (p0.x + p1.x) / 2;
      final midY = (p0.y + p1.y) / 2;
      path.quadraticBezierTo(p0.x, p0.y, midX, midY);
    }
    path.lineTo(_activePoints.last.x, _activePoints.last.y);

    canvas.drawPath(path, paint);
  }

  @override
  void cancelActiveGesture() {
    _activePoints.clear();
    _activePageIndex = null;
  }
}

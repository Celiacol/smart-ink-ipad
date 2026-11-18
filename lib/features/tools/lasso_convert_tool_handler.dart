import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path;

import '../../core/commands/command_manager.dart';
import '../../core/models/canvas_element.dart';
import '../handwriting_ocr/handwriting_ocr_service.dart';
import 'canvas_tool_handler.dart';

/// Strumento Lazo **"Converti Cerchio"** (`✨ Converti Cerchio`):
/// L'utente scrive liberamente a mano con la penna senza interruzioni, poi seleziona
/// questo strumento e **cerchia** la scrittura che desidera convertire in testo digitale.
///
/// Applica tutte le regole definite nell'app:
/// - Distingue testo da figure geometriche
/// - Calibrazione personale + Smart Re-Ranking Top-10 + accenti/tagli delle 't'
/// - Allineamento preciso sopra righe e quadretti (gestendo le discendenti come 'p')
/// - Dim. Auto-Snap (BETA) con tolleranza oppure Dim. Fissa da Toolbar
/// - Accorpa Riga ON/OFF (con continuità <= 1.2s tra righe consecutive)
/// - Completamente reversibile con Undo
class LassoConvertToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.lassoConvert;

  final HandwritingOcrService ocrService;

  int? _activePageIndex;
  final List<Offset> _lassoPoints = [];

  LassoConvertToolHandler({required this.ocrService});

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    _activePageIndex = event.pageIndex;
    _lassoPoints
      ..clear()
      ..add(event.a4Position);
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex) return;
    _lassoPoints.add(event.a4Position);
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    final pageIndex = _activePageIndex;
    final polygon = List<Offset>.from(_lassoPoints);
    _activePageIndex = null;
    _lassoPoints.clear();

    if (pageIndex == null || polygon.length < 3) return;

    final page = commandManager.state.pageAt(pageIndex);
    final selectedStrokes = <StrokeElement>[];

    for (final el in page.elements.whereType<StrokeElement>()) {
      if (el.isHighlighter || el.points.isEmpty) continue;
      if (_isStrokeInsidePolygon(el, polygon)) {
        selectedStrokes.add(el);
      }
    }

    if (selectedStrokes.isEmpty) return;
    ocrService.convertSelectedStrokes(pageIndex, selectedStrokes);
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex || _lassoPoints.length < 2) return;

    final path = Path()..moveTo(_lassoPoints.first.dx, _lassoPoints.first.dy);
    for (int i = 1; i < _lassoPoints.length; i++) {
      path.lineTo(_lassoPoints[i].dx, _lassoPoints[i].dy);
    }
    path.close();

    final fillPaint = Paint()
      ..color = const Color(0x147C3AED)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF7C3AED)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  void cancelActiveGesture() {
    _activePageIndex = null;
    _lassoPoints.clear();
  }

  bool _isStrokeInsidePolygon(StrokeElement stroke, List<Offset> polygon) {
    if (_isPointInPolygon(stroke.boundingBox.center, polygon)) return true;
    int insideCount = 0;
    final step = stroke.points.length > 20 ? (stroke.points.length ~/ 15) : 1;
    int sampled = 0;
    for (int i = 0; i < stroke.points.length; i += step) {
      sampled++;
      if (_isPointInPolygon(stroke.points[i].offset, polygon)) {
        insideCount++;
      }
    }
    return sampled > 0 && (insideCount / sampled) >= 0.40;
  }

  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;
      final intersect = ((yi > point.dy) != (yj > point.dy)) &&
          (point.dx <
              (xj - xi) *
                      (point.dy - yi) /
                      ((yj - yi) == 0 ? 0.00001 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}

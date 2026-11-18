import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, Rect;

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/models/canvas_element.dart';
import 'canvas_tool_handler.dart';

/// Strumento **"Lazo Sposta"** (`🔲 Lazo Sposta`):
/// Permette di cerchiare qualsiasi elemento sul foglio (testo convertito,
/// scrittura a mano libera, evidenziatori, forme) e trascinarlo liberamente.
class LassoMoveToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.lassoMove;

  int? _activePageIndex;
  final List<Offset> _lassoPoints = [];
  final List<CanvasElement> _selectedElements = [];
  Rect? _selectionBounds;

  bool _isDraggingSelection = false;
  Offset? _dragStartPos;
  Offset _dragDelta = Offset.zero;

  bool get hasSelection => _selectedElements.isNotEmpty;

  void clearSelection() {
    _selectedElements.clear();
    _selectionBounds = null;
    _isDraggingSelection = false;
    _dragStartPos = null;
    _dragDelta = Offset.zero;
  }

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    // Se c'è già una selezione sulla stessa pagina e l'utente tocca dentro, inizia a spostare!
    if (_activePageIndex == event.pageIndex &&
        _selectionBounds != null &&
        _selectionBounds!.inflate(14.0).contains(event.a4Position)) {
      _isDraggingSelection = true;
      _dragStartPos = event.a4Position;
      _dragDelta = Offset.zero;
      return;
    }

    // Altrimenti inizia un nuovo cerchio lazo
    clearSelection();
    _activePageIndex = event.pageIndex;
    _lassoPoints
      ..clear()
      ..add(event.a4Position);
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex) return;

    if (_isDraggingSelection && _dragStartPos != null) {
      _dragDelta = event.a4Position - _dragStartPos!;
    } else {
      _lassoPoints.add(event.a4Position);
    }
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    final pageIndex = _activePageIndex;
    if (pageIndex == null) return;

    if (_isDraggingSelection) {
      final delta = _dragDelta;
      final ids = _selectedElements.map((e) => e.id).toSet();
      _isDraggingSelection = false;
      _dragStartPos = null;
      _dragDelta = Offset.zero;

      if (ids.isNotEmpty && delta.distance > 2.0) {
        commandManager.executeCommand(
          TranslateElementsCommand(
            pageIndex: pageIndex,
            elementIds: ids,
            dx: delta.dx,
            dy: delta.dy,
          ),
        );
        // Aggiorna la selezione con gli elementi spostati
        final updatedPage = commandManager.state.pageAt(pageIndex);
        _selectedElements
          ..clear()
          ..addAll(updatedPage.elements.where((e) => ids.contains(e.id)));
        _recomputeSelectionBounds();
      }
      return;
    }

    // Completa il lazo e seleziona tutto ciò che è dentro
    final polygon = List<Offset>.from(_lassoPoints);
    _lassoPoints.clear();
    if (polygon.length < 3) {
      clearSelection();
      return;
    }

    final page = commandManager.state.pageAt(pageIndex);
    _selectedElements.clear();
    for (final el in page.elements) {
      if (_isElementInsidePolygon(el, polygon)) {
        _selectedElements.add(el);
      }
    }
    _recomputeSelectionBounds();
  }

  void _recomputeSelectionBounds() {
    if (_selectedElements.isEmpty) {
      _selectionBounds = null;
      return;
    }
    var box = _selectedElements.first.boundingBox;
    for (int i = 1; i < _selectedElements.length; i++) {
      box = box.expandToInclude(_selectedElements[i].boundingBox);
    }
    _selectionBounds = box.inflate(6.0);
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex) return;

    if (_lassoPoints.length >= 2) {
      final path = Path()..moveTo(_lassoPoints.first.dx, _lassoPoints.first.dy);
      for (int i = 1; i < _lassoPoints.length; i++) {
        path.lineTo(_lassoPoints[i].dx, _lassoPoints[i].dy);
      }
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x1416A34A)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF16A34A)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }

    if (_selectionBounds != null) {
      final shifted = _selectionBounds!.shift(_dragDelta);
      canvas.drawRect(
        shifted,
        Paint()
          ..color = const Color(0x1016A34A)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        shifted,
        Paint()
          ..color = const Color(0xFF16A34A)
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  void cancelActiveGesture() {
    _lassoPoints.clear();
    _isDraggingSelection = false;
    _dragStartPos = null;
    _dragDelta = Offset.zero;
  }

  bool _isElementInsidePolygon(CanvasElement el, List<Offset> polygon) {
    final box = el.boundingBox;
    return _isPointInPolygon(box.center, polygon) ||
        _isPointInPolygon(Offset(box.left + box.width * 0.25, box.center.dy), polygon) ||
        _isPointInPolygon(Offset(box.left + box.width * 0.75, box.center.dy), polygon);
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

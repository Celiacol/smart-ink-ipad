import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle;

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/models/canvas_element.dart';
import 'canvas_tool_handler.dart';

/// Callback invocato quando l'utente tocca un blocco di testo convertito
/// per modificarne il contenuto o la dimensione del font.
typedef OnTextElementTapped = void Function(TextElement textElement);

/// Strumento Selezione & Spostamento.
///
/// Permette di:
/// - Toccare un qualsiasi elemento (incluso un [TextElement] convertito) per selezionarlo.
/// - Trascinarlo in una nuova posizione sul foglio A4.
/// - Toccare due volte / cliccare su "Modifica testo" per aprire l'editor del testo convertito.
class SelectionToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.selection;

  final OnTextElementTapped? onTextElementSelected;

  CanvasElement? _selectedElement;
  Offset? _dragStartA4Pos;
  Offset _currentDragDelta = Offset.zero;

  SelectionToolHandler({this.onTextElementSelected});

  CanvasElement? get selectedElement => _selectedElement;

  void clearSelection() {
    _selectedElement = null;
    _dragStartA4Pos = null;
    _currentDragDelta = Offset.zero;
  }

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    final page = commandManager.state.pageAt(event.pageIndex);

    // Cerca l'elemento più in alto nello z-order toccato dall'utente
    CanvasElement? hit;
    for (int i = page.elements.length - 1; i >= 0; i--) {
      final candidate = page.elements[i];
      if (candidate.hitTest(event.a4Position, radius: 10.0)) {
        hit = candidate;
        break;
      }
    }

    _selectedElement = hit;
    _dragStartA4Pos = hit != null ? event.a4Position : null;
    _currentDragDelta = Offset.zero;

    if (hit is TextElement && onTextElementSelected != null) {
      onTextElementSelected!(hit);
    }
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_selectedElement == null ||
        _dragStartA4Pos == null ||
        _selectedElement!.pageIndex != event.pageIndex) {
      return;
    }
    _currentDragDelta = event.a4Position - _dragStartA4Pos!;
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    if (_selectedElement != null && _currentDragDelta.distance > 2.0) {
      final movedElement = _selectedElement!.translate(
        _currentDragDelta.dx,
        _currentDragDelta.dy,
      );
      commandManager.executeCommand(
        UpdateElementCommand(
          previousElement: _selectedElement!,
          updatedElement: movedElement,
        ),
      );
      _selectedElement = movedElement;
    }
    _dragStartA4Pos = null;
    _currentDragDelta = Offset.zero;
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_selectedElement == null || _selectedElement!.pageIndex != pageIndex) {
      return;
    }

    final box = _selectedElement!.boundingBox
        .shift(_currentDragDelta)
        .inflate(6.0);

    final borderPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final handlePaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    canvas.drawRect(box, borderPaint);

    // Disegna i 4 quadratini di selezione agli angoli
    const handleRadius = 4.0;
    canvas.drawCircle(box.topLeft, handleRadius, handlePaint);
    canvas.drawCircle(box.topRight, handleRadius, handlePaint);
    canvas.drawCircle(box.bottomLeft, handleRadius, handlePaint);
    canvas.drawCircle(box.bottomRight, handleRadius, handlePaint);
  }

  @override
  void cancelActiveGesture() {
    _dragStartA4Pos = null;
    _currentDragDelta = Offset.zero;
  }
}

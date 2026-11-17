import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle;

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/models/canvas_element.dart';
import 'canvas_tool_handler.dart';

/// Strumento Gomma isolato.
///
/// Cancella qualsiasi [CanvasElement] (tratto a mano, forma o blocco di testo)
/// toccato dal cursore della gomma ed emette un unico [RemoveElementsCommand]
/// reversibile con Undo al termine del gesto.
class EraserToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.eraser;

  double eraserRadius;

  int? _activePageIndex;
  Offset? _currentPointerPos;
  final Map<String, CanvasElement> _erasedInCurrentStroke = {};

  EraserToolHandler({this.eraserRadius = 14.0});

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    _activePageIndex = event.pageIndex;
    _currentPointerPos = event.a4Position;
    _erasedInCurrentStroke.clear();
    _collectElementsUnderEraser(event, commandManager);
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex) return;
    _currentPointerPos = event.a4Position;
    _collectElementsUnderEraser(event, commandManager);
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != null && _erasedInCurrentStroke.isNotEmpty) {
      commandManager.executeCommand(
        RemoveElementsCommand(
          pageIndex: _activePageIndex!,
          removedElements: _erasedInCurrentStroke.values.toList(),
        ),
      );
    }
    _erasedInCurrentStroke.clear();
    _currentPointerPos = null;
    _activePageIndex = null;
  }

  void _collectElementsUnderEraser(
    CanvasPointerEvent event,
    CommandManager commandManager,
  ) {
    final page = commandManager.state.pageAt(event.pageIndex);
    for (final element in page.elements) {
      if (_erasedInCurrentStroke.containsKey(element.id)) continue;
      if (element.hitTest(event.a4Position, radius: eraserRadius)) {
        _erasedInCurrentStroke[element.id] = element;
      }
    }
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex || _currentPointerPos == null) return;

    // Disegna il cerchio guida della gomma
    final fillPaint = Paint()
      ..color = const Color(0x33EF4444)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(_currentPointerPos!, eraserRadius, fillPaint);
    canvas.drawCircle(_currentPointerPos!, eraserRadius, borderPaint);
  }

  @override
  void cancelActiveGesture() {
    _erasedInCurrentStroke.clear();
    _currentPointerPos = null;
    _activePageIndex = null;
  }
}

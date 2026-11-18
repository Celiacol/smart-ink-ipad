import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Size;

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/constants/page_constants.dart';
import 'canvas_tool_handler.dart';

/// Strumento **"Sposta Spazio"** (`↕️ Sposta Spazio`):
/// Scelto un punto verticale `Y`, permette di trascinare verso l'alto o verso il basso
/// tutto ciò che si trova sotto (o sopra, scegliendo l'opzione in toolbar) quel punto!
class VerticalSpaceToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.verticalSpace;

  /// `true` = sposta tutto ciò che è SOTTO il punto toccato;
  /// `false` = sposta tutto ciò che è SOPRA il punto toccato.
  bool moveBelowPoint = true;

  int? _activePageIndex;
  double? _splitY;
  double _currentDeltaY = 0.0;
  final Set<String> _affectedIds = {};

  @override
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager) {
    _activePageIndex = event.pageIndex;
    _splitY = event.a4Position.dy;
    _currentDeltaY = 0.0;
    _affectedIds.clear();

    final page = commandManager.state.pageAt(event.pageIndex);
    for (final el in page.elements) {
      final centerY = el.boundingBox.center.dy;
      final matches = moveBelowPoint ? (centerY >= _splitY!) : (centerY <= _splitY!);
      if (matches) {
        _affectedIds.add(el.id);
      }
    }
  }

  @override
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager) {
    if (_activePageIndex != event.pageIndex || _splitY == null) return;
    _currentDeltaY = event.a4Position.dy - _splitY!;
  }

  @override
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager) {
    final pageIndex = _activePageIndex;
    final ids = Set<String>.from(_affectedIds);
    final dy = _currentDeltaY;

    _activePageIndex = null;
    _splitY = null;
    _currentDeltaY = 0.0;
    _affectedIds.clear();

    if (pageIndex != null && ids.isNotEmpty && dy.abs() > 2.0) {
      commandManager.executeCommand(
        TranslateElementsCommand(
          pageIndex: pageIndex,
          elementIds: ids,
          dx: 0.0,
          dy: dy,
        ),
      );
    }
  }

  @override
  void renderActiveOverlay(Canvas canvas, int pageIndex) {
    if (_activePageIndex != pageIndex || _splitY == null) return;

    final currentY = (_splitY! + _currentDeltaY).clamp(0.0, PageConstants.a4Height);

    // Zona evidenziata che mostra la direzione dello spostamento
    final areaPaint = Paint()
      ..color = const Color(0x140EA5E9)
      ..style = PaintingStyle.fill;
    if (moveBelowPoint) {
      final h = PageConstants.a4Height - currentY;
      canvas.drawRect(
        Offset(0, currentY) & Size(PageConstants.a4Width, h < 0 ? 0 : h),
        areaPaint,
      );
    } else {
      canvas.drawRect(
        Offset.zero & Size(PageConstants.a4Width, currentY < 0 ? 0 : currentY),
        areaPaint,
      );
    }

    // Linea guida orizzontale di taglio
    final linePaint = Paint()
      ..color = const Color(0xFF0284C7)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, currentY),
      Offset(PageConstants.a4Width, currentY),
      linePaint,
    );
  }

  @override
  void cancelActiveGesture() {
    _activePageIndex = null;
    _splitY = null;
    _currentDeltaY = 0.0;
    _affectedIds.clear();
  }
}

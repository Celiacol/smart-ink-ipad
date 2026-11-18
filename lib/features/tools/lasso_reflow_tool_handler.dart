import 'dart:math' as math;
import 'dart:ui' show Canvas, Color, Offset, Paint, PaintingStyle, Path, TextDirection;

import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:uuid/uuid.dart';

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/page_model.dart';
import 'canvas_tool_handler.dart';

/// Strumento Lazo "Cerchia Testo":
/// L'utente cerchia uno o più blocchi di testo convertito e tutto il testo
/// all'interno viene riformattato compattando qualsiasi spaziatura a spazi da uno (' ')
/// e riempiendo al massimo ogni riga (tirando su le parole dalle righe inferiori).
class LassoReflowToolHandler implements CanvasToolHandler {
  @override
  ToolType get toolType => ToolType.lassoReflow;

  final Uuid _uuid = const Uuid();
  int? _activePageIndex;
  final List<Offset> _lassoPoints = [];

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
    final selectedTexts = <TextElement>[];

    for (final el in page.elements.whereType<TextElement>()) {
      final box = el.boundingBox;
      final midY = box.center.dy;
      final hit = _isPointInPolygon(box.center, polygon) ||
          _isPointInPolygon(Offset(box.left + box.width * 0.2, midY), polygon) ||
          _isPointInPolygon(Offset(box.left + box.width * 0.8, midY), polygon);
      if (hit) {
        selectedTexts.add(el);
      }
    }

    if (selectedTexts.isEmpty) return;

    // 1. Raggruppa per riga orizzontale per mantenere l'ordine di lettura
    final rowGroups = <List<TextElement>>[];
    for (final textEl in selectedTexts) {
      final baselineY = textEl.y + textEl.fontSize * 0.82;
      List<TextElement>? matchingRow;
      for (final row in rowGroups) {
        final ref = row.first;
        final refBaseline = ref.y + ref.fontSize * 0.82;
        if ((baselineY - refBaseline).abs() <=
            math.max(12.0, ref.fontSize * 0.65)) {
          matchingRow = row;
          break;
        }
      }
      if (matchingRow != null) {
        matchingRow.add(textEl);
      } else {
        rowGroups.add([textEl]);
      }
    }

    rowGroups.sort((a, b) => a.first.y.compareTo(b.first.y));

    // 2. Estrae tutte le parole in ordine (alto->basso, sinistra->destra)
    final allWords = <String>[];
    for (final row in rowGroups) {
      row.sort((a, b) => a.x.compareTo(b.x));
      for (final item in row) {
        final words = item.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty);
        allWords.addAll(words);
      }
    }

    if (allWords.isEmpty) return;

    // 3. Riempie al massimo ogni riga fino al margine destro A4
    final first = rowGroups.first.first;
    final startX = rowGroups.first.map((e) => e.x).reduce(math.min);
    final maxLineWidth = math.max(120.0, PageConstants.a4Width - 28.0 - startX);
    final defaultLineStep = page.background == PageBackgroundTemplate.ruled
        ? 24.0
        : first.fontSize * 1.32;

    final packedLines = <String>[];
    String currentLine = '';

    for (final word in allWords) {
      final candidate = currentLine.isEmpty ? word : '$currentLine $word';
      final width = _measureTextWidth(candidate, first.fontSize, first.fontFamily);
      if (currentLine.isNotEmpty && width > maxLineWidth) {
        packedLines.add(currentLine);
        currentLine = word;
      } else {
        currentLine = candidate;
      }
    }
    if (currentLine.isNotEmpty) {
      packedLines.add(currentLine);
    }

    final reformatted = <TextElement>[];
    final firstLineY = rowGroups.first.first.y;
    for (int idx = 0; idx < packedLines.length; idx++) {
      // Riempie tutte le righe consecutive senza lasciare righe vuote di scarto!
      final targetY = firstLineY + idx * defaultLineStep;

      reformatted.add(
        TextElement(
          id: _uuid.v4(),
          pageIndex: pageIndex,
          colorValue: first.colorValue,
          x: startX,
          y: targetY,
          text: packedLines[idx],
          fontSize: first.fontSize,
          maxWidth: maxLineWidth,
          fontFamily: first.fontFamily,
        ),
      );
    }

    if (reformatted.isEmpty) return;

    commandManager.executeCommand(
      ReflowTextSpacingCommand(
        pageIndex: pageIndex,
        originalTexts: selectedTexts,
        reformattedTexts: reformatted,
      ),
    );
  }

  double _measureTextWidth(String text, double fontSize, String fontFamily) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontFamily: fontFamily),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
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
      ..color = const Color(0x142563EB)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF2563EB)
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

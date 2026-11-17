import 'package:flutter/material.dart';

import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/page_model.dart';
import '../tools/canvas_tool_handler.dart';
import '../tools/shape_tool_handler.dart';

/// CustomPainter che disegna una singola pagina A4 nello spazio logico
/// 595.28 x 841.89 pt.
class A4PagePainter extends CustomPainter {
  final PageModel page;
  final int totalPages;
  final CanvasToolHandler activeTool;

  A4PagePainter({
    required this.page,
    required this.totalPages,
    required this.activeTool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scala automatica dalle dimensioni del widget sullo schermo
    // alle coordinate logiche standard A4 (595.28 x 841.89 pt).
    final scaleX = size.width / PageConstants.a4Width;
    final scaleY = size.height / PageConstants.a4Height;

    canvas.save();
    canvas.scale(scaleX, scaleY);

    // 1. Disegna il fondo carta A4 e la rigatura scelta (Bianco, Righe, Quadretti, Puntinato)
    _drawPaperBackground(canvas);

    // 2. Disegna tutti gli elementi consolidati della pagina
    for (final element in page.elements) {
      if (element is StrokeElement) {
        _drawStrokeElement(canvas, element);
      } else if (element is ShapeElement) {
        _drawShapeElement(canvas, element);
      } else if (element is TextElement) {
        _drawTextElement(canvas, element);
      }
    }

    // 3. Disegna l'anteprima in tempo reale dello strumento attivo (es. tratto in corso)
    activeTool.renderActiveOverlay(canvas, page.pageIndex);

    // 4. Disegna il piè di pagina discreto con il numero di pagina
    _drawPageNumberFooter(canvas);

    canvas.restore();
  }

  void _drawPaperBackground(Canvas canvas) {
    const pageRect = Rect.fromLTWH(
      0,
      0,
      PageConstants.a4Width,
      PageConstants.a4Height,
    );

    final paperPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(pageRect, paperPaint);

    final guidePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 0.8;

    const topMargin = 56.0;
    const bottomMargin = PageConstants.a4Height - 42.0;

    switch (page.background) {
      case PageBackgroundTemplate.blank:
        break;

      case PageBackgroundTemplate.ruled:
        // Margine verticale rosso chiaro a sinistra (stile quaderno)
        final marginPaint = Paint()
          ..color = const Color(0xFFFCA5A5).withOpacity(0.55)
          ..strokeWidth = 1.0;
        canvas.drawLine(
          const Offset(52.0, 0),
          const Offset(52.0, PageConstants.a4Height),
          marginPaint,
        );

        const lineSpacing = 24.0;
        for (double y = topMargin; y <= bottomMargin; y += lineSpacing) {
          canvas.drawLine(
            Offset(0, y),
            Offset(PageConstants.a4Width, y),
            guidePaint,
          );
        }
        break;

      case PageBackgroundTemplate.grid:
        // Quadretti da ~5mm (14.17 pt a 72 DPI)
        const gridStep = 14.17;
        for (double x = gridStep; x < PageConstants.a4Width; x += gridStep) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x, PageConstants.a4Height),
            guidePaint,
          );
        }
        for (double y = gridStep; y < PageConstants.a4Height; y += gridStep) {
          canvas.drawLine(
            Offset(0, y),
            Offset(PageConstants.a4Width, y),
            guidePaint,
          );
        }
        break;

      case PageBackgroundTemplate.dotted:
        final dotPaint = Paint()
          ..color = const Color(0xFFCBD5E1)
          ..style = PaintingStyle.fill;
        const dotStep = 18.0;
        for (double y = topMargin; y <= bottomMargin; y += dotStep) {
          for (double x = 24.0; x <= PageConstants.a4Width - 24.0; x += dotStep) {
            canvas.drawCircle(Offset(x, y), 1.1, dotPaint);
          }
        }
        break;
    }
  }

  void _drawStrokeElement(Canvas canvas, StrokeElement stroke) {
    if (stroke.points.isEmpty) return;

    final baseColor = stroke.color;
    final paint = Paint()
      ..color = stroke.isHighlighter ? baseColor.withOpacity(0.35) : baseColor
      ..strokeWidth = stroke.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = stroke.isHighlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode =
          stroke.isHighlighter ? BlendMode.multiply : BlendMode.srcOver;

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      canvas.drawCircle(
        Offset(p.x, p.y),
        stroke.strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
      return;
    }

    final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
    for (int i = 1; i < stroke.points.length - 1; i++) {
      final p0 = stroke.points[i];
      final p1 = stroke.points[i + 1];
      final midX = (p0.x + p1.x) / 2;
      final midY = (p0.y + p1.y) / 2;
      path.quadraticBezierTo(p0.x, p0.y, midX, midY);
    }
    path.lineTo(stroke.points.last.x, stroke.points.last.y);

    canvas.drawPath(path, paint);
  }

  void _drawShapeElement(Canvas canvas, ShapeElement shape) {
    ShapeToolHandler.drawShape(
      canvas: canvas,
      kind: shape.kind,
      start: shape.startPoint,
      end: shape.endPoint,
      color: shape.color,
      strokeWidth: shape.strokeWidth,
    );
  }

  void _drawTextElement(Canvas canvas, TextElement textElement) {
    final textStyle = TextStyle(
      color: textElement.color,
      fontSize: textElement.fontSize,
      fontFamily: textElement.fontFamily,
      height: 1.32,
    );

    final textSpan = TextSpan(
      text: textElement.text,
      style: textStyle,
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textElement.maxWidth);

    textPainter.paint(canvas, Offset(textElement.x, textElement.y));
  }

  void _drawPageNumberFooter(Canvas canvas) {
    final footerPainter = TextPainter(
      text: TextSpan(
        text: 'Pagina ${page.pageIndex + 1} di $totalPages',
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 9.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    footerPainter.paint(
      canvas,
      Offset(
        (PageConstants.a4Width - footerPainter.width) / 2,
        PageConstants.a4Height - 22.0,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant A4PagePainter oldDelegate) => true;
}

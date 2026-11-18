import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/document_state.dart';
import '../../core/models/page_model.dart';

/// Servizio indipendente per l'esportazione in PDF A4 vettoriale 1:1
/// e la stampa diretta (AirPrint su iPad / Mopria su Android).
///
/// Di default genera un documento professionale su **sfondo bianco pulito**
/// (senza la griglia di righe/quadretti usata come guida durante la scrittura),
/// mantenendo testo convertito, disegni e figure esattamente nelle stesse
/// posizioni logiche A4 (595.28 x 841.89 pt).
class PdfExportService {
  const PdfExportService();

  /// Genera i byte del file PDF A4 a partire dallo stato attuale del documento.
  ///
  /// [includePageBackgroundGuides] è `false` di default per produrre un PDF
  /// su foglio bianco pulito pronto per la stampa e la condivisione.
  Future<Uint8List> generatePdfBytes(
    DocumentState documentState, {
    bool includePageBackgroundGuides = false,
  }) async {
    final pdf = pw.Document(
      title: documentState.title,
      creator: 'Smart Ink Notebook',
    );

    for (final page in documentState.pages) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Container(
              width: PageConstants.a4Width,
              height: PageConstants.a4Height,
              color: PdfColors.white,
              child: pw.Stack(
                children: [
                  // 1. Livello inferiore: eventuale sfondo opzionale + evidenziatori (sotto al testo)
                  pw.CustomPaint(
                    size: const PdfPoint(
                      PageConstants.a4Width,
                      PageConstants.a4Height,
                    ),
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      if (includePageBackgroundGuides) {
                        _paintPdfBackgroundGuides(canvas, page.background);
                      }
                      for (final element in page.elements) {
                        if (element is StrokeElement && element.isHighlighter) {
                          _paintPdfStroke(canvas, element);
                        }
                      }
                    },
                  ),

                  // 2. Livello intermedio: tutti i blocchi di testo convertiti come vero testo
                  //    vettoriale selezionabile e ricercabile nel PDF alle stesse coordinate!
                  for (final element in page.elements.whereType<TextElement>())
                    pw.Positioned(
                      left: element.x,
                      top: element.y,
                      child: pw.ConstrainedBox(
                        constraints: pw.BoxConstraints(
                          maxWidth: element.maxWidth,
                        ),
                        child: pw.Text(
                          element.text,
                          style: pw.TextStyle(
                            fontSize: element.fontSize,
                            color: _solidPdfColor(element.colorValue),
                            lineSpacing: element.fontSize * 0.25,
                          ),
                        ),
                      ),
                    ),

                  // 3. Livello superiore: tratti a mano libera (disegni/schemi) e forme geometriche
                  pw.CustomPaint(
                    size: const PdfPoint(
                      PageConstants.a4Width,
                      PageConstants.a4Height,
                    ),
                    painter: (PdfGraphics canvas, PdfPoint size) {
                      for (final element in page.elements) {
                        if (element is StrokeElement && !element.isHighlighter) {
                          _paintPdfStroke(canvas, element);
                        } else if (element is ShapeElement) {
                          _paintPdfShape(canvas, element);
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  /// Apre l'anteprima pulita (sfondo bianco) e la finestra di esportazione/stampa PDF nativa.
  Future<void> printOrShareDocument(
    DocumentState documentState, {
    bool includePageBackgroundGuides = false,
  }) async {
    await Printing.layoutPdf(
      name: '${documentState.title}.pdf',
      format: PdfPageFormat.a4,
      onLayout: (_) => generatePdfBytes(
        documentState,
        includePageBackgroundGuides: includePageBackgroundGuides,
      ),
    );
  }

  /// Nota sulle coordinate PDF: in `PdfGraphics` l'origine Y=0 è in basso a sinistra,
  /// perciò convertiamo `yPdf = a4Height - yScreen`.
  double _toPdfY(double screenY) => PageConstants.a4Height - screenY;

  PdfColor _solidPdfColor(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    return PdfColor(r, g, b);
  }

  PdfColor _highlighterPdfColor(int argb) {
    // Simula la trasparenza dell'evidenziatore schiarendo il colore verso il bianco (35% intensità)
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    return PdfColor(
      1.0 - (1.0 - r) * 0.35,
      1.0 - (1.0 - g) * 0.35,
      1.0 - (1.0 - b) * 0.35,
    );
  }

  void _paintPdfBackgroundGuides(
    PdfGraphics canvas,
    PageBackgroundTemplate background,
  ) {
    canvas
      ..setStrokeColor(PdfColor.fromInt(0xFFE2E8F0))
      ..setLineWidth(0.6);

    const topMargin = 56.0;
    const bottomMargin = PageConstants.a4Height - 42.0;

    if (background == PageBackgroundTemplate.ruled) {
      const lineSpacing = 24.0;
      for (double y = topMargin; y <= bottomMargin; y += lineSpacing) {
        final pdfY = _toPdfY(y);
        canvas
          ..moveTo(0, pdfY)
          ..lineTo(PageConstants.a4Width, pdfY)
          ..strokePath();
      }
    } else if (background == PageBackgroundTemplate.grid) {
      const gridStep = 14.17;
      for (double x = gridStep; x < PageConstants.a4Width; x += gridStep) {
        canvas
          ..moveTo(x, 0)
          ..lineTo(x, PageConstants.a4Height)
          ..strokePath();
      }
      for (double y = gridStep; y < PageConstants.a4Height; y += gridStep) {
        final pdfY = _toPdfY(y);
        canvas
          ..moveTo(0, pdfY)
          ..lineTo(PageConstants.a4Width, pdfY)
          ..strokePath();
      }
    }
  }

  void _paintPdfStroke(PdfGraphics canvas, StrokeElement stroke) {
    if (stroke.points.isEmpty) return;

    final color = stroke.isHighlighter
        ? _highlighterPdfColor(stroke.colorValue)
        : _solidPdfColor(stroke.colorValue);

    canvas
      ..setStrokeColor(color)
      ..setLineWidth(stroke.strokeWidth)
      ..setLineCap(stroke.isHighlighter ? PdfLineCap.butt : PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round);

    final first = stroke.points.first;
    canvas.moveTo(first.x, _toPdfY(first.y));
    for (int i = 1; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      canvas.lineTo(p.x, _toPdfY(p.y));
    }
    canvas.strokePath();
  }

  void _paintPdfShape(PdfGraphics canvas, ShapeElement shape) {
    canvas
      ..setStrokeColor(_solidPdfColor(shape.colorValue))
      ..setLineWidth(shape.strokeWidth)
      ..setLineCap(PdfLineCap.round)
      ..setLineJoin(PdfLineJoin.round);

    final x1 = shape.startPoint.dx;
    final y1 = _toPdfY(shape.startPoint.dy);
    final x2 = shape.endPoint.dx;
    final y2 = _toPdfY(shape.endPoint.dy);

    switch (shape.kind) {
      case ShapeKind.rectangle:
        canvas
          ..drawRect(
            x1 < x2 ? x1 : x2,
            y1 < y2 ? y1 : y2,
            (x2 - x1).abs(),
            (y2 - y1).abs(),
          )
          ..strokePath();
        break;
      case ShapeKind.circle:
        canvas
          ..drawEllipse(
            (x1 + x2) / 2,
            (y1 + y2) / 2,
            (x2 - x1).abs() / 2,
            (y2 - y1).abs() / 2,
          )
          ..strokePath();
        break;
      case ShapeKind.line:
        canvas
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..strokePath();
        break;
      case ShapeKind.arrow:
        canvas
          ..moveTo(x1, y1)
          ..lineTo(x2, y2)
          ..strokePath();
        final angle = math.atan2(y2 - y1, x2 - x1);
        const headLength = 14.0;
        const headAngle = 0.5;
        canvas
          ..moveTo(x2, y2)
          ..lineTo(
            x2 - headLength * math.cos(angle - headAngle),
            y2 - headLength * math.sin(angle - headAngle),
          )
          ..moveTo(x2, y2)
          ..lineTo(
            x2 - headLength * math.cos(angle + headAngle),
            y2 - headLength * math.sin(angle + headAngle),
          )
          ..strokePath();
        break;
    }
  }
}

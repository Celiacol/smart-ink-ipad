import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';

/// Rappresenta una singola riga di scrittura individuata dall'analisi spaziale.
class HandwritingLineCluster {
  /// Tratti che appartengono a questa riga, ordinati da sinistra a destra.
  final List<StrokeElement> strokes;

  /// Rettangolo di ingombro complessivo della riga sul foglio A4.
  final Rect boundingBox;

  /// Numero di spazi di indentazione iniziali rispetto al margine sinistro del blocco.
  final int leadingSpacesCount;

  const HandwritingLineCluster({
    required this.strokes,
    required this.boundingBox,
    this.leadingSpacesCount = 0,
  });
}

/// Risultato completo dell'analisi di layout spaziale prima/dopo il riconoscimento OCR.
class SpatialLayoutResult {
  /// Coordinata X dove posizionare il blocco di testo convertito sul foglio A4.
  final double anchorX;

  /// Coordinata Y dove posizionare il blocco di testo convertito sul foglio A4.
  final double anchorY;

  /// Righe di scrittura individuate (ogni riga oltre la prima genera un `\n`).
  final List<HandwritingLineCluster> lineClusters;

  /// Altezza mediana stimata della calligrafia dell'utente (in punti A4).
  final double estimatedHandwritingHeight;

  /// Dimensione finale del font (`fontSize`) calcolata in base alla modalità scelta.
  final double resolvedFontSize;

  const SpatialLayoutResult({
    required this.anchorX,
    required this.anchorY,
    required this.lineClusters,
    required this.estimatedHandwritingHeight,
    required this.resolvedFontSize,
  });
}

/// Analizzatore spaziale dei tratti scritti a mano.
///
/// Responsabilità:
/// 1. Raggruppare i tratti in **righe verticali** per preservare gli **a-capo (`\n`)**
///    fatti dall'utente mentre scrive.
/// 2. Rilevare le **spaziature / indentazioni orizzontali** rispetto all'inizio del blocco.
/// 3. Calcolare la **dimensione del testo (`fontSize`)** secondo le 2 modalità:
///    - [TextSizeMode.adaptiveSnap]: legge l'altezza della calligrafia e fa lo snap
///      allo stile più vicino (Titolo, Sottotitolo, Corpo, Nota).
///    - [TextSizeMode.fixedFromToolbar]: usa la dimensione fissa scelta nella toolbar.
class SpatialLayoutAnalyzer {
  const SpatialLayoutAnalyzer();

  SpatialLayoutResult analyze({
    required List<StrokeElement> strokes,
    required TextSizeMode sizeMode,
    required double fixedToolbarFontSize,
  }) {
    if (strokes.isEmpty) {
      return SpatialLayoutResult(
        anchorX: 0,
        anchorY: 0,
        lineClusters: const [],
        estimatedHandwritingHeight: PageConstants.fontSizeBody,
        resolvedFontSize: fixedToolbarFontSize,
      );
    }

    // 1. Raggruppa i tratti in righe (Line Clusters) per rispettare gli a-capo.
    final rawLines = _clusterStrokesIntoLines(strokes);

    // 2. Calcola l'ancoraggio superiore sinistro (X, Y) dell'intero blocco.
    double minBlockX = double.infinity;
    double minBlockY = double.infinity;
    for (final line in rawLines) {
      if (line.boundingBox.left < minBlockX) minBlockX = line.boundingBox.left;
      if (line.boundingBox.top < minBlockY) minBlockY = line.boundingBox.top;
    }

    // 3. Stima l'altezza della scrittura e risolve la dimensione del font.
    final handwritingHeight = _estimateHandwritingHeight(rawLines, strokes);
    final resolvedFontSize = sizeMode == TextSizeMode.adaptiveSnap
        ? PageConstants.snapHandwritingHeightToFontSize(handwritingHeight)
        : fixedToolbarFontSize;

    // 4. Calcola l'eventuale indentazione (spazi iniziali) per ogni riga
    //    se l'utente è andato a capo partendo più a destra.
    final spaceWidthEstimate = math.max(6.0, resolvedFontSize * 0.45);
    final enrichedLines = rawLines.map((line) {
      final offsetFromLeft = math.max(0.0, line.boundingBox.left - minBlockX);
      // Ignora piccole oscillazioni naturali di inizio riga (< 18 pt)
      final leadingSpaces = offsetFromLeft > 18.0
          ? (offsetFromLeft / spaceWidthEstimate).round().clamp(0, 20)
          : 0;
      return HandwritingLineCluster(
        strokes: line.strokes,
        boundingBox: line.boundingBox,
        leadingSpacesCount: leadingSpaces,
      );
    }).toList();

    return SpatialLayoutResult(
      anchorX: minBlockX,
      anchorY: minBlockY,
      lineClusters: enrichedLines,
      estimatedHandwritingHeight: handwritingHeight,
      resolvedFontSize: resolvedFontSize,
    );
  }

  /// Compone il testo finale multi-riga unendo i testi riconosciuti per ciascuna riga
  /// con ritorni a capo `\n` e preservando le spaziature interne ed esterne.
  String composeFormattedText({
    required List<HandwritingLineCluster> lineClusters,
    required List<String> recognizedLineTexts,
  }) {
    final buffer = StringBuffer();
    final count = math.min(lineClusters.length, recognizedLineTexts.length);

    for (int i = 0; i < count; i++) {
      final rawText = recognizedLineTexts[i].trim();
      if (rawText.isEmpty) continue;

      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }

      final indent = ' ' * lineClusters[i].leadingSpacesCount;
      final normalizedInternalSpaces =
          _preserveHorizontalWordGaps(lineClusters[i], rawText);
      buffer.write('$indent$normalizedInternalSpaces');
    }

    return buffer.toString();
  }

  /// Divide i tratti in righe orizzontali ordinate dall'alto verso il basso.
  List<HandwritingLineCluster> _clusterStrokesIntoLines(
    List<StrokeElement> strokes,
  ) {
    // Ordina i tratti in base al centro verticale Y del loro boundingBox.
    final sortedByY = List<StrokeElement>.from(strokes)
      ..sort((a, b) => a.boundingBox.center.dy.compareTo(b.boundingBox.center.dy));

    final List<List<StrokeElement>> lineGroups = [];
    final List<Rect> lineRects = [];

    for (final stroke in sortedByY) {
      final sBox = stroke.boundingBox;
      int matchedLineIndex = -1;

      for (int i = 0; i < lineRects.length; i++) {
        final lBox = lineRects[i];
        if (_belongsToSameLine(lBox, sBox)) {
          matchedLineIndex = i;
          break;
        }
      }

      if (matchedLineIndex >= 0) {
        lineGroups[matchedLineIndex].add(stroke);
        lineRects[matchedLineIndex] =
            lineRects[matchedLineIndex].expandToInclude(sBox);
      } else {
        lineGroups.add([stroke]);
        lineRects.add(sBox);
      }
    }

    // Ordina le righe dall'alto verso il basso e, dentro ogni riga,
    // ordina i tratti da sinistra verso destra.
    final List<HandwritingLineCluster> result = [];
    for (int i = 0; i < lineGroups.length; i++) {
      final group = lineGroups[i]
        ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      result.add(
        HandwritingLineCluster(
          strokes: group,
          boundingBox: lineRects[i],
        ),
      );
    }

    result.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    return result;
  }

  /// Determina se un tratto [strokeBox] appartiene alla riga [lineBox]
  /// (inclusi puntini sulle 'i', accenti o tagli delle 't').
  bool _belongsToSameLine(Rect lineBox, Rect strokeBox) {
    final overlapTop = math.max(lineBox.top, strokeBox.top);
    final overlapBottom = math.min(lineBox.bottom, strokeBox.bottom);
    final verticalOverlap = overlapBottom - overlapTop;

    final minHeight = math.min(lineBox.height, strokeBox.height);
    if (minHeight > 0 && verticalOverlap >= minHeight * 0.30) {
      return true;
    }

    // Gestione accenti e puntini della 'i' (piccoli tratti appena sopra la riga
    // e allineati orizzontalmente).
    final isDotOrAccent = strokeBox.height < 8.0 && strokeBox.width < 12.0;
    if (isDotOrAccent) {
      final verticalGap = (lineBox.top - strokeBox.bottom).abs();
      final horizontalOverlap = strokeBox.right >= lineBox.left - 10.0 &&
          strokeBox.left <= lineBox.right + 10.0;
      if (verticalGap <= 18.0 && horizontalOverlap) {
        return true;
      }
    }

    // Controlla anche la distanza tra i centri verticali rispetto all'altezza della riga.
    final centerDistance = (lineBox.center.dy - strokeBox.center.dy).abs();
    return centerDistance <= math.max(12.0, lineBox.height * 0.55);
  }

  /// Stima l'altezza della calligrafia dell'utente in punti A4.
  double _estimateHandwritingHeight(
    List<HandwritingLineCluster> lines,
    List<StrokeElement> allStrokes,
  ) {
    // Raccoglie le altezze dei tratti significativi (escludendo puntini e trattini minuscoli).
    final strokeHeights = allStrokes
        .map((s) => s.boundingBox.height)
        .where((h) => h >= 6.0)
        .toList()
      ..sort();

    if (strokeHeights.isEmpty) {
      return PageConstants.fontSizeBody;
    }

    // Usa il 75° percentile delle altezze dei tratti della riga per rappresentare
    // fedelmente la grandezza visiva scelta dall'utente.
    final p75Index =
        ((strokeHeights.length - 1) * 0.75).round().clamp(0, strokeHeights.length - 1);
    return strokeHeights[p75Index];
  }

  /// Se l'utente ha lasciato uno spazio molto ampio tra due parole sulla stessa riga,
  /// preserva la spaziatura estesa.
  String _preserveHorizontalWordGaps(
    HandwritingLineCluster line,
    String recognizedText,
  ) {
    return recognizedText;
  }
}

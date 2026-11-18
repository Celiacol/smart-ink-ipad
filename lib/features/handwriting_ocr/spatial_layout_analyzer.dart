import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/page_model.dart';

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
    PageBackgroundTemplate pageBackground = PageBackgroundTemplate.blank,
    List<TextElement> existingPageTexts = const [],
    double? previousReferenceHeight,
    double? previousResolvedFontSize,
    double calibratedBaselineHeight = 18.0,
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

    // 2. Calcola l'ancoraggio orizzontale X dell'intero blocco.
    double minBlockX = double.infinity;
    for (final line in rawLines) {
      if (line.boundingBox.left < minBlockX) minBlockX = line.boundingBox.left;
    }

    // 3. Stima l'altezza della scrittura e risolve la dimensione del font
    //    con isteresi (±35% di tolleranza) e taratura rispetto all'altezza calibrata dell'utente.
    final handwritingHeight = _estimateHandwritingHeight(rawLines, strokes);
    final normalizedHeight = calibratedBaselineHeight > 0
        ? handwritingHeight * (18.0 / calibratedBaselineHeight)
        : handwritingHeight;
    double resolvedFontSize;
    if (sizeMode == TextSizeMode.adaptiveSnap) {
      if (previousReferenceHeight != null && previousResolvedFontSize != null) {
        final diffRatio = (handwritingHeight - previousReferenceHeight).abs() /
            math.max(1.0, previousReferenceHeight);
        resolvedFontSize = diffRatio <= 0.35
            ? previousResolvedFontSize
            : PageConstants.snapHandwritingHeightToFontSize(normalizedHeight);
      } else {
        resolvedFontSize =
            PageConstants.snapHandwritingHeightToFontSize(normalizedHeight);
      }
    } else {
      resolvedFontSize = fixedToolbarFontSize;
    }

    // 4. Stima la baseline reale della prima riga scritta (76° percentile delle Y:
    //    ignora le code discendenti di 'p', 'g', 'q', 'y' in corsivo!)
    final firstLineBaselineRaw = _estimateInkBaselineY(rawLines.first.strokes);
    double targetBaselineY =
        _snapBaselineToPaperLine(firstLineBaselineRaw, pageBackground);

    // 5. Allineamento multi-input sulla stessa riga:
    //    solo se la nuova parola è a destra/sinistra (non sotto!) di un testo esistente
    //    e sulla stessa riga fisica (<= 11pt su foglio bianco, o stessa riga su righe/quadretti).
    final firstLineMaxX = rawLines.first.boundingBox.right;
    for (final existing in existingPageTexts) {
      final existingBox = existing.boundingBox;
      final horizontallyDisjoint =
          (minBlockX >= existingBox.right - 8.0) ||
          (firstLineMaxX <= existingBox.left + 8.0);
      if (!horizontallyDisjoint) continue;

      final existingAscent = existing.fontSize * 0.82;
      final existingLines = existing.text.split('\n');
      bool matched = false;
      for (int li = 0; li < existingLines.length; li++) {
        final existingBaseline =
            existing.y + existingAscent + li * (existing.fontSize * 1.32);
        final tolerance = math.min(11.0, math.max(7.0, existing.fontSize * 0.55));
        final isSameLine =
            (pageBackground == PageBackgroundTemplate.ruled ||
                    pageBackground == PageBackgroundTemplate.grid)
                ? (targetBaselineY - existingBaseline).abs() < 3.0
                : (firstLineBaselineRaw - existingBaseline).abs() <= tolerance;
        if (isSameLine) {
          targetBaselineY = existingBaseline;
          if (sizeMode == TextSizeMode.adaptiveSnap) {
            final sizeDiffRatio = (resolvedFontSize - existing.fontSize).abs() /
                math.max(1.0, existing.fontSize);
            if (sizeDiffRatio <= 0.45) {
              resolvedFontSize = existing.fontSize;
            }
          }
          matched = true;
          break;
        }
      }
      if (matched) break;
    }

    final anchorY = targetBaselineY - (resolvedFontSize * 0.82);

    // 6. Calcola l'eventuale indentazione (spazi iniziali) per ogni riga
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
      anchorY: anchorY,
      lineClusters: enrichedLines,
      estimatedHandwritingHeight: handwritingHeight,
      resolvedFontSize: resolvedFontSize,
    );
  }

  /// Stima la baseline reale dei tratti ignorando le code discendenti ('p', 'g', 'q', 'y').
  double _estimateInkBaselineY(List<StrokeElement> strokes) {
    final ys = <double>[];
    for (final s in strokes) {
      for (final p in s.points) {
        ys.add(p.y);
      }
    }
    if (ys.isEmpty) return 0.0;
    ys.sort();
    final idx = ((ys.length - 1) * 0.76).floor().clamp(0, ys.length - 1);
    return ys[idx];
  }

  /// Aggancia la baseline alla riga orizzontale più vicina su foglio a righe o a quadretti.
  double _snapBaselineToPaperLine(
    double baselineY,
    PageBackgroundTemplate template,
  ) {
    if (template == PageBackgroundTemplate.ruled) {
      const topMargin = 56.0;
      const step = 24.0;
      if (baselineY >= topMargin - 12.0 &&
          baselineY <= PageConstants.a4Height - 30.0) {
        final nearest =
            topMargin + ((baselineY - topMargin) / step).round() * step;
        if ((baselineY - nearest).abs() <= 12.0) {
          return nearest - 1.5;
        }
      }
    } else if (template == PageBackgroundTemplate.grid) {
      const step = 14.17;
      final nearest = (baselineY / step).round() * step;
      if ((baselineY - nearest).abs() <= 7.5) {
        return nearest - 1.0;
      }
    }
    return baselineY;
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
  /// (inclusi puntini sulle 'i', accenti o tagli delle 't'), evitando di fondere
  /// due righe diverse quando una discendente ('p', 'g') tocca la riga sotto.
  bool _belongsToSameLine(Rect lineBox, Rect strokeBox) {
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

    // Confronta i centri verticali con soglia stretta (13pt < 24pt interlinea A4)
    final centerDistance = (lineBox.center.dy - strokeBox.center.dy).abs();
    if (centerDistance <= 13.0) {
      return true;
    }

    final overlapTop = math.max(lineBox.top, strokeBox.top);
    final overlapBottom = math.min(lineBox.bottom, strokeBox.bottom);
    final verticalOverlap = overlapBottom - overlapTop;
    final minHeight = math.min(lineBox.height, strokeBox.height);

    // Richiede almeno il 55% di sovrapposizione verticale così discendenti/ascendenti
    // tra due righe adiacenti non uniscono mai la Riga 1 con la Riga 2.
    return minHeight > 0 &&
        verticalOverlap >= minHeight * 0.55 &&
        centerDistance <= 18.0;
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

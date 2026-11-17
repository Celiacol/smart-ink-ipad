import 'dart:math' as math;

import '../../core/models/canvas_element.dart';

/// Risultato della classificazione dell'intento dell'utente.
enum InkIntent {
  /// L'utente ha scritto del testo (in corsivo o stampatello) che va convertito.
  handwritingText,

  /// L'utente ha disegnato una figura geometrica, una freccia, uno schema o un divisore
  /// che NON deve essere convertito in testo per errore.
  drawingOrDiagram,
}

/// Classificatore geometrico che distingue il testo scritto a mano dalle figure/disegni.
///
/// Lavora interamente offline e a latenza zero analizzando la topologia dei tratti
/// prima di inviarli al motore OCR.
class InkIntentClassifier {
  const InkIntentClassifier();

  /// Valuta se una lista di tratti appena scritti rappresenta testo oppure una figura.
  InkIntent classify(List<StrokeElement> strokes) {
    if (strokes.isEmpty) return InkIntent.drawingOrDiagram;

    // 1. Gli evidenziatori non vanno mai convertiti in testo.
    if (strokes.every((s) => s.isHighlighter)) {
      return InkIntent.drawingOrDiagram;
    }

    // 2. Caso di un singolo tratto isolato:
    // Verifichiamo se è una grande forma chiusa (cerchio/rettangolo) o una lunga linea dritta.
    if (strokes.length == 1) {
      final stroke = strokes.first;
      if (_isSingleLargeClosedShape(stroke) || _isLongStraightLine(stroke)) {
        return InkIntent.drawingOrDiagram;
      }
    }

    // 3. Caso di 2 tratti che formano una freccia isolata (linea lunga + punta)
    // o una grande cornice rettangolare.
    if (strokes.length <= 2 && _isLargeDiagramBox(strokes)) {
      return InkIntent.drawingOrDiagram;
    }

    return InkIntent.handwritingText;
  }

  /// Rileva se un singolo tratto è una figura chiusa grande (es. cerchio, ovale, rettangolo)
  /// e non una semplice lettera "o" o "D" di dimensioni normali.
  bool _isSingleLargeClosedShape(StrokeElement stroke) {
    if (stroke.points.length < 10) return false;

    final box = stroke.boundingBox;
    // Una lettera "O" normale o di titolo raramente supera 65x65 pt su un foglio A4
    // come unico tratto isolato.
    final isLarge = box.width > 65.0 && box.height > 65.0;
    if (!isLarge) return false;

    final first = stroke.points.first;
    final last = stroke.points.last;
    final startEndDistance = math.sqrt(
      math.pow(first.x - last.x, 2) + math.pow(first.y - last.y, 2),
    );

    final diagonal = math.sqrt(box.width * box.width + box.height * box.height);
    // Se l'inizio e la fine del tratto sono molto vicini rispetto alla diagonale,
    // e il perimetro segue il bordo esterno senza oscillazioni interne da parola corsiva:
    final isClosed = startEndDistance < diagonal * 0.28;
    final perimeterRatio = stroke.pathLength / (2 * (box.width + box.height));

    return isClosed && perimeterRatio > 0.65 && perimeterRatio < 1.35;
  }

  /// Rileva se un singolo tratto è una linea dritta lunga (es. separatore o sottolineatura).
  bool _isLongStraightLine(StrokeElement stroke) {
    if (stroke.points.length < 2) return false;

    final first = stroke.points.first;
    final last = stroke.points.last;
    final directDistance = math.sqrt(
      math.pow(first.x - last.x, 2) + math.pow(first.y - last.y, 2),
    );

    // Deve essere abbastanza lunga (> 80 pt su A4) e avere un rapporto
    // distanza-diretta / lunghezza-percorso quasi pari a 1.0 (nessuna curva di lettere).
    if (directDistance < 80.0) return false;
    final straightness = directDistance / math.max(1.0, stroke.pathLength);
    return straightness > 0.94;
  }

  /// Rileva se un piccolo gruppo di tratti occupa un'area enorme con pochissima
  /// complessità di scrittura (es. un grande riquadro per uno schema).
  bool _isLargeDiagramBox(List<StrokeElement> strokes) {
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    double totalPath = 0.0;

    for (final s in strokes) {
      final b = s.boundingBox;
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;
      totalPath += s.pathLength;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    if (width > 120.0 && height > 120.0) {
      final boxPerimeter = 2 * (width + height);
      // Nel testo scritto a mano (anche corsivo), la lunghezza del tracciato
      // interno è molto maggiore del perimetro; in una cornice è ~1.0x il perimetro.
      if (totalPath < boxPerimeter * 1.25) {
        return true;
      }
    }
    return false;
  }
}

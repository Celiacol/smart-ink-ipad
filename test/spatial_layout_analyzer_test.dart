import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/constants/page_constants.dart';
import 'package:smart_ink_notebook/core/models/canvas_element.dart';
import 'package:smart_ink_notebook/features/handwriting_ocr/spatial_layout_analyzer.dart';

StrokeElement _createSyntheticWordStroke({
  required String id,
  required double startX,
  required double topY,
  required double width,
  required double height,
}) {
  return StrokeElement(
    id: id,
    pageIndex: 0,
    colorValue: 0xFF1E293B,
    points: [
      InkPoint(x: startX, y: topY, timestampMs: 10),
      InkPoint(x: startX + width / 2, y: topY + height, timestampMs: 20),
      InkPoint(x: startX + width, y: topY, timestampMs: 30),
    ],
  );
}

void main() {
  const analyzer = SpatialLayoutAnalyzer();

  group('SpatialLayoutAnalyzer - A-Capo (\\n) e Modalità Dimensione Font', () {
    test('Rileva più righe verticali e inserisce gli a-capo (\\n) nel testo convertito', () {
      // Riga 1 a Y = 100..118
      final line1Stroke = _createSyntheticWordStroke(
        id: 's1',
        startX: 60,
        topY: 100,
        width: 120,
        height: 18,
      );
      // Riga 2 (a capo) a Y = 150..168
      final line2Stroke = _createSyntheticWordStroke(
        id: 's2',
        startX: 60,
        topY: 150,
        width: 140,
        height: 18,
      );

      final layout = analyzer.analyze(
        strokes: [line1Stroke, line2Stroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 14.0,
      );

      expect(layout.lineClusters.length, 2);
      expect(layout.anchorX, closeTo(60.0, 2.0));
      expect(layout.anchorY, closeTo(100.0, 2.0));

      final formatted = analyzer.composeFormattedText(
        lineClusters: layout.lineClusters,
        recognizedLineTexts: ['Prima riga di appunti', 'Seconda riga a capo'],
      );

      expect(formatted, 'Prima riga di appunti\nSeconda riga a capo');
    });

    test('Modalità 1 (Auto-Snap): scrittura grande diventa Titolo (28pt), normale diventa Corpo (14pt)', () {
      final largeTitleStroke = _createSyntheticWordStroke(
        id: 'title',
        startX: 50,
        topY: 80,
        width: 200,
        height: 42, // > 36pt -> Titolo 28pt
      );

      final titleLayout = analyzer.analyze(
        strokes: [largeTitleStroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 12.0,
      );
      expect(titleLayout.resolvedFontSize, PageConstants.fontSizeTitle);

      final bodyStroke = _createSyntheticWordStroke(
        id: 'body',
        startX: 50,
        topY: 150,
        width: 200,
        height: 18, // 14..24pt -> Corpo 14pt
      );

      final bodyLayout = analyzer.analyze(
        strokes: [bodyStroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 12.0,
      );
      expect(bodyLayout.resolvedFontSize, PageConstants.fontSizeBody);
    });

    test('Modalità 2 (Fissa da Toolbar): ignora la grandezza scritta e usa la taglia scelta dall\'utente', () {
      final hugeHandwritingStroke = _createSyntheticWordStroke(
        id: 'huge',
        startX: 50,
        topY: 80,
        width: 220,
        height: 48,
      );

      final fixedLayout = analyzer.analyze(
        strokes: [hugeHandwritingStroke],
        sizeMode: TextSizeMode.fixedFromToolbar,
        fixedToolbarFontSize: 12.0,
      );

      expect(fixedLayout.resolvedFontSize, 12.0);
    });
  });
}

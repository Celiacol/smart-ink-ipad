import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/constants/page_constants.dart';
import 'package:smart_ink_notebook/core/models/canvas_element.dart';
import 'package:smart_ink_notebook/core/models/page_model.dart';
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
      InkPoint(x: startX + width * 0.25, y: topY + height, timestampMs: 15),
      InkPoint(x: startX + width * 0.5, y: topY + height, timestampMs: 20),
      InkPoint(x: startX + width * 0.75, y: topY + height, timestampMs: 25),
      InkPoint(x: startX + width, y: topY, timestampMs: 30),
    ],
  );
}

void main() {
  const analyzer = SpatialLayoutAnalyzer();

  group('SpatialLayoutAnalyzer - A-Capo (\\n), Dimensione Adattiva e Allineamento Righe', () {
    test('Rileva più righe verticali e inserisce gli a-capo (\\n) nel testo convertito', () {
      // Riga 1 a Y = 86..104 (poggia sulla riga 104 del foglio a righe)
      final line1Stroke = _createSyntheticWordStroke(
        id: 's1',
        startX: 60,
        topY: 86,
        width: 120,
        height: 18,
      );
      // Riga 2 (a capo) a Y = 136..154
      final line2Stroke = _createSyntheticWordStroke(
        id: 's2',
        startX: 60,
        topY: 136,
        width: 140,
        height: 18,
      );

      final layout = analyzer.analyze(
        strokes: [line1Stroke, line2Stroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 14.0,
        pageBackground: PageBackgroundTemplate.ruled,
      );

      expect(layout.lineClusters.length, 2);
      expect(layout.anchorX, closeTo(60.0, 2.0));
      // Baseline agganciata sopra la riga 104 (con 1.5pt di respiro): 102.5 - (14 * 0.82)
      expect(layout.anchorY, closeTo(102.5 - 14.0 * 0.82, 0.5));

      final formatted = analyzer.composeFormattedText(
        lineClusters: layout.lineClusters,
        recognizedLineTexts: ['Prima riga di appunti', 'Seconda riga a capo'],
      );

      expect(formatted, 'Prima riga di appunti\nSeconda riga a capo');
    });

    test('Modalità 1 (Auto-Snap con tolleranza ±35%): mantiene la stessa grandezza per variazioni lievi, cambia per variazioni nette', () {
      final normalStroke = _createSyntheticWordStroke(
        id: 'normal-1',
        startX: 50,
        topY: 80,
        width: 180,
        height: 22, // Corpo 14pt
      );

      final firstLayout = analyzer.analyze(
        strokes: [normalStroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 12.0,
      );
      expect(firstLayout.resolvedFontSize, PageConstants.fontSizeBody);

      // Secondo input leggermente più grande (27pt = +22% rispetto a 22pt, entro il ±35%):
      // deve restare 14pt invece di saltare a 20pt!
      final slightlyLargerStroke = _createSyntheticWordStroke(
        id: 'normal-2',
        startX: 50,
        topY: 130,
        width: 180,
        height: 27,
      );

      final secondLayout = analyzer.analyze(
        strokes: [slightlyLargerStroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 12.0,
        previousReferenceHeight: firstLayout.estimatedHandwritingHeight,
        previousResolvedFontSize: firstLayout.resolvedFontSize,
      );
      expect(secondLayout.resolvedFontSize, PageConstants.fontSizeBody);

      // Terzo input molto più grande (44pt = +100% rispetto a 22pt -> cambio stravolgente):
      // deve passare a Titolo 28pt!
      final hugeTitleStroke = _createSyntheticWordStroke(
        id: 'title-1',
        startX: 50,
        topY: 200,
        width: 240,
        height: 44,
      );

      final thirdLayout = analyzer.analyze(
        strokes: [hugeTitleStroke],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 12.0,
        previousReferenceHeight: firstLayout.estimatedHandwritingHeight,
        previousResolvedFontSize: firstLayout.resolvedFontSize,
      );
      expect(thirdLayout.resolvedFontSize, PageConstants.fontSizeTitle);
    });

    test('Più input sulla stessa riga restano allineati esattamente alla stessa Y', () {
      const existingWord = TextElement(
        id: 'txt-1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        x: 60.0,
        y: 92.52, // baseline a ~104.0
        text: 'Ciao',
        fontSize: 14.0,
      );

      // Il secondo input viene scritto leggermente più in basso (baseline ~109 invece di 104)
      final secondWordOnSameLine = _createSyntheticWordStroke(
        id: 'w2',
        startX: 140,
        topY: 91,
        width: 90,
        height: 18,
      );

      final layout = analyzer.analyze(
        strokes: [secondWordOnSameLine],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 14.0,
        existingPageTexts: [existingWord],
      );

      expect(layout.anchorY, closeTo(existingWord.y, 0.01));
    });

    test('Foglio a righe: una parola con discendenti (es. "p" in corsivo sotto la riga) poggia comunque sulla riga', () {
      // Corpo principale tra Y=88 e Y=104 (sulla riga 104), coda della 'p' scende fino a Y=118
      final wordWithDescenderP = StrokeElement(
        id: 'word-p',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 60, y: 90, timestampMs: 1),
          InkPoint(x: 65, y: 118, timestampMs: 2), // Gambo discendente della 'p' sotto la riga 104
          InkPoint(x: 70, y: 92, timestampMs: 3),
          InkPoint(x: 78, y: 103, timestampMs: 4),
          InkPoint(x: 88, y: 92, timestampMs: 5),
          InkPoint(x: 96, y: 104, timestampMs: 6),
          InkPoint(x: 105, y: 93, timestampMs: 7),
          InkPoint(x: 115, y: 104, timestampMs: 8),
        ],
      );

      final layout = analyzer.analyze(
        strokes: [wordWithDescenderP],
        sizeMode: TextSizeMode.adaptiveSnap,
        fixedToolbarFontSize: 14.0,
        pageBackground: PageBackgroundTemplate.ruled,
      );

      // La baseline deve agganciarsi esattamente sopra la riga Y=104 (102.5, non scendere verso 118!)
      final resolvedBaseline = layout.anchorY + layout.resolvedFontSize * 0.82;
      expect(resolvedBaseline, closeTo(102.5, 0.5));
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

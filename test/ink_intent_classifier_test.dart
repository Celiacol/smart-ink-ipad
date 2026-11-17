import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/models/canvas_element.dart';
import 'package:smart_ink_notebook/features/handwriting_ocr/ink_intent_classifier.dart';

void main() {
  const classifier = InkIntentClassifier();

  group('InkIntentClassifier - Distinzione Testo vs Figure', () {
    test('Un grande cerchio chiuso disegnato a mano libera viene classificato come Figura (NON convertito)', () {
      final circlePoints = <InkPoint>[];
      const centerX = 250.0;
      const centerY = 300.0;
      const radius = 55.0; // Diametro 110 pt (> 65 pt)

      for (int i = 0; i <= 36; i++) {
        final angle = (i / 36) * 2 * math.pi;
        circlePoints.add(
          InkPoint(
            x: centerX + radius * math.cos(angle),
            y: centerY + radius * math.sin(angle),
            timestampMs: i * 10,
          ),
        );
      }

      final circleStroke = StrokeElement(
        id: 'circle-1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: circlePoints,
      );

      expect(classifier.classify([circleStroke]), InkIntent.drawingOrDiagram);
    });

    test('Una lunga linea dritta separatrice viene classificata come Figura', () {
      final lineStroke = StrokeElement(
        id: 'line-1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 50, y: 200, timestampMs: 0),
          InkPoint(x: 200, y: 200, timestampMs: 20),
          InkPoint(x: 380, y: 201, timestampMs: 40),
        ],
      );

      expect(classifier.classify([lineStroke]), InkIntent.drawingOrDiagram);
    });

    test('Tratti multipli di scrittura normale vengono classificati come Testo da convertire', () {
      final s1 = StrokeElement(
        id: 'w1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 60, y: 120, timestampMs: 0),
          InkPoint(x: 65, y: 105, timestampMs: 10),
          InkPoint(x: 72, y: 120, timestampMs: 20),
          InkPoint(x: 80, y: 108, timestampMs: 30),
        ],
      );
      final s2 = StrokeElement(
        id: 'w2',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 88, y: 118, timestampMs: 40),
          InkPoint(x: 95, y: 106, timestampMs: 50),
          InkPoint(x: 105, y: 118, timestampMs: 60),
        ],
      );

      expect(classifier.classify([s1, s2]), InkIntent.handwritingText);
    });
  });
}

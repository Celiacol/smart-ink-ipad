import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/models/canvas_element.dart';
import 'package:smart_ink_notebook/features/handwriting_ocr/handwriting_calibration.dart';

StrokeElement _strokeBox(String id, double minX, double maxX, double minY, double maxY) {
  return StrokeElement(
    id: id,
    pageIndex: 0,
    colorValue: 0xFF1E293B,
    points: [
      InkPoint(x: minX, y: minY, timestampMs: 10),
      InkPoint(x: maxX, y: maxY, timestampMs: 20),
    ],
  );
}

void main() {
  const calibrator = HandwritingCalibrator();
  const reranker = OcrCandidateReranker();

  group('Calibrazione Offline Calligrafia & Smart Re-Ranking Top-10', () {
    test('Calcola correttamente soglia spazio-parola personale e correzioni apprese dalle 3 frasi', () {
      // Frase a 2 parole ("Oggi tutto"):
      // Parola 1: X=20..40 e X=44..60 (gap interno = 4pt)
      // Parola 2: X=86..110 (gap tra parole = 26pt)
      final sample = CalibrationSample(
        targetText: 'Oggi tutto',
        rawRecognizedText: 'Oggi tu-to',
        strokes: [
          _strokeBox('s1', 20, 40, 80, 100),
          _strokeBox('s2', 44, 60, 80, 100),
          _strokeBox('s3', 86, 110, 78, 100),
        ],
      );

      final profile = calibrator.buildProfile([sample]);

      expect(profile.isCalibrated, isTrue);
      // Media tra gap parola (26) e gap lettera (4) = 15pt
      expect(profile.wordGapThreshold, closeTo(15.0, 0.5));
      expect(profile.personalCorrections['tu-to'], 'tutto');
    });

    test('Smart Re-Ranker preferisce il candidato valido con "t" e accenti invece di "l-" quando c\'è una sbarra orizzontale', () {
      final strokesWithCrossbarAndAccent = [
        _strokeBox('c1', 50, 62, 70, 96), // Gambo alto
        _strokeBox('tbar', 48, 66, 76, 78), // Sbarra orizzontale della 't'
        _strokeBox('c2', 70, 90, 82, 96), // Resto parola
        _strokeBox('acc', 84, 92, 68, 71), // Accento finale
      ];

      final best = reranker.selectBestCandidate(
        candidates: const ['sl-tuazione', 'situazione', 'citta\''],
        strokes: strokesWithCrossbarAndAccent,
        profile: const HandwritingCalibrationProfile(),
      );

      expect(best, 'situazione');
    });

    test('Normalizza automaticamente gli accenti italiani con apostrofo (perche\' -> perché, citta\' -> città)', () {
      final best = reranker.selectBestCandidate(
        candidates: const ["citta' perche'"],
        strokes: [_strokeBox('w1', 50, 120, 80, 96)],
        profile: const HandwritingCalibrationProfile(),
      );

      expect(best, 'città perché');
    });
  });
}

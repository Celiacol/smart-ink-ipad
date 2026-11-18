import 'dart:math' as math;

import '../../core/models/canvas_element.dart';

/// Frase guidata utilizzata nella procedura di calibrazione offline della calligrafia.
class CalibrationPhrase {
  final String title;
  final String targetText;
  final String purposeHint;

  const CalibrationPhrase({
    required this.title,
    required this.targetText,
    required this.purposeHint,
  });
}

/// Le 3 frasi italiane ottimali per calibrare velocemente:
/// 1) distanza lettere vs parole + 't' staccate + puntini 'i' + doppie
/// 2) parole lunghe + accenti italiani (à, è, é, ù)
/// 3) aste discendenti (p, g, q) + maiuscole + numeri
const List<CalibrationPhrase> defaultCalibrationPhrases = [
  CalibrationPhrase(
    title: 'Frase 1 di 3 — Spazi, doppie e taglio delle "t"',
    targetText: 'Oggi tutto funziona perfettamente',
    purposeHint: 'Scrivi col tuo ritmo naturale (corsivo o stampatello).',
  ),
  CalibrationPhrase(
    title: 'Frase 2 di 3 — Parole lunghe e accenti italiani',
    targetText: 'La situazione in città è già più chiara perché',
    purposeHint: 'Aggiungi gli accenti e i tagli delle "t" come fai di solito.',
  ),
  CalibrationPhrase(
    title: 'Frase 3 di 3 — Altezza lettere, numeri e discendenti',
    targetText: 'Appunti di pagina 4 con qualche dettaglio',
    purposeHint: 'Utile per tarare dimensione Auto-Snap e base della riga.',
  ),
];

/// Profilo leggero di calibrazione personale (100% locale e offline).
class HandwritingCalibrationProfile {
  /// Soglia personale (in pt A4) che separa due lettere della stessa parola
  /// da uno spazio tra due parole diverse (default non calibrato: 13.0 pt).
  final double wordGapThreshold;

  /// Altezza tipica della calligrafia normale dell'utente (default: 18.0 pt),
  /// usata per tarare `Auto-Snap` sulla mano reale dell'utente.
  final double baselineHandwritingHeight;

  /// Inclinazione media (shear dx/dy) della scrittura dell'utente (0.0 = dritta).
  final double slantShear;

  /// Dizionario personale di correzioni apprese (OCR grezzo -> testo corretto).
  final Map<String, String> personalCorrections;

  /// Indica se l'utente ha completato la calibrazione guidata.
  final bool isCalibrated;

  const HandwritingCalibrationProfile({
    this.wordGapThreshold = 13.0,
    this.baselineHandwritingHeight = 18.0,
    this.slantShear = 0.0,
    this.personalCorrections = const {},
    this.isCalibrated = false,
  });

  HandwritingCalibrationProfile copyWith({
    double? wordGapThreshold,
    double? baselineHandwritingHeight,
    double? slantShear,
    Map<String, String>? personalCorrections,
    bool? isCalibrated,
  }) {
    return HandwritingCalibrationProfile(
      wordGapThreshold: wordGapThreshold ?? this.wordGapThreshold,
      baselineHandwritingHeight:
          baselineHandwritingHeight ?? this.baselineHandwritingHeight,
      slantShear: slantShear ?? this.slantShear,
      personalCorrections: personalCorrections ?? this.personalCorrections,
      isCalibrated: isCalibrated ?? this.isCalibrated,
    );
  }

  /// Aggiunge o aggiorna una correzione personale (es. "sl-tuazione" -> "situazione").
  HandwritingCalibrationProfile learnCorrection(
    String rawOcrWord,
    String trueWord,
  ) {
    final cleanRaw = rawOcrWord.trim().toLowerCase();
    final cleanTrue = trueWord.trim();
    if (cleanRaw.isEmpty || cleanTrue.isEmpty || cleanRaw == cleanTrue.toLowerCase()) {
      return this;
    }
    final updated = Map<String, String>.from(personalCorrections);
    updated[cleanRaw] = cleanTrue;
    return copyWith(personalCorrections: updated);
  }

  Map<String, dynamic> toJson() => {
        'wordGapThreshold': wordGapThreshold,
        'baselineHandwritingHeight': baselineHandwritingHeight,
        'slantShear': slantShear,
        'personalCorrections': personalCorrections,
        'isCalibrated': isCalibrated,
      };

  factory HandwritingCalibrationProfile.fromJson(Map<String, dynamic> json) {
    return HandwritingCalibrationProfile(
      wordGapThreshold:
          (json['wordGapThreshold'] as num?)?.toDouble() ?? 13.0,
      baselineHandwritingHeight:
          (json['baselineHandwritingHeight'] as num?)?.toDouble() ?? 18.0,
      slantShear: (json['slantShear'] as num?)?.toDouble() ?? 0.0,
      personalCorrections: Map<String, String>.from(
        (json['personalCorrections'] as Map?) ?? const {},
      ),
      isCalibrated: (json['isCalibrated'] as bool?) ?? false,
    );
  }
}

/// Dati raccolti per una singola frase di calibrazione.
class CalibrationSample {
  final String targetText;
  final List<StrokeElement> strokes;
  final String rawRecognizedText;

  const CalibrationSample({
    required this.targetText,
    required this.strokes,
    this.rawRecognizedText = '',
  });
}

/// Calcolatore offline del profilo calligrafico a costo computazionale quasi nullo (< 1ms).
class HandwritingCalibrator {
  const HandwritingCalibrator();

  HandwritingCalibrationProfile buildProfile(List<CalibrationSample> samples) {
    if (samples.isEmpty) return const HandwritingCalibrationProfile();

    final List<double> estimatedWordGaps = [];
    final List<double> estimatedLetterGaps = [];
    final List<double> significantHeights = [];
    final List<double> slantEstimates = [];
    final Map<String, String> learnedCorrections = {};

    for (final sample in samples) {
      if (sample.strokes.isEmpty) continue;

      // 1. Altezza tipica dei tratti principali
      for (final s in sample.strokes) {
        final h = s.boundingBox.height;
        if (h >= 8.0) significantHeights.add(h);
        if (h >= 12.0 && s.points.length >= 2) {
          final first = s.points.first;
          final last = s.points.last;
          final dy = last.y - first.y;
          if (dy.abs() >= 10.0) {
            // dx/dy indica quanto inclina rispetto alla verticale
            final shear = ((first.x - last.x) / dy).clamp(-0.35, 0.35);
            slantEstimates.add(shear);
          }
        }
      }

      // 2. Analisi dei gap orizzontali sapendo esattamente quante parole ci sono nella frase target
      final targetWords = sample.targetText
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final expectedWordSpaces = math.max(0, targetWords.length - 1);

      final mainStrokes = sample.strokes
          .where((s) => !(s.boundingBox.height < 11 && s.boundingBox.width < 28))
          .toList()
        ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

      if (mainStrokes.length >= 2 && expectedWordSpaces > 0) {
        final positiveGaps = <double>[];
        double runningMaxX = mainStrokes.first.boundingBox.right;
        for (int i = 1; i < mainStrokes.length; i++) {
          final s = mainStrokes[i];
          final gap = s.boundingBox.left - runningMaxX;
          if (gap > 1.5) {
            positiveGaps.add(gap);
          }
          if (s.boundingBox.right > runningMaxX) {
            runningMaxX = s.boundingBox.right;
          }
        }
        positiveGaps.sort((a, b) => b.compareTo(a)); // decrescente

        if (positiveGaps.length >= expectedWordSpaces) {
          final wordGaps = positiveGaps.take(expectedWordSpaces);
          final letterGaps = positiveGaps.skip(expectedWordSpaces);
          estimatedWordGaps.addAll(wordGaps);
          estimatedLetterGaps.addAll(letterGaps);
        }
      }

      // 3. Apprendimento correzioni personali (parola per parola se il conteggio corrisponde)
      if (sample.rawRecognizedText.trim().isNotEmpty) {
        final recognizedWords = sample.rawRecognizedText
            .trim()
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .toList();
        if (recognizedWords.length == targetWords.length) {
          for (int i = 0; i < targetWords.length; i++) {
            final raw = recognizedWords[i].trim().toLowerCase();
            final target = targetWords[i].trim();
            if (raw != target.toLowerCase()) {
              learnedCorrections[raw] = target;
            }
          }
        }
      }
    }

    // Calcola soglia personale tra spazio-lettera e spazio-parola
    double resolvedWordGap = 13.0;
    if (estimatedWordGaps.isNotEmpty) {
      estimatedWordGaps.sort();
      final smallestWordGap = estimatedWordGaps.first;
      final largestLetterGap = estimatedLetterGaps.isNotEmpty
          ? (estimatedLetterGaps..sort()).last
          : smallestWordGap * 0.45;
      resolvedWordGap =
          ((smallestWordGap + largestLetterGap) / 2.0).clamp(8.0, 26.0);
    }

    // Calcola altezza tipica (75° percentile)
    double resolvedHeight = 18.0;
    if (significantHeights.isNotEmpty) {
      significantHeights.sort();
      final idx = ((significantHeights.length - 1) * 0.75)
          .round()
          .clamp(0, significantHeights.length - 1);
      resolvedHeight = significantHeights[idx].clamp(10.0, 42.0);
    }

    // Calcola inclinazione mediana
    double resolvedSlant = 0.0;
    if (slantEstimates.isNotEmpty) {
      slantEstimates.sort();
      resolvedSlant = slantEstimates[slantEstimates.length ~/ 2];
    }

    return HandwritingCalibrationProfile(
      wordGapThreshold: resolvedWordGap,
      baselineHandwritingHeight: resolvedHeight,
      slantShear: resolvedSlant,
      personalCorrections: learnedCorrections,
      isCalibrated: true,
    );
  }
}

/// Motore di Smart Re-Ranking dei Top-10 candidati restituiti da ML Kit / Digital Ink.
///
/// Lavora interamente offline in < 0.3ms utilizzando:
/// - Evidenza geometrica dei tratti (es. presenza di sbarre della 't' o accenti finali)
/// - Normalizzazione automatica degli accenti italiani (es. perche' -> perché)
/// - Dizionario delle correzioni personali apprese dalla calibrazione e dalle modifiche utente
class OcrCandidateReranker {
  const OcrCandidateReranker();

  static const Map<String, String> _italianApostropheAccents = {
    "perche'": 'perché',
    "poiche'": 'poiché',
    "finche'": 'finché',
    "citta'": 'città',
    "gia'": 'già',
    "piu'": 'più',
    "puo'": 'può',
    "cosi'": 'così',
    "cio'": 'ciò',
    "percio'": 'perciò',
    "e'": 'è',
    "lunedi'": 'lunedì',
    "martedi'": 'martedì',
    "mercoledi'": 'mercoledì',
    "giovedi'": 'giovedì',
    "venerdi'": 'venerdì',
    "universita'": 'università',
    "qualita'": 'qualità',
    "realta'": 'realtà',
    "verita'": 'verità',
    "liberta'": 'libertà',
  };

  /// Sceglie il candidato migliore tra i [candidates] (fino a 10 alternative)
  /// analizzando i tratti originali [strokes] e il [profile] dell'utente.
  String selectBestCandidate({
    required List<String> candidates,
    required List<StrokeElement> strokes,
    required HandwritingCalibrationProfile profile,
  }) {
    if (candidates.isEmpty) return '';

    final crossbarCount = _countHorizontalCrossbars(strokes);
    final hasTrailingAccentStroke = _hasTrailingHighDiacritic(strokes);

    String bestText = candidates.first;
    double bestScore = double.negativeInfinity;

    final limit = math.min(candidates.length, 10);
    for (int i = 0; i < limit; i++) {
      final raw = candidates[i].trim();
      if (raw.isEmpty) continue;

      final normalized = _applyCorrectionsAndItalianRules(raw, profile);

      // Punteggio base legato alla confidenza originale del motore OCR
      double score = 100.0 - (i * 8.0);

      // Penalizza simboli di rumore in mezzo alle parole (tipici di 't' spezzate: "l-", "l|", "si-tuazione")
      if (RegExp(r'[a-zA-Z][-_|/\\][a-zA-Z]').hasMatch(normalized)) {
        score -= 28.0;
      }

      // Se nei tratti ci sono sbarre orizzontali ('t') ma il candidato non contiene 't'
      // mentre ha 'l-' o 'i-', penalizza; premia invece il candidato con la 't'
      if (crossbarCount > 0) {
        final tCount = 't'.allMatches(normalized.toLowerCase()).length;
        if (tCount > 0) {
          score += math.min(12.0, tCount * 5.0);
        }
        if (RegExp(r'\b[li]\s*[-–]\s*[a-zA-Z]').hasMatch(normalized)) {
          score -= 22.0;
        }
      }

      // Se l'utente ha messo un tratto piccolo sopra la parte finale della parola (accento),
      // premia i candidati con vocali accentate italiane (à, è, é, ì, ò, ù)
      if (hasTrailingAccentStroke &&
          RegExp(r'[àèéìòùÀÈÉÌÒÙ]').hasMatch(normalized)) {
        score += 14.0;
      }

      // Premia corrispondenze trovate nella memoria personale dell'utente
      if (normalized != raw) {
        score += 10.0;
      }

      if (score > bestScore) {
        bestScore = score;
        bestText = normalized;
      }
    }

    return bestText;
  }

  String _applyCorrectionsAndItalianRules(
    String text,
    HandwritingCalibrationProfile profile,
  ) {
    final words = text.split(RegExp(r'\s+'));
    final corrected = words.map((w) {
      final lower = w.toLowerCase();

      // 1. Dizionario personale appreso dalla calibrazione / correzioni utente
      final personal = profile.personalCorrections[lower];
      if (personal != null) {
        // Preserva maiuscola iniziale se presente nell'originale
        if (w.isNotEmpty && w[0].toUpperCase() == w[0]) {
          return personal[0].toUpperCase() + personal.substring(1);
        }
        return personal;
      }

      // 2. Normalizzazione apostrofo -> accento italiano (es. citta' -> città)
      final accentFix = _italianApostropheAccents[lower];
      if (accentFix != null) {
        if (w.isNotEmpty && w[0].toUpperCase() == w[0]) {
          return accentFix[0].toUpperCase() + accentFix.substring(1);
        }
        return accentFix;
      }

      return w;
    });
    return corrected.join(' ');
  }

  int _countHorizontalCrossbars(List<StrokeElement> strokes) {
    int count = 0;
    for (final s in strokes) {
      final b = s.boundingBox;
      if (b.height < 11.0 && b.width >= 4.0 && b.width < 28.0 && b.width > b.height) {
        count++;
      }
    }
    return count;
  }

  bool _hasTrailingHighDiacritic(List<StrokeElement> strokes) {
    if (strokes.length < 2) return false;
    double maxRight = double.negativeInfinity;
    double minTop = double.infinity;
    for (final s in strokes) {
      final b = s.boundingBox;
      if (b.right > maxRight) maxRight = b.right;
      if (b.top < minTop) minTop = b.top;
    }
    for (final s in strokes) {
      final b = s.boundingBox;
      final isSmall = b.height < 11.0 && b.width < 22.0;
      final isNearEnd = b.right >= maxRight - 24.0;
      final isHigh = b.top <= minTop + 14.0;
      if (isSmall && isNearEnd && isHigh) return true;
    }
    return false;
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show TextDirection;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;
import 'package:uuid/uuid.dart';

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/page_model.dart';
import 'handwriting_calibration.dart';
import 'ink_intent_classifier.dart';
import 'spatial_layout_analyzer.dart';

/// Servizio autonomo che coordina:
/// 1. Il buffer dei tratti scritti a mano in attesa di conversione.
/// 2. Il timer di inattività (che parte quando la penna si stacca dallo schermo
///    e si azzera se l'utente riprende a scrivere prima dello scadere).
/// 3. La classificazione Testo vs Figura ([InkIntentClassifier]).
/// 4. L'analisi delle righe, a-capo e dimensione del font ([SpatialLayoutAnalyzer]).
/// 5. Il riconoscimento offline con ML Kit Digital Ink e l'invio di
///    [ConvertInkToTextCommand] al [CommandManager].
class HandwritingOcrService extends ChangeNotifier {
  final CommandManager commandManager;
  final InkIntentClassifier intentClassifier;
  final SpatialLayoutAnalyzer layoutAnalyzer;
  final HandwritingCalibrator calibrator;
  final OcrCandidateReranker reranker;
  final Uuid _uuid = const Uuid();

  /// Profilo calligrafico calibrato (100% offline).
  HandwritingCalibrationProfile _calibrationProfile =
      const HandwritingCalibrationProfile();

  /// Se `true`, i tratti riconosciuti come testo vengono convertiti automaticamente
  /// allo scadere del timer. L'utente può disattivarlo con il Toggle in toolbar.
  bool _autoConvertEnabled = true;

  /// Se `true`, il testo scritto sulla stessa riga si accorpa con spazio singolo (' ')
  /// andando a capo a fine riga. Se `false`, l'utente può scrivere testo separato sulla stessa riga.
  bool _mergeSameLineEnabled = true;

  /// Modalità di calcolo della dimensione del font (Auto-Snap a stili vs Fissa da toolbar).
  TextSizeMode _textSizeMode = TextSizeMode.adaptiveSnap;

  /// Dimensione fissa del font (usata quando [_textSizeMode] == [TextSizeMode.fixedFromToolbar]).
  double _fixedFontSize = PageConstants.fontSizeBody;

  /// Tempo di attesa in millisecondi dopo che la penna non tocca più lo schermo.
  int _debounceDurationMs = PageConstants.defaultOcrDebounceMs;

  /// Lingua del modello ML Kit (default Italiano `it-IT`).
  String _languageTag = 'it-IT';

  /// Buffer dei tratti scritti nella sessione corrente su una specifica pagina.
  final List<StrokeElement> _pendingStrokes = [];
  int? _pendingPageIndex;

  Timer? _inactivityTimer;
  bool _isConverting = false;

  /// Memoria dell'ultima altezza e font usati in modalità Auto-Snap (isteresi ±35%).
  double? _lastAdaptiveReferenceHeight;
  double? _lastAdaptiveFontSize;

  /// Stato continuità scrittura multi-riga (pausa <= 1200ms = flusso continuo).
  DateTime? _lastStrokeCompletedAt;
  bool _pendingBatchIsContinuous = false;
  String? _lastFlowTailTextId;
  int? _lastFlowPageIndex;
  static const int _continuousWrapPauseMs = 1200;

  mlkit.DigitalInkRecognizer? _recognizer;
  final mlkit.DigitalInkRecognizerModelManager _modelManager =
      mlkit.DigitalInkRecognizerModelManager();

  HandwritingOcrService({
    required this.commandManager,
    this.intentClassifier = const InkIntentClassifier(),
    this.layoutAnalyzer = const SpatialLayoutAnalyzer(),
    this.calibrator = const HandwritingCalibrator(),
    this.reranker = const OcrCandidateReranker(),
  });

  // ---------------------------------------------------------------------------
  // Getters & Setters per la Toolbar e Calibrazione
  // ---------------------------------------------------------------------------

  bool get autoConvertEnabled => _autoConvertEnabled;
  bool get mergeSameLineEnabled => _mergeSameLineEnabled;
  TextSizeMode get textSizeMode => _textSizeMode;
  double get fixedFontSize => _fixedFontSize;
  int get debounceDurationMs => _debounceDurationMs;
  bool get isConverting => _isConverting;
  bool get hasPendingStrokes => _pendingStrokes.isNotEmpty;
  HandwritingCalibrationProfile get calibrationProfile => _calibrationProfile;

  /// Applica i campioni raccolti dalla procedura guidata in 3 frasi.
  Future<HandwritingCalibrationProfile> calibrateFromGuidedSamples(
    List<CalibrationSample> rawSamples,
  ) async {
    final enrichedSamples = <CalibrationSample>[];
    for (final sample in rawSamples) {
      final rawCandidates = await _recognizeRawCandidates(sample.strokes);
      enrichedSamples.add(
        CalibrationSample(
          targetText: sample.targetText,
          strokes: sample.strokes,
          rawRecognizedText:
              rawCandidates.isNotEmpty ? rawCandidates.first : '',
        ),
      );
    }
    _calibrationProfile = calibrator.buildProfile(enrichedSamples);
    notifyListeners();
    return _calibrationProfile;
  }

  /// Apprende automaticamente quando l'utente corregge una parola tradotta.
  void learnUserCorrection(String originalText, String correctedText) {
    final oldWords = originalText.trim().split(RegExp(r'\s+'));
    final newWords = correctedText.trim().split(RegExp(r'\s+'));
    if (oldWords.length == newWords.length) {
      var updated = _calibrationProfile;
      for (int i = 0; i < oldWords.length; i++) {
        updated = updated.learnCorrection(oldWords[i], newWords[i]);
      }
      _calibrationProfile = updated;
      notifyListeners();
    }
  }

  void setAutoConvertEnabled(bool enabled) {
    if (_autoConvertEnabled == enabled) return;
    _autoConvertEnabled = enabled;
    if (!enabled) {
      cancelPendingConversion();
    }
    notifyListeners();
  }

  void setMergeSameLineEnabled(bool enabled) {
    if (_mergeSameLineEnabled == enabled) return;
    _mergeSameLineEnabled = enabled;
    notifyListeners();
  }

  void setTextSizeMode(TextSizeMode mode) {
    if (_textSizeMode == mode) return;
    _textSizeMode = mode;
    notifyListeners();
  }

  void setFixedFontSize(double size) {
    if (_fixedFontSize == size) return;
    _fixedFontSize = size;
    notifyListeners();
  }

  void setDebounceDurationMs(int durationMs) {
    _debounceDurationMs = durationMs.clamp(
      PageConstants.minOcrDebounceMs,
      PageConstants.maxOcrDebounceMs,
    );
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Gestione Eventi Penna & Timer di Inattività
  // ---------------------------------------------------------------------------

  /// Chiamato non appena la penna tocca lo schermo:
  /// ferma subito il conto alla rovescia finché l'utente sta scrivendo.
  void onPenDown(int pageIndex) {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    final isContinuous = _lastStrokeCompletedAt != null &&
        DateTime.now().difference(_lastStrokeCompletedAt!).inMilliseconds <=
            _continuousWrapPauseMs;

    if (_pendingStrokes.isEmpty) {
      _pendingBatchIsContinuous = isContinuous;
      if (!isContinuous) {
        _lastFlowTailTextId = null;
      }
    }

    // Se l'utente inizia a scrivere su una pagina diversa, processa subito
    // i tratti rimasti in sospeso sulla pagina precedente.
    if (_pendingPageIndex != null &&
        _pendingPageIndex != pageIndex &&
        _pendingStrokes.isNotEmpty) {
      unawaited(flushAndConvertNow());
    }
  }

  /// Chiamato quando la penna si solleva dallo schermo e termina un tratto.
  /// Aggiunge il tratto al buffer e avvia il timer di inattività.
  void onStrokeCompleted(StrokeElement stroke) {
    if (!_autoConvertEnabled || stroke.isHighlighter) return;

    _lastStrokeCompletedAt = DateTime.now();
    _pendingPageIndex = stroke.pageIndex;
    _pendingStrokes.add(stroke);
    notifyListeners();

    _restartInactivityTimer();
  }

  void _restartInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(
      Duration(milliseconds: _debounceDurationMs),
      () => unawaited(flushAndConvertNow()),
    );
  }

  /// Svuota il buffer senza convertire (es. se l'utente preme Undo o disattiva l'auto-conversione).
  void cancelPendingConversion() {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _pendingStrokes.clear();
    _pendingPageIndex = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pipeline di Conversione (Classificazione -> Layout -> ML Kit -> Command)
  // ---------------------------------------------------------------------------

  Future<void> convertSelectedStrokes(
    int pageIndex,
    List<StrokeElement> selectedStrokes,
  ) async {
    if (selectedStrokes.isEmpty) return;
    _pendingStrokes.clear();
    _pendingStrokes.addAll(selectedStrokes);
    _pendingPageIndex = pageIndex;
    _pendingBatchIsContinuous = false;
    await flushAndConvertNow();
  }

  Future<void> flushAndConvertNow() async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    if (_pendingStrokes.isEmpty || _pendingPageIndex == null) return;

    final strokesToProcess = List<StrokeElement>.from(_pendingStrokes);
    final pageIndex = _pendingPageIndex!;
    final batchIsContinuous = _pendingBatchIsContinuous;
    _pendingStrokes.clear();
    _pendingPageIndex = null;
    _pendingBatchIsContinuous = false;

    // Verifica che i tratti esistano ancora sulla pagina (l'utente potrebbe averli
    // appena cancellati con Undo o Gomma).
    final currentPageElements =
        commandManager.state.pageAt(pageIndex).elements.map((e) => e.id).toSet();
    final activeStrokes = strokesToProcess
        .where((s) => currentPageElements.contains(s.id))
        .toList();

    if (activeStrokes.isEmpty) {
      notifyListeners();
      return;
    }

    // FASE 1: È testo o una figura geometrica/schema?
    final intent = intentClassifier.classify(activeStrokes);
    if (intent == InkIntent.drawingOrDiagram) {
      // È una figura: non convertiamo in testo, i tratti restano sul foglio!
      notifyListeners();
      return;
    }

    // FASE 2 & 3: Raggruppa per righe e converte OGNI RIGA nella sua esatta posizione X/Y
    final initialLayout = layoutAnalyzer.analyze(
      strokes: activeStrokes,
      sizeMode: _textSizeMode,
      fixedToolbarFontSize: _fixedFontSize,
    );

    if (initialLayout.lineClusters.isEmpty) {
      notifyListeners();
      return;
    }

    _isConverting = true;
    notifyListeners();

    try {
      for (int lineIdx = 0;
          lineIdx < initialLayout.lineClusters.length;
          lineIdx++) {
        final lineCluster = initialLayout.lineClusters[lineIdx];
        final pageModel = commandManager.state.pageAt(pageIndex);
        final existingTexts =
            pageModel.elements.whereType<TextElement>().toList();

        final lineLayout = layoutAnalyzer.analyze(
          strokes: lineCluster.strokes,
          sizeMode: _textSizeMode,
          fixedToolbarFontSize: _fixedFontSize,
          pageBackground: pageModel.background,
          existingPageTexts: existingTexts,
          previousReferenceHeight: _lastAdaptiveReferenceHeight,
          previousResolvedFontSize: _lastAdaptiveFontSize,
          calibratedBaselineHeight:
              _calibrationProfile.baselineHandwritingHeight,
        );

        if (_textSizeMode == TextSizeMode.adaptiveSnap &&
            _lastAdaptiveFontSize != lineLayout.resolvedFontSize) {
          _lastAdaptiveReferenceHeight = lineLayout.estimatedHandwritingHeight;
          _lastAdaptiveFontSize = lineLayout.resolvedFontSize;
        }

        // Controlla se siamo in flusso continuo da una riga superiore (pausa <= 1.2s tra fine riga N e inizio riga N+1)
        TextElement? continuousTail;
        if (_mergeSameLineEnabled && lineIdx > 0) {
          final prevLine = initialLayout.lineClusters[lineIdx - 1];
          final prevEndMs = prevLine.strokes
              .where((s) => s.points.isNotEmpty)
              .map((s) => s.points.last.timestampMs)
              .fold<int>(0, (a, b) => a > b ? a : b);
          final currStartMs = lineCluster.strokes
              .where((s) => s.points.isNotEmpty)
              .map((s) => s.points.first.timestampMs)
              .fold<int>(0x7fffffff, (a, b) => a < b ? a : b);
          final linePauseMs = (currStartMs - prevEndMs).abs();
          final wasContinuous = prevEndMs > 0 &&
              currStartMs < 0x7fffffff &&
              linePauseMs <= _continuousWrapPauseMs;

          if (wasContinuous &&
              _lastFlowPageIndex == pageIndex &&
              _lastFlowTailTextId != null) {
            for (final el in existingTexts) {
              if (el.id == _lastFlowTailTextId &&
                  lineLayout.anchorY >= el.y - 14.0) {
                continuousTail = el;
                break;
              }
            }
          }
        }

        // Se "Accorpa Riga" è attivo, riunisce la riga con spazi singoli e va a capo se supera il margine;
        // altrimenti mantiene gruppi separati dove sono stati scritti (es. liste/colonne).
        final positionedGroups = _mergeSameLineEnabled
            ? [lineCluster]
            : _splitLineByWideHorizontalGaps(lineCluster);

        for (final groupCluster in positionedGroups) {
          final groupX = groupCluster.boundingBox.left;
          String runningContext = continuousTail?.text ??
              _findSameLineLeftText(
                existingTexts: existingTexts,
                lineY: lineLayout.anchorY,
                newMinX: groupX,
                fontSize: lineLayout.resolvedFontSize,
              )?.text ??
              '';

          // Suddivide per cambi di colore (es. parola nera + parola rossa) così i colori
          // originali restano sempre fedeli anche dopo l'accorpamento sulla stessa riga!
          final colorRuns = _splitClusterByColorRuns(groupCluster);
          final newColoredWords = <_ColoredWord>[];

          for (final runCluster in colorRuns) {
            final runColor = runCluster.strokes.first.colorValue;
            final runText = (await _recognizeLineStrokes(
              runCluster,
              preContext: runningContext.isNotEmpty ? runningContext : null,
            ))
                .replaceAll(RegExp(r'[ \t]+'), ' ')
                .trim();
            if (runText.isEmpty) continue;
            runningContext = '$runningContext $runText'.trim();
            for (final w in runText.split(RegExp(r'\s+'))) {
              if (w.isNotEmpty) {
                newColoredWords.add(_ColoredWord(text: w, colorValue: runColor));
              }
            }
          }

          if (newColoredWords.isEmpty) continue;

          if (_mergeSameLineEnabled) {
            final anchorEl = continuousTail ??
                _findSameLineLeftText(
                  existingTexts: existingTexts,
                  lineY: lineLayout.anchorY,
                  newMinX: groupX,
                  fontSize: lineLayout.resolvedFontSize,
                );
            final startX = anchorEl?.x ?? groupX;
            final baseLineY = anchorEl?.y ?? lineLayout.anchorY;
            final maxLineWidth =
                math.max(120.0, PageConstants.a4Width - 28.0 - startX);
            final lineStep = pageModel.background == PageBackgroundTemplate.ruled
                ? 24.0
                : lineLayout.resolvedFontSize * 1.32;

            final combinedColoredWords = <_ColoredWord>[
              if (anchorEl != null) ..._extractColoredWordsFromElement(anchorEl),
              ...newColoredWords,
            ];

            final wrappedLines = _wrapColoredWordsToWidth(
              words: combinedColoredWords,
              maxWidth: maxLineWidth,
              fontSize: lineLayout.resolvedFontSize,
            );
            if (wrappedLines.isEmpty) continue;

            if (anchorEl != null) {
              final firstSpans = _buildSpansFromColoredWords(wrappedLines.first);
              final updatedTarget = anchorEl.copyWith(
                text: wrappedLines.first.map((w) => w.text).join(' '),
                spans: firstSpans,
              );
              final extraLines = <TextElement>[];
              TextElement tail = updatedTarget;
              for (int wi = 1; wi < wrappedLines.length; wi++) {
                final lineSpans = _buildSpansFromColoredWords(wrappedLines[wi]);
                final overflowEl = TextElement(
                  id: _uuid.v4(),
                  pageIndex: pageIndex,
                  colorValue: lineSpans.first.colorValue,
                  x: startX,
                  y: baseLineY + wi * lineStep,
                  text: wrappedLines[wi].map((w) => w.text).join(' '),
                  fontSize: lineLayout.resolvedFontSize,
                  maxWidth: maxLineWidth,
                  spans: lineSpans,
                );
                extraLines.add(overflowEl);
                tail = overflowEl;
              }
              _lastFlowTailTextId = tail.id;
              _lastFlowPageIndex = pageIndex;
              continuousTail = tail;

              commandManager.executeCommand(
                MergeInkIntoTextCommand(
                  pageIndex: pageIndex,
                  originalStrokes: groupCluster.strokes,
                  previousTargetText: anchorEl,
                  updatedTargetText: updatedTarget,
                  additionalWrappedTexts: extraLines,
                ),
              );
            } else {
              final created = <TextElement>[];
              for (int wi = 0; wi < wrappedLines.length; wi++) {
                final lineSpans = _buildSpansFromColoredWords(wrappedLines[wi]);
                created.add(
                  TextElement(
                    id: _uuid.v4(),
                    pageIndex: pageIndex,
                    colorValue: lineSpans.first.colorValue,
                    x: startX,
                    y: baseLineY + wi * lineStep,
                    text: wrappedLines[wi].map((w) => w.text).join(' '),
                    fontSize: lineLayout.resolvedFontSize,
                    maxWidth: maxLineWidth,
                    spans: lineSpans,
                    sourceStrokeIds: wi == 0
                        ? groupCluster.strokes.map((s) => s.id).toList()
                        : const [],
                  ),
                );
              }
              if (created.isNotEmpty) {
                _lastFlowTailTextId = created.last.id;
                _lastFlowPageIndex = pageIndex;
                continuousTail = created.last;
              }
              commandManager.executeCommand(
                MergeInkIntoTextCommand(
                  pageIndex: pageIndex,
                  originalStrokes: groupCluster.strokes,
                  additionalWrappedTexts: created,
                ),
              );
            }
          } else {
            final lineSpans = _buildSpansFromColoredWords(newColoredWords);
            final newTextElement = TextElement(
              id: _uuid.v4(),
              pageIndex: pageIndex,
              colorValue: lineSpans.first.colorValue,
              x: groupX,
              y: lineLayout.anchorY,
              text: newColoredWords.map((w) => w.text).join(' '),
              fontSize: lineLayout.resolvedFontSize,
              maxWidth: PageConstants.a4Width - groupX - 24.0,
              spans: lineSpans,
              sourceStrokeIds: groupCluster.strokes.map((s) => s.id).toList(),
            );

            commandManager.executeCommand(
              ConvertInkToTextCommand(
                pageIndex: pageIndex,
                originalStrokes: groupCluster.strokes,
                convertedTextElement: newTextElement,
              ),
            );
          }
        }
      }
    } finally {
      _isConverting = false;
      notifyListeners();
    }
  }

  TextElement? _findSameLineLeftText({
    required List<TextElement> existingTexts,
    required double lineY,
    required double newMinX,
    required double fontSize,
  }) {
    final tol = math.min(11.0, math.max(6.0, fontSize * 0.55));
    for (final el in existingTexts) {
      if ((el.y - lineY).abs() <= tol && newMinX >= el.x) {
        return el;
      }
    }
    return null;
  }

  List<List<_ColoredWord>> _wrapColoredWordsToWidth({
    required List<_ColoredWord> words,
    required double maxWidth,
    required double fontSize,
  }) {
    final lines = <List<_ColoredWord>>[];
    List<_ColoredWord> current = [];
    for (final w in words) {
      final candText = current.isEmpty
          ? w.text
          : '${current.map((e) => e.text).join(' ')} ${w.text}';
      final painter = TextPainter(
        text: TextSpan(
          text: candText,
          style: TextStyle(fontSize: fontSize, fontFamily: 'Roboto'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (current.isNotEmpty && painter.width > maxWidth) {
        lines.add(current);
        current = [w];
      } else {
        current.add(w);
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  List<_ColoredWord> _extractColoredWordsFromElement(TextElement el) {
    if (el.spans.isEmpty) {
      return el.text
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .map((w) => _ColoredWord(text: w, colorValue: el.colorValue))
          .toList();
    }
    final result = <_ColoredWord>[];
    for (final sp in el.spans) {
      for (final w in sp.text.trim().split(RegExp(r'\s+'))) {
        if (w.isNotEmpty) {
          result.add(_ColoredWord(text: w, colorValue: sp.colorValue));
        }
      }
    }
    return result;
  }

  List<TextColorSpan> _buildSpansFromColoredWords(List<_ColoredWord> words) {
    if (words.isEmpty) return const [];
    final spans = <TextColorSpan>[];
    int curColor = words.first.colorValue;
    final buf = StringBuffer(words.first.text);

    for (int i = 1; i < words.length; i++) {
      final w = words[i];
      if (w.colorValue == curColor) {
        buf.write(' ${w.text}');
      } else {
        // Mantiene lo spazio di separazione prima del cambio colore
        buf.write(' ');
        spans.add(TextColorSpan(text: buf.toString(), colorValue: curColor));
        curColor = w.colorValue;
        buf
          ..clear()
          ..write(w.text);
      }
    }
    spans.add(TextColorSpan(text: buf.toString(), colorValue: curColor));
    return spans;
  }

  List<HandwritingLineCluster> _splitClusterByColorRuns(
    HandwritingLineCluster cluster,
  ) {
    final sorted = List<StrokeElement>.from(cluster.strokes)
      ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
    if (sorted.isEmpty) return const [];

    final runs = <List<StrokeElement>>[
      [sorted.first],
    ];
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i].colorValue == runs.last.first.colorValue) {
        runs.last.add(sorted[i]);
      } else {
        runs.add([sorted[i]]);
      }
    }

    return runs.map((strokes) {
      var rect = strokes.first.boundingBox;
      for (int i = 1; i < strokes.length; i++) {
        rect = rect.expandToInclude(strokes[i].boundingBox);
      }
      return HandwritingLineCluster(strokes: strokes, boundingBox: rect);
    }).toList();
  }

  /// Divide una riga in più blocchi se tra una parola e la successiva c'è uno spazio
  /// più ampio di un singolo spazio normale (> 24 pt), mantenendo la posizione X esatta.
  List<HandwritingLineCluster> _splitLineByWideHorizontalGaps(
    HandwritingLineCluster lineCluster,
  ) {
    final sorted = List<StrokeElement>.from(lineCluster.strokes)
      ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

    if (sorted.isEmpty) return [];

    final groups = <List<StrokeElement>>[
      [sorted.first],
    ];
    double currentMaxX = sorted.first.boundingBox.right;

    for (int i = 1; i < sorted.length; i++) {
      final stroke = sorted[i];
      if (stroke.boundingBox.left - currentMaxX > 24.0) {
        groups.add([stroke]);
        currentMaxX = stroke.boundingBox.right;
      } else {
        groups.last.add(stroke);
        if (stroke.boundingBox.right > currentMaxX) {
          currentMaxX = stroke.boundingBox.right;
        }
      }
    }

    return groups.map((strokes) {
      var rect = strokes.first.boundingBox;
      for (int i = 1; i < strokes.length; i++) {
        rect = rect.expandToInclude(strokes[i].boundingBox);
      }
      return HandwritingLineCluster(strokes: strokes, boundingBox: rect);
    }).toList();
  }

  /// Riconosce una singola riga di tratti tramite Google ML Kit Digital Ink,
  /// applicando correzione leggera dell'inclinazione, `preContext` e Smart Re-Ranking
  /// dei Top-10 candidati (100% offline e leggerissimo).
  Future<String> _recognizeLineStrokes(
    HandwritingLineCluster lineCluster, {
    String? preContext,
  }) async {
    final rawCandidates = await _recognizeRawCandidates(
      lineCluster.strokes,
      preContext: preContext,
      writingAreaWidth: lineCluster.boundingBox.width,
      writingAreaHeight: lineCluster.boundingBox.height,
    );

    if (rawCandidates.isNotEmpty) {
      return reranker.selectBestCandidate(
        candidates: rawCandidates,
        strokes: lineCluster.strokes,
        profile: _calibrationProfile,
      );
    }

    return _fallbackHeuristicText(lineCluster);
  }

  /// Restituisce fino a 10 candidati grezzi da ML Kit Digital Ink (offline).
  Future<List<String>> _recognizeRawCandidates(
    List<StrokeElement> strokes, {
    String? preContext,
    double? writingAreaWidth,
    double? writingAreaHeight,
  }) async {
    if (strokes.isEmpty) return const [];
    try {
      final isIosOrAndroid = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);

      if (isIosOrAndroid) {
        _recognizer ??= mlkit.DigitalInkRecognizer(languageCode: _languageTag);
        final isDownloaded = await _modelManager.isModelDownloaded(_languageTag);
        if (!isDownloaded) {
          await _modelManager.downloadModel(_languageTag);
        }

        // Eventuale raddrizzamento leggero se l'utente scrive molto inclinato
        final slantCorrection = _calibrationProfile.slantShear.abs() > 0.14
            ? _calibrationProfile.slantShear * 0.5
            : 0.0;
        final refY = strokes.first.boundingBox.bottom;

        final ink = mlkit.Ink();
        for (final stroke in strokes) {
          final mlStroke = mlkit.Stroke();
          for (final pt in stroke.points) {
            final adjustedX = slantCorrection != 0.0
                ? pt.x + slantCorrection * (pt.y - refY)
                : pt.x;
            mlStroke.points.add(
              mlkit.StrokePoint(
                x: adjustedX,
                y: pt.y,
                t: pt.timestampMs,
              ),
            );
          }
          ink.strokes.add(mlStroke);
        }

        final trimmedPreContext = (preContext ?? '').trim();
        final safePreContext = trimmedPreContext.length > 20
            ? trimmedPreContext.substring(trimmedPreContext.length - 20)
            : trimmedPreContext;

        final context = mlkit.DigitalInkRecognitionContext(
          preContext: safePreContext.isNotEmpty ? safePreContext : null,
          writingArea: mlkit.WritingArea(
            width: writingAreaWidth ?? 520.0,
            height: writingAreaHeight ?? 120.0,
          ),
        );

        final candidates =
            await _recognizer!.recognize(ink, context: context);
        if (candidates.isNotEmpty) {
          return candidates.take(10).map((c) => c.text).toList();
        }
      }
    } catch (_) {
      // Fallback silenzioso in ambiente di test/desktop senza plugin nativo
    }
    return const [];
  }

  /// Fallback usato durante i test unitari o su ambienti desktop dove ML Kit
  /// nativo iOS/Android non è caricato.
  String _fallbackHeuristicText(HandwritingLineCluster lineCluster) {
    final wordCountEstimate =
        (lineCluster.boundingBox.width / 65.0).ceil().clamp(1, 12);
    return List.generate(wordCountEstimate, (i) => 'testo').join(' ');
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _recognizer?.close();
    super.dispose();
  }
}

class _ColoredWord {
  final String text;
  final int colorValue;
  const _ColoredWord({required this.text, required this.colorValue});
}

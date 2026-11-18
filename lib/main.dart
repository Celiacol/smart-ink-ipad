import 'package:flutter/material.dart';

import 'core/commands/command_manager.dart';
import 'core/commands/document_command.dart';
import 'core/constants/page_constants.dart';
import 'core/models/canvas_element.dart';
import 'core/models/page_model.dart';
import 'features/canvas_view/paginated_notebook_view.dart';
import 'features/handwriting_ocr/handwriting_calibration.dart';
import 'features/handwriting_ocr/handwriting_ocr_service.dart';
import 'features/pdf_export/pdf_export_service.dart';
import 'features/toolbar/notebook_toolbar.dart';
import 'features/tools/canvas_tool_handler.dart';
import 'features/tools/eraser_tool_handler.dart';
import 'features/tools/lasso_convert_tool_handler.dart';
import 'features/tools/lasso_move_tool_handler.dart';
import 'features/tools/lasso_reflow_tool_handler.dart';
import 'features/tools/pen_tool_handler.dart';
import 'features/tools/selection_tool_handler.dart';
import 'features/tools/shape_tool_handler.dart';
import 'features/tools/vertical_space_tool_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartInkNotebookApp());
}

class SmartInkNotebookApp extends StatelessWidget {
  const SmartInkNotebookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Ink Notebook (iPad & Android)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      ),
      home: const NotebookWorkspaceScreen(),
    );
  }
}

/// Schermata principale che collega il [CommandManager] ai plugin degli strumenti,
/// al servizio di conversione [HandwritingOcrService], alla vista A4 paginata
/// e all'esportatore PDF.
class NotebookWorkspaceScreen extends StatefulWidget {
  const NotebookWorkspaceScreen({super.key});

  @override
  State<NotebookWorkspaceScreen> createState() =>
      _NotebookWorkspaceScreenState();
}

class _NotebookWorkspaceScreenState extends State<NotebookWorkspaceScreen> {
  late final CommandManager _commandManager;
  late final HandwritingOcrService _ocrService;
  final PdfExportService _pdfExportService = const PdfExportService();
  final TransformationController _zoomController = TransformationController();

  late final PenToolHandler _penTool;
  late final PenToolHandler _highlighterTool;
  late final EraserToolHandler _eraserTool;
  late final ShapeToolHandler _shapeTool;
  late final SelectionToolHandler _selectionTool;
  late final LassoConvertToolHandler _lassoConvertTool;
  late final LassoReflowToolHandler _lassoReflowTool;
  late final VerticalSpaceToolHandler _verticalSpaceTool;
  late final LassoMoveToolHandler _lassoMoveTool;

  ToolType _activeToolType = ToolType.pen;
  int _selectedColorValue = 0xFF1E293B;
  ShapeKind _selectedShapeKind = ShapeKind.rectangle;
  // Di default su iPad usiamo "Solo Apple Pencil" (false) così il palmo non scrive
  // e 1 dito scorre / 2 dita fanno Pinch-to-Zoom!
  bool _allowFingerDrawing = false;
  bool _verticalSpaceMovesBelow = true;

  @override
  void initState() {
    super.initState();
    _commandManager = CommandManager();
    _ocrService = HandwritingOcrService(commandManager: _commandManager);

    _penTool = PenToolHandler(
      ocrService: _ocrService,
      toolType: ToolType.pen,
      colorValue: _selectedColorValue,
    );
    _highlighterTool = PenToolHandler(
      ocrService: _ocrService,
      toolType: ToolType.highlighter,
      colorValue: 0xFFD97706,
    );
    _eraserTool = EraserToolHandler();
    _shapeTool = ShapeToolHandler(
      selectedShapeKind: _selectedShapeKind,
      colorValue: _selectedColorValue,
    );
    _selectionTool = SelectionToolHandler(
      onTextElementSelected: _showEditConvertedTextDialog,
    );
    _lassoConvertTool = LassoConvertToolHandler(ocrService: _ocrService);
    _lassoReflowTool = LassoReflowToolHandler();
    _verticalSpaceTool = VerticalSpaceToolHandler();
    _lassoMoveTool = LassoMoveToolHandler();
  }

  @override
  void dispose() {
    _zoomController.dispose();
    _ocrService.dispose();
    _commandManager.dispose();
    super.dispose();
  }

  void _stepZoom(double factor) {
    final current = _zoomController.value.clone();
    final curScale = current.getMaxScaleOnAxis();
    final nextScale = (curScale * factor).clamp(0.5, 3.0);
    final ratio = nextScale / curScale;
    current.scale(ratio);
    _zoomController.value = current;
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
  }

  CanvasToolHandler get _currentToolHandler {
    switch (_activeToolType) {
      case ToolType.pen:
        return _penTool;
      case ToolType.highlighter:
        return _highlighterTool;
      case ToolType.eraser:
        return _eraserTool;
      case ToolType.shape:
        return _shapeTool;
      case ToolType.selection:
        return _selectionTool;
      case ToolType.lassoConvert:
        return _lassoConvertTool;
      case ToolType.lassoReflow:
        return _lassoReflowTool;
      case ToolType.verticalSpace:
        return _verticalSpaceTool;
      case ToolType.lassoMove:
        return _lassoMoveTool;
    }
  }

  void _handleToolSelected(ToolType type) {
    setState(() {
      _activeToolType = type;
    });
  }

  void _handleColorSelected(int colorVal) {
    setState(() {
      _selectedColorValue = colorVal;
      _penTool.colorValue = colorVal;
      _shapeTool.colorValue = colorVal;
    });
  }

  void _handleShapeKindSelected(ShapeKind kind) {
    setState(() {
      _selectedShapeKind = kind;
      _shapeTool.selectedShapeKind = kind;
    });
  }

  void _handleBackgroundChanged(PageBackgroundTemplate newBg) {
    final lastPage = _commandManager.state.pages.last;
    _commandManager.executeCommand(
      ChangePageBackgroundCommand(
        pageIndex: lastPage.pageIndex,
        previousBackground: lastPage.background,
        newBackground: newBg,
      ),
    );
  }

  /// Permette di modificare con tastiera o ridimensionare qualsiasi blocco di testo
  /// convertito dalla scrittura a mano.
  Future<void> _showEditConvertedTextDialog(TextElement element) async {
    final textController = TextEditingController(text: element.text);
    double selectedSize = element.fontSize;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Modifica Testo Convertito'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: textController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Testo (supporta più righe / a-capo)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Dimensione Font: '),
                      const SizedBox(width: 8),
                      DropdownButton<double>(
                        value: PageConstants.standardFontSizes
                                .contains(selectedSize)
                            ? selectedSize
                            : PageConstants.fontSizeBody,
                        items: PageConstants.standardFontSizes
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text('${s.toInt()} pt'),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedSize = val);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                FilledButton(
                  onPressed: () {
                    // Apprende l'eventuale correzione manuale fatta dall'utente per migliorare i futuri riconoscimenti
                    if (textController.text.trim() != element.text.trim()) {
                      _ocrService.learnUserCorrection(
                        element.text,
                        textController.text,
                      );
                    }
                    final updated = element.copyWith(
                      text: textController.text,
                      fontSize: selectedSize,
                    );
                    _commandManager.executeCommand(
                      UpdateElementCommand(
                        previousElement: element,
                        updatedElement: updated,
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Salva Modifiche'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _commandManager,
          builder: (context, _) {
            final currentBg = _commandManager.state.pages.last.background;
            return Column(
              children: [
                NotebookToolbar(
                  activeToolType: _activeToolType,
                  onToolSelected: _handleToolSelected,
                  selectedColorValue: _selectedColorValue,
                  onColorSelected: _handleColorSelected,
                  selectedShapeKind: _selectedShapeKind,
                  onShapeKindSelected: _handleShapeKindSelected,
                  ocrService: _ocrService,
                  canUndo: _commandManager.canUndo,
                  canRedo: _commandManager.canRedo,
                  onUndo: () {
                    _ocrService.cancelPendingConversion();
                    _commandManager.undo();
                  },
                  onRedo: _commandManager.redo,
                  currentBackground: currentBg,
                  onBackgroundChanged: _handleBackgroundChanged,
                  allowFingerDrawing: _allowFingerDrawing,
                  onAllowFingerDrawingChanged: (val) {
                    setState(() => _allowFingerDrawing = val);
                  },
                  verticalSpaceMovesBelow: _verticalSpaceMovesBelow,
                  onVerticalSpaceDirectionChanged: (movesBelow) {
                    setState(() {
                      _verticalSpaceMovesBelow = movesBelow;
                      _verticalSpaceTool.moveBelowPoint = movesBelow;
                    });
                  },
                  zoomScale: _zoomController.value.getMaxScaleOnAxis(),
                  onZoomIn: () => _stepZoom(1.15),
                  onZoomOut: () => _stepZoom(0.85),
                  onZoomReset: _resetZoom,
                  onCalibrateHandwriting: _showCalibrationDialog,
                  onExportPdf: () => _pdfExportService.printOrShareDocument(
                    _commandManager.state,
                  ),
                ),
                Expanded(
                  child: PaginatedNotebookView(
                    commandManager: _commandManager,
                    activeTool: _currentToolHandler,
                    allowFingerDrawing: _allowFingerDrawing,
                    zoomController: _zoomController,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Procedura guidata in 3 frasi per calibrare l'app sulla calligrafia dell'utente (100% offline).
  Future<void> _showCalibrationDialog() async {
    int phraseIdx = 0;
    final List<CalibrationSample> collectedSamples = [];
    final List<StrokeElement> currentStrokes = [];
    List<InkPoint> activePts = [];
    int strokeSeq = 0;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final phrase = defaultCalibrationPhrases[phraseIdx];
            return AlertDialog(
              title: Text(phrase.title),
              content: SizedBox(
                width: 540,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        phrase.targetText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      phrase.purposeHint,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Listener(
                        onPointerDown: (e) {
                          activePts = [
                            InkPoint(
                              x: e.localPosition.dx,
                              y: e.localPosition.dy,
                              timestampMs: e.timeStamp.inMilliseconds,
                            ),
                          ];
                          setDialogState(() {});
                        },
                        onPointerMove: (e) {
                          activePts.add(
                            InkPoint(
                              x: e.localPosition.dx,
                              y: e.localPosition.dy,
                              timestampMs: e.timeStamp.inMilliseconds,
                            ),
                          );
                          setDialogState(() {});
                        },
                        onPointerUp: (_) {
                          if (activePts.length >= 2) {
                            currentStrokes.add(
                              StrokeElement(
                                id: 'cal_${strokeSeq++}',
                                pageIndex: 0,
                                colorValue: 0xFF1E293B,
                                points: List<InkPoint>.from(activePts),
                              ),
                            );
                          }
                          activePts = [];
                          setDialogState(() {});
                        },
                        child: CustomPaint(
                          painter: _CalibrationPadPainter(
                            strokes: currentStrokes,
                            activePoints: activePts,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      currentStrokes.clear();
                      activePts = [];
                    });
                  },
                  child: const Text('Pulisci'),
                ),
                FilledButton(
                  onPressed: currentStrokes.isEmpty
                      ? null
                      : () async {
                          collectedSamples.add(
                            CalibrationSample(
                              targetText: phrase.targetText,
                              strokes: List<StrokeElement>.from(currentStrokes),
                            ),
                          );
                          if (phraseIdx < defaultCalibrationPhrases.length - 1) {
                            setDialogState(() {
                              phraseIdx++;
                              currentStrokes.clear();
                              activePts = [];
                            });
                          } else {
                            await _ocrService
                                .calibrateFromGuidedSamples(collectedSamples);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                  child: Text(
                    phraseIdx < defaultCalibrationPhrases.length - 1
                        ? 'Avanti (${phraseIdx + 1}/3)'
                        : 'Completa Calibrazione',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CalibrationPadPainter extends CustomPainter {
  final List<StrokeElement> strokes;
  final List<InkPoint> activePoints;

  _CalibrationPadPainter({
    required this.strokes,
    required this.activePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height * 0.68),
      Offset(size.width, size.height * 0.68),
      guidePaint,
    );

    final inkPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    void drawPts(List<InkPoint> pts) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(pts.first.x, pts.first.y);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].x, pts[i].y);
      }
      canvas.drawPath(path, inkPaint);
    }

    for (final s in strokes) {
      drawPts(s.points);
    }
    drawPts(activePoints);
  }

  @override
  bool shouldRepaint(covariant _CalibrationPadPainter oldDelegate) => true;
}

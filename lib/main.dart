import 'package:flutter/material.dart';

import 'core/commands/command_manager.dart';
import 'core/commands/document_command.dart';
import 'core/constants/page_constants.dart';
import 'core/models/canvas_element.dart';
import 'core/models/page_model.dart';
import 'features/canvas_view/paginated_notebook_view.dart';
import 'features/handwriting_ocr/handwriting_ocr_service.dart';
import 'features/pdf_export/pdf_export_service.dart';
import 'features/toolbar/notebook_toolbar.dart';
import 'features/tools/canvas_tool_handler.dart';
import 'features/tools/eraser_tool_handler.dart';
import 'features/tools/pen_tool_handler.dart';
import 'features/tools/selection_tool_handler.dart';
import 'features/tools/shape_tool_handler.dart';

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

  late final PenToolHandler _penTool;
  late final PenToolHandler _highlighterTool;
  late final EraserToolHandler _eraserTool;
  late final ShapeToolHandler _shapeTool;
  late final SelectionToolHandler _selectionTool;

  ToolType _activeToolType = ToolType.pen;
  int _selectedColorValue = 0xFF1E293B;
  ShapeKind _selectedShapeKind = ShapeKind.rectangle;
  // Di default su iPad usiamo "Solo Apple Pencil" (false) così il palmo non scrive
  // e 1 dito scorre / 2 dita fanno Pinch-to-Zoom!
  bool _allowFingerDrawing = false;

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
  }

  @override
  void dispose() {
    _ocrService.dispose();
    _commandManager.dispose();
    super.dispose();
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
                  onExportPdf: () => _pdfExportService.printOrShareDocument(
                    _commandManager.state,
                  ),
                ),
                Expanded(
                  child: PaginatedNotebookView(
                    commandManager: _commandManager,
                    activeTool: _currentToolHandler,
                    allowFingerDrawing: _allowFingerDrawing,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

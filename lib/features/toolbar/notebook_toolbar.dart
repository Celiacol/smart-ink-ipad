import 'package:flutter/material.dart';

import '../../core/constants/page_constants.dart';
import '../../core/models/canvas_element.dart';
import '../../core/models/page_model.dart';
import '../handwriting_ocr/handwriting_ocr_service.dart';
import '../tools/canvas_tool_handler.dart';

/// Barra degli strumenti modulare per iPad e Tablet Android.
///
/// Include:
/// - Selezione Strumento (Penna, Evidenziatore, Gomma, Forme, Selezione)
/// - Scelta Colore e Spessore
/// - Toggle **Auto-Testo ON/OFF**
/// - Selettore **Modalità Dimensione Testo** (*Auto-Snap a Stili* vs *Fissa da Toolbar*)
/// - Pulsanti **Undo / Redo**, **Sfondo Pagina** ed **Esporta PDF / Stampa**
class NotebookToolbar extends StatelessWidget {
  final ToolType activeToolType;
  final ValueChanged<ToolType> onToolSelected;

  final int selectedColorValue;
  final ValueChanged<int> onColorSelected;

  final ShapeKind selectedShapeKind;
  final ValueChanged<ShapeKind> onShapeKindSelected;

  final HandwritingOcrService ocrService;

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  final PageBackgroundTemplate currentBackground;
  final ValueChanged<PageBackgroundTemplate> onBackgroundChanged;

  final bool allowFingerDrawing;
  final ValueChanged<bool> onAllowFingerDrawingChanged;

  final bool verticalSpaceMovesBelow;
  final ValueChanged<bool> onVerticalSpaceDirectionChanged;

  final double zoomScale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomReset;

  final VoidCallback onCalibrateHandwriting;
  final VoidCallback onExportPdf;

  static const List<int> paletteColors = [
    0xFF1E293B, // Nero / Antracite
    0xFF2563EB, // Blu Penna
    0xFFDC2626, // Rosso
    0xFF16A34A, // Verde
    0xFF9333EA, // Viola
    0xFFD97706, // Ambra / Evidenziatore
  ];

  const NotebookToolbar({
    super.key,
    required this.activeToolType,
    required this.onToolSelected,
    required this.selectedColorValue,
    required this.onColorSelected,
    required this.selectedShapeKind,
    required this.onShapeKindSelected,
    required this.ocrService,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.currentBackground,
    required this.onBackgroundChanged,
    required this.allowFingerDrawing,
    required this.onAllowFingerDrawingChanged,
    required this.verticalSpaceMovesBelow,
    required this.onVerticalSpaceDirectionChanged,
    required this.zoomScale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onZoomReset,
    required this.onCalibrateHandwriting,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58.0,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 8.0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 1. Strumenti principali
            _buildToolButton(
              icon: Icons.edit_rounded,
              label: 'Penna',
              type: ToolType.pen,
            ),
            _buildToolButton(
              icon: Icons.brush_rounded,
              label: 'Evidenz.',
              type: ToolType.highlighter,
            ),
            _buildToolButton(
              icon: Icons.cleaning_services_rounded,
              label: 'Gomma',
              type: ToolType.eraser,
            ),
            _buildToolButton(
              icon: Icons.category_rounded,
              label: 'Forme',
              type: ToolType.shape,
            ),
            _buildToolButton(
              icon: Icons.open_with_rounded,
              label: 'Seleziona',
              type: ToolType.selection,
            ),
            _buildToolButton(
              icon: Icons.crop_free_rounded,
              label: 'Lazo Sposta',
              type: ToolType.lassoMove,
            ),
            _buildToolButton(
              icon: Icons.height_rounded,
              label: 'Sposta Spazio',
              type: ToolType.verticalSpace,
            ),
            _buildToolButton(
              icon: Icons.auto_awesome_rounded,
              label: 'Converti Cerchio',
              type: ToolType.lassoConvert,
            ),
            _buildToolButton(
              icon: Icons.gesture_rounded,
              label: 'Compatta Testo',
              type: ToolType.lassoReflow,
            ),

            if (activeToolType == ToolType.verticalSpace) ...[
              const SizedBox(width: 8),
              DropdownButton<bool>(
                value: verticalSpaceMovesBelow,
                underline: const SizedBox.shrink(),
                onChanged: (val) {
                  if (val != null) onVerticalSpaceDirectionChanged(val);
                },
                items: const [
                  DropdownMenuItem(
                    value: true,
                    child: Text('Sposta: Sotto ↓'),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text('Sposta: Sopra ↑'),
                  ),
                ],
              ),
            ],

            if (activeToolType == ToolType.shape) ...[
              const SizedBox(width: 8),
              DropdownButton<ShapeKind>(
                value: selectedShapeKind,
                underline: const SizedBox.shrink(),
                onChanged: (val) {
                  if (val != null) onShapeKindSelected(val);
                },
                items: const [
                  DropdownMenuItem(
                    value: ShapeKind.rectangle,
                    child: Text('Rettangolo'),
                  ),
                  DropdownMenuItem(
                    value: ShapeKind.circle,
                    child: Text('Cerchio'),
                  ),
                  DropdownMenuItem(
                    value: ShapeKind.line,
                    child: Text('Linea'),
                  ),
                  DropdownMenuItem(
                    value: ShapeKind.arrow,
                    child: Text('Freccia'),
                  ),
                ],
              ),
            ],

            _buildVerticalDivider(),

            // 2. Palette Colori
            for (final colorVal in paletteColors)
              GestureDetector(
                onTap: () => onColorSelected(colorVal),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: Color(colorVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selectedColorValue == colorVal
                          ? const Color(0xFF2563EB)
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              ),

            _buildVerticalDivider(),

            // 3. Controlli Conversione Scrittura a Mano -> Testo + Modalità Dimensione Font
            AnimatedBuilder(
              animation: ocrService,
              builder: (context, _) {
                return Row(
                  children: [
                    FilterChip(
                      selected: ocrService.mergeSameLineEnabled,
                      label: Text(
                        ocrService.mergeSameLineEnabled
                            ? 'Accorpa Riga: ON'
                            : 'Accorpa Riga: OFF',
                      ),
                      avatar: Icon(
                        Icons.wrap_text_rounded,
                        size: 18,
                        color: ocrService.mergeSameLineEnabled
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF64748B),
                      ),
                      onSelected: ocrService.setMergeSameLineEnabled,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      selected: !allowFingerDrawing,
                      label: Text(
                        !allowFingerDrawing
                            ? 'Solo Apple Pencil'
                            : 'Penna + Dito',
                      ),
                      avatar: Icon(
                        !allowFingerDrawing
                            ? Icons.draw_rounded
                            : Icons.touch_app_rounded,
                        size: 18,
                        color: !allowFingerDrawing
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF64748B),
                      ),
                      onSelected: (penOnly) =>
                          onAllowFingerDrawingChanged(!penOnly),
                    ),
                  ],
                );
              },
            ),

            _buildVerticalDivider(),

            // 4. Undo / Redo
            IconButton(
              tooltip: 'Annulla (Undo)',
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo_rounded),
            ),
            IconButton(
              tooltip: 'Ripeti (Redo)',
              onPressed: canRedo ? onRedo : null,
              icon: const Icon(Icons.redo_rounded),
            ),

            _buildVerticalDivider(),

            // 5. Menu a tre lineette (☰) con: Dim. Testo (+ pt), Sfondo Foglio, Calibrazione e Zoom %
            _buildSettingsHamburgerMenu(context),

            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onExportPdf,
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: const Text('Esporta PDF / Stampa'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsHamburgerMenu(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.menu_rounded, size: 20),
          label: const Text('Opzioni'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );
      },
      menuChildren: [
        AnimatedBuilder(
          animation: ocrService,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.all(14.0),
              child: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A. Dimensione Testo (+ pt)
                    const Text(
                      'Dimensione Testo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<TextSizeMode>(
                      segments: const [
                        ButtonSegment<TextSizeMode>(
                          value: TextSizeMode.adaptiveSnap,
                          label: Text(
                            'Auto-Snap (BETA)',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        ButtonSegment<TextSizeMode>(
                          value: TextSizeMode.fixedFromToolbar,
                          label: Text(
                            'Fissa',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      selected: {ocrService.textSizeMode},
                      onSelectionChanged: (sel) =>
                          ocrService.setTextSizeMode(sel.first),
                    ),
                    if (ocrService.textSizeMode ==
                        TextSizeMode.fixedFromToolbar) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Grandezza font:'),
                          DropdownButton<double>(
                            value: ocrService.fixedFontSize,
                            underline: const SizedBox.shrink(),
                            onChanged: (size) {
                              if (size != null) ocrService.setFixedFontSize(size);
                            },
                            items: PageConstants.standardFontSizes
                                .map(
                                  (pt) => DropdownMenuItem<double>(
                                    value: pt,
                                    child: Text('${pt.toInt()} pt'),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ],

                    const Divider(height: 22),

                    // B. Scelta del Foglio
                    const Text(
                      'Tipo di Foglio A4',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<PageBackgroundTemplate>(
                      isExpanded: true,
                      value: currentBackground,
                      underline: const SizedBox.shrink(),
                      onChanged: (bg) {
                        if (bg != null) onBackgroundChanged(bg);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: PageBackgroundTemplate.ruled,
                          child: Text('Foglio a Righe'),
                        ),
                        DropdownMenuItem(
                          value: PageBackgroundTemplate.grid,
                          child: Text('Foglio a Quadretti'),
                        ),
                        DropdownMenuItem(
                          value: PageBackgroundTemplate.dotted,
                          child: Text('Foglio Puntinato'),
                        ),
                        DropdownMenuItem(
                          value: PageBackgroundTemplate.blank,
                          child: Text('Foglio Bianco'),
                        ),
                      ],
                    ),

                    const Divider(height: 22),

                    // C. Calibrazione
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onCalibrateHandwriting,
                        icon: Icon(
                          ocrService.calibrationProfile.isCalibrated
                              ? Icons.verified_rounded
                              : Icons.tune_rounded,
                          size: 18,
                          color: ocrService.calibrationProfile.isCalibrated
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF2563EB),
                        ),
                        label: Text(
                          ocrService.calibrationProfile.isCalibrated
                              ? 'Calligrafia Calibrata ✓'
                              : 'Calibra Scrittura (3 Frasi)',
                        ),
                      ),
                    ),

                    const Divider(height: 22),

                    // D. Percentuale di Zoom
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Zoom',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: onZoomOut,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            TextButton(
                              onPressed: onZoomReset,
                              child: Text(
                                '${(zoomScale * 100).round()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: onZoomIn,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required ToolType type,
  }) {
    final isSelected = activeToolType == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: ChoiceChip(
        selected: isSelected,
        avatar: Icon(
          icon,
          size: 18,
          color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF475569),
        ),
        label: Text(label),
        onSelected: (_) => onToolSelected(type),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12.0),
      color: const Color(0xFFE2E8F0),
    );
  }
}

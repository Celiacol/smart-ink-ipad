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
              icon: Icons.gesture_rounded,
              label: 'Cerchia Testo',
              type: ToolType.lassoReflow,
            ),

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
                      selected: ocrService.autoConvertEnabled,
                      label: Text(
                        ocrService.autoConvertEnabled
                            ? 'Auto-Testo: ON'
                            : 'Auto-Testo: OFF',
                      ),
                      avatar: Icon(
                        Icons.text_fields_rounded,
                        size: 18,
                        color: ocrService.autoConvertEnabled
                            ? const Color(0xFF1D4ED8)
                            : const Color(0xFF64748B),
                      ),
                      onSelected: ocrService.setAutoConvertEnabled,
                    ),
                    const SizedBox(width: 8),
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
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: Icon(
                        ocrService.calibrationProfile.isCalibrated
                            ? Icons.verified_rounded
                            : Icons.tune_rounded,
                        size: 17,
                        color: ocrService.calibrationProfile.isCalibrated
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF2563EB),
                      ),
                      label: Text(
                        ocrService.calibrationProfile.isCalibrated
                            ? 'Calibrata ✓'
                            : 'Calibra Scrittura',
                      ),
                      onPressed: onCalibrateHandwriting,
                    ),
                    const SizedBox(width: 10),

                    // Scelta tra Punto 1 (Auto-Snap a Stili) e Punto 2 (Fissa da Toolbar)
                    SegmentedButton<TextSizeMode>(
                      segments: const [
                        const ButtonSegment<TextSizeMode>(
                          value: TextSizeMode.adaptiveSnap,
                          label: Text(
                            'Dim. Auto-Snap (BETA)',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          icon: Icon(
                            Icons.auto_fix_high_rounded,
                            size: 16,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        ButtonSegment<TextSizeMode>(
                          value: TextSizeMode.fixedFromToolbar,
                          label: Text('Dim. Fissa'),
                          icon: Icon(Icons.format_size_rounded, size: 16),
                        ),
                      ],
                      selected: {ocrService.textSizeMode},
                      onSelectionChanged: (selection) {
                        ocrService.setTextSizeMode(selection.first);
                      },
                    ),

                    if (ocrService.textSizeMode ==
                        TextSizeMode.fixedFromToolbar) ...[
                      const SizedBox(width: 8),
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
                  ],
                );
              },
            ),

            _buildVerticalDivider(),

            // 4. Undo / Redo + Sfondo A4 + Esporta PDF
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
            const SizedBox(width: 6),
            DropdownButton<PageBackgroundTemplate>(
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
            const SizedBox(width: 10),
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

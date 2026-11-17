import 'dart:ui' show Canvas, Offset;

import '../../core/commands/command_manager.dart';

/// Tipi di strumenti disponibili nella barra degli strumenti.
enum ToolType {
  /// Penna per scrivere (con auto-conversione in testo opzionale) o disegnare.
  pen,

  /// Evidenziatore semitrasparente.
  highlighter,

  /// Gomma per cancellare tratti, forme o blocchi di testo.
  eraser,

  /// Disegno di forme geometriche perfette (Rettangolo, Cerchio, Linea, Freccia).
  shape,

  /// Strumento di selezione per spostare elementi o modificare i blocchi di testo.
  selection,
}

/// Evento del puntatore normalizzato nello spazio di coordinate logiche A4 (595.28 x 841.89 pt).
class CanvasPointerEvent {
  final int pageIndex;
  final Offset a4Position;
  final double pressure;
  final int timestampMs;

  const CanvasPointerEvent({
    required this.pageIndex,
    required this.a4Position,
    this.pressure = 0.5,
    required this.timestampMs,
  });
}

/// Contratto comune per ogni strumento della toolbar (Plugin Pattern).
///
/// REGOLA ARCHITETTURALE:
/// Ogni strumento è una classe isolata che implementa [CanvasToolHandler].
/// Per aggiungere un nuovo strumento in futuro, basta implementare questa interfaccia
/// senza modificare alcuno degli altri strumenti.
abstract class CanvasToolHandler {
  ToolType get toolType;

  /// Chiamato quando la penna/dito tocca la pagina A4.
  void onPointerDown(CanvasPointerEvent event, CommandManager commandManager);

  /// Chiamato mentre la penna/dito si muove sulla pagina A4.
  void onPointerMove(CanvasPointerEvent event, CommandManager commandManager);

  /// Chiamato quando la penna/dito si solleva dalla pagina A4.
  void onPointerUp(CanvasPointerEvent event, CommandManager commandManager);

  /// Disegna un'anteprima in tempo reale sul foglio [pageIndex] mentre il gesto è in corso
  /// (es. il tratto che si sta scrivendo, la forma che si sta trascinando o il mirino della gomma).
  void renderActiveOverlay(Canvas canvas, int pageIndex);

  /// Annulla il gesto in corso senza salvare alcun comando (es. quando inizia un pinch-to-zoom a 2 dita).
  void cancelActiveGesture();
}

import 'package:flutter/foundation.dart';

import '../models/document_state.dart';
import 'document_command.dart';

/// Gestore centrale dello stato del documento e dello storico Undo/Redo.
///
/// Estende [ChangeNotifier] per notificare la UI ogni volta che un comando
/// viene eseguito, annullato o ripetuto.
class CommandManager extends ChangeNotifier {
  DocumentState _state;
  final List<DocumentCommand> _undoStack = [];
  final List<DocumentCommand> _redoStack = [];

  /// Numero massimo di operazioni memorizzate nello storico Undo.
  final int maxHistoryDepth;

  CommandManager({
    DocumentState? initialState,
    this.maxHistoryDepth = 100,
  }) : _state = initialState ?? DocumentState.initial();

  DocumentState get state => _state;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  List<DocumentCommand> get undoHistory => List.unmodifiable(_undoStack);

  /// Esegue un comando sul documento, aggiorna lo stato e pulisce lo stack Redo.
  void executeCommand(DocumentCommand command) {
    _state = command.execute(_state);
    _undoStack.add(command);
    if (_undoStack.length > maxHistoryDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    notifyListeners();
  }

  /// Annulla l'ultimo comando eseguito (es. riporta il testo convertito ai tratti a mano).
  void undo() {
    if (!canUndo) return;
    final lastCommand = _undoStack.removeLast();
    _state = lastCommand.undo(_state);
    _redoStack.add(lastCommand);
    notifyListeners();
  }

  /// Ripete l'ultimo comando annullato.
  void redo() {
    if (!canRedo) return;
    final nextCommand = _redoStack.removeLast();
    _state = nextCommand.execute(_state);
    _undoStack.add(nextCommand);
    notifyListeners();
  }
}

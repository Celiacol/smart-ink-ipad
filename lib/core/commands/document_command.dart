import '../models/canvas_element.dart';
import '../models/document_state.dart';
import '../models/page_model.dart';

/// Contratto base per tutte le modifiche al documento (Pattern Command).
///
/// Ogni operazione deve implementare sia [execute] sia [undo] in modo puro
/// (restituendo un nuovo [DocumentState] immutabile).
abstract class DocumentCommand {
  /// Descrizione leggibile del comando (utile per log, debug e accessibilità).
  String get description;

  /// Applica la modifica e restituisce il nuovo stato del documento.
  DocumentState execute(DocumentState currentState);

  /// Annulla la modifica e ripristina esattamente lo stato precedente.
  DocumentState undo(DocumentState currentState);
}

// =============================================================================
// 1. AGGIUNTA DI UN ELEMENTO (Tratto Penna, Forma o Casella di Testo)
// =============================================================================

class AddElementCommand extends DocumentCommand {
  final CanvasElement element;

  AddElementCommand(this.element);

  @override
  String get description => 'Aggiungi elemento (${element.runtimeType})';

  @override
  DocumentState execute(DocumentState currentState) {
    return currentState.updatePage(element.pageIndex, (page) {
      return page.copyWith(
        elements: [...page.elements, element],
      );
    });
  }

  @override
  DocumentState undo(DocumentState currentState) {
    return currentState.updatePage(element.pageIndex, (page) {
      return page.copyWith(
        elements: page.elements.where((e) => e.id != element.id).toList(),
      );
    });
  }
}

// =============================================================================
// 2. RIMOZIONE DI UNO O PIÙ ELEMENTI (Usato dalla Gomma o dal tasto Elimina)
// =============================================================================

class RemoveElementsCommand extends DocumentCommand {
  final int pageIndex;
  final List<CanvasElement> removedElements;

  RemoveElementsCommand({
    required this.pageIndex,
    required this.removedElements,
  });

  @override
  String get description => 'Rimuovi ${removedElements.length} elementi';

  @override
  DocumentState execute(DocumentState currentState) {
    final idsToRemove = removedElements.map((e) => e.id).toSet();
    return currentState.updatePage(pageIndex, (page) {
      return page.copyWith(
        elements: page.elements.where((e) => !idsToRemove.contains(e.id)).toList(),
      );
    });
  }

  @override
  DocumentState undo(DocumentState currentState) {
    return currentState.updatePage(pageIndex, (page) {
      return page.copyWith(
        elements: [...page.elements, ...removedElements],
      );
    });
  }
}

// =============================================================================
// 3. AGGIORNAMENTO DI UN ELEMENTO (Spostamento, Modifica Testo o Dimensione Font)
// =============================================================================

class UpdateElementCommand extends DocumentCommand {
  final CanvasElement previousElement;
  final CanvasElement updatedElement;

  UpdateElementCommand({
    required this.previousElement,
    required this.updatedElement,
  });

  @override
  String get description => 'Modifica elemento (${updatedElement.id})';

  @override
  DocumentState execute(DocumentState currentState) {
    return currentState.updatePage(updatedElement.pageIndex, (page) {
      return page.copyWith(
        elements: page.elements
            .map((e) => e.id == previousElement.id ? updatedElement : e)
            .toList(),
      );
    });
  }

  @override
  DocumentState undo(DocumentState currentState) {
    return currentState.updatePage(previousElement.pageIndex, (page) {
      return page.copyWith(
        elements: page.elements
            .map((e) => e.id == updatedElement.id ? previousElement : e)
            .toList(),
      );
    });
  }
}

// =============================================================================
// 4. CONVERSIONE AUTOMATICA SCRITTURA A MANO -> TESTO DIGITALE
// =============================================================================

/// Sostituisce atomicamente i tratti scritti a mano ([originalStrokes]) con
/// il blocco di testo convertito ([convertedTextElement]).
///
/// Premendo Undo, il blocco di testo scompare e riappaiono esattamente
/// i tratti originali scritti con la penna!
class ConvertInkToTextCommand extends DocumentCommand {
  final int pageIndex;
  final List<StrokeElement> originalStrokes;
  final TextElement convertedTextElement;

  ConvertInkToTextCommand({
    required this.pageIndex,
    required this.originalStrokes,
    required this.convertedTextElement,
  });

  @override
  String get description =>
      'Converti scrittura in testo: "${convertedTextElement.text}"';

  @override
  DocumentState execute(DocumentState currentState) {
    final strokeIds = originalStrokes.map((s) => s.id).toSet();
    return currentState.updatePage(pageIndex, (page) {
      final remainingElements =
          page.elements.where((e) => !strokeIds.contains(e.id)).toList();
      return page.copyWith(
        elements: [...remainingElements, convertedTextElement],
      );
    });
  }

  @override
  DocumentState undo(DocumentState currentState) {
    return currentState.updatePage(pageIndex, (page) {
      final withoutText = page.elements
          .where((e) => e.id != convertedTextElement.id)
          .toList();
      return page.copyWith(
        elements: [...withoutText, ...originalStrokes],
      );
    });
  }
}

// =============================================================================
// 5. SBLOCCO NUOVA PAGINA A4 (Attivato al 100% della circonferenza Pull-Up & Hold)
// =============================================================================

class AddPageCommand extends DocumentCommand {
  final PageBackgroundTemplate? templateOverride;

  AddPageCommand({this.templateOverride});

  @override
  String get description => 'Sblocca nuova pagina A4';

  @override
  DocumentState execute(DocumentState currentState) {
    final nextIndex = currentState.pages.length;
    final inheritedTemplate = templateOverride ??
        (currentState.pages.isNotEmpty
            ? currentState.pages.last.background
            : PageBackgroundTemplate.ruled);

    final newPage = PageModel(
      pageIndex: nextIndex,
      background: inheritedTemplate,
      elements: const [],
    );

    return currentState.copyWith(
      pages: [...currentState.pages, newPage],
    );
  }

  @override
  DocumentState undo(DocumentState currentState) {
    if (currentState.pages.length <= 1) return currentState;
    return currentState.copyWith(
      pages: currentState.pages.sublist(0, currentState.pages.length - 1),
    );
  }
}

// =============================================================================
// 6. CAMBIO SFONDO DELLA PAGINA (Bianco, Righe, Quadretti, Puntinato)
// =============================================================================

class ChangePageBackgroundCommand extends DocumentCommand {
  final int pageIndex;
  final PageBackgroundTemplate previousBackground;
  final PageBackgroundTemplate newBackground;

  ChangePageBackgroundCommand({
    required this.pageIndex,
    required this.previousBackground,
    required this.newBackground,
  });

  @override
  String get description => 'Cambia sfondo pagina ${pageIndex + 1}';

  @override
  DocumentState execute(DocumentState currentState) {
    return currentState.updatePage(pageIndex, (page) {
      return page.copyWith(background: newBackground);
    });
  }

  @override
  DocumentState undo(DocumentState currentState) {
    return currentState.updatePage(pageIndex, (page) {
      return page.copyWith(background: previousBackground);
    });
  }
}

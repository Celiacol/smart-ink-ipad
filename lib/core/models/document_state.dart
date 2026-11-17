import 'canvas_element.dart';
import 'page_model.dart';

/// Stato immutabile dell'intero documento multi-pagina A4.
///
/// Il documento inizia sempre con 1 sola pagina A4 e le pagine successive
/// vengono sbloccate una ad una dall'utente tramite il gesto "Pull-Up & Hold".
class DocumentState {
  final String documentId;
  final String title;
  final List<PageModel> pages;

  const DocumentState({
    required this.documentId,
    required this.title,
    required this.pages,
  });

  /// Crea un nuovo documento vuoto con la sola Pagina 1 (A4).
  factory DocumentState.initial({
    String documentId = 'default-notebook',
    String title = 'Appunti Smart A4',
    PageBackgroundTemplate initialBackground = PageBackgroundTemplate.ruled,
  }) {
    return DocumentState(
      documentId: documentId,
      title: title,
      pages: [
        PageModel(
          pageIndex: 0,
          background: initialBackground,
          elements: const [],
        ),
      ],
    );
  }

  int get pageCount => pages.length;

  PageModel pageAt(int index) => pages[index];

  DocumentState copyWith({
    String? documentId,
    String? title,
    List<PageModel>? pages,
  }) {
    return DocumentState(
      documentId: documentId ?? this.documentId,
      title: title ?? this.title,
      pages: pages ?? this.pages,
    );
  }

  /// Restituisce un nuovo [DocumentState] aggiornando solo la pagina [pageIndex].
  DocumentState updatePage(int pageIndex, PageModel Function(PageModel page) updater) {
    if (pageIndex < 0 || pageIndex >= pages.length) return this;
    final updatedPages = List<PageModel>.from(pages);
    updatedPages[pageIndex] = updater(updatedPages[pageIndex]);
    return copyWith(pages: updatedPages);
  }

  /// Cerca un elemento tramite il suo [elementId] su una specifica pagina.
  CanvasElement? findElement(int pageIndex, String elementId) {
    if (pageIndex < 0 || pageIndex >= pages.length) return null;
    for (final element in pages[pageIndex].elements) {
      if (element.id == elementId) return element;
    }
    return null;
  }
}

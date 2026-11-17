import 'canvas_element.dart';

/// Tipi di sfondo per il foglio A4.
enum PageBackgroundTemplate {
  /// Foglio completamente bianco.
  blank,

  /// Foglio a righe orizzontali (ideale per appunti testuali).
  ruled,

  /// Foglio a quadretti 5mm (ideale per matematica, schemi e tabelle).
  grid,

  /// Foglio puntinato (Bullet Journal style).
  dotted,
}

/// Rappresenta una singola pagina A4 del quaderno.
class PageModel {
  /// Indice 0-based della pagina.
  final int pageIndex;

  /// Stile dello sfondo della pagina.
  final PageBackgroundTemplate background;

  /// Lista ordinata (dal basso verso l'alto nello z-order) degli elementi sulla pagina.
  final List<CanvasElement> elements;

  const PageModel({
    required this.pageIndex,
    this.background = PageBackgroundTemplate.ruled,
    this.elements = const [],
  });

  PageModel copyWith({
    int? pageIndex,
    PageBackgroundTemplate? background,
    List<CanvasElement>? elements,
  }) {
    return PageModel(
      pageIndex: pageIndex ?? this.pageIndex,
      background: background ?? this.background,
      elements: elements ?? this.elements,
    );
  }

  Map<String, dynamic> toJson() => {
        'pageIndex': pageIndex,
        'background': background.name,
        'elements': elements.map((e) => e.toJson()).toList(),
      };
}

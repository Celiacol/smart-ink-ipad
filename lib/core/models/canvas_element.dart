import 'dart:math' as math;
import 'dart:ui' show Color, Offset, Rect;

/// Punto singolo catturato dalla penna sul foglio A4.
class InkPoint {
  /// Coordinata X in punti logici A4 (0 .. 595.28).
  final double x;

  /// Coordinata Y in punti logici A4 (0 .. 841.89).
  final double y;

  /// Pressione della penna (da 0.0 a 1.0, default 0.5).
  final double pressure;

  /// Timestamp in millisecondi (usato da ML Kit Digital Ink per capire la dinamica del tratto).
  final int timestampMs;

  const InkPoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
    required this.timestampMs,
  });

  Offset get offset => Offset(x, y);

  InkPoint translate(double dx, double dy) {
    return InkPoint(
      x: x + dx,
      y: y + dy,
      pressure: pressure,
      timestampMs: timestampMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'p': pressure,
        't': timestampMs,
      };

  factory InkPoint.fromJson(Map<String, dynamic> json) => InkPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['p'] as num?)?.toDouble() ?? 0.5,
        timestampMs: (json['t'] as num).toInt(),
      );
}

/// Contratto base immutabile per qualsiasi elemento posizionato su una pagina A4.
///
/// REGOLA ARCHITETTURALE:
/// Per aggiungere un nuovo tipo di elemento in futuro (es. Immagine, Tabella, Post-it),
/// basta creare una sottoclasse di [CanvasElement] senza modificare le altre classi.
abstract class CanvasElement {
  /// Identificatore univoco dell'elemento.
  final String id;

  /// Indice della pagina A4 a cui appartiene (0-based).
  final int pageIndex;

  /// Colore principale dell'elemento (in formato ARGB 32-bit).
  final int colorValue;

  const CanvasElement({
    required this.id,
    required this.pageIndex,
    required this.colorValue,
  });

  Color get color => Color(colorValue);

  /// Rettangolo di ingombro in coordinate logiche A4 (usato da Gomma, Selezione e Layout).
  Rect get boundingBox;

  /// Restituisce una copia dell'elemento traslata di (dx, dy) sul foglio A4.
  CanvasElement translate(double dx, double dy);

  /// Verifica se un punto (con raggio di tolleranza [radius]) tocca l'elemento.
  bool hitTest(Offset point, {double radius = 8.0}) {
    return boundingBox.inflate(radius).contains(point);
  }

  /// Serializzazione JSON per salvataggio locale.
  Map<String, dynamic> toJson();
}

// =============================================================================
// 1. TRATTO A MANO LIBERA (Penna o Evidenziatore)
// =============================================================================

class StrokeElement extends CanvasElement {
  final List<InkPoint> points;
  final double strokeWidth;
  final bool isHighlighter;

  const StrokeElement({
    required super.id,
    required super.pageIndex,
    required super.colorValue,
    required this.points,
    this.strokeWidth = 2.5,
    this.isHighlighter = false,
  });

  @override
  Rect get boundingBox {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    final halfStroke = strokeWidth / 2.0;
    return Rect.fromLTRB(
      minX - halfStroke,
      minY - halfStroke,
      maxX + halfStroke,
      maxY + halfStroke,
    );
  }

  /// Lunghezza totale del percorso disegnato con la penna.
  double get pathLength {
    if (points.length < 2) return 0.0;
    double length = 0.0;
    for (int i = 1; i < points.length; i++) {
      final dx = points[i].x - points[i - 1].x;
      final dy = points[i].y - points[i - 1].y;
      length += math.sqrt(dx * dx + dy * dy);
    }
    return length;
  }

  @override
  bool hitTest(Offset point, {double radius = 8.0}) {
    if (!boundingBox.inflate(radius).contains(point)) return false;
    final thresholdSq = math.pow(radius + strokeWidth / 2, 2);
    for (final p in points) {
      final dx = p.x - point.dx;
      final dy = p.y - point.dy;
      if (dx * dx + dy * dy <= thresholdSq) {
        return true;
      }
    }
    return false;
  }

  @override
  StrokeElement translate(double dx, double dy) {
    return StrokeElement(
      id: id,
      pageIndex: pageIndex,
      colorValue: colorValue,
      strokeWidth: strokeWidth,
      isHighlighter: isHighlighter,
      points: points.map((p) => p.translate(dx, dy)).toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'stroke',
        'id': id,
        'pageIndex': pageIndex,
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'isHighlighter': isHighlighter,
        'points': points.map((p) => p.toJson()).toList(),
      };
}

// =============================================================================
// 2. BLOCCO DI TESTO DIGITALE (Convertito dalla scrittura a mano o digitato)
// =============================================================================

/// Singolo segmento colorato all'interno di un [TextElement] multi-colore.
class TextColorSpan {
  final String text;
  final int colorValue;

  const TextColorSpan({
    required this.text,
    required this.colorValue,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'colorValue': colorValue,
      };
}

class TextElement extends CanvasElement {
  /// Coordinata X dell'angolo superiore sinistro sul foglio A4.
  final double x;

  /// Coordinata Y dell'angolo superiore sinistro sul foglio A4.
  final double y;

  /// Testo (può contenere ritorni a capo `\n` e spaziature di allineamento).
  final String text;

  /// Dimensione del font in punti tipografici A4.
  final double fontSize;

  /// Larghezza massima opzionale prima del wrapping automatico.
  final double maxWidth;

  /// Famiglia del font (default 'Inter' / 'Roboto').
  final String fontFamily;

  /// ID dei tratti originali da cui è stato generato questo testo (utile per debug/storia).
  final List<String> sourceStrokeIds;

  /// Segmenti multi-colore opzionali (se vuoto, usa `colorValue` unico per tutto `text`).
  final List<TextColorSpan> spans;

  const TextElement({
    required super.id,
    required super.pageIndex,
    required super.colorValue,
    required this.x,
    required this.y,
    required this.text,
    required this.fontSize,
    this.maxWidth = 520.0,
    this.fontFamily = 'Roboto',
    this.sourceStrokeIds = const [],
    this.spans = const [],
  });

  @override
  Rect get boundingBox {
    final lines = text.split('\n');
    int maxCharsInLine = 1;
    for (final line in lines) {
      if (line.length > maxCharsInLine) {
        maxCharsInLine = line.length;
      }
    }
    final estimatedWidth =
        math.min(maxWidth, math.max(fontSize * 1.5, maxCharsInLine * fontSize * 0.58));
    final estimatedHeight = lines.length * (fontSize * 1.35);
    return Rect.fromLTWH(x, y, estimatedWidth, estimatedHeight);
  }

  TextElement copyWith({
    double? x,
    double? y,
    String? text,
    double? fontSize,
    int? colorValue,
    double? maxWidth,
    List<TextColorSpan>? spans,
  }) {
    return TextElement(
      id: id,
      pageIndex: pageIndex,
      colorValue: colorValue ?? this.colorValue,
      x: x ?? this.x,
      y: y ?? this.y,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      maxWidth: maxWidth ?? this.maxWidth,
      fontFamily: fontFamily,
      sourceStrokeIds: sourceStrokeIds,
      spans: spans ?? this.spans,
    );
  }

  @override
  TextElement translate(double dx, double dy) {
    return copyWith(x: x + dx, y: y + dy);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text',
        'id': id,
        'pageIndex': pageIndex,
        'colorValue': colorValue,
        'x': x,
        'y': y,
        'text': text,
        'fontSize': fontSize,
        'maxWidth': maxWidth,
        'fontFamily': fontFamily,
        'sourceStrokeIds': sourceStrokeIds,
        'spans': spans.map((s) => s.toJson()).toList(),
      };
}

// =============================================================================
// 3. FORMA GEOMETRICA (Rettangolo, Cerchio/Ellisse, Linea, Freccia)
// =============================================================================

enum ShapeKind {
  rectangle,
  circle,
  line,
  arrow,
}

class ShapeElement extends CanvasElement {
  final ShapeKind kind;
  final Offset startPoint;
  final Offset endPoint;
  final double strokeWidth;

  const ShapeElement({
    required super.id,
    required super.pageIndex,
    required super.colorValue,
    required this.kind,
    required this.startPoint,
    required this.endPoint,
    this.strokeWidth = 2.5,
  });

  @override
  Rect get boundingBox {
    return Rect.fromPoints(startPoint, endPoint).inflate(strokeWidth / 2.0);
  }

  @override
  ShapeElement translate(double dx, double dy) {
    final delta = Offset(dx, dy);
    return ShapeElement(
      id: id,
      pageIndex: pageIndex,
      colorValue: colorValue,
      kind: kind,
      startPoint: startPoint + delta,
      endPoint: endPoint + delta,
      strokeWidth: strokeWidth,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'shape',
        'id': id,
        'pageIndex': pageIndex,
        'colorValue': colorValue,
        'kind': kind.name,
        'startX': startPoint.dx,
        'startY': startPoint.dy,
        'endX': endPoint.dx,
        'endY': endPoint.dy,
        'strokeWidth': strokeWidth,
      };
}

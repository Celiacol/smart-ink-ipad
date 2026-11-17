import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/commands/command_manager.dart';
import 'package:smart_ink_notebook/core/commands/document_command.dart';
import 'package:smart_ink_notebook/core/models/canvas_element.dart';

void main() {
  group('CommandManager & ConvertInkToTextCommand (Undo/Redo)', () {
    test('La conversione rimuove i tratti a mano e inserisce il TextElement; Undo ripristina i tratti originali', () {
      final manager = CommandManager();

      final stroke1 = StrokeElement(
        id: 'stroke-1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 80, y: 120, timestampMs: 10),
          InkPoint(x: 110, y: 125, timestampMs: 20),
        ],
      );
      final stroke2 = StrokeElement(
        id: 'stroke-2',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        points: const [
          InkPoint(x: 120, y: 120, timestampMs: 30),
          InkPoint(x: 150, y: 125, timestampMs: 40),
        ],
      );

      // 1. L'utente scrive due tratti con la penna
      manager.executeCommand(AddElementCommand(stroke1));
      manager.executeCommand(AddElementCommand(stroke2));
      expect(manager.state.pageAt(0).elements.length, 2);

      // 2. Scade il timer e i due tratti vengono convertiti in un unico blocco di testo
      const convertedText = TextElement(
        id: 'text-1',
        pageIndex: 0,
        colorValue: 0xFF1E293B,
        x: 80,
        y: 120,
        text: 'Ciao mondo',
        fontSize: 14.0,
        sourceStrokeIds: ['stroke-1', 'stroke-2'],
      );

      manager.executeCommand(
        ConvertInkToTextCommand(
          pageIndex: 0,
          originalStrokes: [stroke1, stroke2],
          convertedTextElement: convertedText,
        ),
      );

      final elementsAfterConvert = manager.state.pageAt(0).elements;
      expect(elementsAfterConvert.length, 1);
      expect(elementsAfterConvert.first, isA<TextElement>());
      expect((elementsAfterConvert.first as TextElement).text, 'Ciao mondo');

      // 3. L'utente preme Undo: il testo sparisce e tornano i 2 tratti a mano libera
      manager.undo();
      final elementsAfterUndo = manager.state.pageAt(0).elements;
      expect(elementsAfterUndo.length, 2);
      expect(elementsAfterUndo.every((e) => e is StrokeElement), isTrue);
    });
  });
}

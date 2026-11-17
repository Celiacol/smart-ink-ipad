import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ink_notebook/core/commands/command_manager.dart';
import 'package:smart_ink_notebook/core/commands/document_command.dart';
import 'package:smart_ink_notebook/core/constants/page_constants.dart';
import 'package:smart_ink_notebook/features/canvas_view/page_unlock_ring_indicator.dart';

void main() {
  group('Sblocco Pagina A4 con gesto "Pull-Up & Hold" e Circonferenza', () {
    test(
      'Rilasciando il dito prima che la circonferenza sia al 100%, la nuova pagina NON viene creata',
      () {
        final commandManager = CommandManager();
        expect(commandManager.state.pageCount, 1);

        final unlockController = PullUpUnlockController(
          onPageUnlocked: () => commandManager.executeCommand(AddPageCommand()),
        );

        // L'utente trascina verso l'alto oltre la soglia (es. 80 pt > 60 pt)
        unlockController.updatePullUpDistance(80.0);
        expect(unlockController.isHoldThresholdReached, isTrue);

        // Tiene premuto solo per metà del tempo richiesto (350 ms su 700 ms)
        unlockController.advanceHoldTime(350);
        expect(unlockController.ringProgress, closeTo(0.5, 0.01));
        expect(commandManager.state.pageCount, 1);

        // Rilascia il dito in anticipo: la circonferenza si azzera e resta 1 pagina
        unlockController.onPointerReleased();
        expect(unlockController.ringProgress, 0.0);
        expect(commandManager.state.pageCount, 1);

        unlockController.dispose();
      },
    );

    test(
      'Mantenendo premuto finché la circonferenza raggiunge il 100%, viene sbloccata la Pagina 2 (reversibile con Undo)',
      () {
        TestWidgetsFlutterBinding.ensureInitialized();
        final commandManager = CommandManager();
        expect(commandManager.state.pageCount, 1);

        final unlockController = PullUpUnlockController(
          onPageUnlocked: () => commandManager.executeCommand(AddPageCommand()),
        );

        // Trascina oltre la soglia
        unlockController.updatePullUpDistance(PageConstants.pullUpDistanceThreshold + 10);

        // Tiene premuto fino al completamento della circonferenza (700 ms)
        unlockController.advanceHoldTime(PageConstants.holdToUnlockDurationMs);

        expect(unlockController.ringProgress, 1.0);
        expect(unlockController.hasUnlockedInCurrentGesture, isTrue);
        expect(commandManager.state.pageCount, 2);

        // Verifica che Undo rimuova la Pagina 2 appena sbloccata
        commandManager.undo();
        expect(commandManager.state.pageCount, 1);

        unlockController.dispose();
      },
    );
  });
}

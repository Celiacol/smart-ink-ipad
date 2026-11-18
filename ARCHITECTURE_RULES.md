# Architecture Rules & AI-Agent Modification Guide (`ARCHITECTURE_RULES.md`)

> **LEGGERE PRIMA DI MODIFICARE IL CODICE (PER AGENTI IA E SVILUPPATORI)**
> Questa applicazione è stata progettata con un'architettura **Zero-Coupling Feature-First + Command Bus**.
> L'obiettivo principale è garantire che l'aggiunta, la modifica o la rimozione di una funzionalità **non possa mai rompere** altre funzionalità esistenti.

---

## 1. Mappa dei Moduli e Confini di Dipendenza

```text
lib/
├── main.dart                          # Entrypoint dell'applicazione
├── core/                              # NUCLEO IMMUTABILE (Zero dipendenze da UI o feature)
│   ├── constants/
│   │   └── page_constants.dart        # Costanti A4 (595.28 x 841.89 pt), Soglie Pull-Up, Stili Font
│   ├── models/
│   │   ├── canvas_element.dart        # Contratto base + StrokeElement, TextElement, ShapeElement
│   │   ├── page_model.dart            # Modello di una singola pagina A4
│   │   └── document_state.dart        # Stato immutabile dell'intero quaderno
│   └── commands/
│       ├── document_command.dart      # Interfaccia reversibile Command (execute / undo)
│       └── command_manager.dart       # Gestore centrale dello stato e dello storico Undo/Redo
│
├── features/                          # MODULI INDIPENDENTI (Non devono mai importarsi a vicenda)
│   ├── handwriting_ocr/               # Conversione Scrittura -> Testo + Layout + Calibrazione
│   │   ├── handwriting_calibration.dart # Profilo offline 3 frasi + Smart Re-Ranking Top-10
│   │   ├── ink_intent_classifier.dart # Distingue Testo da Figure/Disegni geometrici
│   │   ├── spatial_layout_analyzer.dart # Rileva righe, a-capo (\n), indentazione e Font Size
│   │   └── handwriting_ocr_service.dart # Pipeline conversione + Accorpa Riga + ML Kit Digital Ink
│   │
│   ├── tools/                         # Plugin degli Strumenti di Disegno/Scrittura
│   │   ├── canvas_tool_handler.dart   # Interfaccia comune per ogni strumento
│   │   ├── pen_tool_handler.dart      # Penna ed Evidenziatore (scrittura libera senza interruzioni)
│   │   ├── eraser_tool_handler.dart   # Gomma (cancella tratti, forme o testi)
│   │   ├── shape_tool_handler.dart    # Creazione forme geometriche (Rettangolo, Cerchio, Linea, Freccia)
│   │   ├── selection_tool_handler.dart# Selezione, spostamento e modifica testo/elementi
│   │   ├── lasso_convert_tool_handler.dart # Cerchia scrittura a mano -> converte in testo digitale
│   │   └── lasso_reflow_tool_handler.dart  # Cerchia testo convertito -> compatta spazi su righe consecutive
│   │
│   ├── canvas_view/                   # Rendering A4, Paginazione e Gesto "Pull-Up & Hold"
│   │   ├── a4_page_painter.dart       # CustomPainter puro per foglio A4 + sfondi (righe/quadretti)
│   │   ├── page_unlock_ring_indicator.dart # Circonferenza animata per sblocco nuova pagina
│   │   └── paginated_notebook_view.dart    # Vista multi-pagina + Palm Rejection (Penna vs Dita)
│   │
│   ├── toolbar/                       # Barra degli strumenti modulare
│   │   └── notebook_toolbar.dart      # Selettore strumenti, colori, Toggle Auto-Testo, Modalità Font
│   │
│   └── pdf_export/                    # Esportazione PDF A4 vettoriale 1:1 e Stampa
│       └── pdf_export_service.dart    # Converte DocumentState in PDF A4 pronto per la stampa
```

---

## 2. Le 4 Regole d'Oro (Inviolabili)

### Regola 1: Vietato modificare `DocumentState` fuori da un `DocumentCommand`
Nessun widget, strumento o servizio può aggiungere, modificare o cancellare direttamente elementi da una pagina.
Ogni modifica **deve** essere incapsulata in una sottoclasse di `DocumentCommand` e inviata a `CommandManager.executeCommand(cmd)`.
- **Perché?** Garantisce che `Undo` e `Redo` funzionino sempre al 100% senza codice aggiuntivo e mantiene tracciabile ogni mutazione.

### Regola 2: Vietato importare una Feature dentro un'altra Feature
- `features/pdf_export/` **non** deve mai importare `features/tools/` o `features/handwriting_ocr/`.
- `features/tools/eraser_tool_handler.dart` **non** deve sapere nulla di `pen_tool_handler.dart`.
- Tutte le feature comunicano **esclusivamente** attraverso i modelli in `lib/core/models/` e i comandi in `lib/core/commands/`.

### Regola 3: Coordinate Sempre in Punti Logici A4 (`595.28 x 841.89 pt`)
Tutte le coordinate $(x, y)$, gli spessori dei tratti e le dimensioni dei font (`fontSize`) salvati in `CanvasElement` sono espressi nello spazio logico **A4 a 72 DPI** (`PageConstants.a4Width` × `PageConstants.a4Height`).
- Non salvare **mai** coordinate in pixel fisici dello schermo del dispositivo.
- Questo garantisce che ciò che si vede su iPad o tablet Android corrisponda al millimetro al PDF esportato e stampato.

### Regola 4: Come Aggiungere Nuove Funzionalità (Ricette per Agenti IA)

#### A. Come aggiungere un nuovo Strumento (es. "Laser Pointer" o "Righello")
1. Crea un nuovo file in `lib/features/tools/mio_strumento_handler.dart` che implementa `CanvasToolHandler`.
2. Aggiungi il valore nell'enum `ToolType` e registralo nella mappa degli strumenti.
3. Aggiungi il pulsante corrispondente in `lib/features/toolbar/notebook_toolbar.dart`.
*(Nessun altro file dell'applicazione deve essere modificato).*

#### B. Come aggiungere un nuovo Elemento sul Foglio (es. "Immagine" o "Tabella")
1. Crea la classe `ImageElement extends CanvasElement` in `lib/core/models/canvas_element.dart` implementando `boundingBox`, `copyWith`, `toJson`.
2. Aggiungi il case di rendering grafico in `a4_page_painter.dart` e il case di rendering PDF in `pdf_export_service.dart`.
*(La gomma, lo spostamento, il salvataggio e l'Undo/Redo funzioneranno automaticamente grazie al contratto `CanvasElement`!).*

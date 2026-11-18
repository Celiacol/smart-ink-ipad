/// Costanti fisiche, tipografiche e di interazione del foglio A4.
///
/// Tutte le coordinate dell'app sono espresse in punti logici A4 standard
/// (72 DPI = 595.28 x 841.89 pt) per garantire una corrispondenza 1:1
/// tra vista su tablet (iPad / Android), esportazione PDF e carta stampata.
class PageConstants {
  PageConstants._();

  /// Larghezza standard ISO A4 a 72 DPI (210 mm).
  static const double a4Width = 595.28;

  /// Altezza standard ISO A4 a 72 DPI (297 mm).
  static const double a4Height = 841.89;

  /// Rapporto d'aspetto del foglio A4 (1 : √2).
  static const double a4AspectRatio = a4Width / a4Height;

  /// Spaziatura visiva tra una pagina e la successiva nella vista scorrevole.
  static const double interPageSpacing = 24.0;

  // ---------------------------------------------------------------------------
  // Parametri per lo sblocco pagina "Pull-Up & Hold" con circonferenza animata
  // ---------------------------------------------------------------------------

  /// Distanza minima di trascinamento verso l'alto (in px/pt oltre il fondo
  /// dell'ultima pagina) per attivare il caricamento della circonferenza.
  static const double pullUpDistanceThreshold = 60.0;

  /// Tempo di tenuta (in millisecondi) necessario per completare il contorno
  /// della circonferenza da 0% a 100% e sbloccare la nuova pagina.
  static const int holdToUnlockDurationMs = 700;

  // ---------------------------------------------------------------------------
  // Parametri per la conversione automatica Scrittura a Mano -> Testo
  // ---------------------------------------------------------------------------

  /// Tempo di inattività predefinito (dopo il distacco della penna dallo schermo)
  /// prima di avviare la conversione in testo digitale (1.8s per dare tempo a tagli delle 't' e accenti).
  static const int defaultOcrDebounceMs = 1800;

  /// Limiti configurabili dall'utente per il timer di conversione.
  static const int minOcrDebounceMs = 600;
  static const int maxOcrDebounceMs = 2500;

  // ---------------------------------------------------------------------------
  // Preset tipografici per la Modalità 1 ("Auto-Snap a Stili") e Modalità 2 ("Fissa")
  // ---------------------------------------------------------------------------

  /// Stile Nota / Testo piccolo (10 pt).
  static const double fontSizeSmall = 10.0;

  /// Stile Corpo del testo standard (14 pt).
  static const double fontSizeBody = 14.0;

  /// Stile Sottotitolo H2 (20 pt).
  static const double fontSizeSubtitle = 20.0;

  /// Stile Titolo H1 (28 pt).
  static const double fontSizeTitle = 28.0;

  /// Lista delle dimensioni selezionabili nella toolbar (Modalità Fissa)
  /// e usate come bersagli di "Snap" (Modalità Adattiva).
  static const List<double> standardFontSizes = [
    fontSizeSmall,
    12.0,
    fontSizeBody,
    16.0,
    fontSizeSubtitle,
    24.0,
    fontSizeTitle,
  ];

  /// Mappa l'altezza rilevata della scrittura a mano (in punti A4) allo stile
  /// tipografico standard più vicino ("Snap"), così il documento resta ordinato.
  static double snapHandwritingHeightToFontSize(double medianStrokeHeight) {
    if (medianStrokeHeight < 14.0) {
      return fontSizeSmall; // 10 pt
    } else if (medianStrokeHeight <= 24.0) {
      return fontSizeBody; // 14 pt
    } else if (medianStrokeHeight <= 36.0) {
      return fontSizeSubtitle; // 20 pt
    } else {
      return fontSizeTitle; // 28 pt
    }
  }
}

/// Modalità di calcolo della dimensione del testo convertito.
enum TextSizeMode {
  /// L'app legge la grandezza della scrittura dell'utente e fa lo "snap"
  /// allo stile più vicino (Titolo, Sottotitolo, Corpo, Nota).
  adaptiveSnap,

  /// Il testo convertito assume sempre la dimensione fissa scelta nella toolbar,
  /// indipendentemente da quanto grande l'utente ha scritto con la penna.
  fixedFromToolbar,
}

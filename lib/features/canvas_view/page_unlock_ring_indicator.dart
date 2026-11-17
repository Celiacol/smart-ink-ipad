import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/page_constants.dart';

/// Controller logico puro che gestisce il gesto **"Pull-Up & Hold"**
/// per sbloccare la pagina A4 successiva.
///
/// Come funziona:
/// 1. Quando l'utente trascina verso l'alto oltre il fondo dell'ultima pagina
///    di almeno [PageConstants.pullUpDistanceThreshold], entra nello stato di "Hold attivo".
/// 2. Finché tiene premuto, il progresso della circonferenza (`ringProgress`)
///    avanza da `0.0` a `1.0` nell'arco di [PageConstants.holdToUnlockDurationMs] (es. 700ms).
/// 3. Se l'utente rilascia il dito prima che `ringProgress` raggiunga `1.0`,
///    il caricamento si interrompe e torna a `0.0` senza creare la pagina.
/// 4. Non appena `ringProgress` raggiunge `1.0`, viene invocato [onPageUnlocked]
///    e la nuova pagina A4 appare!
class PullUpUnlockController extends ChangeNotifier {
  final VoidCallback onPageUnlocked;
  final double pullDistanceThreshold;
  final int holdDurationMs;

  double _currentPullDistance = 0.0;
  double _ringProgress = 0.0;
  bool _hasUnlockedInCurrentGesture = false;
  Timer? _holdTickTimer;

  PullUpUnlockController({
    required this.onPageUnlocked,
    this.pullDistanceThreshold = PageConstants.pullUpDistanceThreshold,
    this.holdDurationMs = PageConstants.holdToUnlockDurationMs,
  });

  double get currentPullDistance => _currentPullDistance;

  /// Progresso di completamento del contorno della circonferenza (da `0.0` a `1.0`).
  double get ringProgress => _ringProgress;

  /// `true` quando l'utente ha trascinato abbastanza in alto e la circonferenza si sta caricando.
  bool get isHoldThresholdReached =>
      _currentPullDistance >= pullDistanceThreshold && !_hasUnlockedInCurrentGesture;

  bool get hasUnlockedInCurrentGesture => _hasUnlockedInCurrentGesture;

  /// Aggiorna la distanza di trascinamento verso l'alto (in punti/pixel).
  void updatePullUpDistance(double distance) {
    if (_hasUnlockedInCurrentGesture) return;

    _currentPullDistance = math.max(0.0, distance);

    if (_currentPullDistance >= pullDistanceThreshold) {
      _startHoldTimerIfNeeded();
    } else {
      // Se l'utente abbassa il dito sotto la soglia prima di aver completato il cerchio,
      // il caricamento del contorno si ferma e si azzera.
      _stopHoldTimerAndResetProgress();
    }
    notifyListeners();
  }

  /// Fa avanzare manualmente il tempo di tenuta di [elapsedMs] millisecondi
  /// (usato sia dal timer interno sia dai test unitari).
  void advanceHoldTime(int elapsedMs) {
    if (_hasUnlockedInCurrentGesture ||
        _currentPullDistance < pullDistanceThreshold) {
      return;
    }

    final increment = elapsedMs / holdDurationMs;
    _ringProgress = (_ringProgress + increment).clamp(0.0, 1.0);

    if (_ringProgress >= 1.0) {
      _hasUnlockedInCurrentGesture = true;
      _holdTickTimer?.cancel();
      _holdTickTimer = null;
      HapticFeedback.mediumImpact();
      onPageUnlocked();
    }
    notifyListeners();
  }

  /// Chiamato quando l'utente solleva il dito dallo schermo.
  void onPointerReleased() {
    _holdTickTimer?.cancel();
    _holdTickTimer = null;
    _currentPullDistance = 0.0;
    _ringProgress = 0.0;
    _hasUnlockedInCurrentGesture = false;
    notifyListeners();
  }

  void _startHoldTimerIfNeeded() {
    if (_holdTickTimer != null || _hasUnlockedInCurrentGesture) return;
    const tickIntervalMs = 16; // ~60 FPS
    _holdTickTimer = Timer.periodic(
      const Duration(milliseconds: tickIntervalMs),
      (_) => advanceHoldTime(tickIntervalMs),
    );
  }

  void _stopHoldTimerAndResetProgress() {
    _holdTickTimer?.cancel();
    _holdTickTimer = null;
    _ringProgress = 0.0;
  }

  @override
  void dispose() {
    _holdTickTimer?.cancel();
    super.dispose();
  }
}

/// Widget posizionato subito sotto l'ultima pagina A4 che mostra e gestisce
/// il gesto **"Trascina verso l'alto e tieni premuto"** con il caricamento
/// del contorno della circonferenza.
class PageUnlockRingIndicator extends StatelessWidget {
  final PullUpUnlockController controller;
  final int nextPageNumber;

  const PageUnlockRingIndicator({
    super.key,
    required this.controller,
    required this.nextPageNumber,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final pullRatio = (controller.currentPullDistance /
                controller.pullDistanceThreshold)
            .clamp(0.0, 1.0);
        final ringProgress = controller.ringProgress;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) {
            // Trascinamento verso l'alto ha delta.dy negativo
            final newDistance =
                controller.currentPullDistance - details.delta.dy;
            controller.updatePullUpDistance(newDistance);
          },
          onVerticalDragEnd: (_) => controller.onPointerReleased(),
          onVerticalDragCancel: () => controller.onPointerReleased(),
          child: Container(
            width: PageConstants.a4Width,
            padding: const EdgeInsets.symmetric(vertical: 24.0),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: CustomPaint(
                    painter: _CircumferenceProgressPainter(
                      pullActivationRatio: pullRatio,
                      circumferenceProgress: ringProgress,
                      isCompleted: controller.hasUnlockedInCurrentGesture,
                    ),
                    child: Center(
                      child: Icon(
                        controller.hasUnlockedInCurrentGesture
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                        color: ringProgress > 0
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF64748B),
                        size: 26,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  controller.hasUnlockedInCurrentGesture
                      ? 'Pagina $nextPageNumber sbloccata!'
                      : (controller.isHoldThresholdReached
                          ? 'Tieni premuto per sbloccare Pagina $nextPageNumber... ${(ringProgress * 100).round()}%'
                          : 'Trascina verso l\'alto e tieni premuto per sbloccare Pagina $nextPageNumber'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: ringProgress > 0
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: ringProgress > 0
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Disegna il contorno della circonferenza che si carica progressivamente
/// da 0° a 360° mentre l'utente tiene premuto.
class _CircumferenceProgressPainter extends CustomPainter {
  final double pullActivationRatio;
  final double circumferenceProgress;
  final bool isCompleted;

  _CircumferenceProgressPainter({
    required this.pullActivationRatio,
    required this.circumferenceProgress,
    required this.isCompleted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 4.0;

    // 1. Contorno guida di sfondo della circonferenza
    final trackPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withOpacity(0.4 + 0.6 * pullActivationRatio)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, trackPaint);

    // 2. Contorno attivo della circonferenza che si carica tenendo premuto
    if (circumferenceProgress > 0.0 || isCompleted) {
      final progressPaint = Paint()
        ..color = isCompleted
            ? const Color(0xFF16A34A)
            : const Color(0xFF2563EB)
        ..strokeWidth = 4.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final sweepAngle = 2 * math.pi * (isCompleted ? 1.0 : circumferenceProgress);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // Parte dalle ore 12 in alto
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CircumferenceProgressPainter oldDelegate) {
    return oldDelegate.pullActivationRatio != pullActivationRatio ||
        oldDelegate.circumferenceProgress != circumferenceProgress ||
        oldDelegate.isCompleted != isCompleted;
  }
}

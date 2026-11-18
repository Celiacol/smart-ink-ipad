import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/commands/command_manager.dart';
import '../../core/commands/document_command.dart';
import '../../core/constants/page_constants.dart';
import '../../core/models/page_model.dart';
import '../tools/canvas_tool_handler.dart';
import 'a4_page_painter.dart';
import 'page_unlock_ring_indicator.dart';

/// Vista principale multi-pagina che mostra i fogli A4 impilati verticalmente
/// e il meccanismo "Pull-Up & Hold" con circonferenza di caricamento in fondo
/// all'ultima pagina.
class PaginatedNotebookView extends StatefulWidget {
  final CommandManager commandManager;
  final CanvasToolHandler activeTool;

  /// Se `false` (default su tablet con penna), solo la penna (`PointerDeviceKind.stylus`)
  /// scrive sul foglio mentre il dito serve per scorrere la pagina e sbloccare
  /// la pagina successiva. Se `true`, anche il dito o il mouse possono scrivere.
  final bool allowFingerDrawing;

  const PaginatedNotebookView({
    super.key,
    required this.commandManager,
    required this.activeTool,
    this.allowFingerDrawing = true,
  });

  @override
  State<PaginatedNotebookView> createState() => _PaginatedNotebookViewState();
}

class _PaginatedNotebookViewState extends State<PaginatedNotebookView> {
  final TransformationController _zoomController = TransformationController();
  late final PullUpUnlockController _unlockController;

  /// Pointers touch (dita) attualmente appoggiati sullo schermo (per distinguere 1 dito vs 2 dita Pinch-to-Zoom).
  final Set<int> _activeTouchPointers = {};

  /// Pointer attivo che sta attualmente scrivendo sul foglio.
  int? _activeDrawingPointerId;
  bool _isStylusActive = false;
  bool _didCenterInitialViewport = false;

  @override
  void initState() {
    super.initState();
    _unlockController = PullUpUnlockController(
      onPageUnlocked: _handleUnlockNextPage,
    );
  }

  void _handleUnlockNextPage() {
    widget.commandManager.executeCommand(AddPageCommand());
    // Dopo aver sbloccato la nuova pagina, sposta dolcemente la visuale per mostrarla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _zoomController.value.clone();
      final scale = current.getMaxScaleOnAxis();
      current.translate(0.0, -240.0 / scale);
      _zoomController.value = current;
    });
  }

  @override
  void dispose() {
    _unlockController.dispose();
    _zoomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_didCenterInitialViewport && constraints.maxWidth > PageConstants.a4Width) {
          _didCenterInitialViewport = true;
          final dx = (constraints.maxWidth - (PageConstants.a4Width + 32.0)) / 2.0;
          _zoomController.value = Matrix4.translationValues(dx, 0.0, 0.0);
        }

        return AnimatedBuilder(
          animation: widget.commandManager,
          builder: (context, _) {
            final pages = widget.commandManager.state.pages;
            // Blocca pan dello sfondo solo mentre la penna scrive o mentre si disegna con 1 dito;
            // con 2 dita (Pinch-to-Zoom) è SEMPRE abilitato!
            final lockPanForDrawing = _isStylusActive ||
                (widget.allowFingerDrawing && _activeTouchPointers.length == 1);

            return InteractiveViewer(
              transformationController: _zoomController,
              constrained: false,
              boundaryMargin: const EdgeInsets.symmetric(
                horizontal: 320.0,
                vertical: 240.0,
              ),
              minScale: 0.5,
              maxScale: 3.0,
              panEnabled: !lockPanForDrawing,
              scaleEnabled: !_isStylusActive,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 28.0,
                  horizontal: 16.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < pages.length; i++) ...[
                      _buildSingleA4Sheet(pages[i], pages.length),
                      if (i < pages.length - 1)
                        const SizedBox(height: PageConstants.interPageSpacing),
                    ],
                    // In fondo all'ultima pagina: indicatore con circonferenza di sblocco
                    PageUnlockRingIndicator(
                      controller: _unlockController,
                      nextPageNumber: pages.length + 1,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSingleA4Sheet(PageModel page, int totalPages) {
    return Container(
      width: PageConstants.a4Width,
      height: PageConstants.a4Height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4.0),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F0F172A),
            blurRadius: 16.0,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.0),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _onPointerDown(event, page.pageIndex),
          onPointerMove: (event) => _onPointerMove(event, page.pageIndex),
          onPointerUp: (event) => _onPointerUp(event, page.pageIndex),
          onPointerCancel: (event) => _onPointerCancel(event),
          child: CustomPaint(
            size: const Size(PageConstants.a4Width, PageConstants.a4Height),
            painter: A4PagePainter(
              page: page,
              totalPages: totalPages,
              activeTool: widget.activeTool,
            ),
          ),
        ),
      ),
    );
  }

  bool _isStylus(PointerEvent event) {
    return event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
  }

  bool _isPalmRejectableTouch(PointerEvent event) {
    // Se il raggio di contatto del tocco è grande (palmo poggiato sullo schermo), lo ignoriamo
    return event.kind == PointerDeviceKind.touch && event.radiusMajor > 22.0;
  }

  CanvasPointerEvent _toA4Event(PointerEvent event, int pageIndex) {
    final clampedX = event.localPosition.dx.clamp(0.0, PageConstants.a4Width);
    final clampedY = event.localPosition.dy.clamp(0.0, PageConstants.a4Height);
    return CanvasPointerEvent(
      pageIndex: pageIndex,
      a4Position: Offset(clampedX, clampedY),
      pressure: event.pressure > 0 ? event.pressure : 0.5,
      timestampMs: event.timeStamp.inMilliseconds,
    );
  }

  void _onPointerDown(PointerDownEvent event, int pageIndex) {
    if (_isStylus(event)) {
      setState(() {
        _isStylusActive = true;
        _activeDrawingPointerId = event.pointer;
        widget.activeTool.onPointerDown(
          _toA4Event(event, pageIndex),
          widget.commandManager,
        );
      });
      return;
    }

    if (_isPalmRejectableTouch(event) || _isStylusActive) return;

    if (event.kind == PointerDeviceKind.touch) {
      _activeTouchPointers.add(event.pointer);
      // Se un secondo dito tocca lo schermo (Pinch-to-Zoom), annulliamo il tratto in corso!
      if (_activeTouchPointers.length >= 2) {
        if (_activeDrawingPointerId != null) {
          setState(() {
            _activeDrawingPointerId = null;
            widget.activeTool.cancelActiveGesture();
          });
        }
        return;
      }
    }

    if (!widget.allowFingerDrawing) return;

    setState(() {
      _activeDrawingPointerId = event.pointer;
      widget.activeTool.onPointerDown(
        _toA4Event(event, pageIndex),
        widget.commandManager,
      );
    });
  }

  void _onPointerMove(PointerMoveEvent event, int pageIndex) {
    if (event.pointer != _activeDrawingPointerId) return;
    if (!_isStylus(event) && _activeTouchPointers.length >= 2) return;

    setState(() {
      widget.activeTool.onPointerMove(
        _toA4Event(event, pageIndex),
        widget.commandManager,
      );
    });
  }

  void _onPointerUp(PointerUpEvent event, int pageIndex) {
    _activeTouchPointers.remove(event.pointer);
    if (event.pointer != _activeDrawingPointerId) return;

    setState(() {
      _activeDrawingPointerId = null;
      if (_isStylus(event)) {
        _isStylusActive = false;
      }
      widget.activeTool.onPointerUp(
        _toA4Event(event, pageIndex),
        widget.commandManager,
      );
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activeTouchPointers.remove(event.pointer);
    if (event.pointer == _activeDrawingPointerId) {
      setState(() {
        _activeDrawingPointerId = null;
        _isStylusActive = false;
        widget.activeTool.cancelActiveGesture();
      });
    }
  }
}

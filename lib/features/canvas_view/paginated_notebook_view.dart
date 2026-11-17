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
  final ScrollController _scrollController = ScrollController();
  final TransformationController _zoomController = TransformationController();
  late final PullUpUnlockController _unlockController;

  /// Pointers touch (dita) attualmente appoggiati sullo schermo (per distinguere 1 dito vs 2 dita Pinch-to-Zoom).
  final Set<int> _activeTouchPointers = {};

  /// Pointer attivo che sta attualmente scrivendo sul foglio.
  int? _activeDrawingPointerId;
  bool _isStylusActive = false;

  @override
  void initState() {
    super.initState();
    _unlockController = PullUpUnlockController(
      onPageUnlocked: _handleUnlockNextPage,
    );
  }

  void _handleUnlockNextPage() {
    widget.commandManager.executeCommand(AddPageCommand());
    // Dopo aver sbloccato la nuova pagina, scorre dolcemente per mostrarla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          (_scrollController.offset + 260.0)
              .clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _unlockController.dispose();
    _zoomController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.commandManager,
      builder: (context, _) {
        final pages = widget.commandManager.state.pages;
        // Blocca lo scorrimento verticale quando la penna sta scrivendo o quando si disegna a 1 dito
        final lockScrollForDrawing = _isStylusActive ||
            (widget.allowFingerDrawing && _activeTouchPointers.length == 1);

        return InteractiveViewer(
          transformationController: _zoomController,
          minScale: 0.5,
          maxScale: 3.0,
          panEnabled: !lockScrollForDrawing,
          scaleEnabled: !_isStylusActive,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleOverscrollForPageUnlock,
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: lockScrollForDrawing
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
              padding: const EdgeInsets.symmetric(vertical: 28.0, horizontal: 16.0),
              child: Center(
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
            ),
          ),
        );
      },
    );
  }

  /// Intercetta il trascinamento verso l'alto oltre il fondo dell'ultima pagina
  /// (overscroll inferiore) per alimentare la circonferenza di sblocco pagina.
  bool _handleOverscrollForPageUnlock(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      final overscrollBottom = metrics.pixels - metrics.maxScrollExtent;
      if (overscrollBottom > 0) {
        _unlockController.updatePullUpDistance(overscrollBottom);
      } else if (_unlockController.currentPullDistance > 0) {
        _unlockController.updatePullUpDistance(0);
      }
    } else if (notification is ScrollEndNotification) {
      _unlockController.onPointerReleased();
    }
    return false;
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

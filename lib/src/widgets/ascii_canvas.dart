import "package:flutter/material.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";

import "../services/layout_engine.dart";
import "../state/app_controller.dart";

const TextStyle _canvasTextStyle = TextStyle(
  fontFamily: "monospace",
  fontFamilyFallback: <String>[
    "Consolas",
    "Courier New",
    "Menlo",
    "Monaco",
    "Liberation Mono",
  ],
  fontSize: 13,
  color: Color(0xFFF7F7F7),
  height: 1.0,
);

class AsciiCanvas extends StatefulWidget {
  const AsciiCanvas({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  State<AsciiCanvas> createState() => _AsciiCanvasState();
}

class _AsciiCanvasState extends State<AsciiCanvas> {
  double _dragRemainderX = 0;
  double _dragRemainderY = 0;
  final FocusNode _canvasFocusNode = FocusNode();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  _ResizeHandle? _activeResizeHandle;
  bool _dragActive = false;
  bool _panActive = false;

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _canvasFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final text = widget.controller.asciiOutput;
        final selected = _selectedLayoutNode(widget.controller);
        final boardRegions = widget.controller.asciiBoardRegions;
        final zoom = widget.controller.canvasZoom;
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        final scaledTextStyle = _canvasTextStyle.copyWith(
          fontSize: (_canvasTextStyle.fontSize ?? 13) * zoom,
        );
        final metrics = _measureCell(scaledTextStyle);
        final charWidth = _snapToDevicePixel(metrics.width, devicePixelRatio);
        final charHeight = _snapToDevicePixel(metrics.height, devicePixelRatio);
        final lines = text.split("\n");
        var renderWidthChars = 0;
        for (final line in lines) {
          if (line.length > renderWidthChars) {
            renderWidthChars = line.length;
          }
        }
        if (renderWidthChars < 1) {
          renderWidthChars = 1;
        }
        final renderHeightChars = lines.isEmpty ? 1 : lines.length;
        final canvasWidth = renderWidthChars * charWidth;
        final canvasHeight = renderHeightChars * charHeight;

        final surface = Container(
          color: const Color(0xFF0E1511),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.all(8),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerSignal: (event) {
              if (event is! PointerScrollEvent) {
                return;
              }
              final x = (event.localPosition.dx / charWidth).floor();
              final y = (event.localPosition.dy / charHeight).floor();
              if (!_isEmptyAsciiCell(text, x, y)) {
                return;
              }

              GestureBinding.instance.pointerSignalResolver.register(
                event,
                (signalEvent) {
                  final scroll = signalEvent as PointerScrollEvent;
                  if (scroll.scrollDelta.dy < 0) {
                    widget.controller.zoomInCanvasView();
                  } else if (scroll.scrollDelta.dy > 0) {
                    widget.controller.zoomOutCanvasView();
                  }
                },
              );
            },
            onPointerDown: (event) {
              if ((event.buttons & kPrimaryMouseButton) == 0) {
                return;
              }
              _canvasFocusNode.requestFocus();
              final x = (event.localPosition.dx / charWidth).floor();
              final y = (event.localPosition.dy / charHeight).floor();
              widget.controller.selectNodeAt(x, y);
              if (widget.controller.selectedNode == null) {
                _panActive = true;
                _dragActive = false;
                _activeResizeHandle = null;
                widget.controller.endPointerAdjustSession();
                setState(() {});
                return;
              }

              final selectedAfterPick = _selectedLayoutNode(widget.controller);
              _activeResizeHandle = null;

              if (widget.controller.pointerEditMode == PointerEditMode.resize &&
                  selectedAfterPick != null) {
                final selectedRect = _selectionRectPixels(
                    selectedAfterPick.rect, charWidth, charHeight);
                _activeResizeHandle = _hitTestResizeHandle(
                  event.localPosition,
                  selectedRect,
                  charWidth,
                  charHeight,
                );
              }

              final shouldStartDrag =
                  widget.controller.pointerEditMode == PointerEditMode.move
                      ? widget.controller.selectedNode != null
                      : _activeResizeHandle != null;

              if (shouldStartDrag) {
                widget.controller.beginPointerAdjustSession();
              }
              _panActive = false;
              _dragActive = shouldStartDrag;
              _dragRemainderX = 0;
              _dragRemainderY = 0;
              setState(() {});
            },
            onPointerMove: (event) {
              if ((event.buttons & kPrimaryMouseButton) == 0) {
                return;
              }
              if (_panActive) {
                _panViewportBy(event.delta);
                return;
              }
              if (!_dragActive) {
                return;
              }
              if (widget.controller.selectedNode == null) {
                return;
              }
              _dragRemainderX += event.delta.dx;
              _dragRemainderY += event.delta.dy;

              while (_dragRemainderX.abs() >= charWidth) {
                final step = _dragRemainderX > 0 ? 1 : -1;
                if (_dragRemainderX > 0) {
                  if (widget.controller.pointerEditMode ==
                      PointerEditMode.move) {
                    widget.controller.moveSelected(1, 0, captureUndo: false);
                  } else {
                    _applyResizeStep(stepX: step);
                  }
                  _dragRemainderX -= charWidth;
                } else {
                  if (widget.controller.pointerEditMode ==
                      PointerEditMode.move) {
                    widget.controller.moveSelected(-1, 0, captureUndo: false);
                  } else {
                    _applyResizeStep(stepX: step);
                  }
                  _dragRemainderX += charWidth;
                }
              }
              while (_dragRemainderY.abs() >= charHeight) {
                final step = _dragRemainderY > 0 ? 1 : -1;
                if (_dragRemainderY > 0) {
                  if (widget.controller.pointerEditMode ==
                      PointerEditMode.move) {
                    widget.controller.moveSelected(0, 1, captureUndo: false);
                  } else {
                    _applyResizeStep(stepY: step);
                  }
                  _dragRemainderY -= charHeight;
                } else {
                  if (widget.controller.pointerEditMode ==
                      PointerEditMode.move) {
                    widget.controller.moveSelected(0, -1, captureUndo: false);
                  } else {
                    _applyResizeStep(stepY: step);
                  }
                  _dragRemainderY += charHeight;
                }
              }
            },
            onPointerUp: (_) {
              if (_dragActive) {
                widget.controller.endPointerAdjustSession();
              }
              _dragActive = false;
              _panActive = false;
              _activeResizeHandle = null;
              setState(() {});
            },
            onPointerCancel: (_) {
              if (_dragActive) {
                widget.controller.endPointerAdjustSession();
              }
              _dragActive = false;
              _panActive = false;
              _activeResizeHandle = null;
              setState(() {});
            },
            child: CustomPaint(
              size: Size(canvasWidth, canvasHeight),
              painter: _AsciiPainter(
                ascii: text,
                textStyle: scaledTextStyle,
                charWidth: charWidth,
                charHeight: charHeight,
                devicePixelRatio: devicePixelRatio,
                boardRegions: boardRegions,
                selected: selected?.rect,
                showResizeHandles: widget.controller.pointerEditMode ==
                        PointerEditMode.resize &&
                    selected != null,
                activeHandle: _activeResizeHandle,
              ),
            ),
          ),
        );

        return Focus(
          focusNode: _canvasFocusNode,
          onKeyEvent: (node, event) => _onKeyEvent(event),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Scrollbar(
              controller: _horizontalScrollController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: Scrollbar(
                  controller: _verticalScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.vertical,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    child: surface,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  LayoutNode? _selectedLayoutNode(AppController controller) {
    final selectedId = controller.selectedNodeId;
    if (selectedId == null || selectedId.isEmpty) {
      return null;
    }
    final exact = controller.layoutById[selectedId];
    if (exact != null) {
      return exact;
    }
    for (final entry in controller.layoutById.entries) {
      if (entry.key.startsWith("${selectedId}__")) {
        return entry.value;
      }
    }
    return null;
  }

  _CellMetrics _measureCell(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: "M", style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    final rawWidth = painter.size.width;
    final rawHeight = painter.preferredLineHeight;
    final width = rawWidth <= 0 ? 8.0 : rawWidth;
    final height = rawHeight <= 0 ? 16.0 : rawHeight;
    return _CellMetrics(width: width, height: height);
  }

  double _snapToDevicePixel(double value, double dpr) {
    if (value <= 0 || dpr <= 0) {
      return value <= 0 ? 1.0 : value;
    }
    final snapped = (value * dpr).roundToDouble() / dpr;
    return snapped <= 0 ? 1.0 : snapped;
  }

  bool _isEmptyAsciiCell(String ascii, int x, int y) {
    final lines = ascii.split("\n");
    if (y < 0 || y >= lines.length) {
      return true;
    }
    final line = lines[y];
    if (x < 0 || x >= line.length) {
      return true;
    }
    return line[x] == " ";
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyQ) {
      widget.controller.setPointerEditMode(PointerEditMode.move);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      widget.controller.setPointerEditMode(PointerEditMode.resize);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _applyResizeStep({int stepX = 0, int stepY = 0}) {
    final handle = _activeResizeHandle;
    if (handle == null) {
      return;
    }

    var dLeft = 0;
    var dRight = 0;
    var dTop = 0;
    var dBottom = 0;

    if (stepX != 0) {
      if (handle.affectsLeft) {
        dLeft = stepX;
      }
      if (handle.affectsRight) {
        dRight = stepX;
      }
    }
    if (stepY != 0) {
      if (handle.affectsTop) {
        dTop = stepY;
      }
      if (handle.affectsBottom) {
        dBottom = stepY;
      }
    }

    if (dLeft == 0 && dRight == 0 && dTop == 0 && dBottom == 0) {
      return;
    }

    widget.controller.resizeSelectedByEdges(
      dLeft: dLeft,
      dTop: dTop,
      dRight: dRight,
      dBottom: dBottom,
      captureUndo: false,
    );
  }

  _ResizeHandle? _hitTestResizeHandle(
    Offset point,
    Rect selectedRect,
    double charWidth,
    double charHeight,
  ) {
    final centers = _handleCenters(selectedRect);
    final hitHalf = _handleHitHalf(charWidth, charHeight);
    for (final entry in centers.entries) {
      final dx = (point.dx - entry.value.dx).abs();
      final dy = (point.dy - entry.value.dy).abs();
      if (dx <= hitHalf && dy <= hitHalf) {
        return entry.key;
      }
    }
    return null;
  }

  void _panViewportBy(Offset delta) {
    _jumpBy(_horizontalScrollController, -delta.dx);
    _jumpBy(_verticalScrollController, -delta.dy);
  }

  void _jumpBy(ScrollController controller, double delta) {
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final current = controller.offset;
    var target = current + delta;
    if (target < position.minScrollExtent) {
      target = position.minScrollExtent;
    }
    if (target > position.maxScrollExtent) {
      target = position.maxScrollExtent;
    }
    if ((target - current).abs() < 0.01) {
      return;
    }
    controller.jumpTo(target);
  }
}

class _AsciiPainter extends CustomPainter {
  _AsciiPainter({
    required this.ascii,
    required this.textStyle,
    required this.charWidth,
    required this.charHeight,
    required this.devicePixelRatio,
    required this.boardRegions,
    this.selected,
    required this.showResizeHandles,
    this.activeHandle,
  });

  final String ascii;
  final TextStyle textStyle;
  final double charWidth;
  final double charHeight;
  final double devicePixelRatio;
  final List<RectI> boardRegions;
  final RectI? selected;
  final bool showResizeHandles;
  final _ResizeHandle? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = ascii.split("\n");
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final snap = _snapper(devicePixelRatio);

    final gridPaint = Paint()
      ..color = const Color(0x1EFFFFFF)
      ..strokeWidth = 1
      ..isAntiAlias = false;
    final boardBorderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x4DFFFFFF)
      ..isAntiAlias = false;

    if (boardRegions.isEmpty) {
      for (var x = 0.0; x <= size.width; x += charWidth) {
        final sx = snap(x);
        canvas.drawLine(
          Offset(sx, 0),
          Offset(sx, snap(size.height)),
          gridPaint,
        );
      }
      for (var y = 0.0; y <= size.height; y += charHeight) {
        final sy = snap(y);
        canvas.drawLine(
          Offset(0, sy),
          Offset(snap(size.width), sy),
          gridPaint,
        );
      }
    } else {
      for (final board in boardRegions) {
        final left = snap(board.x * charWidth);
        final top = snap(board.y * charHeight);
        final width = snap(board.width * charWidth);
        final height = snap(board.height * charHeight);

        for (var i = 0; i <= board.width; i++) {
          final x = snap(left + i * charWidth);
          canvas.drawLine(
              Offset(x, top), Offset(x, snap(top + height)), gridPaint);
        }
        for (var i = 0; i <= board.height; i++) {
          final y = snap(top + i * charHeight);
          canvas.drawLine(
            Offset(left, y),
            Offset(snap(left + width), y),
            gridPaint,
          );
        }

        canvas.drawRect(
          Rect.fromLTWH(left, top, width, height).deflate(0.5),
          boardBorderPaint,
        );
      }
    }

    for (var i = 0; i < lines.length; i++) {
      painter.text = TextSpan(text: lines[i], style: textStyle);
      painter.layout();
      painter.paint(canvas, Offset(0, snap(i * charHeight)));
    }

    if (selected != null) {
      final rectPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE7C04D);
      final selectionRect =
          _selectionRectPixels(selected!, charWidth, charHeight);
      canvas.drawRect(selectionRect, rectPaint);
      if (showResizeHandles) {
        _drawResizeHandles(canvas, selectionRect);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AsciiPainter oldDelegate) {
    return ascii != oldDelegate.ascii ||
        selected != oldDelegate.selected ||
        boardRegions != oldDelegate.boardRegions ||
        textStyle != oldDelegate.textStyle ||
        charWidth != oldDelegate.charWidth ||
        charHeight != oldDelegate.charHeight ||
        showResizeHandles != oldDelegate.showResizeHandles ||
        activeHandle != oldDelegate.activeHandle;
  }

  double Function(double) _snapper(double dpr) {
    if (dpr <= 0) {
      return (v) => v;
    }
    return (v) => (v * dpr).roundToDouble() / dpr;
  }

  void _drawResizeHandles(Canvas canvas, Rect selectionRect) {
    final centers = _handleCenters(selectionRect);
    final size = _handleVisualSize(charWidth, charHeight);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF3A2E00);

    for (final entry in centers.entries) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = entry.key == activeHandle
            ? const Color(0xFFFFE082)
            : const Color(0xFFE7C04D);

      final handleRect = Rect.fromCenter(
        center: entry.value,
        width: size,
        height: size,
      );
      canvas.drawRect(handleRect, fillPaint);
      canvas.drawRect(handleRect, strokePaint);
    }
  }
}

class _CellMetrics {
  const _CellMetrics({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;
}

enum _ResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

extension on _ResizeHandle {
  bool get affectsLeft {
    return this == _ResizeHandle.topLeft ||
        this == _ResizeHandle.left ||
        this == _ResizeHandle.bottomLeft;
  }

  bool get affectsRight {
    return this == _ResizeHandle.topRight ||
        this == _ResizeHandle.right ||
        this == _ResizeHandle.bottomRight;
  }

  bool get affectsTop {
    return this == _ResizeHandle.topLeft ||
        this == _ResizeHandle.top ||
        this == _ResizeHandle.topRight;
  }

  bool get affectsBottom {
    return this == _ResizeHandle.bottomLeft ||
        this == _ResizeHandle.bottom ||
        this == _ResizeHandle.bottomRight;
  }
}

Rect _selectionRectPixels(RectI selected, double charWidth, double charHeight) {
  final left = selected.x * charWidth;
  final top = selected.y * charHeight;
  final width = selected.width * charWidth;
  final height = selected.height * charHeight;
  return Rect.fromLTWH(left, top, width, height).deflate(0.5);
}

Map<_ResizeHandle, Offset> _handleCenters(Rect rect) {
  final centerX = rect.left + rect.width / 2;
  final centerY = rect.top + rect.height / 2;
  return <_ResizeHandle, Offset>{
    _ResizeHandle.topLeft: Offset(rect.left, rect.top),
    _ResizeHandle.top: Offset(centerX, rect.top),
    _ResizeHandle.topRight: Offset(rect.right, rect.top),
    _ResizeHandle.right: Offset(rect.right, centerY),
    _ResizeHandle.bottomRight: Offset(rect.right, rect.bottom),
    _ResizeHandle.bottom: Offset(centerX, rect.bottom),
    _ResizeHandle.bottomLeft: Offset(rect.left, rect.bottom),
    _ResizeHandle.left: Offset(rect.left, centerY),
  };
}

double _handleVisualSize(double charWidth, double charHeight) {
  final base = (charWidth < charHeight ? charWidth : charHeight) * 0.55;
  if (base < 6) {
    return 6;
  }
  if (base > 12) {
    return 12;
  }
  return base;
}

double _handleHitHalf(double charWidth, double charHeight) {
  final size = _handleVisualSize(charWidth, charHeight);
  final half = size / 2 + 2;
  if (half < 4) {
    return 4;
  }
  if (half > 10) {
    return 10;
  }
  return half;
}

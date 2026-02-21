import "package:flutter/material.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";

import "../services/layout_engine.dart";
import "../state/app_controller.dart";

const TextStyle _canvasTextStyle = TextStyle(
  fontFamily: "Consolas",
  fontFamilyFallback: <String>["Courier New", "monospace"],
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
  _ResizeHandle? _activeResizeHandle;
  bool _dragActive = false;

  @override
  void dispose() {
    _canvasFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final canvas = widget.controller.project.canvas;
        final text = widget.controller.asciiOutput;
        final selected = _selectedLayoutNode(widget.controller);
        final metrics = _measureCell(_canvasTextStyle);
        final charWidth = metrics.width;
        final charHeight = metrics.height;

        final surface = Container(
          color: const Color(0xFF0E1511),
          alignment: Alignment.topLeft,
          padding: const EdgeInsets.all(8),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) {
              if ((event.buttons & kPrimaryMouseButton) == 0) {
                return;
              }
              _canvasFocusNode.requestFocus();
              final x = (event.localPosition.dx / charWidth).floor();
              final y = (event.localPosition.dy / charHeight).floor();
              widget.controller.selectNodeAt(x, y);

              final selectedAfterPick = _selectedLayoutNode(widget.controller);
              _activeResizeHandle = null;

              if (widget.controller.pointerEditMode == PointerEditMode.resize &&
                  selectedAfterPick != null) {
                final selectedRect =
                    _selectionRectPixels(selectedAfterPick.rect, charWidth, charHeight);
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
              _dragActive = shouldStartDrag;
              _dragRemainderX = 0;
              _dragRemainderY = 0;
              setState(() {});
            },
            onPointerMove: (event) {
              if ((event.buttons & kPrimaryMouseButton) == 0) {
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
                  if (widget.controller.pointerEditMode == PointerEditMode.move) {
                    widget.controller.moveSelected(1, 0, captureUndo: false);
                  } else {
                    _applyResizeStep(stepX: step);
                  }
                  _dragRemainderX -= charWidth;
                } else {
                  if (widget.controller.pointerEditMode == PointerEditMode.move) {
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
                  if (widget.controller.pointerEditMode == PointerEditMode.move) {
                    widget.controller.moveSelected(0, 1, captureUndo: false);
                  } else {
                    _applyResizeStep(stepY: step);
                  }
                  _dragRemainderY -= charHeight;
                } else {
                  if (widget.controller.pointerEditMode == PointerEditMode.move) {
                    widget.controller.moveSelected(0, -1, captureUndo: false);
                  } else {
                    _applyResizeStep(stepY: step);
                  }
                  _dragRemainderY += charHeight;
                }
              }
            },
            onPointerUp: (_) {
              widget.controller.endPointerAdjustSession();
              _dragActive = false;
              _activeResizeHandle = null;
              setState(() {});
            },
            onPointerCancel: (_) {
              widget.controller.endPointerAdjustSession();
              _dragActive = false;
              _activeResizeHandle = null;
              setState(() {});
            },
            child: CustomPaint(
              size: Size(
                canvas.width * charWidth,
                canvas.height * charHeight,
              ),
              painter: _AsciiPainter(
                ascii: text,
                textStyle: _canvasTextStyle,
                charWidth: charWidth,
                charHeight: charHeight,
                selected: selected?.rect,
                showResizeHandles: widget.controller.pointerEditMode == PointerEditMode.resize &&
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: surface,
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
    final rawHeight = painter.size.height;
    final width = rawWidth <= 0 ? 8.0 : rawWidth;
    final height = rawHeight <= 0 ? 16.0 : rawHeight;
    return _CellMetrics(width: width, height: height);
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
}

class _AsciiPainter extends CustomPainter {
  _AsciiPainter({
    required this.ascii,
    required this.textStyle,
    required this.charWidth,
    required this.charHeight,
    this.selected,
    required this.showResizeHandles,
    this.activeHandle,
  });

  final String ascii;
  final TextStyle textStyle;
  final double charWidth;
  final double charHeight;
  final RectI? selected;
  final bool showResizeHandles;
  final _ResizeHandle? activeHandle;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = ascii.split("\n");
    final painter = TextPainter(textDirection: TextDirection.ltr);

    final gridPaint = Paint()
      ..color = const Color(0x1EFFFFFF)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += charWidth) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += charHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < lines.length; i++) {
      painter.text = TextSpan(text: lines[i], style: textStyle);
      painter.layout();
      painter.paint(canvas, Offset(0, i * charHeight));
    }

    if (selected != null) {
      final rectPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE7C04D);
      final selectionRect = _selectionRectPixels(selected!, charWidth, charHeight);
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
        textStyle != oldDelegate.textStyle ||
        charWidth != oldDelegate.charWidth ||
        charHeight != oldDelegate.charHeight ||
        showResizeHandles != oldDelegate.showResizeHandles ||
        activeHandle != oldDelegate.activeHandle;
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

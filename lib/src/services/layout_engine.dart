import "../model/diagnostic.dart";
import "../model/ui_node.dart";

class RectI {
  const RectI({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width - 1;
  int get bottom => y + height - 1;

  bool contains(int px, int py) {
    return px >= x && py >= y && px <= right && py <= bottom;
  }

  RectI deflate(int amount) {
    if (width - amount * 2 <= 0 || height - amount * 2 <= 0) {
      return const RectI(x: 0, y: 0, width: 0, height: 0);
    }
    return RectI(
      x: x + amount,
      y: y + amount,
      width: width - amount * 2,
      height: height - amount * 2,
    );
  }
}

class LayoutNode {
  LayoutNode({
    required this.id,
    required this.kind,
    required this.rect,
    required this.props,
    required this.styleRef,
    List<LayoutNode>? children,
  }) : children = children ?? <LayoutNode>[];

  final String id;
  final NodeKind kind;
  final RectI rect;
  final Map<String, dynamic> props;
  final String? styleRef;
  final List<LayoutNode> children;
}

class LayoutResult {
  LayoutResult({
    required this.nodes,
    required this.byId,
    List<Diagnostic>? diagnostics,
  }) : diagnostics = diagnostics ?? <Diagnostic>[];

  final List<LayoutNode> nodes;
  final Map<String, LayoutNode> byId;
  final List<Diagnostic> diagnostics;
}

class LayoutEngine {
  LayoutResult compute({
    required List<UiNode> nodes,
    required int canvasWidth,
    required int canvasHeight,
  }) {
    final diagnostics = <Diagnostic>[];
    final byId = <String, LayoutNode>{};
    final rootRect = RectI(x: 0, y: 0, width: canvasWidth, height: canvasHeight);
    final laidOut = _layoutNodes(nodes, rootRect, diagnostics, byId);
    return LayoutResult(nodes: laidOut, byId: byId, diagnostics: diagnostics);
  }

  List<LayoutNode> _layoutNodes(
    List<UiNode> nodes,
    RectI parent,
    List<Diagnostic> diagnostics,
    Map<String, LayoutNode> byId,
  ) {
    final output = <LayoutNode>[];
    var remain = parent;

    for (final node in nodes) {
      final rect = _rectForNode(node, parent, remain);
      final clipped = _intersect(rect, parent);

      if (clipped.width <= 0 || clipped.height <= 0) {
        diagnostics.add(
          Diagnostic.warning(
            "layout.outside_canvas",
            "Node '${node.id}' is outside visible bounds.",
            path: "node:${node.id}",
          ),
        );
        continue;
      }

      remain = _consumeDock(node, remain, clipped);
      final childParent = _contentRect(node.kind, clipped);
      final children = _layoutChildren(node, childParent, diagnostics, byId);

      final layoutNode = LayoutNode(
        id: node.id,
        kind: node.kind,
        rect: clipped,
        props: Map<String, dynamic>.from(node.props),
        styleRef: node.styleRef,
        children: children,
      );

      byId[node.id] = layoutNode;
      output.add(layoutNode);
    }
    return output;
  }

  List<LayoutNode> _layoutChildren(
    UiNode node,
    RectI contentRect,
    List<Diagnostic> diagnostics,
    Map<String, LayoutNode> byId,
  ) {
    if (contentRect.width <= 0 || contentRect.height <= 0) {
      return <LayoutNode>[];
    }

    switch (node.kind) {
      case NodeKind.stack:
        return _layoutStackChildren(node.children, contentRect, diagnostics, byId, node.id, node.props);
      case NodeKind.grid:
        return _layoutGridChildren(node.children, contentRect, diagnostics, byId, node.id, node.props);
      case NodeKind.box:
      case NodeKind.label:
      case NodeKind.line:
      case NodeKind.input:
      case NodeKind.button:
      case NodeKind.tab:
      case NodeKind.list:
      case NodeKind.popup:
      case NodeKind.toggle:
      case NodeKind.combo:
        return _layoutNodes(node.children, contentRect, diagnostics, byId);
    }
  }

  List<LayoutNode> _layoutStackChildren(
    List<UiNode> children,
    RectI contentRect,
    List<Diagnostic> diagnostics,
    Map<String, LayoutNode> byId,
    String parentId,
    Map<String, dynamic> props,
  ) {
    if (children.isEmpty) {
      return <LayoutNode>[];
    }

    final direction = (props["direction"] ?? "vertical").toString().toLowerCase();
    final spacing = _toInt(props["spacing"], fallback: 0);
    final horizontal = direction == "horizontal";
    final totalSpan = horizontal ? contentRect.width : contentRect.height;
    final freeSpan = _clampInt(totalSpan - ((children.length - 1) * spacing), 1, totalSpan);
    final chunk = children.isEmpty ? freeSpan : (freeSpan / children.length).floor();

    final output = <LayoutNode>[];
    var cursorX = contentRect.x;
    var cursorY = contentRect.y;

    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      final isLast = index == children.length - 1;
      final span = isLast
          ? (horizontal
              ? (contentRect.x + contentRect.width - cursorX)
              : (contentRect.y + contentRect.height - cursorY))
          : chunk;
      final rect = horizontal
          ? RectI(x: cursorX, y: contentRect.y, width: span, height: contentRect.height)
          : RectI(x: contentRect.x, y: cursorY, width: contentRect.width, height: span);
      final nodeRect = _intersect(rect, contentRect);

      final childChildren = _layoutChildren(child, _contentRect(child.kind, nodeRect), diagnostics, byId);
      final layoutNode = LayoutNode(
        id: child.id,
        kind: child.kind,
        rect: nodeRect,
        props: Map<String, dynamic>.from(child.props),
        styleRef: child.styleRef,
        children: childChildren,
      );
      byId[child.id] = layoutNode;
      output.add(layoutNode);

      if (horizontal) {
        cursorX += span + spacing;
      } else {
        cursorY += span + spacing;
      }
    }

    diagnostics.add(
      Diagnostic.info(
        "layout.stack",
        "Stack layout applied for '$parentId'.",
        path: "node:$parentId",
      ),
    );
    return output;
  }

  List<LayoutNode> _layoutGridChildren(
    List<UiNode> children,
    RectI contentRect,
    List<Diagnostic> diagnostics,
    Map<String, LayoutNode> byId,
    String parentId,
    Map<String, dynamic> props,
  ) {
    if (children.isEmpty) {
      return <LayoutNode>[];
    }

    final cols = _clampInt(_toInt(props["cols"], fallback: 2), 1, children.length);
    final rows = _clampInt(_toInt(props["rows"], fallback: (children.length / cols).ceil()), 1, children.length);
    final cellWidth = _clampInt((contentRect.width / cols).floor(), 1, contentRect.width);
    final cellHeight = _clampInt((contentRect.height / rows).floor(), 1, contentRect.height);

    final output = <LayoutNode>[];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final row = i ~/ cols;
      final col = i % cols;
      if (row >= rows) {
        diagnostics.add(
          Diagnostic.warning(
            "layout.grid_overflow",
            "Grid '$parentId' has more children than available cells; child '${child.id}' skipped.",
            path: "node:$parentId",
          ),
        );
        continue;
      }

      final x = contentRect.x + col * cellWidth;
      final y = contentRect.y + row * cellHeight;
      final width = col == cols - 1 ? (contentRect.x + contentRect.width - x) : cellWidth;
      final height = row == rows - 1 ? (contentRect.y + contentRect.height - y) : cellHeight;

      final rect = RectI(x: x, y: y, width: width, height: height);
      final childChildren = _layoutChildren(child, _contentRect(child.kind, rect), diagnostics, byId);
      final layoutNode = LayoutNode(
        id: child.id,
        kind: child.kind,
        rect: rect,
        props: Map<String, dynamic>.from(child.props),
        styleRef: child.styleRef,
        children: childChildren,
      );
      byId[child.id] = layoutNode;
      output.add(layoutNode);
    }

    diagnostics.add(
      Diagnostic.info(
        "layout.grid",
        "Grid layout applied for '$parentId' ($rows x $cols).",
        path: "node:$parentId",
      ),
    );
    return output;
  }

  RectI _rectForNode(UiNode node, RectI parent, RectI remain) {
    final dock = node.dock.toLowerCase();
    switch (dock) {
      case "top":
        return RectI(
          x: remain.x,
          y: remain.y,
          width: remain.width,
          height: _clampInt(node.height, 1, remain.height),
        );
      case "bottom":
        final h = _clampInt(node.height, 1, remain.height);
        return RectI(
          x: remain.x,
          y: remain.y + remain.height - h,
          width: remain.width,
          height: h,
        );
      case "left":
        return RectI(
          x: remain.x,
          y: remain.y,
          width: _clampInt(node.width, 1, remain.width),
          height: remain.height,
        );
      case "right":
        final w = _clampInt(node.width, 1, remain.width);
        return RectI(
          x: remain.x + remain.width - w,
          y: remain.y,
          width: w,
          height: remain.height,
        );
      case "fill":
        return remain;
      case "none":
      default:
        return RectI(
          x: parent.x + node.x,
          y: parent.y + node.y,
          width: node.width,
          height: node.height,
        );
    }
  }

  RectI _consumeDock(UiNode node, RectI remain, RectI allocated) {
    final dock = node.dock.toLowerCase();
    switch (dock) {
      case "top":
        return RectI(
          x: remain.x,
          y: _clampInt(allocated.y + allocated.height, remain.y, remain.y + remain.height),
          width: remain.width,
          height: _clampInt(remain.height - allocated.height, 0, remain.height),
        );
      case "bottom":
        return RectI(
          x: remain.x,
          y: remain.y,
          width: remain.width,
          height: _clampInt(remain.height - allocated.height, 0, remain.height),
        );
      case "left":
        return RectI(
          x: _clampInt(allocated.x + allocated.width, remain.x, remain.x + remain.width),
          y: remain.y,
          width: _clampInt(remain.width - allocated.width, 0, remain.width),
          height: remain.height,
        );
      case "right":
        return RectI(
          x: remain.x,
          y: remain.y,
          width: _clampInt(remain.width - allocated.width, 0, remain.width),
          height: remain.height,
        );
      case "fill":
      case "none":
      default:
        return remain;
    }
  }

  RectI _contentRect(NodeKind kind, RectI rect) {
    switch (kind) {
      case NodeKind.box:
      case NodeKind.button:
      case NodeKind.input:
      case NodeKind.tab:
      case NodeKind.list:
      case NodeKind.popup:
      case NodeKind.toggle:
      case NodeKind.combo:
      case NodeKind.stack:
      case NodeKind.grid:
        if (rect.width >= 3 && rect.height >= 3) {
          return rect.deflate(1);
        }
        return rect;
      case NodeKind.label:
      case NodeKind.line:
        return rect;
    }
  }

  RectI _intersect(RectI a, RectI b) {
    final left = a.x > b.x ? a.x : b.x;
    final top = a.y > b.y ? a.y : b.y;
    final right = a.right < b.right ? a.right : b.right;
    final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;

    if (right < left || bottom < top) {
      return const RectI(x: 0, y: 0, width: 0, height: 0);
    }
    return RectI(
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  int _clampInt(int value, int min, int max) {
    if (max < min) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}

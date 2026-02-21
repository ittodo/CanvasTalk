import "../model/canvas_config.dart";
import "../model/ui_node.dart";
import "layout_engine.dart";

class AsciiRenderer {
  String render({
    required CanvasConfig canvas,
    required List<LayoutNode> nodes,
  }) {
    final grid = List<List<String>>.generate(
      canvas.height,
      (_) => List<String>.filled(canvas.width, " "),
    );
    final charset = _charset(canvas.charset);

    void drawNode(LayoutNode node) {
      switch (node.kind) {
        case NodeKind.box:
          _drawBox(grid, node.rect, charset);
          final title = node.props["title"]?.toString();
          if (title != null && title.isNotEmpty && node.rect.width > 4) {
            _drawText(
              grid,
              node.rect.x + 2,
              node.rect.y,
              title,
              maxWidth: node.rect.width - 4,
            );
          }
          break;
        case NodeKind.label:
          final text = node.props["text"]?.toString() ?? node.id;
          _drawText(
            grid,
            node.rect.x,
            node.rect.y,
            text,
            maxWidth: node.rect.width,
          );
          break;
        case NodeKind.line:
          final orientation = (node.props["orientation"] ?? "horizontal").toString().toLowerCase();
          if (orientation == "vertical") {
            _drawVLine(grid, node.rect.x, node.rect.y, node.rect.height, charset.v);
          } else {
            _drawHLine(grid, node.rect.x, node.rect.y, node.rect.width, charset.h);
          }
          break;
        case NodeKind.stack:
        case NodeKind.grid:
        case NodeKind.input:
        case NodeKind.button:
        case NodeKind.tab:
        case NodeKind.list:
        case NodeKind.popup:
        case NodeKind.toggle:
        case NodeKind.combo:
          _drawBox(grid, node.rect, charset);
      }

      for (final child in node.children) {
        drawNode(child);
      }
    }

    for (final node in nodes) {
      drawNode(node);
    }

    return grid.map((line) => line.join()).join("\n");
  }

  _BoxCharset _charset(Charset charset) {
    if (charset == Charset.ascii) {
      return const _BoxCharset(
        tl: "+",
        tr: "+",
        bl: "+",
        br: "+",
        h: "-",
        v: "|",
      );
    }
    return const _BoxCharset(
      tl: "┌",
      tr: "┐",
      bl: "└",
      br: "┘",
      h: "─",
      v: "│",
    );
  }

  void _drawBox(List<List<String>> grid, RectI rect, _BoxCharset cs) {
    if (rect.width <= 0 || rect.height <= 0) {
      return;
    }
    if (rect.width == 1 && rect.height == 1) {
      _put(grid, rect.x, rect.y, cs.tl);
      return;
    }
    if (rect.height == 1) {
      _drawHLine(grid, rect.x, rect.y, rect.width, cs.h);
      return;
    }
    if (rect.width == 1) {
      _drawVLine(grid, rect.x, rect.y, rect.height, cs.v);
      return;
    }

    _put(grid, rect.x, rect.y, cs.tl);
    _put(grid, rect.x + rect.width - 1, rect.y, cs.tr);
    _put(grid, rect.x, rect.y + rect.height - 1, cs.bl);
    _put(grid, rect.x + rect.width - 1, rect.y + rect.height - 1, cs.br);

    _drawHLine(grid, rect.x + 1, rect.y, rect.width - 2, cs.h);
    _drawHLine(grid, rect.x + 1, rect.y + rect.height - 1, rect.width - 2, cs.h);
    _drawVLine(grid, rect.x, rect.y + 1, rect.height - 2, cs.v);
    _drawVLine(grid, rect.x + rect.width - 1, rect.y + 1, rect.height - 2, cs.v);
  }

  void _drawHLine(List<List<String>> grid, int x, int y, int length, String char) {
    for (var i = 0; i < length; i++) {
      _put(grid, x + i, y, char);
    }
  }

  void _drawVLine(List<List<String>> grid, int x, int y, int length, String char) {
    for (var i = 0; i < length; i++) {
      _put(grid, x, y + i, char);
    }
  }

  void _drawText(
    List<List<String>> grid,
    int x,
    int y,
    String text, {
    int? maxWidth,
  }) {
    final limit = maxWidth == null
        ? text.length
        : _clampInt(maxWidth, 0, text.length);
    for (var i = 0; i < limit; i++) {
      _put(grid, x + i, y, text[i]);
    }
  }

  void _put(List<List<String>> grid, int x, int y, String char) {
    if (y < 0 || y >= grid.length) {
      return;
    }
    if (x < 0 || x >= grid[y].length) {
      return;
    }
    grid[y][x] = char;
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

class _BoxCharset {
  const _BoxCharset({
    required this.tl,
    required this.tr,
    required this.bl,
    required this.br,
    required this.h,
    required this.v,
  });

  final String tl;
  final String tr;
  final String bl;
  final String br;
  final String h;
  final String v;
}

import "../model/ui_node.dart";

class ComponentExpander {
  List<UiNode> expandAll(List<UiNode> nodes) {
    return nodes.map(_expandNode).toList();
  }

  UiNode _expandNode(UiNode node) {
    final expandedChildren = node.children.map(_expandNode).toList();
    final base = node.copy()..children = expandedChildren;

    switch (node.kind) {
      case NodeKind.button:
        return _expandButton(base);
      case NodeKind.input:
        return _expandInput(base);
      case NodeKind.toggle:
        return _expandToggle(base);
      case NodeKind.combo:
        return _expandCombo(base);
      case NodeKind.tab:
        return _expandTab(base);
      case NodeKind.list:
        return _expandList(base);
      case NodeKind.popup:
        return _expandPopup(base);
      case NodeKind.box:
      case NodeKind.label:
      case NodeKind.line:
      case NodeKind.stack:
      case NodeKind.grid:
        return base;
    }
  }

  UiNode _expandButton(UiNode node) {
    final text = node.props["text"]?.toString() ?? "Button";
    final disabled = _toBool(node.props["disabled"]);
    final variant = node.props["variant"]?.toString() ?? "primary";
    final hotkey = node.props["hotkey"]?.toString() ?? "";

    var label = disabled ? "( $text )" : "[ $text ]";
    if (hotkey.isNotEmpty) {
      label = "$label <$hotkey>";
    }
    if (variant != "primary") {
      label = "{$variant} $label";
    }

    return _asRoleBox(
      node,
      role: "button",
      generatedChildren: <UiNode>[
        _labelNode(
          id: "${node.id}__caption",
          text: label,
          y: _labelY(node.height),
          width: _labelWidth(node),
        ),
      ],
    );
  }

  UiNode _expandInput(UiNode node) {
    final value = node.props["value"]?.toString() ?? "";
    final placeholder = node.props["placeholder"]?.toString() ?? "Input";
    final readOnly = _toBool(node.props["readOnly"]);
    final password = _toBool(node.props["password"]);

    String shown;
    if (value.isEmpty) {
      shown = "<$placeholder>";
    } else {
      shown = password ? _repeat("*", value.length) : value;
    }

    final roPrefix = readOnly ? "[RO] " : "";
    final caret = readOnly ? "" : " |";
    final line = "$roPrefix$shown$caret";

    return _asRoleBox(
      node,
      role: "input",
      generatedChildren: <UiNode>[
        _labelNode(
          id: "${node.id}__value",
          text: line,
          y: _labelY(node.height),
          width: _labelWidth(node),
        ),
      ],
    );
  }

  UiNode _expandToggle(UiNode node) {
    final isOn = _toBool(node.props["value"]);
    final text = node.props["text"]?.toString() ?? "Toggle";
    final label = "${isOn ? "[x]" : "[ ]"} $text";

    return _asRoleBox(
      node,
      role: "toggle",
      generatedChildren: <UiNode>[
        _labelNode(
          id: "${node.id}__toggle",
          text: label,
          y: _labelY(node.height),
          width: _labelWidth(node),
        ),
      ],
    );
  }

  UiNode _expandCombo(UiNode node) {
    final items = _stringListFrom(node.props["items"]);
    final selectedIndex = _toInt(node.props["selectedIndex"], fallback: 0);
    final expanded = _toBool(node.props["expanded"]);
    final placeholder = node.props["placeholder"]?.toString() ?? "Select";

    final selectedText = (selectedIndex >= 0 && selectedIndex < items.length)
        ? items[selectedIndex]
        : placeholder;
    final lineWidth = _labelWidth(node);
    final arrowToken = expanded ? "[^]" : "[v]";
    final selectedWidth =
        _clampInt(lineWidth - arrowToken.length - 1, 1, lineWidth);
    final selectedLine =
        "${_fitText(selectedText, selectedWidth).padRight(selectedWidth)} $arrowToken";

    final generated = <UiNode>[
      _labelNode(
        id: "${node.id}__selected",
        text: selectedLine,
        y: 0,
        width: lineWidth,
      ),
    ];

    if (expanded) {
      generated.add(
        UiNode(
          id: "${node.id}__divider",
          kind: NodeKind.line,
          x: 1,
          y: 1,
          width: lineWidth,
          height: 1,
          props: <String, dynamic>{"orientation": "horizontal"},
        ),
      );
      if (items.isEmpty) {
        generated.add(
          _labelNode(
            id: "${node.id}__empty",
            text: "(no items)",
            y: 2,
            width: lineWidth,
          ),
        );
      } else {
        final maxItems = _clampInt(_contentHeight(node) - 2, 0, items.length);
        final itemWidth = _clampInt(lineWidth - 2, 1, lineWidth);
        for (var i = 0; i < maxItems; i++) {
          final marker = i == selectedIndex ? ">" : " ";
          generated.add(
            _labelNode(
              id: "${node.id}__item_$i",
              text: "$marker ${_fitText(items[i], itemWidth)}",
              y: 2 + i,
              width: lineWidth,
            ),
          );
        }
      }
    }

    return _asRoleBox(
      node,
      role: "combo",
      generatedChildren: generated,
    );
  }

  UiNode _expandTab(UiNode node) {
    final items = _stringListFrom(node.props["items"]);
    final activeIndex = _toInt(node.props["activeIndex"], fallback: 0);
    final safeIndex =
        items.isEmpty ? -1 : _clampInt(activeIndex, 0, items.length - 1);

    final header = items.isEmpty
        ? "[Tab]"
        : items.asMap().entries.map((entry) {
            final active = entry.key == safeIndex;
            return active ? "[${entry.value}]" : " ${entry.value} ";
          }).join(" | ");
    final activeLabel = safeIndex >= 0 ? items[safeIndex] : "None";

    return _asRoleBox(
      node,
      role: "tab",
      generatedChildren: <UiNode>[
        _labelNode(
          id: "${node.id}__header",
          text: header,
          y: 0,
          width: _labelWidth(node),
        ),
        UiNode(
          id: "${node.id}__header_line",
          kind: NodeKind.line,
          x: 1,
          y: 1,
          width: _labelWidth(node),
          height: 1,
          props: <String, dynamic>{"orientation": "horizontal"},
        ),
        _labelNode(
          id: "${node.id}__active",
          text: "Active: $activeLabel",
          y: 2,
          width: _labelWidth(node),
        ),
      ],
    );
  }

  UiNode _expandList(UiNode node) {
    final title = node.props["title"]?.toString() ?? "List";
    final items = _stringListFrom(node.props["items"]);
    final selectedIndex = _toInt(node.props["selectedIndex"], fallback: 0);

    final generated = <UiNode>[
      _labelNode(
        id: "${node.id}__title",
        text: title,
        y: 0,
        width: _labelWidth(node),
      ),
      UiNode(
        id: "${node.id}__title_line",
        kind: NodeKind.line,
        x: 1,
        y: 1,
        width: _labelWidth(node),
        height: 1,
        props: <String, dynamic>{"orientation": "horizontal"},
      ),
    ];

    final maxItems = _clampInt(_contentHeight(node) - 2, 0, items.length);
    for (var i = 0; i < maxItems; i++) {
      final marker = i == selectedIndex ? ">" : " ";
      generated.add(
        _labelNode(
          id: "${node.id}__item_$i",
          text: "$marker ${items[i]}",
          y: 2 + i,
          width: _labelWidth(node),
        ),
      );
    }

    return _asRoleBox(
      node,
      role: "list",
      generatedChildren: generated,
    );
  }

  UiNode _expandPopup(UiNode node) {
    final title = node.props["title"]?.toString() ?? "Popup";
    final message = node.props["message"]?.toString() ?? "";
    final buttons = _stringListFrom(node.props["buttons"]);

    final innerWidth = _clampInt(node.width - 2, 1, node.width);
    final innerHeight = _clampInt(node.height - 2, 1, node.height);
    final buttonText = buttons.map((e) => "[ $e ]").join(" ");

    final dialog = UiNode(
      id: "${node.id}__dialog",
      kind: NodeKind.box,
      x: 0,
      y: 0,
      width: innerWidth,
      height: innerHeight,
      props: <String, dynamic>{"title": title},
      children: <UiNode>[
        _labelNode(
          id: "${node.id}__message",
          text: message.isEmpty ? "(empty message)" : message,
          y: 1,
          width: _clampInt(innerWidth - 3, 1, innerWidth),
        ),
        if (buttonText.isNotEmpty)
          _labelNode(
            id: "${node.id}__buttons",
            text: buttonText,
            y: _clampInt(innerHeight - 3, 0, innerHeight),
            width: _clampInt(innerWidth - 3, 1, innerWidth),
          ),
        ...node.children,
      ],
    );

    return _asRoleBox(
      node,
      role: "popup",
      generatedChildren: <UiNode>[dialog],
      includeExistingChildren: false,
    );
  }

  UiNode _asRoleBox(
    UiNode node, {
    required String role,
    required List<UiNode> generatedChildren,
    bool includeExistingChildren = true,
  }) {
    final updated = node.copy()
      ..kind = NodeKind.box
      ..props = <String, dynamic>{
        ...node.props,
        "role": role,
      };

    updated.children = <UiNode>[
      ...generatedChildren,
      if (includeExistingChildren) ...updated.children,
    ];
    return updated;
  }

  UiNode _labelNode({
    required String id,
    required String text,
    required int y,
    required int width,
  }) {
    return UiNode(
      id: id,
      kind: NodeKind.label,
      x: 1,
      y: y,
      width: width,
      height: 1,
      props: <String, dynamic>{"text": text},
    );
  }

  List<String> _stringListFrom(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value == null) {
      return <String>[];
    }
    return <String>[value.toString()];
  }

  bool _toBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return value?.toString().toLowerCase() == "true";
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

  int _labelY(int containerHeight) {
    final innerHeight = _contentHeightRaw(containerHeight);
    if (innerHeight <= 1) {
      return 0;
    }
    return innerHeight ~/ 2;
  }

  int _labelWidth(UiNode node) {
    final contentWidth = _contentWidth(node);
    return _clampInt(contentWidth - 1, 1, contentWidth);
  }

  int _contentWidth(UiNode node) => _contentWidthRaw(node.width);
  int _contentHeight(UiNode node) => _contentHeightRaw(node.height);

  int _contentWidthRaw(int width) {
    if (width >= 3) {
      return _clampInt(width - 2, 1, width);
    }
    return _clampInt(width, 1, 1 << 30);
  }

  int _contentHeightRaw(int height) {
    if (height >= 3) {
      return _clampInt(height - 2, 1, height);
    }
    return _clampInt(height, 1, 1 << 30);
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

  String _fitText(String text, int width) {
    if (width <= 0) {
      return "";
    }
    if (text.length <= width) {
      return text;
    }
    if (width <= 3) {
      return text.substring(0, width);
    }
    return "${text.substring(0, width - 3)}...";
  }

  String _repeat(String unit, int count) {
    if (count <= 0) {
      return "";
    }
    return List<String>.filled(count, unit).join();
  }
}

import "dart:convert";

import "package:flutter/material.dart";

import "../model/ui_node.dart";
import "../state/app_controller.dart";

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final List<_PropDraft> _propDrafts = <_PropDraft>[];
  String? _boundNodeId;
  String? _propError;

  @override
  void dispose() {
    _disposePropDrafts();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final node = widget.controller.selectedNode;
        if (node?.id != _boundNodeId) {
          _boundNodeId = node?.id;
          _rebindProps(node);
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: node == null
                ? _emptyState(context)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Inspector",
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text("ID: ${node.id}"),
                      Text("Kind: ${node.kind.name}"),
                      const SizedBox(height: 8),
                      Text("Pointer Mode",
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      SegmentedButton<PointerEditMode>(
                        segments: const <ButtonSegment<PointerEditMode>>[
                          ButtonSegment<PointerEditMode>(
                            value: PointerEditMode.move,
                            icon: Icon(Icons.open_with),
                            label: Text("Move (Q)"),
                          ),
                          ButtonSegment<PointerEditMode>(
                            value: PointerEditMode.resize,
                            icon: Icon(Icons.straighten),
                            label: Text("Size (W)"),
                          ),
                        ],
                        selected: <PointerEditMode>{
                          widget.controller.pointerEditMode
                        },
                        onSelectionChanged: (selection) {
                          widget.controller.setPointerEditMode(selection.first);
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Drag on canvas uses selected mode.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Bounds: x=${node.x}, y=${node.y}, w=${node.width}, h=${node.height}",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _axisEditor(
                                label: "Move",
                                onLeft: () =>
                                    widget.controller.moveSelected(-1, 0),
                                onRight: () =>
                                    widget.controller.moveSelected(1, 0),
                                onUp: () =>
                                    widget.controller.moveSelected(0, -1),
                                onDown: () =>
                                    widget.controller.moveSelected(0, 1),
                              ),
                              const SizedBox(height: 8),
                              _axisEditor(
                                label: "Resize",
                                onLeft: () =>
                                    widget.controller.resizeSelected(-1, 0),
                                onRight: () =>
                                    widget.controller.resizeSelected(1, 0),
                                onUp: () =>
                                    widget.controller.resizeSelected(0, -1),
                                onDown: () =>
                                    widget.controller.resizeSelected(0, 1),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                "Kind Properties",
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 6),
                              _kindPropsEditor(context, node),
                              const SizedBox(height: 8),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed:
                                          widget.controller.deleteSelectedNode,
                                      child: const Text("Delete Node"),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text("Inspector", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text("Select a node on the canvas to edit properties."),
      ],
    );
  }

  Widget _axisEditor({
    required String label,
    required VoidCallback onLeft,
    required VoidCallback onRight,
    required VoidCallback onUp,
    required VoidCallback onDown,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: <Widget>[
            IconButton.filledTonal(
                onPressed: onLeft, icon: const Icon(Icons.arrow_left)),
            IconButton.filledTonal(
                onPressed: onRight, icon: const Icon(Icons.arrow_right)),
            IconButton.filledTonal(
                onPressed: onUp, icon: const Icon(Icons.arrow_upward)),
            IconButton.filledTonal(
                onPressed: onDown, icon: const Icon(Icons.arrow_downward)),
          ],
        ),
      ],
    );
  }

  Widget _kindPropsEditor(BuildContext context, UiNode node) {
    final fields = _kindSpecificFields(node);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_propError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _propError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (fields.isEmpty)
            Text(
              "No kind-specific properties for this node.",
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            ..._withSpacing(fields),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _applyProps,
                  child: const Text("Apply Properties"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _rebindProps(widget.controller.selectedNode);
                    });
                  },
                  child: const Text("Reset"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Types: string, int, bool, list<string>.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  List<Widget> _kindSpecificFields(UiNode node) {
    final fields = <Widget>[];

    switch (node.kind) {
      case NodeKind.box:
        fields.add(_textPropField(key: "title", label: "Title (string)"));
      case NodeKind.label:
        fields.add(_textPropField(key: "text", label: "Text (string)"));
      case NodeKind.line:
        fields.add(
          _enumPropField(
            key: "orientation",
            label: "Orientation (enum<string>)",
            options: const <String>["horizontal", "vertical"],
          ),
        );
      case NodeKind.stack:
        fields.add(
          _enumPropField(
            key: "direction",
            label: "Direction (enum<string>)",
            options: const <String>["vertical", "horizontal"],
          ),
        );
        fields.add(_intPropField(key: "spacing", label: "Spacing (int)"));
      case NodeKind.grid:
        fields.add(_intPropField(key: "rows", label: "Rows (int)"));
        fields.add(_intPropField(key: "cols", label: "Columns (int)"));
      case NodeKind.input:
        fields.add(_textPropField(key: "value", label: "Value (string)"));
        fields.add(
            _textPropField(key: "placeholder", label: "Placeholder (string)"));
        fields.add(_boolPropField(key: "readOnly", label: "Read Only (bool)"));
        fields.add(
            _boolPropField(key: "password", label: "Password Mode (bool)"));
        fields.add(_intPropField(key: "maxLength", label: "Max Length (int)"));
      case NodeKind.button:
        fields.add(_textPropField(key: "text", label: "Text (string)"));
        fields.add(
          _enumPropField(
            key: "variant",
            label: "Variant (enum<string>)",
            options: const <String>["primary", "secondary", "danger", "ghost"],
          ),
        );
        fields.add(_boolPropField(key: "disabled", label: "Disabled (bool)"));
        fields.add(_textPropField(key: "hotkey", label: "Hotkey (string)"));
      case NodeKind.tab:
        fields.add(
          _stringListPropField(
            key: "items",
            label: "Tab Items (list<string>)",
            helperText: "One item per line or comma-separated.",
          ),
        );
        fields.add(
            _intPropField(key: "activeIndex", label: "Active Index (int)"));
      case NodeKind.list:
        fields.add(_textPropField(key: "title", label: "Title (string)"));
        fields.add(
          _stringListPropField(
            key: "items",
            label: "List Items (list<string>)",
            helperText: "One item per line or comma-separated.",
          ),
        );
        fields.add(
            _intPropField(key: "selectedIndex", label: "Selected Index (int)"));
      case NodeKind.popup:
        fields.add(_textPropField(key: "title", label: "Title (string)"));
        fields.add(
          _textPropField(
            key: "message",
            label: "Message (string)",
            minLines: 2,
            maxLines: 4,
          ),
        );
        fields.add(
          _stringListPropField(
            key: "buttons",
            label: "Buttons (list<string>)",
            helperText: "One button label per line or comma-separated.",
          ),
        );
        fields.add(_boolPropField(key: "visible", label: "Visible (bool)"));
      case NodeKind.toggle:
        fields.add(_textPropField(key: "text", label: "Text (string)"));
        fields.add(_boolPropField(key: "value", label: "On (bool)"));
      case NodeKind.combo:
        fields.add(
          _stringListPropField(
            key: "items",
            label: "Items (list<string>)",
            helperText: "One option per line or comma-separated.",
          ),
        );
        fields.add(
            _intPropField(key: "selectedIndex", label: "Selected Index (int)"));
        fields.add(
            _textPropField(key: "placeholder", label: "Placeholder (string)"));
        fields.add(_boolPropField(key: "expanded", label: "Expanded (bool)"));
    }

    fields.add(
      _textPropField(
        key: "llmComment",
        label: "LLM Comment (string)",
        minLines: 2,
        maxLines: 5,
      ),
    );

    return fields;
  }

  Widget _textPropField({
    required String key,
    required String label,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final controller = _valueControllerForKey(key);
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      onChanged: (_) {
        if (_propError != null) {
          setState(() {
            _propError = null;
          });
        }
      },
      onSubmitted: (_) => _applyProps(),
    );
  }

  Widget _intPropField({
    required String key,
    required String label,
  }) {
    final controller = _valueControllerForKey(key);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      onChanged: (_) {
        if (_propError != null) {
          setState(() {
            _propError = null;
          });
        }
      },
      onSubmitted: (_) => _applyProps(),
    );
  }

  Widget _enumPropField({
    required String key,
    required String label,
    required List<String> options,
  }) {
    final controller = _valueControllerForKey(key, defaultValue: options.first);
    final current =
        controller.text.trim().isEmpty ? options.first : controller.text.trim();
    final values = <String>[...options];
    if (!values.contains(current)) {
      values.add(current);
    }

    return DropdownButtonFormField<String>(
      initialValue: current,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
      ),
      items: values
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(value),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next == null) {
          return;
        }
        setState(() {
          controller.text = next;
          _propError = null;
        });
        _applyProps();
      },
    );
  }

  Widget _boolPropField({
    required String key,
    required String label,
  }) {
    final controller = _valueControllerForKey(key);
    final value =
        _toBool(_parsePropertyValue(controller.text), fallback: false);
    return SwitchListTile.adaptive(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: (next) {
        setState(() {
          controller.text = next ? "true" : "false";
          _propError = null;
        });
        _applyProps();
      },
    );
  }

  Widget _stringListPropField({
    required String key,
    required String label,
    String? helperText,
  }) {
    final controller = _valueControllerForKey(key);
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 5,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        labelText: label,
        helperText: helperText,
      ),
      onChanged: (_) {
        if (_propError != null) {
          setState(() {
            _propError = null;
          });
        }
      },
    );
  }

  void _applyProps() {
    final node = widget.controller.selectedNode;
    if (node == null) {
      return;
    }

    final seen = <String>{};
    final nextProps = <String, dynamic>{};
    final listPropKeys = _listPropKeysForKind(node.kind);
    for (final draft in _propDrafts) {
      final key = draft.keyController.text.trim();
      if (key.isEmpty) {
        setState(() {
          _propError = "Property key cannot be empty.";
        });
        return;
      }
      if (!seen.add(key)) {
        setState(() {
          _propError = "Duplicate property key: '$key'.";
        });
        return;
      }
      if (listPropKeys.contains(key)) {
        nextProps[key] = _parseStringListValue(draft.valueController.text);
      } else {
        nextProps[key] = _parsePropertyValue(draft.valueController.text);
      }
    }

    setState(() {
      _propError = null;
    });
    widget.controller.replaceSelectedProps(nextProps);
    setState(() {
      _rebindProps(widget.controller.selectedNode);
    });
  }

  void _rebindProps(UiNode? node) {
    _disposePropDrafts();
    _propDrafts.clear();
    _propError = null;

    if (node == null) {
      return;
    }

    final defaults = _kindDefaultProps(node.kind);
    for (final entry in defaults.entries) {
      final key = entry.key;
      final value = node.props.containsKey(key) ? node.props[key] : entry.value;
      _propDrafts.add(
        _PropDraft(
          keyController: TextEditingController(text: key),
          valueController: TextEditingController(
            text: _valueToEditorText(key, value, node.kind),
          ),
        ),
      );
    }

    if (_findDraftByKey("llmComment") == null) {
      final llmValue = node.props["llmComment"];
      _propDrafts.add(
        _PropDraft(
          keyController: TextEditingController(text: "llmComment"),
          valueController:
              TextEditingController(text: llmValue?.toString() ?? ""),
        ),
      );
    }

    final extraKeys = node.props.keys
        .map((e) => e.toString())
        .where((key) => !defaults.containsKey(key) && key != "llmComment")
        .toList()
      ..sort();
    for (final key in extraKeys) {
      _propDrafts.add(
        _PropDraft(
          keyController: TextEditingController(text: key),
          valueController: TextEditingController(
            text: _valueToEditorText(key, node.props[key], node.kind),
          ),
        ),
      );
    }
  }

  void _disposePropDrafts() {
    for (final draft in _propDrafts) {
      draft.dispose();
    }
  }

  TextEditingController _valueControllerForKey(String key,
      {String defaultValue = ""}) {
    final existing = _findDraftByKey(key);
    if (existing != null) {
      return existing.valueController;
    }
    final created = _PropDraft(
      keyController: TextEditingController(text: key),
      valueController: TextEditingController(text: defaultValue),
    );
    _propDrafts.add(created);
    return created.valueController;
  }

  _PropDraft? _findDraftByKey(String key) {
    for (final draft in _propDrafts) {
      if (draft.keyController.text.trim() == key) {
        return draft;
      }
    }
    return null;
  }

  dynamic _parsePropertyValue(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return "";
    }

    final lower = value.toLowerCase();
    if (lower == "null") {
      return null;
    }
    if (lower == "true") {
      return true;
    }
    if (lower == "false") {
      return false;
    }

    final intValue = int.tryParse(value);
    if (intValue != null) {
      return intValue;
    }
    final doubleValue = double.tryParse(value);
    if (doubleValue != null) {
      return doubleValue;
    }
    if ((value.startsWith("[") && value.endsWith("]")) ||
        (value.startsWith("{") && value.endsWith("}"))) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  List<String> _parseStringListValue(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return <String>[];
    }
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {
        // Fallback to line/comma split below.
      }
    }

    final parts = input.contains("\n") || input.contains("\r")
        ? input.split(RegExp(r"\r?\n"))
        : input.split(",");
    return parts.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  String _valueToEditorText(String key, dynamic value, NodeKind kind) {
    if (_listPropKeysForKind(kind).contains(key)) {
      if (value is List) {
        return value.map((e) => e.toString()).join("\n");
      }
      if (value == null) {
        return "";
      }
      return value.toString();
    }

    if (value == null) {
      return "null";
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return value.toString();
  }

  bool _toBool(dynamic value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == "true") {
      return true;
    }
    if (text == "false") {
      return false;
    }
    return fallback;
  }

  Map<String, dynamic> _kindDefaultProps(NodeKind kind) {
    switch (kind) {
      case NodeKind.box:
        return <String, dynamic>{"title": "Box"};
      case NodeKind.label:
        return <String, dynamic>{"text": "Label"};
      case NodeKind.line:
        return <String, dynamic>{"orientation": "horizontal"};
      case NodeKind.stack:
        return <String, dynamic>{"direction": "vertical", "spacing": 1};
      case NodeKind.grid:
        return <String, dynamic>{"rows": 2, "cols": 2};
      case NodeKind.input:
        return <String, dynamic>{
          "value": "",
          "placeholder": "Type here",
          "readOnly": false,
          "password": false,
          "maxLength": 64,
        };
      case NodeKind.button:
        return <String, dynamic>{
          "text": "Button",
          "variant": "primary",
          "disabled": false,
          "hotkey": "Enter",
        };
      case NodeKind.tab:
        return <String, dynamic>{
          "items": <String>["General", "Network", "Advanced"],
          "activeIndex": 0,
        };
      case NodeKind.list:
        return <String, dynamic>{
          "title": "List",
          "items": <String>["Item A", "Item B", "Item C"],
          "selectedIndex": 0,
        };
      case NodeKind.popup:
        return <String, dynamic>{
          "title": "Confirm",
          "message": "Are you sure?",
          "buttons": <String>["Cancel", "OK"],
          "visible": true,
        };
      case NodeKind.toggle:
        return <String, dynamic>{"text": "Toggle", "value": false};
      case NodeKind.combo:
        return <String, dynamic>{
          "items": <String>["One", "Two", "Three"],
          "selectedIndex": 0,
          "placeholder": "Select",
          "expanded": true,
        };
    }
  }

  Set<String> _listPropKeysForKind(NodeKind kind) {
    switch (kind) {
      case NodeKind.tab:
      case NodeKind.list:
      case NodeKind.combo:
        return <String>{"items"};
      case NodeKind.popup:
        return <String>{"buttons"};
      case NodeKind.box:
      case NodeKind.label:
      case NodeKind.line:
      case NodeKind.stack:
      case NodeKind.grid:
      case NodeKind.input:
      case NodeKind.button:
      case NodeKind.toggle:
        return const <String>{};
    }
  }

  List<Widget> _withSpacing(List<Widget> fields) {
    final out = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      if (i > 0) {
        out.add(const SizedBox(height: 8));
      }
      out.add(fields[i]);
    }
    return out;
  }
}

class _PropDraft {
  _PropDraft({
    required this.keyController,
    required this.valueController,
  });

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

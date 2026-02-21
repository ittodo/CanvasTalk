import "package:flutter/material.dart";

import "../state/app_controller.dart";

class YamlEditorPanel extends StatefulWidget {
  const YamlEditorPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  State<YamlEditorPanel> createState() => _YamlEditorPanelState();
}

class _YamlEditorPanelState extends State<YamlEditorPanel> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _textController.text = widget.controller.yamlSource;
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!_focusNode.hasFocus && _textController.text != widget.controller.yamlSource) {
          _textController.text = widget.controller.yamlSource;
        }

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: () async {
                      await widget.controller.updateYamlFromEditor(_textController.text);
                    },
                    child: const Text("Apply YAML"),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      widget.controller.resetYamlFromProject();
                      _textController.text = widget.controller.yamlSource;
                    },
                    child: const Text("Reset From Model"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: "Courier",
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Edit YAML definition here...",
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

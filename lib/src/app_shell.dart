import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "state/app_controller.dart";
import "widgets/ascii_canvas.dart";
import "widgets/ascii_output_panel.dart";
import "widgets/component_palette.dart";
import "widgets/diagnostics_panel.dart";
import "widgets/inspector_panel.dart";
import "widgets/llm_control_panel.dart";
import "widgets/page_control_bar.dart";
import "widgets/yaml_editor_panel.dart";
import "widgets/yaml_hierarchy_panel.dart";

class AppShell extends StatelessWidget {
  const AppShell({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _UndoIntent(),
            SingleActivator(LogicalKeyboardKey.keyZ,
                control: true, shift: true): _RedoIntent(),
            SingleActivator(LogicalKeyboardKey.keyY, control: true):
                _RedoIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _UndoIntent: CallbackAction<_UndoIntent>(
                onInvoke: (_) {
                  controller.undo();
                  return null;
                },
              ),
              _RedoIntent: CallbackAction<_RedoIntent>(
                onInvoke: (_) {
                  controller.redo();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text("AsciiPaint Runtime Studio"),
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        controller.statusMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  actions: <Widget>[
                    IconButton(
                      tooltip: "Undo (Ctrl+Z)",
                      onPressed: controller.canUndo ? controller.undo : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: "Redo (Ctrl+Y)",
                      onPressed: controller.canRedo ? controller.redo : null,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: "Clear Canvas",
                      onPressed: controller.clearCanvas,
                      icon: const Icon(Icons.cleaning_services_outlined),
                    ),
                  ],
                ),
                body: Column(
                  children: <Widget>[
                    PageControlBar(controller: controller),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const paletteWidth = 230.0;
                          const inspectorWidth = 320.0;
                          const yamlWidth = 340.0;
                          const canvasMinWidth = 560.0;
                          const minimumWidth = paletteWidth +
                              inspectorWidth +
                              yamlWidth +
                              canvasMinWidth;
                          final contentWidth =
                              constraints.maxWidth < minimumWidth
                                  ? minimumWidth
                                  : constraints.maxWidth;

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: contentWidth,
                              child: Row(
                                children: <Widget>[
                                  SizedBox(
                                    width: paletteWidth,
                                    child: ComponentPalette(
                                        controller: controller),
                                  ),
                                  Expanded(
                                    child: AsciiCanvas(controller: controller),
                                  ),
                                  SizedBox(
                                    width: inspectorWidth,
                                    child:
                                        InspectorPanel(controller: controller),
                                  ),
                                  SizedBox(
                                    width: yamlWidth,
                                    child: YamlHierarchyPanel(
                                        controller: controller),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(
                      height: 280,
                      child: DefaultTabController(
                        length: 4,
                        child: Column(
                          children: <Widget>[
                            const TabBar(
                              tabs: <Tab>[
                                Tab(text: "ASCII"),
                                Tab(text: "YAML"),
                                Tab(text: "Diagnostics"),
                                Tab(text: "LLM Control"),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                children: <Widget>[
                                  AsciiOutputPanel(controller: controller),
                                  YamlEditorPanel(controller: controller),
                                  DiagnosticsPanel(controller: controller),
                                  LlmControlPanel(controller: controller),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

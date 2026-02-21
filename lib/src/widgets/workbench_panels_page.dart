import "package:flutter/material.dart";

import "../state/app_controller.dart";
import "ascii_output_panel.dart";
import "diagnostics_panel.dart";
import "llm_control_panel.dart";
import "yaml_editor_panel.dart";

class WorkbenchPanelsPage extends StatelessWidget {
  const WorkbenchPanelsPage({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Panels"),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: "ASCII"),
              Tab(text: "YAML"),
              Tab(text: "Diagnostics"),
              Tab(text: "LLM Control"),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            AsciiOutputPanel(controller: controller),
            YamlEditorPanel(controller: controller),
            DiagnosticsPanel(controller: controller),
            LlmControlPanel(controller: controller),
          ],
        ),
      ),
    );
  }
}

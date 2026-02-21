import "package:flutter/material.dart";

import "../model/diagnostic.dart";
import "../state/app_controller.dart";

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final diagnostics = controller.diagnostics;
        if (diagnostics.isEmpty) {
          return const Center(
            child: Text("No diagnostics."),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: diagnostics.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final d = diagnostics[index];
            final color = _colorForSeverity(d.severity);
            return ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 10, color: color),
              title: Text(d.message),
              subtitle: Text("${d.code}${d.path == null ? "" : " @ ${d.path}"}"),
            );
          },
        );
      },
    );
  }

  Color _colorForSeverity(DiagnosticSeverity severity) {
    switch (severity) {
      case DiagnosticSeverity.error:
        return const Color(0xFFB42318);
      case DiagnosticSeverity.warning:
        return const Color(0xFFB54708);
      case DiagnosticSeverity.info:
        return const Color(0xFF175CD3);
    }
  }
}

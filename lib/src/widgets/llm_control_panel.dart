import "package:flutter/material.dart";

import "../state/app_controller.dart";

class LlmControlPanel extends StatelessWidget {
  const LlmControlPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final running = controller.serverRunning;
        final port = controller.serverPort ?? 4049;
        final token = controller.serverToken ?? "(starting...)";

        return LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        running
                            ? FilledButton.tonal(
                                onPressed: () async {
                                  await controller.stopControlServer();
                                },
                                child: const Text("Stop Server"),
                              )
                            : FilledButton(
                                onPressed: () async {
                                  await controller.startControlServer();
                                },
                                child: const Text("Start Server"),
                              ),
                        OutlinedButton(
                          onPressed: () async {
                            await controller.resetSession();
                          },
                          child: const Text("Reset Session"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("Status: ${running ? "running" : "stopped"}"),
                    Text("Base URL: http://127.0.0.1:$port"),
                    Text("Token: $token"),
                    const SizedBox(height: 12),
                    const Text("HTTP endpoints"),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surface,
                      ),
                      child: SelectableText(
                        _examples(port, token),
                        style: const TextStyle(
                            fontFamily: "Courier", fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _examples(int port, String token) {
    return [
      "GET /health",
      "curl http://127.0.0.1:$port/health",
      "",
      "POST /yaml/validate",
      "curl -X POST http://127.0.0.1:$port/yaml/validate \\",
      "  -H \"x-canvastalk-token: $token\" \\",
      "  -H \"content-type: application/json\" \\",
      "  -d '{\"yaml\":\"version: 1.0\\ncanvas:\\n  width: 80\\n  height: 24\\nnodes: []\"}'",
      "",
      "POST /render/preview",
      "POST /canvas/patch",
      "POST /project/load",
      "POST /project/save",
      "POST /session/reset",
    ].join("\n");
  }
}

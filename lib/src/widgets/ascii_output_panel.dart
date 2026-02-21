import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../state/app_controller.dart";

class AsciiOutputPanel extends StatelessWidget {
  const AsciiOutputPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          color: const Color(0xFF0E1511),
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: controller.asciiOutput));
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text("ASCII copied to clipboard.")),
                        );
                      },
                      icon: const Icon(Icons.content_copy),
                      label: const Text("Copy ASCII"),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(
                            text: controller.buildLlmMarkdownExport(),
                          ),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                "Markdown (active-page ASCII + YAML) copied."),
                          ),
                        );
                      },
                      icon: const Icon(Icons.description_outlined),
                      label: const Text("Copy Markdown"),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        controller.asciiOutput,
                        style: const TextStyle(
                          fontFamily: "Consolas",
                          fontFamilyFallback: <String>[
                            "Courier New",
                            "monospace"
                          ],
                          fontSize: 13,
                          color: Color(0xFFF7F7F7),
                          height: 1.0,
                        ),
                      ),
                    ),
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

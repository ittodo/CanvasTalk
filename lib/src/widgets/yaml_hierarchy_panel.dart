import "package:flutter/material.dart";
import "package:json2yaml/json2yaml.dart";

import "../model/ui_node.dart";
import "../state/app_controller.dart";

class YamlHierarchyPanel extends StatelessWidget {
  const YamlHierarchyPanel({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selected = controller.selectedNode;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border(
              left: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("YAML Hierarchy",
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: _hierarchyList(context),
                ),
                const SizedBox(height: 12),
                Text("Selected YAML",
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).dividerColor),
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(context).colorScheme.surface,
                    ),
                    child: SelectableText(
                      selected == null
                          ? "No node selected."
                          : _nodeYaml(selected),
                      style: const TextStyle(
                        fontFamily: "Consolas",
                        fontFamilyFallback: <String>[
                          "Courier New",
                          "monospace"
                        ],
                        fontSize: 12,
                      ),
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

  Widget _hierarchyList(BuildContext context) {
    final items = controller.nodeHierarchy;
    if (items.isEmpty) {
      return const Text("No nodes.");
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = item.id == controller.selectedNodeId;
          return InkWell(
            onTap: () => controller.selectNode(item.id),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8 + (item.depth * 14), 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "${item.id} (${item.kind.name})",
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    item.path,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _nodeYaml(UiNode node) {
    return json2yaml(node.toMap());
  }
}

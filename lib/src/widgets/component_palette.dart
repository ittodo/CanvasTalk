import "package:flutter/material.dart";

import "../model/ui_node.dart";
import "../state/app_controller.dart";

class ComponentPalette extends StatelessWidget {
  const ComponentPalette({
    required this.controller,
    super.key,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Text("Palette", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Text("Primitives", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _kindButton(context, NodeKind.box),
          _kindButton(context, NodeKind.label),
          _kindButton(context, NodeKind.line),
          _kindButton(context, NodeKind.stack),
          _kindButton(context, NodeKind.grid),
          const SizedBox(height: 12),
          Text("Composed", style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _kindButton(context, NodeKind.button),
          _kindButton(context, NodeKind.input),
          _kindButton(context, NodeKind.toggle),
          _kindButton(context, NodeKind.tab),
          _kindButton(context, NodeKind.combo),
          _kindButton(context, NodeKind.list),
          _kindButton(context, NodeKind.popup),
        ],
      ),
    );
  }

  Widget _kindButton(BuildContext context, NodeKind kind) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.tonal(
        onPressed: () => controller.insertNode(kind),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(kind.name),
        ),
      ),
    );
  }
}

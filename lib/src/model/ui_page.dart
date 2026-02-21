import "ui_node.dart";

class UiPage {
  UiPage({
    required this.id,
    String? name,
    List<UiNode>? nodes,
    this.llmComment = "",
  })  : name = (name == null || name.trim().isEmpty) ? id : name.trim(),
        nodes = nodes ?? <UiNode>[];

  String id;
  String name;
  List<UiNode> nodes;
  String llmComment;

  factory UiPage.fromMap(Map<String, dynamic> map,
      {required String fallbackId}) {
    final id = (map["id"] ?? fallbackId).toString();
    final name = map["name"]?.toString();
    final rawNodes = map["nodes"];
    final nodes = <UiNode>[];
    if (rawNodes is List) {
      for (final node in rawNodes) {
        if (node is Map) {
          nodes.add(UiNode.fromMap(Map<String, dynamic>.from(node)));
        }
      }
    }

    return UiPage(
      id: id,
      name: name,
      nodes: nodes,
      llmComment: map["llmComment"]?.toString() ?? "",
    );
  }

  UiPage copy() {
    return UiPage(
      id: id,
      name: name,
      nodes: nodes.map((e) => e.copy()).toList(),
      llmComment: llmComment,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "id": id,
      "name": name,
      "nodes": nodes.map((e) => e.toMap()).toList(),
      if (llmComment.trim().isNotEmpty) "llmComment": llmComment,
    };
  }
}

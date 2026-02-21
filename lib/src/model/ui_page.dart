import "ui_node.dart";

enum UiPageMode {
  standalone,
  overlay,
}

UiPageMode pageModeFromString(String? value) {
  final lower = (value ?? "").trim().toLowerCase();
  for (final mode in UiPageMode.values) {
    if (mode.name == lower) {
      return mode;
    }
  }
  return UiPageMode.standalone;
}

String pageModeToString(UiPageMode mode) => mode.name;

class UiPage {
  UiPage({
    required this.id,
    String? name,
    this.mode = UiPageMode.standalone,
    this.basePageId,
    this.previewOrder,
    List<UiNode>? nodes,
    this.llmComment = "",
  })  : name = (name == null || name.trim().isEmpty) ? id : name.trim(),
        nodes = nodes ?? <UiNode>[] {
    if (mode == UiPageMode.standalone) {
      basePageId = null;
    } else if (basePageId != null && basePageId!.trim().isEmpty) {
      basePageId = null;
    }
  }

  String id;
  String name;
  UiPageMode mode;
  String? basePageId;
  int? previewOrder;
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
      mode: pageModeFromString(map["mode"]?.toString()),
      basePageId: map["basePageId"]?.toString(),
      previewOrder: _toNullableInt(map["previewOrder"]),
      nodes: nodes,
      llmComment: map["llmComment"]?.toString() ?? "",
    );
  }

  UiPage copy() {
    return UiPage(
      id: id,
      name: name,
      mode: mode,
      basePageId: basePageId,
      previewOrder: previewOrder,
      nodes: nodes.map((e) => e.copy()).toList(),
      llmComment: llmComment,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "id": id,
      "name": name,
      "mode": pageModeToString(mode),
      if (mode == UiPageMode.overlay &&
          basePageId != null &&
          basePageId!.trim().isNotEmpty)
        "basePageId": basePageId,
      if (previewOrder != null) "previewOrder": previewOrder,
      "nodes": nodes.map((e) => e.toMap()).toList(),
      if (llmComment.trim().isNotEmpty) "llmComment": llmComment,
    };
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}

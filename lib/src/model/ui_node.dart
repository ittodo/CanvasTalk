enum NodeKind {
  box,
  label,
  line,
  stack,
  grid,
  input,
  button,
  tab,
  list,
  popup,
  toggle,
  combo,
}

NodeKind nodeKindFromString(String? value) {
  final lower = (value ?? "").toLowerCase();
  for (final kind in NodeKind.values) {
    if (kind.name == lower) {
      return kind;
    }
  }
  return NodeKind.box;
}

String nodeKindToString(NodeKind kind) => kind.name;

class UiNode {
  UiNode({
    required this.id,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.width = 10,
    this.height = 3,
    this.dock = "none",
    Map<String, dynamic>? props,
    List<UiNode>? children,
    this.styleRef,
  })  : props = props ?? <String, dynamic>{},
        children = children ?? <UiNode>[];

  String id;
  NodeKind kind;
  int x;
  int y;
  int width;
  int height;
  String dock;
  Map<String, dynamic> props;
  List<UiNode> children;
  String? styleRef;

  factory UiNode.fromMap(Map<String, dynamic> map) {
    final rawChildren = map["children"];
    final children = <UiNode>[];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        if (item is Map) {
          children.add(UiNode.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }

    return UiNode(
      id: (map["id"] ?? "").toString(),
      kind: nodeKindFromString(map["kind"]?.toString()),
      x: _toInt(map["x"], fallback: 0),
      y: _toInt(map["y"], fallback: 0),
      width: _toInt(map["width"], fallback: 10),
      height: _toInt(map["height"], fallback: 3),
      dock: (map["dock"] ?? "none").toString(),
      props: _mapFrom(map["props"]),
      children: children,
      styleRef: map["styleRef"]?.toString(),
    );
  }

  UiNode copy() {
    return UiNode(
      id: id,
      kind: kind,
      x: x,
      y: y,
      width: width,
      height: height,
      dock: dock,
      props: Map<String, dynamic>.from(props),
      children: children.map((e) => e.copy()).toList(),
      styleRef: styleRef,
    );
  }

  Map<String, dynamic> toMap() {
    final out = <String, dynamic>{
      "id": id,
      "kind": nodeKindToString(kind),
      "x": x,
      "y": y,
      "width": width,
      "height": height,
      "dock": dock,
    };

    if (props.isNotEmpty) {
      out["props"] = Map<String, dynamic>.from(props);
    }
    if (children.isNotEmpty) {
      out["children"] = children.map((e) => e.toMap()).toList();
    }
    if (styleRef != null && styleRef!.isNotEmpty) {
      out["styleRef"] = styleRef;
    }
    return out;
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  static Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }
}

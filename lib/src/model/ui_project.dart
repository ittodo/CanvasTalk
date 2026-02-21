import "canvas_config.dart";
import "ui_node.dart";
import "ui_page.dart";
import "ui_style.dart";

class UiProject {
  UiProject({
    this.version = "1.0",
    CanvasConfig? canvas,
    List<UiNode>? nodes,
    List<UiPage>? pages,
    String? activePageId,
    Map<String, UiStyle>? styles,
    Map<String, dynamic>? variables,
  })  : canvas = canvas ?? CanvasConfig(width: 100, height: 32),
        pages = _normalizedPages(pages, nodes),
        activePageId = _normalizedActivePageId(activePageId, pages, nodes),
        styles = styles ?? <String, UiStyle>{},
        variables = variables ?? <String, dynamic>{} {
    if (!pagesById.containsKey(this.activePageId)) {
      this.activePageId = this.pages.first.id;
    }
  }

  String version;
  CanvasConfig canvas;
  List<UiPage> pages;
  String activePageId;
  Map<String, UiStyle> styles;
  Map<String, dynamic> variables;

  Map<String, UiPage> get pagesById => <String, UiPage>{
        for (final page in pages) page.id: page,
      };

  UiPage get activePage {
    for (final page in pages) {
      if (page.id == activePageId) {
        return page;
      }
    }
    return pages.first;
  }

  List<UiNode> get nodes => activePage.nodes;
  set nodes(List<UiNode> value) {
    activePage.nodes = value;
  }

  int indexOfPage(String pageId) {
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id == pageId) {
        return i;
      }
    }
    return -1;
  }

  factory UiProject.fromMap(Map<String, dynamic> map) {
    final styleMap = <String, UiStyle>{};
    final rawStyles = map["styles"];
    if (rawStyles is Map) {
      for (final entry in rawStyles.entries) {
        if (entry.value is Map) {
          styleMap[entry.key.toString()] = UiStyle.fromMap(entry.key.toString(),
              Map<String, dynamic>.from(entry.value as Map));
        }
      }
    }

    final pages = <UiPage>[];
    final rawPages = map["pages"];
    if (rawPages is List) {
      for (var i = 0; i < rawPages.length; i++) {
        final page = rawPages[i];
        if (page is Map) {
          pages.add(
            UiPage.fromMap(
              Map<String, dynamic>.from(page),
              fallbackId: "page_${i + 1}",
            ),
          );
        }
      }
    }

    final legacyNodes = <UiNode>[];
    final rawNodes = map["nodes"];
    if (rawNodes is List) {
      for (final node in rawNodes) {
        if (node is Map) {
          legacyNodes.add(UiNode.fromMap(Map<String, dynamic>.from(node)));
        }
      }
    }

    if (pages.isEmpty) {
      pages.add(
        UiPage(
          id: "page_main",
          name: "Main",
          nodes: legacyNodes,
        ),
      );
    }

    final requestedActivePageId = map["activePageId"]?.toString();
    final activePageId = pages.any((page) => page.id == requestedActivePageId)
        ? requestedActivePageId!
        : pages.first.id;

    final canvasMap = map["canvas"];
    return UiProject(
      version: (map["version"] ?? "1.0").toString(),
      canvas: canvasMap is Map
          ? CanvasConfig.fromMap(Map<String, dynamic>.from(canvasMap))
          : CanvasConfig(width: 100, height: 32),
      pages: pages,
      activePageId: activePageId,
      styles: styleMap,
      variables: _variablesFrom(map["variables"]),
    );
  }

  UiProject copy() {
    return UiProject(
      version: version,
      canvas: canvas.copy(),
      pages: pages.map((e) => e.copy()).toList(),
      activePageId: activePageId,
      styles: styles.map(
        (k, v) => MapEntry(
            k, UiStyle(id: v.id, props: Map<String, dynamic>.from(v.props))),
      ),
      variables: Map<String, dynamic>.from(variables),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "version": version,
      "canvas": canvas.toMap(),
      "activePageId": activePageId,
      "pages": pages.map((e) => e.toMap()).toList(),
      "nodes": nodes.map((e) => e.toMap()).toList(),
      if (styles.isNotEmpty)
        "styles": styles.map((key, value) => MapEntry(key, value.toMap())),
      if (variables.isNotEmpty)
        "variables": Map<String, dynamic>.from(variables),
    };
  }

  static UiProject defaultTemplate() {
    return UiProject(
      version: "1.0",
      canvas: CanvasConfig(width: 120, height: 36, charset: Charset.unicode),
      pages: <UiPage>[
        UiPage(
          id: "page_main",
          name: "Main",
          llmComment: "",
          nodes: <UiNode>[
            UiNode(
              id: "root_panel",
              kind: NodeKind.box,
              x: 1,
              y: 1,
              width: 118,
              height: 34,
              props: <String, dynamic>{"title": "ASCII UI Runtime"},
              children: <UiNode>[
                UiNode(
                  id: "headline",
                  kind: NodeKind.label,
                  x: 2,
                  y: 1,
                  width: 40,
                  height: 1,
                  props: <String, dynamic>{
                    "text": "Edit YAML or draw directly on canvas"
                  },
                ),
                UiNode(
                  id: "demo_button",
                  kind: NodeKind.button,
                  x: 2,
                  y: 3,
                  width: 24,
                  height: 3,
                  props: <String, dynamic>{"text": "Run Preview"},
                ),
                UiNode(
                  id: "demo_input",
                  kind: NodeKind.input,
                  x: 2,
                  y: 7,
                  width: 48,
                  height: 3,
                  props: <String, dynamic>{"placeholder": "Type command..."},
                ),
              ],
            ),
          ],
        ),
      ],
      activePageId: "page_main",
    );
  }

  static Map<String, dynamic> _variablesFrom(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static List<UiPage> _normalizedPages(
      List<UiPage>? pages, List<UiNode>? nodes) {
    if (pages != null && pages.isNotEmpty) {
      return pages;
    }
    return <UiPage>[
      UiPage(
        id: "page_main",
        name: "Main",
        nodes: nodes ?? <UiNode>[],
      ),
    ];
  }

  static String _normalizedActivePageId(
    String? activePageId,
    List<UiPage>? pages,
    List<UiNode>? nodes,
  ) {
    final available = _normalizedPages(pages, nodes);
    if (activePageId != null && activePageId.trim().isNotEmpty) {
      final found = available.any((page) => page.id == activePageId);
      if (found) {
        return activePageId;
      }
    }
    return available.first.id;
  }
}

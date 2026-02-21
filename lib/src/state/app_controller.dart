import "dart:async";

import "package:flutter/foundation.dart";

import "../model/diagnostic.dart";
import "../model/ui_node.dart";
import "../model/ui_page.dart";
import "../model/ui_project.dart";
import "../services/ascii_renderer.dart";
import "../services/component_expander.dart";
import "../services/control_api.dart";
import "../services/control_server.dart";
import "../services/editor_config_storage.dart";
import "../services/layout_engine.dart";
import "../services/project_storage.dart";
import "../services/yaml_codec.dart";

enum PointerEditMode {
  move,
  resize,
}

class NodeHierarchyItem {
  NodeHierarchyItem({
    required this.id,
    required this.kind,
    required this.depth,
    required this.path,
  });

  final String id;
  final NodeKind kind;
  final int depth;
  final String path;
}

class AppController extends ChangeNotifier implements ControlApi {
  AppController()
      : _yamlCodec = ProjectYamlCodec(),
        _expander = ComponentExpander(),
        _layoutEngine = LayoutEngine(),
        _renderer = AsciiRenderer() {
    _storage = ProjectStorage(_yamlCodec);
    _configStorage = EditorConfigStorage();
    _server = ControlServer(api: this, defaultPort: 4049);
  }

  final ProjectYamlCodec _yamlCodec;
  final ComponentExpander _expander;
  final LayoutEngine _layoutEngine;
  final AsciiRenderer _renderer;

  late final ProjectStorage _storage;
  late final ControlServer _server;
  late final EditorConfigStorage _configStorage;

  UiProject _project = UiProject.defaultTemplate();
  String _yamlSource = "";
  String _asciiOutput = "";
  String _statusMessage = "Initializing...";
  String? _selectedNodeId;
  String? _currentProjectPath;
  List<String> _recentProjectPaths = <String>[];
  PointerEditMode _pointerEditMode = PointerEditMode.move;

  List<Diagnostic> _diagnostics = <Diagnostic>[];
  List<LayoutNode> _layoutNodes = <LayoutNode>[];
  Map<String, LayoutNode> _layoutById = <String, LayoutNode>{};
  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];
  bool _pointerSessionActive = false;
  int? _lastPickX;
  int? _lastPickY;

  UiProject get project => _project;
  String get yamlSource => _yamlSource;
  String get asciiOutput => _asciiOutput;
  String get statusMessage => _statusMessage;
  String? get selectedNodeId => _selectedNodeId;
  String? get currentProjectPath => _currentProjectPath;
  List<String> get recentProjectPaths =>
      List<String>.unmodifiable(_recentProjectPaths);
  List<UiPage> get pages => List<UiPage>.unmodifiable(_project.pages);
  String get activePageId => _project.activePageId;
  UiPage get activePage => _project.activePage;
  PointerEditMode get pointerEditMode => _pointerEditMode;
  List<Diagnostic> get diagnostics =>
      List<Diagnostic>.unmodifiable(_diagnostics);
  List<LayoutNode> get layoutNodes =>
      List<LayoutNode>.unmodifiable(_layoutNodes);
  Map<String, LayoutNode> get layoutById =>
      Map<String, LayoutNode>.unmodifiable(_layoutById);
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  List<NodeHierarchyItem> get nodeHierarchy {
    final output = <NodeHierarchyItem>[];
    final page = _project.activePage;
    final pageIndex = _project.indexOfPage(page.id);
    final pagePath = pageIndex >= 0 ? "pages[$pageIndex]" : "pages[0]";

    void visit(List<UiNode> nodes, int depth, String parentPath) {
      for (var i = 0; i < nodes.length; i++) {
        final node = nodes[i];
        final path = parentPath.isEmpty
            ? "$pagePath.nodes[$i]"
            : "$parentPath.children[$i]";
        output.add(
          NodeHierarchyItem(
            id: node.id,
            kind: node.kind,
            depth: depth,
            path: path,
          ),
        );
        visit(node.children, depth + 1, path);
      }
    }

    visit(_project.nodes, 0, "");
    return output;
  }

  bool get serverRunning => _server.isRunning;
  int? get serverPort => _server.port;
  String? get serverToken => _server.token;

  Future<void> initialize() async {
    await _loadEditorConfig();
    _yamlSource = _yamlCodec.encode(_project);
    _rebuild(baseDiagnostics: const <Diagnostic>[]);
    await startControlServer();
  }

  @override
  void dispose() {
    unawaited(_server.stop());
    super.dispose();
  }

  Future<void> startControlServer({int port = 4049}) async {
    try {
      await _server.start(port: port);
      _statusMessage = "Control server started on localhost:${_server.port}";
    } catch (error) {
      _statusMessage = "Control server start failed: $error";
    }
    notifyListeners();
  }

  Future<void> stopControlServer() async {
    await _server.stop();
    _statusMessage = "Control server stopped.";
    notifyListeners();
  }

  Future<bool> updateYamlFromEditor(String source) async {
    _yamlSource = source;
    final decoded = _yamlCodec.decodeWithDiagnostics(source);
    if (decoded.project == null || decoded.hasErrors) {
      _diagnostics = decoded.diagnostics;
      _statusMessage = "YAML has validation errors.";
      notifyListeners();
      return false;
    }

    _recordUndoSnapshot();
    _project = decoded.project!;
    if (_selectedNodeId != null && _findNodeById(_selectedNodeId!) == null) {
      _selectedNodeId = null;
    }
    _statusMessage = "YAML applied.";
    _rebuild(baseDiagnostics: decoded.diagnostics);
    return true;
  }

  void resetYamlFromProject() {
    _yamlSource = _yamlCodec.encode(_project);
    _statusMessage = "YAML regenerated from current model.";
    notifyListeners();
  }

  void setActivePage(String pageId, {bool captureUndo = true}) {
    if (pageId.trim().isEmpty) {
      return;
    }
    if (_project.activePageId == pageId) {
      return;
    }
    final exists = _project.pages.any((page) => page.id == pageId);
    if (!exists) {
      return;
    }

    _captureUndoIfNeeded(captureUndo);
    _project.activePageId = pageId;
    _selectedNodeId = null;
    _statusMessage = "Switched to page '$pageId'.";
    _commitAndRebuild();
  }

  void addPage({String? name}) {
    _captureUndoIfNeeded(true);
    final pageId = _nextPageId("page");
    final index = _project.pages.length + 1;
    final requestedName =
        (name == null || name.trim().isEmpty) ? "Page $index" : name.trim();
    final pageName = _nextUniquePageName(requestedName);
    _project.pages.add(
      UiPage(
        id: pageId,
        name: pageName,
        nodes: <UiNode>[],
      ),
    );
    _project.activePageId = pageId;
    _selectedNodeId = null;
    _statusMessage = pageName == requestedName
        ? "Added page '$pageName'."
        : "Added page '$pageName' (name adjusted).";
    _commitAndRebuild();
  }

  void renameActivePage(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final active = _project.activePage;
    final uniqueName = _nextUniquePageName(trimmed, excludePageId: active.id);
    if (active.name == uniqueName) {
      return;
    }
    _captureUndoIfNeeded(true);
    active.name = uniqueName;
    _statusMessage = uniqueName == trimmed
        ? "Renamed page to '$trimmed'."
        : "Renamed page to '$uniqueName' (name adjusted).";
    _commitAndRebuild();
  }

  void setActivePageLlmComment(String comment) {
    final normalized = comment.trim();
    if (_project.activePage.llmComment == normalized) {
      return;
    }
    _captureUndoIfNeeded(true);
    _project.activePage.llmComment = normalized;
    _statusMessage = "Updated page comment.";
    _commitAndRebuild();
  }

  void deleteActivePage() {
    if (_project.pages.length <= 1) {
      _statusMessage = "At least one page must remain.";
      notifyListeners();
      return;
    }

    _captureUndoIfNeeded(true);
    final removedId = _project.activePageId;
    final removeIndex = _project.indexOfPage(removedId);
    if (removeIndex < 0) {
      return;
    }
    _project.pages.removeAt(removeIndex);
    final nextIndex = removeIndex == 0 ? 0 : removeIndex - 1;
    _project.activePageId = _project.pages[nextIndex].id;
    _selectedNodeId = null;
    _statusMessage = "Deleted page '$removedId'.";
    _commitAndRebuild();
  }

  void selectNode(String? nodeId) {
    _selectedNodeId = nodeId;
    notifyListeners();
  }

  void setPointerEditMode(PointerEditMode mode) {
    if (_pointerEditMode == mode) {
      return;
    }
    _pointerEditMode = mode;
    _statusMessage = mode == PointerEditMode.move
        ? "Pointer mode: Move (Q)"
        : "Pointer mode: Size (W)";
    notifyListeners();
  }

  void beginPointerAdjustSession() {
    if (_pointerSessionActive) {
      return;
    }
    if (selectedNode == null) {
      return;
    }
    _pointerSessionActive = true;
    _recordUndoSnapshot();
  }

  void endPointerAdjustSession() {
    _pointerSessionActive = false;
  }

  void selectNodeAt(int x, int y) {
    final hitIds = <String>[];
    for (final node in _flattenLayout(_layoutNodes)) {
      if (!node.rect.contains(x, y)) {
        continue;
      }
      final sourceId = _sourceIdFromLayoutId(node.id);
      if (_findNodeById(sourceId) == null) {
        continue;
      }
      if (hitIds.contains(sourceId)) {
        continue;
      }
      hitIds.add(sourceId);
    }

    if (hitIds.isEmpty) {
      _lastPickX = null;
      _lastPickY = null;
      selectNode(null);
      return;
    }

    final selectedId = _selectedNodeId;
    final samePickSpot = _lastPickX == x && _lastPickY == y;
    String nextId;

    if (!samePickSpot || selectedId == null || !hitIds.contains(selectedId)) {
      nextId = hitIds.last;
    } else {
      final currentIndex = hitIds.indexOf(selectedId);
      final nextIndex = currentIndex > 0 ? currentIndex - 1 : hitIds.length - 1;
      nextId = hitIds[nextIndex];
    }

    _lastPickX = x;
    _lastPickY = y;
    selectNode(nextId);
  }

  void moveSelected(int dx, int dy, {bool captureUndo = true}) {
    final node = selectedNode;
    if (node == null || (dx == 0 && dy == 0)) {
      return;
    }
    _captureUndoIfNeeded(captureUndo);
    node.x += dx;
    node.y += dy;
    _statusMessage = "Moved '${node.id}'.";
    _commitAndRebuild();
  }

  void resizeSelected(int dw, int dh, {bool captureUndo = true}) {
    resizeSelectedByEdges(
      dRight: dw,
      dBottom: dh,
      captureUndo: captureUndo,
    );
  }

  void resizeSelectedByEdges({
    int dLeft = 0,
    int dTop = 0,
    int dRight = 0,
    int dBottom = 0,
    bool captureUndo = true,
  }) {
    final node = selectedNode;
    if (node == null ||
        (dLeft == 0 && dTop == 0 && dRight == 0 && dBottom == 0)) {
      return;
    }

    _captureUndoIfNeeded(captureUndo);

    var left = node.x + dLeft;
    var top = node.y + dTop;
    var right = node.x + node.width + dRight;
    var bottom = node.y + node.height + dBottom;

    if (right - left < 1) {
      if (dLeft != 0 && dRight == 0) {
        left = right - 1;
      } else {
        right = left + 1;
      }
    }
    if (bottom - top < 1) {
      if (dTop != 0 && dBottom == 0) {
        top = bottom - 1;
      } else {
        bottom = top + 1;
      }
    }

    left = _clampInt(left, 0, _project.canvas.width - 1);
    top = _clampInt(top, 0, _project.canvas.height - 1);
    right = _clampInt(right, left + 1, _project.canvas.width);
    bottom = _clampInt(bottom, top + 1, _project.canvas.height);

    node.x = left;
    node.y = top;
    node.width = right - left;
    node.height = bottom - top;

    _statusMessage = "Resized '${node.id}'.";
    _commitAndRebuild();
  }

  void setSelectedText(String value) {
    final node = selectedNode;
    if (node == null) {
      return;
    }
    _captureUndoIfNeeded(true);
    node.props["text"] = value;
    _statusMessage = "Updated text of '${node.id}'.";
    _commitAndRebuild();
  }

  void setSelectedProp(String key, dynamic value) {
    final node = selectedNode;
    if (node == null) {
      return;
    }
    _captureUndoIfNeeded(true);
    node.props[key] = value;
    _statusMessage = "Updated property '$key' on '${node.id}'.";
    _commitAndRebuild();
  }

  void replaceSelectedProps(Map<String, dynamic> newProps) {
    final node = selectedNode;
    if (node == null) {
      return;
    }
    _captureUndoIfNeeded(true);
    node.props
      ..clear()
      ..addAll(newProps);
    _statusMessage = "Updated properties of '${node.id}'.";
    _commitAndRebuild();
  }

  void deleteSelectedNode() {
    final id = _selectedNodeId;
    if (id == null) {
      return;
    }
    _captureUndoIfNeeded(true);
    if (_removeNodeById(_project.nodes, id)) {
      _selectedNodeId = null;
      _statusMessage = "Deleted '$id'.";
      _commitAndRebuild();
    }
  }

  void insertNode(NodeKind kind) {
    _captureUndoIfNeeded(true);
    final newNode = _defaultNodeFor(kind);
    final parent = selectedNode;
    if (parent != null && _isContainer(parent.kind)) {
      parent.children.add(newNode);
    } else {
      _project.nodes.add(newNode);
    }
    _selectedNodeId = newNode.id;
    _statusMessage = "Inserted '${newNode.id}'.";
    _commitAndRebuild();
  }

  void clearCanvas() {
    if (_project.nodes.isEmpty) {
      _statusMessage = "Canvas is already empty.";
      notifyListeners();
      return;
    }
    _captureUndoIfNeeded(true);
    _project.nodes.clear();
    _selectedNodeId = null;
    _statusMessage = "Canvas cleared.";
    _commitAndRebuild();
  }

  Future<void> _loadEditorConfig() async {
    try {
      final config = await _configStorage.load();
      _recentProjectPaths = config.recentProjects;
    } catch (_) {
      _recentProjectPaths = <String>[];
    }
  }

  Future<void> _recordRecentProjectPath(String rootPath) async {
    final normalized = rootPath.trim();
    if (normalized.isEmpty) {
      return;
    }
    final config = await _configStorage.addRecentProject(normalized);
    _recentProjectPaths = config.recentProjects;
  }

  Future<bool> loadProjectFromPath(String rootPath) async {
    try {
      final source = await _storage.loadMainYaml(rootPath);
      final ok = await updateYamlFromEditor(source);
      if (ok) {
        _currentProjectPath = rootPath;
        await _recordRecentProjectPath(rootPath);
        _statusMessage = "Loaded project: $rootPath";
        notifyListeners();
      }
      return ok;
    } catch (error) {
      _statusMessage = "Load failed: $error";
      notifyListeners();
      return false;
    }
  }

  Future<bool> saveProjectToPath(String rootPath) async {
    try {
      await _storage.saveProject(rootPath: rootPath, project: _project);
      _currentProjectPath = rootPath;
      await _recordRecentProjectPath(rootPath);
      _statusMessage = "Saved project: $rootPath";
      notifyListeners();
      return true;
    } catch (error) {
      _statusMessage = "Save failed: $error";
      notifyListeners();
      return false;
    }
  }

  bool applyPatchLocal(Map<String, dynamic> patch) {
    final op = patch["op"]?.toString() ?? "";
    switch (op) {
      case "set_bounds":
        final id = patch["id"]?.toString();
        if (id == null || id.isEmpty) {
          return false;
        }
        final node = _findNodeById(id);
        if (node == null) {
          return false;
        }
        _captureUndoIfNeeded(true);
        node.x = _toInt(patch["x"], fallback: node.x);
        node.y = _toInt(patch["y"], fallback: node.y);
        node.width = _clampInt(_toInt(patch["width"], fallback: node.width), 1,
            _project.canvas.width);
        node.height = _clampInt(_toInt(patch["height"], fallback: node.height),
            1, _project.canvas.height);
        _statusMessage = "Patch applied: set_bounds for '$id'.";
        _commitAndRebuild();
        return true;
      case "set_prop":
        final id = patch["id"]?.toString();
        final key = patch["key"]?.toString();
        if (id == null || key == null || id.isEmpty || key.isEmpty) {
          return false;
        }
        final node = _findNodeById(id);
        if (node == null) {
          return false;
        }
        _captureUndoIfNeeded(true);
        node.props[key] = patch["value"];
        _statusMessage = "Patch applied: set_prop '$key' on '$id'.";
        _commitAndRebuild();
        return true;
      case "add_node":
        final rawNode = patch["node"];
        if (rawNode is! Map) {
          return false;
        }
        _captureUndoIfNeeded(true);
        final node = UiNode.fromMap(Map<String, dynamic>.from(rawNode));
        if (_findNodeById(node.id) != null) {
          node.id = _nextNodeId(node.kind.name);
        }
        final parentId = patch["parentId"]?.toString();
        if (parentId == null || parentId.isEmpty) {
          _project.nodes.add(node);
        } else {
          final parent = _findNodeById(parentId);
          if (parent == null) {
            return false;
          }
          parent.children.add(node);
        }
        _selectedNodeId = node.id;
        _statusMessage = "Patch applied: add_node '${node.id}'.";
        _commitAndRebuild();
        return true;
      case "remove_node":
        final id = patch["id"]?.toString();
        if (id == null || id.isEmpty) {
          return false;
        }
        _captureUndoIfNeeded(true);
        final ok = _removeNodeById(_project.nodes, id);
        if (!ok) {
          return false;
        }
        if (_selectedNodeId == id) {
          _selectedNodeId = null;
        }
        _statusMessage = "Patch applied: remove_node '$id'.";
        _commitAndRebuild();
        return true;
      case "select":
        final id = patch["id"]?.toString();
        _selectedNodeId = id;
        _statusMessage = "Patch applied: select '$id'.";
        notifyListeners();
        return true;
      case "add_page":
        addPage(name: patch["name"]?.toString());
        _statusMessage = "Patch applied: add_page '${_project.activePageId}'.";
        return true;
      case "remove_page":
        final pageId = patch["id"]?.toString();
        if (pageId == null || pageId.isEmpty) {
          return false;
        }
        if (_project.activePageId != pageId) {
          setActivePage(pageId);
        }
        deleteActivePage();
        _statusMessage = "Patch applied: remove_page '$pageId'.";
        return true;
      case "set_active_page":
        final pageId = patch["id"]?.toString();
        if (pageId == null || pageId.isEmpty) {
          return false;
        }
        setActivePage(pageId);
        _statusMessage = "Patch applied: set_active_page '$pageId'.";
        return true;
      case "rename_page":
        final pageId = patch["id"]?.toString();
        final pageName = patch["name"]?.toString();
        if (pageId == null ||
            pageId.isEmpty ||
            pageName == null ||
            pageName.trim().isEmpty) {
          return false;
        }
        if (_project.activePageId != pageId) {
          setActivePage(pageId);
        }
        renameActivePage(pageName);
        _statusMessage = "Patch applied: rename_page '$pageId'.";
        return true;
      case "set_page_comment":
        final pageId = patch["id"]?.toString();
        if (pageId == null || pageId.isEmpty) {
          return false;
        }
        if (_project.activePageId != pageId) {
          setActivePage(pageId);
        }
        setActivePageLlmComment(patch["comment"]?.toString() ?? "");
        _statusMessage = "Patch applied: set_page_comment '$pageId'.";
        return true;
      default:
        return false;
    }
  }

  UiNode? get selectedNode {
    final id = _selectedNodeId;
    if (id == null || id.isEmpty) {
      return null;
    }
    return _findNodeById(id);
  }

  void _commitAndRebuild() {
    _yamlSource = _yamlCodec.encode(_project);
    _rebuild(baseDiagnostics: _yamlCodec.validateOnly(_yamlSource));
  }

  bool undo() {
    if (_undoStack.isEmpty) {
      return false;
    }
    _redoStack.add(_makeSnapshot());
    final snapshot = _undoStack.removeLast();
    _restoreSnapshot(snapshot, "Undo applied.");
    return true;
  }

  bool redo() {
    if (_redoStack.isEmpty) {
      return false;
    }
    _undoStack.add(_makeSnapshot());
    final snapshot = _redoStack.removeLast();
    _restoreSnapshot(snapshot, "Redo applied.");
    return true;
  }

  void _rebuild({required List<Diagnostic> baseDiagnostics}) {
    final expanded =
        _expander.expandAll(_project.nodes.map((e) => e.copy()).toList());
    final layout = _layoutEngine.compute(
      nodes: expanded,
      canvasWidth: _project.canvas.width,
      canvasHeight: _project.canvas.height,
    );

    _layoutNodes = layout.nodes;
    _layoutById = layout.byId;
    _asciiOutput = _renderer.render(
      canvas: _project.canvas,
      nodes: _layoutNodes,
    );
    _diagnostics = <Diagnostic>[
      ...baseDiagnostics,
      ...layout.diagnostics,
    ];
    notifyListeners();
  }

  UiNode _defaultNodeFor(NodeKind kind) {
    final id = _nextNodeId(kind.name);
    switch (kind) {
      case NodeKind.label:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 20,
          height: 1,
          props: <String, dynamic>{"text": "Label"},
        );
      case NodeKind.line:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 20,
          height: 1,
          props: <String, dynamic>{"orientation": "horizontal"},
        );
      case NodeKind.stack:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 30,
          height: 10,
          props: <String, dynamic>{"direction": "vertical", "spacing": 1},
        );
      case NodeKind.grid:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 30,
          height: 10,
          props: <String, dynamic>{"rows": 2, "cols": 2},
        );
      case NodeKind.input:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 34,
          height: 3,
          props: <String, dynamic>{
            "value": "",
            "placeholder": "Type here",
            "readOnly": false,
            "password": false,
            "maxLength": 64,
          },
        );
      case NodeKind.button:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 20,
          height: 3,
          props: <String, dynamic>{
            "text": "Button",
            "variant": "primary",
            "disabled": false,
            "hotkey": "Enter",
          },
        );
      case NodeKind.tab:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 40,
          height: 10,
          props: <String, dynamic>{
            "items": <String>["General", "Network", "Advanced"],
            "activeIndex": 0,
          },
        );
      case NodeKind.list:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 30,
          height: 8,
          props: <String, dynamic>{
            "title": "List",
            "items": <String>["Item A", "Item B", "Item C"],
            "selectedIndex": 0,
          },
        );
      case NodeKind.popup:
        return UiNode(
          id: id,
          kind: kind,
          x: 10,
          y: 6,
          width: 40,
          height: 12,
          props: <String, dynamic>{
            "title": "Confirm",
            "message": "Are you sure?",
            "buttons": <String>["Cancel", "OK"],
            "visible": true,
          },
        );
      case NodeKind.toggle:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 24,
          height: 3,
          props: <String, dynamic>{"text": "Toggle", "value": false},
        );
      case NodeKind.combo:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 24,
          height: 3,
          props: <String, dynamic>{
            "items": <String>["One", "Two", "Three"],
            "selectedIndex": 0,
            "placeholder": "Select",
            "expanded": false,
          },
        );
      case NodeKind.box:
        return UiNode(
          id: id,
          kind: kind,
          x: 2,
          y: 2,
          width: 24,
          height: 8,
          props: <String, dynamic>{"title": "Box"},
        );
    }
  }

  bool _isContainer(NodeKind kind) {
    switch (kind) {
      case NodeKind.box:
      case NodeKind.stack:
      case NodeKind.grid:
      case NodeKind.popup:
      case NodeKind.tab:
      case NodeKind.list:
        return true;
      case NodeKind.label:
      case NodeKind.line:
      case NodeKind.input:
      case NodeKind.button:
      case NodeKind.toggle:
      case NodeKind.combo:
        return false;
    }
  }

  UiNode? _findNodeById(String id, [List<UiNode>? nodes]) {
    final source = nodes ?? _project.nodes;
    for (final node in source) {
      if (node.id == id) {
        return node;
      }
      final found = _findNodeById(id, node.children);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  bool _removeNodeById(List<UiNode> nodes, String id) {
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      if (node.id == id) {
        nodes.removeAt(i);
        return true;
      }
      if (_removeNodeById(node.children, id)) {
        return true;
      }
    }
    return false;
  }

  Iterable<LayoutNode> _flattenLayout(List<LayoutNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* _flattenLayout(node.children);
    }
  }

  String _sourceIdFromLayoutId(String layoutId) {
    final index = layoutId.indexOf("__");
    return index >= 0 ? layoutId.substring(0, index) : layoutId;
  }

  int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  int _clampInt(int value, int min, int max) {
    if (max < min) {
      return min;
    }
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  void _captureUndoIfNeeded(bool captureUndo) {
    if (!captureUndo) {
      return;
    }
    if (_pointerSessionActive) {
      return;
    }
    _recordUndoSnapshot();
  }

  void _recordUndoSnapshot() {
    _undoStack.add(_makeSnapshot());
    if (_undoStack.length > 200) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  _EditorSnapshot _makeSnapshot() {
    return _EditorSnapshot(
      project: _project.copy(),
      selectedNodeId: _selectedNodeId,
    );
  }

  void _restoreSnapshot(_EditorSnapshot snapshot, String message) {
    _project = snapshot.project.copy();
    _selectedNodeId = snapshot.selectedNodeId;
    _yamlSource = _yamlCodec.encode(_project);
    _statusMessage = message;
    _rebuild(baseDiagnostics: _yamlCodec.validateOnly(_yamlSource));
  }

  String _nextNodeId(String prefix) {
    final cleaned = prefix.trim().isEmpty ? "node" : prefix.trim();
    var index = 1;
    while (true) {
      final candidate = "${cleaned}_$index";
      if (_findNodeById(candidate) == null) {
        return candidate;
      }
      index++;
    }
  }

  String _nextPageId(String prefix) {
    final cleaned = prefix.trim().isEmpty ? "page" : prefix.trim();
    var index = 1;
    while (true) {
      final candidate = "${cleaned}_$index";
      final exists = _project.pages.any((page) => page.id == candidate);
      if (!exists) {
        return candidate;
      }
      index++;
    }
  }

  String _nextUniquePageName(String base, {String? excludePageId}) {
    final seed = base.trim().isEmpty ? "Page" : base.trim();
    if (!_pageNameExists(seed, excludePageId: excludePageId)) {
      return seed;
    }

    var index = 2;
    while (true) {
      final candidate = "$seed ($index)";
      if (!_pageNameExists(candidate, excludePageId: excludePageId)) {
        return candidate;
      }
      index++;
    }
  }

  bool _pageNameExists(String name, {String? excludePageId}) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    for (final page in _project.pages) {
      if (excludePageId != null && page.id == excludePageId) {
        continue;
      }
      if (page.name.trim().toLowerCase() == normalized) {
        return true;
      }
    }
    return false;
  }

  @override
  Map<String, dynamic> healthPayload() {
    return <String, dynamic>{
      "ok": true,
      "server": "asciipaint-control",
      "port": _server.port,
      "token": _server.token,
      "selectedNodeId": _selectedNodeId,
      "activePageId": _project.activePageId,
      "pageCount": _project.pages.length,
      "currentProjectPath": _currentProjectPath,
      "recentProjectCount": _recentProjectPaths.length,
      "diagnosticCount": _diagnostics.length,
    };
  }

  @override
  Future<Map<String, dynamic>> applyCanvasPatch(
      Map<String, dynamic> patch) async {
    final ok = applyPatchLocal(patch);
    return <String, dynamic>{
      "ok": ok,
      "status": _statusMessage,
      "ascii": _asciiOutput,
      "diagnostics": _diagnostics.map((d) => d.toMap()).toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> loadProject(String rootPath) async {
    final ok = await loadProjectFromPath(rootPath);
    return <String, dynamic>{
      "ok": ok,
      "status": _statusMessage,
      "path": rootPath,
      "diagnostics": _diagnostics.map((d) => d.toMap()).toList(),
    };
  }

  @override
  Future<Map<String, dynamic>> renderPreview(String yamlSource) async {
    final decoded = _yamlCodec.decodeWithDiagnostics(yamlSource);
    if (decoded.project == null || decoded.hasErrors) {
      return <String, dynamic>{
        "ok": false,
        "diagnostics": decoded.diagnostics.map((d) => d.toMap()).toList(),
      };
    }

    final expanded = _expander
        .expandAll(decoded.project!.nodes.map((e) => e.copy()).toList());
    final layout = _layoutEngine.compute(
      nodes: expanded,
      canvasWidth: decoded.project!.canvas.width,
      canvasHeight: decoded.project!.canvas.height,
    );
    final ascii = _renderer.render(
      canvas: decoded.project!.canvas,
      nodes: layout.nodes,
    );
    return <String, dynamic>{
      "ok": true,
      "ascii": ascii,
      "diagnostics": <Map<String, dynamic>>[
        ...decoded.diagnostics.map((d) => d.toMap()),
        ...layout.diagnostics.map((d) => d.toMap()),
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> resetSession() async {
    _captureUndoIfNeeded(true);
    _project = UiProject.defaultTemplate();
    _selectedNodeId = null;
    _yamlSource = _yamlCodec.encode(_project);
    _statusMessage = "Session reset to default template.";
    _rebuild(baseDiagnostics: _yamlCodec.validateOnly(_yamlSource));
    return <String, dynamic>{
      "ok": true,
      "status": _statusMessage,
      "ascii": _asciiOutput,
    };
  }

  @override
  Future<Map<String, dynamic>> saveProject(String rootPath) async {
    final ok = await saveProjectToPath(rootPath);
    return <String, dynamic>{
      "ok": ok,
      "status": _statusMessage,
      "path": rootPath,
    };
  }

  @override
  Future<Map<String, dynamic>> validateYaml(String yamlSource) async {
    final decoded = _yamlCodec.decodeWithDiagnostics(yamlSource);
    return <String, dynamic>{
      "ok": !decoded.hasErrors,
      "diagnostics": decoded.diagnostics.map((d) => d.toMap()).toList(),
    };
  }
}

class _EditorSnapshot {
  _EditorSnapshot({
    required this.project,
    required this.selectedNodeId,
  });

  final UiProject project;
  final String? selectedNodeId;
}

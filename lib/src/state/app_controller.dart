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

enum StandaloneOverlayPreviewMode {
  oneLevel,
  fullTree,
}

StandaloneOverlayPreviewMode standaloneOverlayPreviewModeFromString(
    String? value) {
  switch ((value ?? "").trim().toLowerCase()) {
    case "full_tree":
    case "fulltree":
      return StandaloneOverlayPreviewMode.fullTree;
    case "one_level":
    case "onelevel":
    default:
      return StandaloneOverlayPreviewMode.oneLevel;
  }
}

String standaloneOverlayPreviewModeToString(StandaloneOverlayPreviewMode mode) {
  switch (mode) {
    case StandaloneOverlayPreviewMode.fullTree:
      return "full_tree";
    case StandaloneOverlayPreviewMode.oneLevel:
      return "one_level";
  }
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
  double _canvasZoom = 1.0;
  List<String> _recentProjectPaths = <String>[];
  PointerEditMode _pointerEditMode = PointerEditMode.move;
  StandaloneOverlayPreviewMode _standaloneOverlayPreviewMode =
      StandaloneOverlayPreviewMode.oneLevel;

  List<Diagnostic> _diagnostics = <Diagnostic>[];
  List<LayoutNode> _layoutNodes = <LayoutNode>[];
  Map<String, LayoutNode> _layoutById = <String, LayoutNode>{};
  List<RectI> _asciiBoardRegions = <RectI>[];
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
  double get canvasZoom => _canvasZoom;
  List<String> get recentProjectPaths =>
      List<String>.unmodifiable(_recentProjectPaths);
  List<UiPage> get pages => List<UiPage>.unmodifiable(_project.pages);
  String get activePageId => _project.activePageId;
  UiPage get activePage => _project.activePage;
  PointerEditMode get pointerEditMode => _pointerEditMode;
  StandaloneOverlayPreviewMode get standaloneOverlayPreviewMode =>
      _standaloneOverlayPreviewMode;
  List<Diagnostic> get diagnostics =>
      List<Diagnostic>.unmodifiable(_diagnostics);
  List<LayoutNode> get layoutNodes =>
      List<LayoutNode>.unmodifiable(_layoutNodes);
  Map<String, LayoutNode> get layoutById =>
      Map<String, LayoutNode>.unmodifiable(_layoutById);
  List<RectI> get asciiBoardRegions =>
      List<RectI>.unmodifiable(_asciiBoardRegions);
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

  String buildLlmMarkdownExport() {
    final active = _project.activePage;
    final activePageAscii = _renderEffectivePageAscii(
      pageId: active.id,
      source: _project,
    );
    final yaml = _yamlSource.trimRight();
    final buffer = StringBuffer()
      ..writeln("# ASCII UI Export")
      ..writeln()
      ..writeln("## Active Page")
      ..writeln("- id: `${active.id}`")
      ..writeln("- name: `${active.name}`")
      ..writeln("- mode: `${active.mode.name}`")
      ..writeln(
          "- basePageId: `${(active.basePageId == null || active.basePageId!.trim().isEmpty) ? "-" : active.basePageId}`")
      ..writeln(
          "- canvas: `${_project.canvas.width} x ${_project.canvas.height}`")
      ..writeln(
          "- standalone overlay preview mode: `${_standaloneOverlayPreviewMode.name}`")
      ..writeln()
      ..writeln("## ASCII (Active Page Only)")
      ..writeln("```text")
      ..writeln(activePageAscii)
      ..writeln("```")
      ..writeln()
      ..writeln("## YAML")
      ..writeln("```yaml")
      ..writeln(yaml)
      ..writeln("```");
    return buffer.toString();
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

  void setActivePageMode(UiPageMode mode) {
    final active = _project.activePage;
    if (active.mode == mode) {
      return;
    }

    if (mode == UiPageMode.overlay &&
        _firstBaseCandidateFor(active.id) == null) {
      _statusMessage = "Overlay mode needs at least one other page.";
      notifyListeners();
      return;
    }

    _captureUndoIfNeeded(true);
    active.mode = mode;
    if (mode == UiPageMode.standalone) {
      active.basePageId = null;
    } else {
      active.basePageId ??= _firstBaseCandidateFor(active.id);
    }
    _statusMessage = "Set page mode to '${mode.name}'.";
    _commitAndRebuild();
  }

  void setActivePageBasePage(String? pageId) {
    final active = _project.activePage;
    if (active.mode != UiPageMode.overlay) {
      return;
    }
    final normalized = pageId?.trim();
    if (normalized == null || normalized.isEmpty) {
      if (active.mode == UiPageMode.standalone && active.basePageId == null) {
        return;
      }
      _captureUndoIfNeeded(true);
      active.mode = UiPageMode.standalone;
      active.basePageId = null;
      _statusMessage = "Overlay disabled (switched to standalone).";
      _commitAndRebuild();
      return;
    }
    if (normalized == active.id) {
      return;
    }
    final exists = _project.pages.any((page) => page.id == normalized);
    if (!exists) {
      return;
    }
    if (active.basePageId == normalized) {
      return;
    }

    _captureUndoIfNeeded(true);
    active.basePageId = normalized;
    _statusMessage = "Set overlay base page to '$normalized'.";
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
    for (final page in _project.pages) {
      if (page.basePageId == removedId) {
        page.mode = UiPageMode.standalone;
        page.basePageId = null;
      }
    }
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

  void setStandaloneOverlayPreviewMode(StandaloneOverlayPreviewMode mode) {
    if (_standaloneOverlayPreviewMode == mode) {
      return;
    }
    _standaloneOverlayPreviewMode = mode;
    _statusMessage = mode == StandaloneOverlayPreviewMode.fullTree
        ? "Standalone overlay preview: full tree"
        : "Standalone overlay preview: 1 level";
    _rebuild(baseDiagnostics: _yamlCodec.validateOnly(_yamlSource));
    unawaited(
      _configStorage.updateStandaloneOverlayPreviewMode(
        standaloneOverlayPreviewModeToString(mode),
      ),
    );
  }

  void setCanvasZoom(double zoom) {
    final clamped = zoom.clamp(0.5, 3.0).toDouble();
    if ((clamped - _canvasZoom).abs() < 0.001) {
      return;
    }
    _canvasZoom = clamped;
    _statusMessage = "Canvas zoom: ${(_canvasZoom * 100).round()}% (view only)";
    notifyListeners();
  }

  void zoomInCanvasView() => setCanvasZoom(_canvasZoom + 0.1);
  void zoomOutCanvasView() => setCanvasZoom(_canvasZoom - 0.1);
  void resetCanvasZoom() => setCanvasZoom(1.0);

  void scaleProject(double factor) {
    if (factor <= 0) {
      return;
    }
    _captureUndoIfNeeded(true);

    _project.canvas.width =
        _clampInt((_project.canvas.width * factor).round(), 1, 10000);
    _project.canvas.height =
        _clampInt((_project.canvas.height * factor).round(), 1, 10000);

    void scaleNodes(List<UiNode> nodes) {
      for (final node in nodes) {
        node.x = (node.x * factor).round();
        node.y = (node.y * factor).round();
        node.width =
            _clampInt((node.width * factor).round(), 1, _project.canvas.width);
        node.height = _clampInt(
            (node.height * factor).round(), 1, _project.canvas.height);
        scaleNodes(node.children);
      }
    }

    for (final page in _project.pages) {
      scaleNodes(page.nodes);
    }

    _statusMessage = "Scaled project by ${(factor * 100).round()}%.";
    _commitAndRebuild();
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
      _standaloneOverlayPreviewMode = standaloneOverlayPreviewModeFromString(
        config.standaloneOverlayPreviewMode,
      );
    } catch (_) {
      _recentProjectPaths = <String>[];
      _standaloneOverlayPreviewMode = StandaloneOverlayPreviewMode.oneLevel;
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
      case "set_page_mode":
        final pageId = patch["id"]?.toString() ?? _project.activePageId;
        final modeRaw = patch["mode"]?.toString();
        if (pageId.trim().isEmpty ||
            modeRaw == null ||
            modeRaw.trim().isEmpty) {
          return false;
        }
        final normalizedMode = modeRaw.trim().toLowerCase();
        if (normalizedMode != UiPageMode.standalone.name &&
            normalizedMode != UiPageMode.overlay.name) {
          return false;
        }
        if (!_project.pagesById.containsKey(pageId)) {
          return false;
        }
        if (_project.activePageId != pageId) {
          setActivePage(pageId, captureUndo: false);
        }
        final mode = pageModeFromString(normalizedMode);
        final before = activePage.mode;
        setActivePageMode(mode);
        if (before == mode) {
          _statusMessage = "Patch applied: set_page_mode '$pageId' unchanged.";
        } else {
          _statusMessage =
              "Patch applied: set_page_mode '$pageId' -> '${mode.name}'.";
        }
        notifyListeners();
        return true;
      case "set_page_base":
        final pageId = patch["id"]?.toString() ?? _project.activePageId;
        if (pageId.trim().isEmpty || !_project.pagesById.containsKey(pageId)) {
          return false;
        }
        final rawBase = patch.containsKey("basePageId")
            ? patch["basePageId"]
            : patch.containsKey("baseId")
                ? patch["baseId"]
                : patch["value"];
        final baseId = rawBase?.toString().trim();
        if (_project.activePageId != pageId) {
          setActivePage(pageId, captureUndo: false);
        }
        if (baseId == null || baseId.isEmpty) {
          if (activePage.mode == UiPageMode.overlay) {
            setActivePageMode(UiPageMode.standalone);
          }
          _statusMessage = "Patch applied: set_page_base '$pageId' cleared.";
          notifyListeners();
          return true;
        }
        if (baseId == pageId || !_project.pagesById.containsKey(baseId)) {
          return false;
        }
        if (activePage.mode != UiPageMode.overlay) {
          setActivePageMode(UiPageMode.overlay);
          if (activePage.mode != UiPageMode.overlay) {
            return false;
          }
        }
        setActivePageBasePage(baseId);
        if (activePage.basePageId != baseId) {
          return false;
        }
        _statusMessage = "Patch applied: set_page_base '$pageId' -> '$baseId'.";
        notifyListeners();
        return true;
      case "set_standalone_overlay_preview_mode":
        final modeRaw = patch["mode"]?.toString();
        if (modeRaw == null || modeRaw.trim().isEmpty) {
          return false;
        }
        final normalized = modeRaw.trim().toLowerCase();
        final valid = normalized == "one_level" ||
            normalized == "onelevel" ||
            normalized == "full_tree" ||
            normalized == "fulltree";
        if (!valid) {
          return false;
        }
        final mode = standaloneOverlayPreviewModeFromString(normalized);
        setStandaloneOverlayPreviewMode(mode);
        _statusMessage =
            "Patch applied: set_standalone_overlay_preview_mode '${mode.name}'.";
        notifyListeners();
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
    final effectiveNodes = _effectiveNodesForPage(_project.activePageId);
    final expanded = _expander.expandAll(effectiveNodes);
    final layout = _layoutEngine.compute(
      nodes: expanded,
      canvasWidth: _project.canvas.width,
      canvasHeight: _project.canvas.height,
    );

    _layoutNodes = layout.nodes;
    _layoutById = layout.byId;
    final baseAscii = _renderer.render(
      canvas: _project.canvas,
      nodes: _layoutNodes,
    );
    final activePage = _project.activePage;
    final includeAllDescendants = activePage.mode == UiPageMode.standalone &&
        _standaloneOverlayPreviewMode == StandaloneOverlayPreviewMode.fullTree;
    final hasOverlayChildren = _hasOverlayChildren(
      pageId: activePage.id,
      source: _project,
    );
    if (hasOverlayChildren) {
      final composite = _composeAsciiWithOverlayPreviews(
        baseAscii: baseAscii,
        basePage: activePage,
        source: _project,
        includeAllDescendants: includeAllDescendants,
      );
      _asciiOutput = composite.ascii;
      _asciiBoardRegions = composite.boardRegions;
    } else {
      _asciiOutput = baseAscii;
      _asciiBoardRegions = <RectI>[
        RectI(
          x: 0,
          y: 0,
          width: _project.canvas.width,
          height: _project.canvas.height,
        ),
      ];
    }
    _diagnostics = <Diagnostic>[
      ...baseDiagnostics,
      ...layout.diagnostics,
    ];
    notifyListeners();
  }

  List<UiNode> _effectiveNodesForPage(
    String pageId, {
    UiProject? project,
  }) {
    final source = project ?? _project;
    UiPage? target;
    for (final page in source.pages) {
      if (page.id == pageId) {
        target = page;
        break;
      }
    }
    target ??= source.pages.isEmpty ? null : source.pages.first;
    if (target == null) {
      return <UiNode>[];
    }

    final output = <UiNode>[];

    void append(UiPage page, Set<String> stack) {
      if (stack.contains(page.id)) {
        return;
      }
      stack.add(page.id);

      if (page.mode == UiPageMode.overlay &&
          page.basePageId != null &&
          page.basePageId!.trim().isNotEmpty) {
        final base = source.pagesById[page.basePageId];
        if (base != null) {
          append(base, stack);
        }
      }

      output.addAll(page.nodes.map((e) => e.copy()));
      stack.remove(page.id);
    }

    append(target, <String>{});
    return output;
  }

  _AsciiCompositeResult _composeAsciiWithOverlayPreviews({
    required String baseAscii,
    required UiPage basePage,
    required UiProject source,
    required bool includeAllDescendants,
  }) {
    final mainBoard = RectI(
      x: 0,
      y: 0,
      width: source.canvas.width,
      height: source.canvas.height,
    );
    final pageOrderById = _pageOrderById(source);
    final roots = _overlayChildrenOf(
      baseId: basePage.id,
      source: source,
      pageOrderById: pageOrderById,
    );
    const columnGap = 12;
    const laneGap = 8;
    const headerHeight = 1;
    const headerBodyGap = 1;
    const rowGap = 3;
    const indentCap = 6;
    final pageWidth = source.canvas.width;
    final pageHeight = source.canvas.height;
    const bodyY = headerHeight + headerBodyGap;
    final tileHeight = bodyY + pageHeight;
    if (roots.isEmpty) {
      return _AsciiCompositeResult(
        ascii: baseAscii,
        boardRegions: <RectI>[mainBoard],
      );
    }

    final lanes = <List<_OverlayPreviewEntry>>[];
    for (final root in roots) {
      if (includeAllDescendants) {
        final entries = _collectOverlayLaneEntries(
          root: root,
          source: source,
          pageOrderById: pageOrderById,
        );
        if (entries.isNotEmpty) {
          lanes.add(entries);
        }
      } else {
        lanes.add(
          <_OverlayPreviewEntry>[
            _OverlayPreviewEntry(page: root, depth: 0),
          ],
        );
      }
    }
    if (lanes.isEmpty) {
      return _AsciiCompositeResult(
        ascii: baseAscii,
        boardRegions: <RectI>[mainBoard],
      );
    }

    var maxLaneHeight = 0;
    for (final lane in lanes) {
      final laneHeight = lane.length * tileHeight + (lane.length - 1) * rowGap;
      if (laneHeight > maxLaneHeight) {
        maxLaneHeight = laneHeight;
      }
    }

    final previewStartX = pageWidth + columnGap;
    final previewWidth =
        lanes.length * pageWidth + (lanes.length - 1) * laneGap;
    final outputWidth = pageWidth + columnGap + previewWidth;
    final outputHeight =
        pageHeight > maxLaneHeight ? pageHeight : maxLaneHeight;
    final boardRegions = <RectI>[mainBoard];
    final grid = List<List<String>>.generate(
      outputHeight,
      (_) => List<String>.filled(outputWidth, " "),
    );

    _blitAscii(
      grid: grid,
      ascii: baseAscii,
      dstX: 0,
      dstY: 0,
      maxWidth: pageWidth,
      maxHeight: pageHeight,
    );

    for (var laneIndex = 0; laneIndex < lanes.length; laneIndex++) {
      final laneX = previewStartX + laneIndex * (pageWidth + laneGap);
      final lane = lanes[laneIndex];
      for (var rowIndex = 0; rowIndex < lane.length; rowIndex++) {
        final entry = lane[rowIndex];
        final slotY = rowIndex * (tileHeight + rowGap);
        final header = includeAllDescendants
            ? () {
                final visualDepth =
                    entry.depth > indentCap ? indentCap : entry.depth;
                final indent = List<String>.filled(visualDepth, "  ").join();
                return "[overlay d${entry.depth + 1}] $indent${entry.page.name}";
              }()
            : "[overlay] ${entry.page.name}";
        _blitText(
          grid: grid,
          text: header,
          x: laneX,
          y: slotY,
          maxWidth: pageWidth,
        );
        final overlayAscii = _renderEffectivePageAscii(
          pageId: entry.page.id,
          source: source,
        );
        _blitAscii(
          grid: grid,
          ascii: overlayAscii,
          dstX: laneX,
          dstY: slotY + bodyY,
          maxWidth: pageWidth,
          maxHeight: pageHeight,
        );
        boardRegions.add(
          RectI(
            x: laneX,
            y: slotY + bodyY,
            width: pageWidth,
            height: pageHeight,
          ),
        );
      }
    }

    return _AsciiCompositeResult(
      ascii: grid.map((line) => line.join()).join("\n"),
      boardRegions: boardRegions,
    );
  }

  List<UiPage> _overlayChildrenOf({
    required String baseId,
    required UiProject source,
    required Map<String, int> pageOrderById,
  }) {
    final children = source.pages
        .where(
          (page) =>
              page.mode == UiPageMode.overlay &&
              page.basePageId != null &&
              page.basePageId!.trim() == baseId,
        )
        .toList();
    children.sort(
      (a, b) => _compareOverlayPreviewOrder(
        a,
        b,
        pageOrderById,
      ),
    );
    return children;
  }

  List<_OverlayPreviewEntry> _collectOverlayLaneEntries({
    required UiPage root,
    required UiProject source,
    required Map<String, int> pageOrderById,
  }) {
    final output = <_OverlayPreviewEntry>[];
    final stack = <String>{};

    void visit(UiPage page, int depth) {
      if (!stack.add(page.id)) {
        return;
      }
      output.add(_OverlayPreviewEntry(page: page, depth: depth));
      final children = _overlayChildrenOf(
        baseId: page.id,
        source: source,
        pageOrderById: pageOrderById,
      );
      for (final child in children) {
        visit(child, depth + 1);
      }
      stack.remove(page.id);
    }

    visit(root, 0);
    return output;
  }

  Map<String, int> _pageOrderById(UiProject source) {
    final output = <String, int>{};
    for (var i = 0; i < source.pages.length; i++) {
      output[source.pages[i].id] = i;
    }
    return output;
  }

  int _compareOverlayPreviewOrder(
    UiPage a,
    UiPage b,
    Map<String, int> pageOrderById,
  ) {
    final aOrder = a.previewOrder;
    final bOrder = b.previewOrder;
    if (aOrder != null && bOrder != null && aOrder != bOrder) {
      return aOrder.compareTo(bOrder);
    }
    if (aOrder != null && bOrder == null) {
      return -1;
    }
    if (aOrder == null && bOrder != null) {
      return 1;
    }
    final aIndex = pageOrderById[a.id] ?? 1 << 20;
    final bIndex = pageOrderById[b.id] ?? 1 << 20;
    if (aIndex != bIndex) {
      return aIndex.compareTo(bIndex);
    }
    return a.id.compareTo(b.id);
  }

  bool _hasOverlayChildren({
    required String pageId,
    required UiProject source,
  }) {
    for (final page in source.pages) {
      if (page.mode != UiPageMode.overlay) {
        continue;
      }
      if (page.basePageId?.trim() == pageId) {
        return true;
      }
    }
    return false;
  }

  String _renderEffectivePageAscii({
    required String pageId,
    required UiProject source,
  }) {
    final effectiveNodes = _effectiveNodesForPage(pageId, project: source);
    final expanded = _expander.expandAll(effectiveNodes);
    final layout = _layoutEngine.compute(
      nodes: expanded,
      canvasWidth: source.canvas.width,
      canvasHeight: source.canvas.height,
    );
    return _renderer.render(
      canvas: source.canvas,
      nodes: layout.nodes,
    );
  }

  void _blitAscii({
    required List<List<String>> grid,
    required String ascii,
    required int dstX,
    required int dstY,
    required int maxWidth,
    required int maxHeight,
  }) {
    final lines = ascii.split("\n");
    final visibleRows = lines.length < maxHeight ? lines.length : maxHeight;
    for (var row = 0; row < visibleRows; row++) {
      final line = lines[row];
      final visibleCols = line.length < maxWidth ? line.length : maxWidth;
      for (var col = 0; col < visibleCols; col++) {
        final y = dstY + row;
        final x = dstX + col;
        if (y < 0 || y >= grid.length) {
          continue;
        }
        if (x < 0 || x >= grid[y].length) {
          continue;
        }
        grid[y][x] = line[col];
      }
    }
  }

  void _blitText({
    required List<List<String>> grid,
    required String text,
    required int x,
    required int y,
    required int maxWidth,
  }) {
    if (y < 0 || y >= grid.length) {
      return;
    }
    final limit = text.length < maxWidth ? text.length : maxWidth;
    for (var i = 0; i < limit; i++) {
      final col = x + i;
      if (col < 0 || col >= grid[y].length) {
        continue;
      }
      grid[y][col] = text[i];
    }
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

  String? _firstBaseCandidateFor(String activePageId) {
    for (final page in _project.pages) {
      if (page.id != activePageId) {
        return page.id;
      }
    }
    return null;
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
      "canvasZoom": _canvasZoom,
      "standaloneOverlayPreviewMode":
          standaloneOverlayPreviewModeToString(_standaloneOverlayPreviewMode),
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

    final previewNodes = _effectiveNodesForPage(
      decoded.project!.activePageId,
      project: decoded.project!,
    );
    final expanded = _expander.expandAll(previewNodes);
    final layout = _layoutEngine.compute(
      nodes: expanded,
      canvasWidth: decoded.project!.canvas.width,
      canvasHeight: decoded.project!.canvas.height,
    );
    final baseAscii = _renderer.render(
      canvas: decoded.project!.canvas,
      nodes: layout.nodes,
    );
    final activePage = decoded.project!.activePage;
    final includeAllDescendants = activePage.mode == UiPageMode.standalone &&
        _standaloneOverlayPreviewMode == StandaloneOverlayPreviewMode.fullTree;
    final ascii = _hasOverlayChildren(
      pageId: activePage.id,
      source: decoded.project!,
    )
        ? _composeAsciiWithOverlayPreviews(
            baseAscii: baseAscii,
            basePage: activePage,
            source: decoded.project!,
            includeAllDescendants: includeAllDescendants,
          ).ascii
        : baseAscii;
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

class _AsciiCompositeResult {
  _AsciiCompositeResult({
    required this.ascii,
    required this.boardRegions,
  });

  final String ascii;
  final List<RectI> boardRegions;
}

class _OverlayPreviewEntry {
  _OverlayPreviewEntry({
    required this.page,
    required this.depth,
  });

  final UiPage page;
  final int depth;
}

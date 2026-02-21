import "package:json2yaml/json2yaml.dart";
import "package:yaml/yaml.dart";

import "../model/diagnostic.dart";
import "../model/ui_node.dart";
import "../model/ui_page.dart";
import "../model/ui_project.dart";

class YamlDecodeResult {
  YamlDecodeResult({
    this.project,
    List<Diagnostic>? diagnostics,
  }) : diagnostics = diagnostics ?? <Diagnostic>[];

  final UiProject? project;
  final List<Diagnostic> diagnostics;

  bool get hasErrors =>
      diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
}

class ProjectYamlCodec {
  YamlDecodeResult decodeWithDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    dynamic raw;

    try {
      raw = loadYaml(source);
    } on YamlException catch (error) {
      final span = error.span;
      final line = span?.start.line ?? 0;
      diagnostics.add(
        Diagnostic.error(
          "yaml.parse_error",
          error.message,
          path: "line:${line + 1}",
        ),
      );
      return YamlDecodeResult(diagnostics: diagnostics);
    } catch (error) {
      diagnostics.add(
        Diagnostic.error("yaml.parse_error", error.toString()),
      );
      return YamlDecodeResult(diagnostics: diagnostics);
    }

    if (raw is! Map) {
      diagnostics.add(
        Diagnostic.error(
            "yaml.root_type", "Root YAML node must be a mapping object."),
      );
      return YamlDecodeResult(diagnostics: diagnostics);
    }

    final normalized = _normalize(raw);
    if (normalized is! Map<String, dynamic>) {
      diagnostics.add(
        Diagnostic.error(
            "yaml.root_type", "Unable to normalize YAML root mapping."),
      );
      return YamlDecodeResult(diagnostics: diagnostics);
    }

    final project = UiProject.fromMap(normalized);
    diagnostics.addAll(_validateProject(project));
    return YamlDecodeResult(project: project, diagnostics: diagnostics);
  }

  List<Diagnostic> validateOnly(String source) {
    return decodeWithDiagnostics(source).diagnostics;
  }

  String encode(UiProject project) {
    return json2yaml(project.toMap());
  }

  dynamic _normalize(dynamic input) {
    if (input is YamlMap) {
      final out = <String, dynamic>{};
      for (final entry in input.entries) {
        out[entry.key.toString()] = _normalize(entry.value);
      }
      return out;
    }
    if (input is YamlList) {
      return input.map(_normalize).toList();
    }
    if (input is Map) {
      final out = <String, dynamic>{};
      for (final entry in input.entries) {
        out[entry.key.toString()] = _normalize(entry.value);
      }
      return out;
    }
    if (input is List) {
      return input.map(_normalize).toList();
    }
    return input;
  }

  List<Diagnostic> _validateProject(UiProject project) {
    final diagnostics = <Diagnostic>[];
    if (project.canvas.width <= 0 || project.canvas.height <= 0) {
      diagnostics.add(
        Diagnostic.error(
          "canvas.size_invalid",
          "Canvas width and height must be greater than zero.",
          path: "canvas",
        ),
      );
    }

    if (project.pages.isEmpty) {
      diagnostics.add(
        Diagnostic.error(
          "project.pages_missing",
          "Project must contain at least one page.",
          path: "pages",
        ),
      );
      return diagnostics;
    }

    final seenPageIds = <String>{};
    final pageById = project.pagesById;
    for (var i = 0; i < project.pages.length; i++) {
      final page = project.pages[i];
      if (page.id.trim().isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            "page.id_missing",
            "Page ID is required.",
            path: "pages[$i]",
          ),
        );
        continue;
      }
      if (!seenPageIds.add(page.id)) {
        diagnostics.add(
          Diagnostic.error(
            "page.id_duplicate",
            "Duplicate page ID '${page.id}'.",
            path: "pages[$i]",
          ),
        );
      }

      if (page.mode == UiPageMode.overlay) {
        final baseId = page.basePageId?.trim();
        if (baseId == null || baseId.isEmpty) {
          diagnostics.add(
            Diagnostic.error(
              "page.base_missing",
              "Overlay page '${page.id}' must set basePageId.",
              path: "pages[$i]",
            ),
          );
        } else if (baseId == page.id) {
          diagnostics.add(
            Diagnostic.error(
              "page.base_self",
              "Overlay page '${page.id}' cannot inherit itself.",
              path: "pages[$i]",
            ),
          );
        } else if (!pageById.containsKey(baseId)) {
          diagnostics.add(
            Diagnostic.error(
              "page.base_not_found",
              "Overlay page '${page.id}' references unknown basePageId '$baseId'.",
              path: "pages[$i]",
            ),
          );
        }
      }
    }

    final visitState = <String, int>{};
    bool detectCycle(String id, List<String> chain) {
      final state = visitState[id] ?? 0;
      if (state == 1) {
        diagnostics.add(
          Diagnostic.error(
            "page.base_cycle",
            "Overlay base cycle detected: ${[...chain, id].join(" -> ")}",
            path: "pages",
          ),
        );
        return true;
      }
      if (state == 2) {
        return false;
      }

      visitState[id] = 1;
      final page = pageById[id];
      final baseId = page?.basePageId?.trim();
      if (page != null &&
          page.mode == UiPageMode.overlay &&
          baseId != null &&
          baseId.isNotEmpty &&
          pageById.containsKey(baseId)) {
        detectCycle(baseId, <String>[...chain, id]);
      }
      visitState[id] = 2;
      return false;
    }

    for (final page in project.pages) {
      detectCycle(page.id, <String>[]);
    }

    if (!project.pagesById.containsKey(project.activePageId)) {
      diagnostics.add(
        Diagnostic.error(
          "page.active_missing",
          "activePageId '${project.activePageId}' is not in pages.",
          path: "activePageId",
        ),
      );
    }

    void visitNode(UiNode node, String parentPath, Set<String> seenNodeIds) {
      final currentPath = "$parentPath/${node.id}";
      if (node.id.isEmpty) {
        diagnostics.add(
          Diagnostic.error(
            "node.id_missing",
            "Node ID is required.",
            path: parentPath,
          ),
        );
      } else if (!seenNodeIds.add(node.id)) {
        diagnostics.add(
          Diagnostic.error(
            "node.id_duplicate",
            "Duplicate node ID '${node.id}'.",
            path: currentPath,
          ),
        );
      }

      if (node.width <= 0 || node.height <= 0) {
        diagnostics.add(
          Diagnostic.error(
            "node.size_invalid",
            "Node '${node.id}' must have positive width and height.",
            path: currentPath,
          ),
        );
      }

      if (node.kind == NodeKind.label && node.props["text"] == null) {
        diagnostics.add(
          Diagnostic.warning(
            "label.text_missing",
            "Label '${node.id}' has no text; fallback to node id will be used.",
            path: currentPath,
          ),
        );
      }

      for (final child in node.children) {
        visitNode(child, "$currentPath/children", seenNodeIds);
      }
    }

    for (var pageIndex = 0; pageIndex < project.pages.length; pageIndex++) {
      final page = project.pages[pageIndex];
      final seenNodeIds = <String>{};
      for (final node in page.nodes) {
        visitNode(node, "pages[$pageIndex]/nodes", seenNodeIds);
      }
    }
    return diagnostics;
  }
}

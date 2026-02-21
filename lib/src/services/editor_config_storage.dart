import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;

class EditorConfig {
  EditorConfig({
    List<String>? recentProjects,
    this.standaloneOverlayPreviewMode = "one_level",
  }) : recentProjects = recentProjects ?? <String>[];

  final List<String> recentProjects;
  final String standaloneOverlayPreviewMode;

  factory EditorConfig.fromMap(Map<String, dynamic> map) {
    final rawRecent = map["recentProjects"];
    final recent = <String>[];
    if (rawRecent is List) {
      for (final value in rawRecent) {
        final path = value?.toString().trim() ?? "";
        if (path.isNotEmpty) {
          recent.add(path);
        }
      }
    }
    return EditorConfig(
      recentProjects: recent,
      standaloneOverlayPreviewMode:
          map["standaloneOverlayPreviewMode"]?.toString() ?? "one_level",
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "recentProjects": recentProjects,
      "standaloneOverlayPreviewMode": standaloneOverlayPreviewMode,
    };
  }
}

class EditorConfigStorage {
  EditorConfigStorage({
    this.maxRecentProjects = 12,
  });

  final int maxRecentProjects;

  Future<EditorConfig> load() async {
    final file = await _configFile();
    File target = file;
    if (!await target.exists()) {
      final legacy = await _legacyConfigFile();
      if (await legacy.exists()) {
        target = legacy;
      } else {
        return EditorConfig();
      }
    }

    try {
      final source = await target.readAsString();
      if (source.trim().isEmpty) {
        return EditorConfig();
      }
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return EditorConfig.fromMap(decoded);
      }
      if (decoded is Map) {
        return EditorConfig.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Fall through to empty defaults.
    }
    return EditorConfig();
  }

  Future<void> save(EditorConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent("  ").convert(config.toMap()),
    );
  }

  Future<EditorConfig> addRecentProject(String rootPath) async {
    final normalized = rootPath.trim();
    if (normalized.isEmpty) {
      return load();
    }

    final current = await load();
    final next = <String>[
      normalized,
      ...current.recentProjects.where(
        (path) => path.trim().toLowerCase() != normalized.toLowerCase(),
      ),
    ];

    final limited = next.take(maxRecentProjects).toList();
    final updated = EditorConfig(
      recentProjects: limited,
      standaloneOverlayPreviewMode: current.standaloneOverlayPreviewMode,
    );
    await save(updated);
    return updated;
  }

  Future<EditorConfig> updateStandaloneOverlayPreviewMode(String mode) async {
    final normalized = mode.trim().isEmpty ? "one_level" : mode.trim();
    final current = await load();
    final updated = EditorConfig(
      recentProjects: current.recentProjects,
      standaloneOverlayPreviewMode: normalized,
    );
    await save(updated);
    return updated;
  }

  Future<File> _configFile() async {
    final home = _userHomePath();
    final dir = Directory(p.join(home, ".canvastalk"));
    return File(p.join(dir.path, "config.json"));
  }

  Future<File> _legacyConfigFile() async {
    final home = _userHomePath();
    final dir = Directory(p.join(home, ".asciipaint"));
    return File(p.join(dir.path, "config.json"));
  }

  String _userHomePath() {
    return Platform.environment["USERPROFILE"] ??
        Platform.environment["HOME"] ??
        Directory.current.path;
  }
}

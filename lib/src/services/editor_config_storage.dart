import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;

class EditorConfig {
  EditorConfig({
    List<String>? recentProjects,
  }) : recentProjects = recentProjects ?? <String>[];

  final List<String> recentProjects;

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
    return EditorConfig(recentProjects: recent);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "recentProjects": recentProjects,
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
    if (!await file.exists()) {
      return EditorConfig();
    }

    try {
      final source = await file.readAsString();
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
    final updated = EditorConfig(recentProjects: limited);
    await save(updated);
    return updated;
  }

  Future<File> _configFile() async {
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

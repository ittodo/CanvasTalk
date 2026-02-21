class EditorConfig {
  EditorConfig({
    List<String>? recentProjects,
    this.standaloneOverlayPreviewMode = "one_level",
  }) : recentProjects = recentProjects ?? <String>[];

  final List<String> recentProjects;
  final String standaloneOverlayPreviewMode;
}

class EditorConfigStorage {
  EditorConfigStorage({
    this.maxRecentProjects = 12,
  });

  final int maxRecentProjects;
  EditorConfig _state = EditorConfig();

  Future<EditorConfig> load() async {
    return EditorConfig(
      recentProjects: List<String>.from(_state.recentProjects),
      standaloneOverlayPreviewMode: _state.standaloneOverlayPreviewMode,
    );
  }

  Future<void> save(EditorConfig config) async {
    _state = EditorConfig(
      recentProjects: List<String>.from(config.recentProjects),
      standaloneOverlayPreviewMode: config.standaloneOverlayPreviewMode,
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
}

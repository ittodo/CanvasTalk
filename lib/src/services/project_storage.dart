import "dart:io";

import "package:path/path.dart" as p;

import "../model/ui_project.dart";
import "yaml_codec.dart";

class ProjectStorage {
  ProjectStorage(this._codec);

  final ProjectYamlCodec _codec;

  Future<void> saveProject({
    required String rootPath,
    required UiProject project,
    bool writeSnapshot = true,
  }) async {
    final root = Directory(rootPath);
    await root.create(recursive: true);

    final uiDir = Directory(p.join(root.path, "ui"));
    await uiDir.create(recursive: true);

    final yaml = _codec.encode(project);
    final mainFile = File(p.join(uiDir.path, "main.yaml"));
    await mainFile.writeAsString(yaml);

    final meta = File(p.join(root.path, "project.yaml"));
    await meta.writeAsString(
      [
        "name: canvastalk-project",
        "version: ${project.version}",
        "activePageId: ${project.activePageId}",
        "pageCount: ${project.pages.length}",
        "updatedAt: ${DateTime.now().toIso8601String()}",
      ].join("\n"),
    );

    if (writeSnapshot) {
      await _writeSnapshot(root.path, yaml);
    }
  }

  Future<String> loadMainYaml(String rootPath) async {
    final file = File(p.join(rootPath, "ui", "main.yaml"));
    if (!await file.exists()) {
      throw StateError("Cannot find ui/main.yaml under '$rootPath'.");
    }
    return file.readAsString();
  }

  Future<void> _writeSnapshot(String rootPath, String yaml) async {
    final historyDir = Directory(p.join(rootPath, ".canvastalk", "history"));
    await historyDir.create(recursive: true);
    final fileName = "${DateTime.now().millisecondsSinceEpoch}.snapshot.yaml";
    final snapshot = File(p.join(historyDir.path, fileName));
    await snapshot.writeAsString(yaml);
  }
}

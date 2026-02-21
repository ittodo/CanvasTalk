import "../model/ui_project.dart";
import "yaml_codec.dart";

class ProjectStorage {
  ProjectStorage(ProjectYamlCodec codec);

  bool get isSupported => false;

  Future<void> saveProject({
    required String rootPath,
    required UiProject project,
    bool writeSnapshot = true,
  }) async {
    throw UnsupportedError(
      "Project save to local filesystem is not supported on web.",
    );
  }

  Future<String> loadMainYaml(String rootPath) async {
    throw UnsupportedError(
      "Project load from local filesystem is not supported on web.",
    );
  }
}

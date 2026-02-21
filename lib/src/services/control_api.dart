abstract class ControlApi {
  Map<String, dynamic> healthPayload();

  Future<Map<String, dynamic>> validateYaml(String yamlSource);
  Future<Map<String, dynamic>> renderPreview(String yamlSource);
  Future<Map<String, dynamic>> applyCanvasPatch(Map<String, dynamic> patch);
  Future<Map<String, dynamic>> loadProject(String rootPath);
  Future<Map<String, dynamic>> saveProject(String rootPath);
  Future<Map<String, dynamic>> resetSession();
}

import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "control_api.dart";

class ControlServer {
  ControlServer({
    required ControlApi api,
    this.defaultPort = 4049,
  }) : _api = api;

  final ControlApi _api;
  final int defaultPort;

  HttpServer? _server;
  String? _token;
  int? _port;

  bool get isRunning => _server != null;
  int? get port => _port;
  String? get token => _token;

  Future<void> start({int? port}) async {
    if (_server != null) {
      return;
    }

    final bindPort = port ?? defaultPort;
    _token = _generateToken();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, bindPort);
    _port = _server!.port;
    unawaited(_listenLoop(_server!));
  }

  Future<void> stop() async {
    final current = _server;
    _server = null;
    _port = null;
    if (current != null) {
      await current.close(force: true);
    }
  }

  Future<void> _listenLoop(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handle(request));
      }
    } catch (_) {
      // Server closed.
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final method = request.method.toUpperCase();
      if (!_authorized(request, path)) {
        await _writeJson(
          request.response,
          HttpStatus.unauthorized,
          <String, dynamic>{
            "ok": false,
            "error": "missing_or_invalid_token",
          },
        );
        return;
      }

      if (method == "GET" && path == "/health") {
        await _writeJson(
          request.response,
          HttpStatus.ok,
          _api.healthPayload(),
        );
        return;
      }

      final body = await _readJsonBody(request);
      switch ("$method $path") {
        case "POST /yaml/validate":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.validateYaml(_readYamlFromBody(body)),
          );
          return;
        case "POST /render/preview":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.renderPreview(_readYamlFromBody(body)),
          );
          return;
        case "POST /canvas/patch":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.applyCanvasPatch(body),
          );
          return;
        case "POST /project/load":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.loadProject(_readPathFromBody(body)),
          );
          return;
        case "POST /project/save":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.saveProject(_readPathFromBody(body)),
          );
          return;
        case "POST /session/reset":
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _api.resetSession(),
          );
          return;
        default:
          await _writeJson(
            request.response,
            HttpStatus.notFound,
            <String, dynamic>{
              "ok": false,
              "error": "not_found",
              "path": path,
              "method": method,
            },
          );
      }
    } on FormatException catch (error) {
      await _writeJson(
        request.response,
        HttpStatus.badRequest,
        <String, dynamic>{
          "ok": false,
          "error": "bad_request",
          "message": error.message,
        },
      );
    } catch (error) {
      await _writeJson(
        request.response,
        HttpStatus.internalServerError,
        <String, dynamic>{"ok": false, "error": error.toString()},
      );
    }
  }

  bool _authorized(HttpRequest request, String path) {
    if (path == "/health") {
      return true;
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return false;
    }
    final header = request.headers.value("x-canvastalk-token") ??
        request.headers.value("x-asciipaint-token");
    return header == token;
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    if (content.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException("Request body must be a JSON object.");
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> payload,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(payload));
    await response.close();
  }

  String _readYamlFromBody(Map<String, dynamic> body) {
    final value = body["yaml"]?.toString();
    if (value == null || value.trim().isEmpty) {
      throw const FormatException("Body must include non-empty 'yaml'.");
    }
    return value;
  }

  String _readPathFromBody(Map<String, dynamic> body) {
    final value = body["path"]?.toString();
    if (value == null || value.trim().isEmpty) {
      throw const FormatException("Body must include non-empty 'path'.");
    }
    return value;
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }
}

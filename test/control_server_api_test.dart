import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

import "package:canvastalk/src/state/app_controller.dart";

void main() {
  test("control server HTTP smoke", () async {
    final controller = AppController();
    Directory? tempDir;

    addTearDown(() async {
      await controller.stopControlServer();
      controller.dispose();
      final dir = tempDir;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });

    await controller.initialize();
    if (!controller.serverRunning) {
      await controller.startControlServer(port: 0);
    }
    final port = controller.serverPort;
    final token = controller.serverToken;
    expect(port, isNotNull);
    expect(token, isNotNull);
    expect(token, isNotEmpty);

    final base = Uri.parse("http://127.0.0.1:$port");

    final health = await _requestJson(
      method: "GET",
      uri: base.resolve("/health"),
    );
    expect(health.statusCode, HttpStatus.ok);
    expect(health.json["ok"], isTrue);

    final unauthorized = await _requestJson(
      method: "POST",
      uri: base.resolve("/session/reset"),
      body: <String, dynamic>{},
    );
    expect(unauthorized.statusCode, HttpStatus.unauthorized);
    expect(unauthorized.json["ok"], isFalse);

    final validate = await _requestJson(
      method: "POST",
      uri: base.resolve("/yaml/validate"),
      token: token,
      body: <String, dynamic>{"yaml": controller.yamlSource},
    );
    expect(validate.statusCode, HttpStatus.ok);
    expect(validate.json["ok"], isTrue);

    final validateBadRequest = await _requestJson(
      method: "POST",
      uri: base.resolve("/yaml/validate"),
      token: token,
      body: <String, dynamic>{},
    );
    expect(validateBadRequest.statusCode, HttpStatus.badRequest);
    expect(validateBadRequest.json["ok"], isFalse);
    expect(validateBadRequest.json["error"], "bad_request");

    final preview = await _requestJson(
      method: "POST",
      uri: base.resolve("/render/preview"),
      token: token,
      body: <String, dynamic>{"yaml": controller.yamlSource},
    );
    expect(preview.statusCode, HttpStatus.ok);
    expect(preview.json["ok"], isTrue);
    expect(preview.json["ascii"], isA<String>());
    expect((preview.json["ascii"] as String).isNotEmpty, isTrue);

    final patch = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "add_node",
        "node": <String, dynamic>{
          "id": "server_test_button",
          "kind": "button",
          "x": 2,
          "y": 2,
          "width": 16,
          "height": 3,
          "props": <String, dynamic>{"text": "Server Test"},
        },
      },
    );
    expect(patch.statusCode, HttpStatus.ok);
    expect(patch.json["ok"], isTrue);

    final addList = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "add_node",
        "node": <String, dynamic>{
          "id": "server_test_list",
          "kind": "list",
          "x": 4,
          "y": 6,
          "width": 30,
          "height": 8,
          "props": <String, dynamic>{
            "items": <String>["A", "B", "C"],
            "selectedIndex": 0,
          },
        },
      },
    );
    expect(addList.statusCode, HttpStatus.ok);
    expect(addList.json["ok"], isTrue);

    final disallowedPopupInList = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "add_node",
        "parentId": "server_test_list",
        "node": <String, dynamic>{
          "id": "server_test_popup_in_list",
          "kind": "popup",
          "x": 1,
          "y": 1,
          "width": 20,
          "height": 8,
          "props": <String, dynamic>{
            "title": "Invalid Nested Popup",
          },
        },
      },
    );
    expect(disallowedPopupInList.statusCode, HttpStatus.ok);
    expect(disallowedPopupInList.json["ok"], isFalse);

    final addPageA = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{"op": "add_page", "name": "Overlay A"},
    );
    expect(addPageA.statusCode, HttpStatus.ok);
    expect(addPageA.json["ok"], isTrue);

    final addPageB = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{"op": "add_page", "name": "Overlay B"},
    );
    expect(addPageB.statusCode, HttpStatus.ok);
    expect(addPageB.json["ok"], isTrue);

    final setModeA = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_page_mode",
        "id": "page_1",
        "mode": "overlay",
      },
    );
    expect(setModeA.statusCode, HttpStatus.ok);
    expect(setModeA.json["ok"], isTrue);

    final setBaseA = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_page_base",
        "id": "page_1",
        "basePageId": "page_main",
      },
    );
    expect(setBaseA.statusCode, HttpStatus.ok);
    expect(setBaseA.json["ok"], isTrue);

    final setModeB = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_page_mode",
        "id": "page_2",
        "mode": "overlay",
      },
    );
    expect(setModeB.statusCode, HttpStatus.ok);
    expect(setModeB.json["ok"], isTrue);

    final setBaseB = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_page_base",
        "id": "page_2",
        "basePageId": "page_1",
      },
    );
    expect(setBaseB.statusCode, HttpStatus.ok);
    expect(setBaseB.json["ok"], isTrue);

    final previewMode = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_standalone_overlay_preview_mode",
        "mode": "full_tree",
      },
    );
    expect(previewMode.statusCode, HttpStatus.ok);
    expect(previewMode.json["ok"], isTrue);

    final badPreviewMode = await _requestJson(
      method: "POST",
      uri: base.resolve("/canvas/patch"),
      token: token,
      body: <String, dynamic>{
        "op": "set_standalone_overlay_preview_mode",
        "mode": "invalid_mode",
      },
    );
    expect(badPreviewMode.statusCode, HttpStatus.ok);
    expect(badPreviewMode.json["ok"], isFalse);

    final createdDir = await Directory.systemTemp.createTemp(
      "canvastalk_srv_test_",
    );
    tempDir = createdDir;
    final tempPath = createdDir.path;
    final save = await _requestJson(
      method: "POST",
      uri: base.resolve("/project/save"),
      token: token,
      body: <String, dynamic>{"path": tempPath},
    );
    expect(save.statusCode, HttpStatus.ok);
    expect(save.json["ok"], isTrue);
    expect(
      File("$tempPath${Platform.pathSeparator}ui${Platform.pathSeparator}main.yaml")
          .existsSync(),
      isTrue,
    );

    final reset = await _requestJson(
      method: "POST",
      uri: base.resolve("/session/reset"),
      token: token,
      body: <String, dynamic>{},
    );
    expect(reset.statusCode, HttpStatus.ok);
    expect(reset.json["ok"], isTrue);

    final load = await _requestJson(
      method: "POST",
      uri: base.resolve("/project/load"),
      token: token,
      body: <String, dynamic>{"path": tempPath},
    );
    expect(load.statusCode, HttpStatus.ok);
    expect(load.json["ok"], isTrue);
  });
}

Future<_HttpResult> _requestJson({
  required String method,
  required Uri uri,
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (token != null && token.isNotEmpty) {
      request.headers.set("x-canvastalk-token", token);
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final content = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(content);
    final json = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
    return _HttpResult(statusCode: response.statusCode, json: json);
  } finally {
    client.close(force: true);
  }
}

class _HttpResult {
  _HttpResult({
    required this.statusCode,
    required this.json,
  });

  final int statusCode;
  final Map<String, dynamic> json;
}

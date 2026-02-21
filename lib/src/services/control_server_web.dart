import "control_api.dart";

class ControlServer {
  ControlServer({
    required ControlApi api,
    this.defaultPort = 4049,
  });

  final int defaultPort;

  bool get isSupported => false;
  bool get isRunning => false;
  int? get port => null;
  String? get token => null;

  Future<void> start({int? port}) async {}
  Future<void> stop() async {}
}

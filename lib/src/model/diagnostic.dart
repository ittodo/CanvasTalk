enum DiagnosticSeverity {
  info,
  warning,
  error,
}

class Diagnostic {
  Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.path,
  });

  final DiagnosticSeverity severity;
  final String code;
  final String message;
  final String? path;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "severity": severity.name,
      "code": code,
      "message": message,
      "path": path,
    };
  }

  static Diagnostic error(String code, String message, {String? path}) {
    return Diagnostic(
      severity: DiagnosticSeverity.error,
      code: code,
      message: message,
      path: path,
    );
  }

  static Diagnostic warning(String code, String message, {String? path}) {
    return Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: code,
      message: message,
      path: path,
    );
  }

  static Diagnostic info(String code, String message, {String? path}) {
    return Diagnostic(
      severity: DiagnosticSeverity.info,
      code: code,
      message: message,
      path: path,
    );
  }
}

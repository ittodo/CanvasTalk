enum Charset {
  unicode,
  ascii,
}

Charset charsetFromString(String? value) {
  switch (value?.toLowerCase()) {
    case "ascii":
      return Charset.ascii;
    case "unicode":
    default:
      return Charset.unicode;
  }
}

String charsetToString(Charset charset) {
  return charset == Charset.ascii ? "ascii" : "unicode";
}

class CanvasConfig {
  CanvasConfig({
    required this.width,
    required this.height,
    this.charset = Charset.unicode,
  });

  int width;
  int height;
  Charset charset;

  factory CanvasConfig.fromMap(Map<String, dynamic> map) {
    return CanvasConfig(
      width: _toInt(map["width"], fallback: 100),
      height: _toInt(map["height"], fallback: 32),
      charset: charsetFromString(map["charset"]?.toString()),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      "width": width,
      "height": height,
      "charset": charsetToString(charset),
    };
  }

  CanvasConfig copy() {
    return CanvasConfig(width: width, height: height, charset: charset);
  }

  static int _toInt(dynamic value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }
}

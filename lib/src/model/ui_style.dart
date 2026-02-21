class UiStyle {
  UiStyle({
    required this.id,
    Map<String, dynamic>? props,
  }) : props = props ?? <String, dynamic>{};

  final String id;
  final Map<String, dynamic> props;

  factory UiStyle.fromMap(String id, Map<String, dynamic> map) {
    return UiStyle(id: id, props: Map<String, dynamic>.from(map));
  }

  Map<String, dynamic> toMap() {
    return Map<String, dynamic>.from(props);
  }
}

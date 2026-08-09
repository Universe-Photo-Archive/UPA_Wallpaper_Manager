class ScreenInfo {
  final int id;
  final String name;
  final int width;
  final int height;
  final int left;
  final int top;
  final bool isPrimary;
  final String? devicePath;

  const ScreenInfo({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    this.left = 0,
    this.top = 0,
    this.isPrimary = false,
    this.devicePath,
  });

  String get resolution => '${width}x$height';

  factory ScreenInfo.fromJson(Map<String, dynamic> json) {
    return ScreenInfo(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Screen',
      width: json['width'] as int? ?? 1920,
      height: json['height'] as int? ?? 1080,
      left: json['left'] as int? ?? 0,
      top: json['top'] as int? ?? 0,
      isPrimary: json['isPrimary'] as bool? ?? false,
      devicePath: json['devicePath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'width': width,
        'height': height,
        'left': left,
        'top': top,
        'isPrimary': isPrimary,
        'devicePath': devicePath,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ScreenInfo && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Screen $id ($name, $resolution, primary=$isPrimary)';
}

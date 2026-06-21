/// 下载状态
enum DownloadItemStatus { downloading, completed, failed }

/// 下载记录数据模型
class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final int fileSize; // 字节，0 表示未知
  final DateTime createdAt; // 本地生成，不走 TimeUtils
  final DownloadItemStatus status;
  final double progress; // 0.0 ~ 1.0
  final String? mimeType;

  const DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.fileSize = 0,
    required this.createdAt,
    this.status = DownloadItemStatus.downloading,
    this.progress = 0,
    this.mimeType,
  });

  DownloadItem copyWith({
    String? fileName,
    String? savePath,
    DownloadItemStatus? status,
    double? progress,
    int? fileSize,
  }) =>
      DownloadItem(
        id: id,
        url: url,
        fileName: fileName ?? this.fileName,
        savePath: savePath ?? this.savePath,
        fileSize: fileSize ?? this.fileSize,
        createdAt: createdAt,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        mimeType: mimeType,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'savePath': savePath,
        'fileSize': fileSize,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'progress': progress,
        'mimeType': mimeType,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        savePath: json['savePath'] as String,
        fileSize: json['fileSize'] as int? ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: DownloadItemStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DownloadItemStatus.failed,
        ),
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        mimeType: json['mimeType'] as String?,
      );
}

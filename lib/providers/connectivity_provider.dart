import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/connectivity_service.dart';

/// 连通性服务 Provider（单例）
final connectivityServiceProvider = Provider((ref) => ConnectivityService());

/// 连接状态 Provider（StreamProvider）
/// 初始值为 true（假定已连接），通过 stream 更新
final isConnectedProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.connectionStream;
});

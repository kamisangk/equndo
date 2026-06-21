import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/message_bus_service.dart';

/// MessageBus 服务 Provider
final messageBusServiceProvider = Provider<MessageBusService>((ref) {
  final service = MessageBusService();
  ref.onDispose(() => service.dispose());
  return service;
});

import 'package:dio/dio.dart';

const String networkAdapterLogExtraKey = '_networkLog_adapter';

void setRequestAdapterLogName(RequestOptions options, String adapterName) {
  options.extra[networkAdapterLogExtraKey] = adapterName;
}

String? getRequestAdapterLogName(RequestOptions options) {
  final value = options.extra[networkAdapterLogExtraKey];
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

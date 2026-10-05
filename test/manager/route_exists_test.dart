import 'package:fl_clash/manager/core_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('识别「路由已存在」', () {
    expect(isRouteAlreadyExistsLog('add route 1.0.0.0/8: file exists'), isTrue);
    expect(isRouteAlreadyExistsLog('Start TUN listening error: configure tun interface: add route 1.0.0.0/8 via utun4: file exists'), isTrue);
    expect(isRouteAlreadyExistsLog('AddRoute failed: The object already exists.'), isTrue);
    expect(isRouteAlreadyExistsLog('dial tcp: connection refused'), isFalse);
    expect(isRouteAlreadyExistsLog('open /tmp/x: file exists'), isFalse);
  });
}

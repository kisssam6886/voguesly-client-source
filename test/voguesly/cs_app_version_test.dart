// [0.9.90] 客服页带版本号(B-CS-APPVER):cs.js getClientMeta 读 ?app_version=,之前冇传 ⇒ 客服睇唔到版本。
import 'package:fl_clash/state.dart';
import 'package:fl_clash/voguesly/voguesly_cs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('packageInfo 未载入 ⇒ 返空字符串(唔带参数),唔会崩', () {
    expect(vogueslyCsAppVersion(), '');
  });

  test('载入后 ⇒ 「版本+构建号」,同上传日志 / 工单主题一致', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'Voguesly',
      packageName: 'com.voguesly.app',
      version: '0.9.90',
      buildNumber: '2026092450',
      buildSignature: '',
    );
    globalState.packageInfo = await PackageInfo.fromPlatform();
    expect(vogueslyCsAppVersion(), '0.9.90+2026092450');
    // 放入 URL 时 + 要编码成 %2B,否则网页读出嚟会变空格
    final q = Uri(queryParameters: {'app_version': vogueslyCsAppVersion()}).query;
    expect(q, 'app_version=0.9.90%2B2026092450');
  });
}

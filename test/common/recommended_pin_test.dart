import 'package:fl_clash/common/compute.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

// [0.9.82] 线路页「推荐置顶」:订阅每个功能组嘅「🛡 自动·…」(fallback)无论点排序都排第一。
void main() {
  const group = Group(
    name: '🏦 AI·金融·住宅',
    type: GroupType.Selector,
    all: [
      Proxy(name: '🏠 美国住宅·Verizon 加州', type: 'Fallback'),
      Proxy(name: '🛡 自动·🏦 AI·金融·住宅', type: 'Fallback'),
      Proxy(name: '🏠 美国住宅·AT&T 加州', type: 'Fallback'),
    ],
  );

  test('isRecommendedProxyName 只认「🛡 自动」开头', () {
    expect(isRecommendedProxyName('🛡 自动·🏦 AI·金融·住宅'), isTrue);
    expect(isRecommendedProxyName('🏠 美国住宅·AT&T 加州'), isFalse);
    expect(isRecommendedProxyName('自动选择'), isFalse);
  });

  for (final sortType in ProxiesSortType.values) {
    test('按 ${sortType.name} 排序后「🛡 自动」仍然第一,其余次序照排序结果', () {
      final out = computeSort(
        groups: [group],
        sortType: sortType,
        delayMap: const {},
        selectedMap: const {},
        defaultTestUrl: 'https://www.gstatic.com/generate_204',
      );
      final names = out.single.all.map((p) => p.name).toList();
      expect(names.first, '🛡 自动·🏦 AI·金融·住宅');
      expect(names.length, 3);
      if (sortType == ProxiesSortType.name) {
        expect(names.sublist(1), ['🏠 美国住宅·AT&T 加州', '🏠 美国住宅·Verizon 加州']);
      }
    });
  }
}

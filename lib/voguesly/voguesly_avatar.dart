import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [0.9.83] 头像换成二次元风插画(DiceBear「Adventurer」,CC BY 4.0,出处见 assets/images/avatar/LICENSE.txt
/// 同「关于」页)。256×256 WebP,12 个合共约 87KB,bundle 喺 app 入面唔靠网络。
/// 想换一套:放同名 anime_XX.webp 入 assets/images/avatar/ 即可(或者改呢个 list)。
const List<String> vogueslyAvatars = [
  'anime_01', 'anime_02', 'anime_03', 'anime_04', 'anime_05', 'anime_06',
  'anime_07', 'anime_08', 'anime_09', 'anime_10', 'anime_11', 'anime_12',
];

/// 0.9.82 或之前嘅 SVG 头像 id(a1–a8)→ 新头像,升级后用户原本揀嘅唔会突然变返默认。
const Map<String, String> _kLegacyAvatarMap = {
  'a1': 'anime_01', 'a2': 'anime_02', 'a3': 'anime_03', 'a4': 'anime_04',
  'a5': 'anime_05', 'a6': 'anime_06', 'a7': 'anime_07', 'a8': 'anime_08',
};

const String _kAvatarKey = 'voguesly_avatar';

String vogueslyAvatarAsset(String id) => 'assets/images/avatar/$id.webp';

/// 圆形头像(所有显示头像嘅地方统一用呢个,唔好再各自 SvgPicture)。
class VogueslyAvatarImage extends StatelessWidget {
  const VogueslyAvatarImage(this.id, {super.key, this.size = 40});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Image.asset(
          vogueslyAvatarAsset(id),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) => ColoredBox(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(Icons.person, size: size * 0.6),
          ),
        ),
      ),
    );
  }
}

/// 当前选中头像(默认第一个),持久化喺 SharedPreferences。
class VogueslyAvatarNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return vogueslyAvatars.first;
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    var v = p.getString(_kAvatarKey);
    if (v != null && _kLegacyAvatarMap.containsKey(v)) {
      v = _kLegacyAvatarMap[v];
      await p.setString(_kAvatarKey, v!);
    }
    if (v != null && vogueslyAvatars.contains(v)) {
      state = v;
    }
  }

  Future<void> select(String id) async {
    if (!vogueslyAvatars.contains(id)) return;
    state = id;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAvatarKey, id);
  }
}

final vogueslyAvatarProvider =
    NotifierProvider<VogueslyAvatarNotifier, String>(
  VogueslyAvatarNotifier.new,
);

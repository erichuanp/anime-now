import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/settings.dart';

/// In-app string table: 'zh' = 简体中文, 'zht' = 繁體中文, 'en' = English.
class S {
  final String lang;
  const S(this.lang);

  static S of(BuildContext context) => S(context.watch<AppSettings>().language);

  bool get zh => lang == 'zh';
  bool get zht => lang == 'zht';
  bool get en => lang == 'en';

  String _t(String hans, String hant, String english) => zh ? hans : (zht ? hant : english);

  String get appName => _t('番时', '番時', 'Anime Now');
  String get tabSearch => _t('查番', '查番', 'Search');
  String get tabSettings => _t('设置', '設定', 'Settings');
  String get backToToday => _t('回到今天', '回到今天', 'Back to today');

  String get emptyDay => _t('这天没有番剧', '這天沒有番劇', 'Nothing airing this day');
  String get upcoming => _t('即将开播', '即將開播', 'Upcoming');
  String get ended => _t('已完结', '已完結', 'Ended');
  String get endedBanner => _t('有番剧已经完结了，请在设置中移除或手动移除。', '有番劇已經完結了，請在設定中移除或手動移除。', 'Some anime have ended. Remove them in Settings or by hand.');
  String get deleted => _t('已移除', '已移除', 'Removed');
  String get copied => _t('已复制', '已複製', 'Copied');
  String get dismiss => _t('移除', '移除', 'Dismiss');
  String get undo => _t('撤销', '復原', 'Undo');
  String get timeUnknown => _t('时间未知', '時間未知', 'time unknown');
  String get firstAir => _t('首播', '首播', 'From'); // short: the card line must fit one row
  String get allPlatforms => _t('各平台放送时间', '各平台播出時間', 'Broadcast times by platform');
  String get localTimeNote => _t('时间已转换为你当前的时区', '時間已轉換為你目前的時區', 'Times converted to your local timezone');
  String get close => _t('关闭', '關閉', 'Close');
  String morePlatforms(int n) => _t('还有 $n 个平台未显示', '還有 $n 個平台未顯示', '$n more platforms not shown');

  String get searchNotice => _t('基于 LLM 搜索，时间略长', '基於 LLM 搜尋，時間略長', 'LLM search, takes a moment');
  String get searchScopeNote => _t('仅支持搜索正在放送/即将放送的番剧', '僅支援搜尋正在播出／即將播出的番劇', 'Airing or upcoming anime only');
  String get searchHint => _t('输入番名关键词', '輸入番名關鍵字', 'Anime keyword');
  String get batchHint => _t('用换行来区分多个番', '用換行來區分多部番', 'One anime per line');
  String hiddenLines(int n) => _t('批量模式还有 $n 行', '批次模式還有 $n 行', '$n more line(s) in batch mode');
  String get batchSearch => _t('高级搜索', '進階搜尋', 'Advanced');
  String get byUserPrefix => _t('根据 ', '根據 ', 'Import from ');
  String get byUserLink => _t('bangumi 用户名', 'bangumi 使用者名稱', "a bangumi user's");
  String get byUserSuffix => _t(' 的在看/想看列表获取番剧', ' 的在看／想看清單取得番劇', ' watching/wish list');
  String get bangumiUserHint => _t('输入准确的 bangumi 用户名', '輸入正確的 bangumi 使用者名稱', 'Exact bangumi username');
  String get fetchList => _t('获取', '取得', 'Fetch');
  String get bangumiUserGuideTitle => _t('怎么找 bangumi 用户名', '怎麼找 bangumi 使用者名稱', 'Where to find the bangumi username');
  String get bangumiUserGuideText => _t(
        '打开 bangumi 个人页，地址栏 bangumi.tv/user/ 后面那段，或昵称旁边 @ 后面的那一段，就是用户名。不带 @ 和 /。',
        '打開 bangumi 個人頁，網址列 bangumi.tv/user/ 後面那段，或暱稱旁邊 @ 後面的那一段，就是使用者名稱。不含 @ 和 /。',
        'Open a bangumi profile: the part after bangumi.tv/user/ in the address bar, or after the @ next to your nickname. No @ or /.',
      );
  String get userNotFound => _t('找不到这个 bangumi 用户', '找不到這個 bangumi 使用者', 'No such bangumi user');
  String get collectionsEmpty => _t('在看/想看里没有正在放送或即将开播的番', '在看／想看裡沒有正在播出或即將開播的番', 'Nothing airing or upcoming in the lists');
  String collectionsSummary(int current) => _t(
        '可用 $current 部，已在番剧页的已跳过',
        '可用 $current 部，已在番劇頁的已略過',
        '$current available, skipped in the schedule page',
      );
  String progressOf(int i, int n) => _t('第 $i/$n 部', '第 $i/$n 部', '$i of $n');
  String fromUser(String user) => _t('来自 bangumi 用户“$user”：', '來自 bangumi 使用者「$user」：', 'From bangumi user "$user":');
  String get search => _t('搜索', '搜尋', 'Search');
  String get addAll => _t('全部添加', '全部加入', 'Add all');
  String resultsFor(String kw) => _t('根据关键词“$kw”搜索到的番：', '根據關鍵字「$kw」搜尋到的番：', 'Results for "$kw":');
  String get added => _t('已添加', '已加入', 'Added');
  String get alreadyAddedNote => _t('已添加，不可以重复添加哦', '已加入，不可以重複加入喔', 'Already added, no duplicates');
  String addedCount(int n) => _t('已添加 $n 部', '已加入 $n 部', 'Added $n');
  String get add => _t('添加', '加入', 'Add');
  String get chooseCandidate => _t('有多个正在放送的候选，请选择：', '有多個正在播出的候選，請選擇：', 'Several airing candidates, pick one:');
  String get notFound => _t('没有找到正在放送的番', '沒有找到正在播出的番', 'No airing anime found');
  String get noSchedule => _t('找到了番剧，但没查到放送时间', '找到了番劇，但查不到播出時間', 'Found the anime but no broadcast time');
  String get needLlmKey => _t('请先在设置里填写 LLM API Key 并选择模型', '請先在設定裡填寫 LLM API Key 並選擇模型', 'Set an LLM API key and model in Settings first');
  String get needTavilyKey => _t('请先在设置里填写 Tavily API Key', '請先在設定裡填寫 Tavily API Key', 'Set a Tavily API key in Settings first');
  String get searching => _t('搜索中…', '搜尋中…', 'Searching…');
  String get callSummary => _t('API 调用', 'API 呼叫', 'API calls');
  String elapsed(double seconds) => _t('耗时 ${seconds.toStringAsFixed(1)} 秒', '耗時 ${seconds.toStringAsFixed(1)} 秒', 'In ${seconds.toStringAsFixed(1)} seconds');

  String get llmSection => _t('LLM 设置', 'LLM 設定', 'LLM Settings');
  String get provider => _t('服务商', '服務商', 'Provider');
  String get customProvider => _t('自定义 (OpenAI 兼容)', '自訂 (OpenAI 相容)', 'Custom (OpenAI-compatible)');
  String get apiKey => 'LLM API Key';
  String get clearKey => _t('清除 Key', '清除 Key', 'Clear key');
  String get baseUrl => 'Base URL';
  String get fetchModels => _t('获取模型列表', '取得模型清單', 'Fetch models');
  String get model => _t('模型ID', '模型ID', 'Model ID');
  String get fetchFailed => _t('获取模型列表失败，请自行输入模型名', '取得模型清單失敗，請自行輸入模型名稱', 'Model list unavailable, type a model name');

  String get searchSection => _t('搜索设置', '搜尋設定', 'Search');
  String get tavilyKey => 'Tavily API Key';
  String get tavilyGuideTitle => _t('如何获取 Tavily API Key', '如何取得 Tavily API Key', 'How to get a Tavily API key');
  String get openTavily => _t('打开 Tavily 官网', '打開 Tavily 官網', 'Open Tavily');
  List<String> get tavilyGuideSteps => zh
      ? const [
          '1. 用浏览器打开 app.tavily.com(点下方按钮可直接跳转)，点击右上角 Sign up 注册。',
          '2. 可以用 Google / GitHub 账号一键注册，也可以用邮箱注册(邮箱需要收验证邮件并点击确认)。',
          '3. 登录后会进入 Overview(概览)页面，找到 API Keys 区域。',
          '4. 点击 “+ Generate new key”(或 “Create API key”)，随便起个名字(比如 anime-now)，点击确认。',
          '5. 复制生成的 Key，它以 tvly- 开头。Key 只显示一次，先复制好。',
          '6. 回到本页面，粘贴到下面的输入框，会自动保存(显示为圆点)。',
          '7. 免费额度：每月 1000 credits，本应用一次基础搜索消耗 1 credit。查一部番通常 1 次搜索，最多 5 次，够查几百部番。',
          '8. 如果搜索时提示 432 / quota，说明本月额度用完，等下月重置或升级套餐。',
        ]
      : zht
          ? const [
              '1. 用瀏覽器打開 app.tavily.com(點下方按鈕可直接前往)，點右上角 Sign up 註冊。',
              '2. 可以用 Google / GitHub 帳號一鍵註冊，也可以用信箱註冊(需要收驗證信並點擊確認)。',
              '3. 登入後會進入 Overview(總覽)頁面，找到 API Keys 區域。',
              '4. 點「+ Generate new key」(或「Create API key」)，隨便取個名字(例如 anime-now)，點擊確認。',
              '5. 複製產生的 Key，它以 tvly- 開頭。Key 只顯示一次，先複製好。',
              '6. 回到本頁面，貼到下面的輸入框，會自動儲存(顯示為圓點)。',
              '7. 免費額度：每月 1000 credits，本應用一次基礎搜尋消耗 1 credit。查一部番通常 1 次搜尋，最多 5 次，夠查幾百部番。',
              '8. 如果搜尋時提示 432 / quota，表示本月額度用完，等下月重置或升級方案。',
            ]
          : const [
              '1. Open app.tavily.com in a browser (button below) and click Sign up.',
              '2. Sign up with Google / GitHub, or with an email address (confirm the verification email).',
              '3. After logging in you land on the Overview page. Find the API Keys section.',
              '4. Click “+ Generate new key” (or “Create API key”), give it any name (e.g. anime-now) and confirm.',
              '5. Copy the key. It starts with tvly- and is shown only once.',
              '6. Come back here and paste it into the field below. It is saved automatically (shown as dots).',
              '7. Free tier: 1000 credits per month; one basic search costs 1 credit. A lookup uses 1 search (max 5).',
              '8. A 432 / quota error means the monthly credits are used up; wait for the reset or upgrade.',
            ];
  /// Mainland-China network notices are shown in Simplified Chinese only.
  bool get showGfwNotice => lang == 'zh';
  String get needVpn => '此服务在中国大陆需要科学上网';

  String get notificationsSection => _t('通知', '通知', 'Notifications');
  String get pushNotifications => _t('推送通知', '推送通知', 'Push notifications');
  String get pushNotificationsHelp => _t('到了番剧的放送时间就提醒你', '到了番劇的播出時間就提醒你', 'Remind you when an episode airs');
  String get notifDenied => _t('没有拿到通知权限，开关保持关闭', '沒有取得通知權限，開關保持關閉', 'No notification permission, switch stays off');
  String get notifTitle => _t('番剧更新啦！', '番劇更新啦！', 'New episode!');
  String get notifChannel => _t('番剧更新', '番劇更新', 'Episode updates');
  String get timeBasis => _t('按什么时间为准呢？', '以哪個時間為準呢？', 'Which time counts?');
  String get basisEarliest => _t('按最早平台的放送时间', '以最早平台的播出時間', 'Earliest platform');
  String get basisLatest => _t('按最晚平台的放送时间', '以最晚平台的播出時間', 'Latest platform');
  String get japaneseWeekday => _t('日式日期', '日式日期', 'Japanese weekday names');
  String get japaneseWeekdayHelp => _t('番剧页显示 X曜日', '番劇頁顯示 X曜日', 'Show X曜日 on the schedule page');
  String get language => _t('语言', '語言', 'Language');
  String get langZhHans => '简体中文';
  String get langZhHant => '繁體中文';
  String get langEn => 'English';

  String get maintenanceSection => _t('维护', '維護', 'Maintenance');
  String get removeEnded => _t('移除全部已完结的番剧', '移除全部已完結的番劇', 'Remove all finished anime');
  String removedCount(int n) => _t('已移除 $n 部', '已移除 $n 部', 'Removed $n');
  String get bangumiSection => _t('Bangumi 访问', 'Bangumi 存取', 'Bangumi access');
  String get bangumiOfficial => _t('官方', '官方', 'Official');
  String get bangumiMirror => _t('番时镜像', '番時鏡像', 'Anime Now mirror');
  String get bangumiMirrorNotice => _t('此服务全局限制每分钟查询次数，使用人数越多越慢', '此服務全域限制每分鐘查詢次數，使用人數越多越慢', 'Shared rate limit: the more users, the slower it gets');
  String get mirrorBusy => _t('镜像站暂时不可用，请在几分钟后尝试', '鏡像站暫時不可用，請在幾分鐘後嘗試', 'The mirror is temporarily unavailable, try again in minutes');
  String get coverUnavailable => _t('暂时不可用', '暫時不可用', 'currently\nunavailable');
  String get bangumiCustom => _t('自定义', '自訂', 'Custom');
  String get bangumiCustomApi => _t('API 镜像站', 'API 鏡像站', 'API mirror');
  String get bangumiCustomImage => _t('图片镜像站', '圖片鏡像站', 'Image mirror');
  String get cancel => _t('取消', '取消', 'Cancel');
  String get save => _t('保存', '儲存', 'Save');
  String get backupSection => _t('备份', '備份', 'Backup');
  String get backupAnime => _t('下载当前的动漫资料', '下載目前的動漫資料', 'Download current anime data');
  String get backupDoneTitle => _t('已下载', '已下載', 'Downloaded');
  String backupDoneBody(String where) => _t(
        'anime.json 已保存到 $where。\n\n恢复时请把它放置在 APP 内根目录下，然后重启 APP：',
        'anime.json 已儲存到 $where。\n\n恢復時請把它放置在 APP 內根目錄下，然後重新啟動 APP：',
        'anime.json was saved to $where.\n\nTo restore, place it in the app\'s root folder and restart the app:',
      );
  String get backupFailed => _t('下载失败', '下載失敗', 'Download Failed');
  String get ok => 'OK';
  String get about => _t('关于', '關於', 'About');
  String get aboutAuthor => _t('作者', '作者', 'Author');
  String get aboutProject => _t('项目主页', '專案首頁', 'Project');
  String get aboutLicense => _t('许可证', '授權條款', 'License');
  String get aboutVersion => _t('版本', '版本', 'Version');
  String get aboutText => _t(
        '数据来自 Bangumi 番组计划，放送时间通过 Tavily 搜索并由 LLM 整理。',
        '資料來自 Bangumi 番組計畫，播出時間透過 Tavily 搜尋並由 LLM 整理。',
        'Data from Bangumi; broadcast times searched via Tavily and structured by an LLM.',
      );

  /// Weekday label, 1 = Monday ... 7 = Sunday.
  String weekday(int w, {required bool japanese}) {
    const jp = ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日'];
    const cn = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    const enDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final i = (w - 1).clamp(0, 6);
    if (japanese) return jp[i];
    return en ? enDays[i] : cn[i];
  }

  /// Short weekday for cards.
  String weekdayShort(int w, {required bool japanese}) {
    const jp = ['月', '火', '水', '木', '金', '土', '日'];
    const hans = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const hant = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
    const enDays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final i = (w - 1).clamp(0, 6);
    if (japanese) return jp[i];
    return zh ? hans[i] : (zht ? hant[i] : enDays[i]);
  }
}

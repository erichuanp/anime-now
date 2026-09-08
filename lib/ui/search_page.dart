import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../main.dart';
import '../models/anime.dart';
import '../services/anime_store.dart';
import '../services/app_log.dart';
import '../services/bangumi_api.dart';
import '../services/llm_client.dart';
import '../services/search_pipeline.dart';
import '../services/settings.dart';
import '../services/tavily_api.dart';
import '../util/batch_text.dart';
import '../util/toast.dart';
import 'anime_card.dart';
import 'context_menu.dart';
import 'cover_image.dart';

class _SearchResult {
  _SearchResult({required this.keyword, this.header, this.loading = false});
  final String keyword;

  /// Overrides the "results for keyword" header (used for bangumi-user imports).
  final String? header;
  AnimeEntry? entry;
  List<Candidate>? choices;
  String? error;
  CallStats? stats;
  Duration elapsed = Duration.zero;
  String? alreadyName;
  int? alreadyId;
  bool loading;
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _userController = TextEditingController();
  bool _batch = false;

  /// Lines 2..n kept aside while batch mode is off (restored when it is
  /// switched back on, discarded once a single-line search runs).
  String _hiddenRest = '';

  void _setBatch(bool on) {
    if (on == _batch) return;
    if (on) {
      _controller.text = BatchText.toBatch(_controller.text, _hiddenRest);
      _hiddenRest = '';
    } else {
      final (visible, hidden) = BatchText.toSingle(_controller.text);
      _controller.text = visible;
      _hiddenRest = hidden;
    }
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _batch = on);
  }

  int get _hiddenCount => BatchText.hiddenCount(_hiddenRest);

  bool _running = false;
  String _progress = '';
  final List<_SearchResult> _results = [];
  SearchPipeline? _pipeline;

  @override
  void dispose() {
    _userController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Keys are decrypted here, right before use, and live only inside the clients.
  Future<SearchPipeline> _buildPipeline(AppSettings settings) async {
    final tavilyKey = await settings.tavilyKey();
    final llmKey = await settings.llmKey();
    return SearchPipeline(
      bangumi: BangumiApi(),
      tavily: TavilyApi(tavilyKey),
      llm: LlmClient(
        provider: settings.provider,
        baseUrl: settings.baseUrl,
        apiKey: llmKey,
        model: settings.model,
      ),
      onProgress: (step) {
        if (mounted) setState(() => _progress = step);
      },
      isAlreadyAdded: (id) => context.read<AnimeStore>().contains(id),
    );
  }

  Future<void> _search() async {
    final s = S.of(context);
    final settings = context.read<AppSettings>();
    if (!settings.llmReady) {
      _toast(s.needLlmKey);
      return;
    }
    if (!settings.tavilyReady) {
      _toast(s.needTavilyKey);
      return;
    }
    // Single mode searches the visible first line only; hidden lines are dropped.
    final keywords = BatchText.keywords(_controller.text, batch: _batch);
    if (keywords.isEmpty) return;
    _hiddenRest = '';

    FocusScope.of(context).unfocus();
    _pipeline = await _buildPipeline(settings);
    setState(() {
      _running = true;
      _results
        ..clear()
        ..addAll(keywords.map((k) => _SearchResult(keyword: k, loading: true)));
    });

    for (final r in _results) {
      await _runOne(r);
    }
    if (mounted) {
      setState(() {
        _running = false;
        _progress = '';
      });
    }
  }

  Future<void> _runOne(_SearchResult r, {int? chosenId}) async {
    final pipeline =
        _pipeline ?? await _buildPipeline(context.read<AppSettings>());
    _pipeline = pipeline;
    setState(() {
      r.loading = true;
      r.error = null;
    });
    final res = await pipeline.run(r.keyword, chosenId: chosenId);
    if (!mounted) return;
    setState(() {
      r.loading = false;
      r.entry = res.entry;
      r.choices = res.choices;
      r.error = res.error;
      r.stats = res.stats;
      r.elapsed = res.elapsed;
      r.alreadyName = res.alreadyName;
      r.alreadyId = res.alreadyId;
    });
  }

  /// Advanced search: pull a bangumi user's watching + wish lists, drop
  /// ended shows, and run the schedule pipeline for the rest (no keyword
  /// search needed, the bangumi id is already known).
  Future<void> _fetchByUser() async {
    final s = S.of(context);
    final settings = context.read<AppSettings>();
    final store = context.read<AnimeStore>();
    if (!settings.llmReady) {
      _toast(s.needLlmKey);
      return;
    }
    if (!settings.tavilyReady) {
      _toast(s.needTavilyKey);
      return;
    }
    final username = _userController.text.trim().replaceAll(RegExp(r'^@'), '');
    if (username.isEmpty) return;
    FocusScope.of(context).unfocus();
    final pipeline = await _buildPipeline(settings);
    _pipeline = pipeline;
    setState(() {
      _running = true;
      _progress = s.fetchList;
      _results.clear();
    });

    List<BgmSubject> subjects;
    try {
      subjects = await pipeline.bangumi.userCollections(username);
    } on BangumiException catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = '';
      });
      _toast(e.message == 'user_not_found' ? s.userNotFound : _bgmError(s, e));
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _progress = '';
      });
      _toast(_bgmError(s, e));
      return;
    }

    final recent = subjects.where(SearchPipeline.plausiblyCurrent).toList();
    final skippedAdded = recent.where((x) => store.contains(x.id)).length;
    final todo = recent.where((x) => !store.contains(x.id)).toList();
    AppLog.instance.i(
      'search',
      'user "$username": ${subjects.length} total, ${recent.length} recent, $skippedAdded already added, ${todo.length} to resolve',
    );
    final summary = s.collectionsSummary(todo.length);
    if (todo.isEmpty) {
      if (mounted) {
        setState(() {
          _running = false;
          _progress = '';
        });
        _toast('$summary\n${s.collectionsEmpty}'); // one notification, not two
      }
      return;
    }
    if (mounted) _toast(summary);

    for (var i = 0; i < todo.length; i++) {
      final subj = todo[i];
      // Provisional label while loading: Japanese for English UI, Chinese otherwise.
      final name = (s.en || subj.nameCn.isEmpty) ? subj.name : subj.nameCn;
      final r = _SearchResult(
        keyword: name,
        header: s.fromUser(username),
        loading: true,
      );
      if (!mounted) return;
      setState(() {
        _results.add(r);
        _progress = '${s.progressOf(i + 1, todo.length)} · $name';
      });
      final res = await pipeline.runSubject(subj);
      if (!mounted) return;
      setState(() {
        if (res.error == 'ended') {
          _results.remove(r); // ended: filtered out silently
        } else {
          r.loading = false;
          r.entry = res.entry;
          r.choices = res.choices;
          r.error = res.error;
          r.stats = res.stats;
          r.elapsed = res.elapsed;
        }
      });
    }
    if (mounted) {
      setState(() {
        _running = false;
        _progress = '';
      });
      if (_results.isEmpty) _toast(s.collectionsEmpty);
    }
  }

  Future<void> _showUserGuide() {
    final s = S.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8FB),
        title: Text(
          s.bangumiUserGuideTitle,
          style: const TextStyle(fontSize: 17),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/guide/bangumi_username.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.bangumiUserGuideText,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  /// A result block disappears once its anime has been added.
  void _removeResult(_SearchResult r) {
    setState(() => _results.remove(r));
  }

  void _toast(String msg) {
    showToast(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final store = context.watch<AnimeStore>();
    // "Add all" only makes sense with more than two addable cards.
    final pendingCount =
        _results.where((r) => r.entry != null && !store.contains(r.entry!.id)).length;
    final pendingAll = _batch && pendingCount > 2;
    final half = MediaQuery.of(context).size.height * 0.22; // batch box: ~quarter screen

    return Scaffold(
      appBar: AppBar(title: Text(s.tabSearch)),
      floatingActionButton: pendingAll
          ? Padding(
              padding: const EdgeInsets.only(
                bottom: 72,
              ), // clear the floating pill
              child: FloatingActionButton.extended(
                backgroundColor: AppColors.addGreen,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.done_all),
                label: Text(s.addAll),
                onPressed: () async {
                  var n = 0;
                  for (final r in List<_SearchResult>.from(_results)) {
                    final e = r.entry;
                    if (e != null) {
                      if (!store.contains(e.id)) await store.add(e);
                      n++;
                      _results.remove(r);
                    }
                  }
                  if (mounted) {
                    setState(() {});
                    _toast(s.addedCount(n));
                  }
                },
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 140),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notice on the left, batch toggle on the right; the toggle wins on narrow screens.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.searchNotice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Text(s.batchSearch, style: const TextStyle(fontSize: 13)),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _batch,
                        activeThumbColor: AppColors.accent,
                        onChanged: _running ? null : _setBatch,
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: _batch ? half : null,
                  child: TextField(
                    controller: _controller,
                    maxLines: _batch ? null : 1,
                    expands: _batch,
                    textAlignVertical: _batch ? TextAlignVertical.top : null,
                    textInputAction: _batch
                        ? TextInputAction.newline
                        : TextInputAction.search,
                    onSubmitted: _batch ? null : (_) => _search(),
                    onChanged: (_) => setState(() {}),
                    // Same font and padding in both modes; only the box height differs.
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _batch ? s.batchHint : s.searchHint,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                if (!_batch && _hiddenCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Text(
                      s.hiddenLines(_hiddenCount),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.searchScopeNote,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                      ),
                      onPressed: _running ? null : _search,
                      icon: _running
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search),
                      label: Text(_running ? s.searching : s.search),
                    ),
                  ],
                ),
                if (_running && _progress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _progress,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                if (_batch) ...[
                  const SizedBox(height: 18),
                  // "From the watching / wish list of [bangumi username]" — link opens the guide.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        s.byUserPrefix,
                        style: const TextStyle(fontSize: 13),
                      ),
                      InkWell(
                        onTap: _showUserGuide,
                        child: Text(
                          s.byUserLink,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.accent,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        s.byUserSuffix,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userController,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _fetchByUser(),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: s.bangumiUserHint,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _running ? null : _fetchByUser,
                        child: Text(s.fetchList),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final r in _results)
            _ResultBlock(
              result: r,
              onChoose: (id) => _runOne(r, chosenId: id),
              onDone: () => _removeResult(r),
            ),
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({
    required this.result,
    required this.onChoose,
    required this.onDone,
  });
  final _SearchResult result;
  final void Function(int id) onChoose;
  /// Drops this result block, whether the anime was added or dismissed.
  final VoidCallback onDone;

  Future<void> _add(BuildContext context, AnimeEntry e, AnimeStore store, S s) async {
    await store.add(e);
    if (context.mounted) showToast(context, '${s.added}: ${e.titleFor(s.lang)}');
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final store = context.watch<AnimeStore>();
    final r = result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            r.header != null
                ? '${r.header}${r.entry?.titleFor(s.lang) ?? (r.alreadyId != null ? _storedTitle(store, r, s) : r.keyword)}'
                : s.resultsFor(r.keyword),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (r.loading)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(
              color: AppColors.accent,
              backgroundColor: Color(0xFFFCE4EC),
            ),
          )
        else if (r.entry != null)
          // Swipe left on a touchscreen, right-click with a mouse: an X that
          // drops this result without adding it.
          ContextMenuRegion(
            items: [
              ContextMenuItem(label: s.add, icon: Icons.check_rounded, onSelected: () => _add(context, r.entry!, store, s)),
              ContextMenuItem(label: s.dismiss, icon: Icons.close, danger: true, onSelected: onDone),
            ],
            child: Slidable(
              key: ValueKey('result-${r.entry!.id}'),
              endActionPane: ActionPane(
                motion: const BehindMotion(),
                extentRatio: 0.28,
                children: [
                  CustomSlidableAction(
                    onPressed: (_) => onDone(),
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    padding: EdgeInsets.zero,
                    child: const Icon(Icons.close, size: 44),
                  ),
                ],
              ),
              child: AnimeCard(
                entry: r.entry!,
                trailing: IconButton(
                  tooltip: s.add,
                  iconSize: 30,
                  color: AppColors.addGreen,
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () => _add(context, r.entry!, store, s),
                ),
              ),
            ),
          )
        else if (r.error == 'already_added')
          // Same card frame as a result, but only the name + a green note;
          // the X removes this whole block silently.
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _storedTitle(store, r, s),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.alreadyAddedNote,
                          style: const TextStyle(color: AppColors.addGreen, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: IconButton(
                      tooltip: s.close,
                      icon: const Icon(Icons.close_rounded, size: 26),
                      color: const Color(0xFF7A4E5E),
                      onPressed: onDone, // dismiss: drops header, card and API line
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (r.choices != null && r.choices!.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              s.chooseCandidate,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          for (final c in r.choices!)
            _CandidateTile(candidate: c, onTap: () => onChoose(c.subject.id)),
        ] else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _errorText(s, r.error),
              style: const TextStyle(color: Color(0xFFC62828)),
            ),
          ),
        if (!r.loading && r.stats != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              '${s.callSummary}: ${r.stats} · ${s.elapsed(r.elapsed.inMilliseconds / 1000)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ),
      ],
    );
  }

  String _errorText(S s, String? err) {
    if (err == null || err == 'not_found') return s.notFound;
    if (err == 'no_schedule') return s.noSchedule;
    return _bgmError(s, err);
  }
}

/// Maps the mirror's queue-full error to a localized message; anything else
/// is shown as-is.
String _bgmError(S s, Object e) {
  final m = e.toString();
  return m.contains('mirror_busy') ? s.mirrorBusy : m;
}

/// Localized title of an already-added show, read from the schedule store.
String _storedTitle(AnimeStore store, _SearchResult r, S s) {
  final id = r.alreadyId;
  if (id != null) {
    for (final e in store.items) {
      if (e.id == id) return e.titleFor(s.lang);
    }
  }
  return r.alreadyName ?? r.keyword;
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.onTap});
  final Candidate candidate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sub = candidate.subject;
    final name = sub.nameCn.isNotEmpty ? sub.nameCn : sub.name;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 40,
            height: 56,
            child: CoverImage(url: sub.coverUrl, fontSize: 7),
          ),
        ),
        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${sub.date ?? ''}  ${candidate.airing ? '' : s.upcoming}',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

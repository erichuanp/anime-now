import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../main.dart';
import '../services/cover_cache.dart';

/// A cover from [CoverCache]: the file once it has been fetched (one at a
/// time, see CoverCache), otherwise a pink placeholder reading 暂时不可用.
/// [url] is the canonical lain.bgm.tv URL stored in anime.json.
class CoverImage extends StatelessWidget {
  const CoverImage({super.key, required this.url, this.fontSize = 10});

  final String url;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return Container(color: const Color(0xFFF8BBD0));
    final cache = context.watch<CoverCache>();
    final file = cache.fileFor(url);
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (context, _, _) => _placeholder(context),
      );
    }
    cache.ensure(url);
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => Container(
        color: const Color(0xFFFCE4EC),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: Text(
          S.of(context).coverUnavailable,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: fontSize, height: 1.2, color: AppColors.accent),
        ),
      );
}

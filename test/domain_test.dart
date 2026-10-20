import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fysg_flutter/l10n/app_localizations.dart';
import 'package:fysg_flutter/providers/song_resolver.dart';
import 'package:fysg_flutter/models/song.dart';
import 'package:fysg_flutter/utils/result.dart';
import 'package:fysg_flutter/utils/toast_utils.dart';
import 'package:fysg_flutter/api/fysg_service.dart';

void main() {
  group('SongResolver', () {
    const resolver = SongResolver();

    test('mergeSong prefers details but keeps base fallbacks', () {
      const base = Song(id: 1, name: 'base', artist: 'a', url: 'u1');
      const details = Song(id: 1, name: '', artist: 'b', lyrics: 'lrc');
      final merged = resolver.mergeSong(base, details);
      expect(merged.name, 'base');
      expect(merged.artist, 'b');
      expect(merged.lyrics, 'lrc');
      expect(merged.url, 'u1');
    });

    test('isSameSong delegates to value equality', () {
      const a = Song(id: 1, name: 'n');
      const b = Song(id: 1, name: 'n');
      expect(resolver.isSameSong(a, b), isTrue);
    });
  });

  group('AppError codes', () {
    test('structured codes do not depend on message text', () {
      expect(NetworkError.timeout().code, 'timeout');
      expect(NetworkError.rateLimited().code, 'rateLimited');
      expect(NetworkError.forbidden(403).code, 'forbidden');
      expect(NetworkError.server(500).code, 'server');
      expect(const NetworkError('x').code, 'network');
      expect(AppError.notFound('歌曲 1').code, 'notFound');
    });

    test('message still readable', () {
      expect(NetworkError.timeout().message, contains('超时'));
    });

    testWidgets('localizedAppError formats NotFoundError without duplication', (
      tester,
    ) async {
      late String zhText;
      late String enText;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: Builder(
            builder: (context) {
              zhText = ToastUtils.localizedAppError(
                context,
                AppError.notFound('歌曲 42'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(zhText, '歌曲 42不存在');
      expect(zhText, isNot(contains('不存在不存在')));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: Builder(
            builder: (context) {
              enText = ToastUtils.localizedAppError(
                context,
                AppError.notFound('Song 42'),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(enText, 'Song 42 not found');
    });
  });

  group('PagedList.hasMore', () {
    test('uses total when known', () {
      const paged = PagedList(items: [], total: 28, page: 0, size: 20);
      expect(paged.hasMore, isTrue);
      const last = PagedList(items: [], total: 28, page: 1, size: 20);
      expect(last.hasMore, isFalse);
    });

    test('falls back to size heuristic when total unknown', () {
      const paged = PagedList(items: [], total: -1, page: 0, size: 20);
      expect(paged.hasMore, isFalse);
    });
  });
}

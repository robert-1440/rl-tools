import 'package:rl_tools/gitty.dart';
import 'package:test/test.dart';

void main() {
  group('parsePrRef', () {
    void expectRef(String input, String host, String owner, String repo, int number) {
      final ref = parsePrRef(input);
      expect(ref, isNotNull, reason: "failed to parse '$input'");
      expect(ref!.host, host);
      expect(ref.owner, owner);
      expect(ref.repo, repo);
      expect(ref.number, number);
    }

    test('parses a full https PR url', () {
      expectRef('https://github.com/rlibby/rl-tools/pull/42', 'github.com', 'rlibby', 'rl-tools', 42);
    });

    test('parses urls without a scheme', () {
      expectRef('github.com/rlibby/rl-tools/pull/42', 'github.com', 'rlibby', 'rl-tools', 42);
    });

    test('ignores trailing path, query and fragment', () {
      expectRef('https://github.com/o/r/pull/7/files', 'github.com', 'o', 'r', 7);
      expectRef('https://github.com/o/r/pull/7#issuecomment-1', 'github.com', 'o', 'r', 7);
      expectRef('https://github.com/o/r/pull/7?w=1', 'github.com', 'o', 'r', 7);
    });

    test('parses enterprise hosts', () {
      expectRef('https://git.example.com/o/r/pull/7', 'git.example.com', 'o', 'r', 7);
    });

    test('parses short forms', () {
      expectRef('rlibby/rl-tools#42', 'github.com', 'rlibby', 'rl-tools', 42);
      expectRef('rlibby/rl-tools/pull/42', 'github.com', 'rlibby', 'rl-tools', 42);
    });

    test('trims surrounding whitespace', () {
      expectRef('  https://github.com/o/r/pull/7\n', 'github.com', 'o', 'r', 7);
    });

    test('rejects unrecognized input', () {
      expect(parsePrRef(''), isNull);
      expect(parsePrRef('42'), isNull);
      expect(parsePrRef('https://github.com/o/r'), isNull);
      expect(parsePrRef('https://github.com/o/r/issues/7'), isNull);
      expect(parsePrRef('https://github.com/o/r/pull/abc'), isNull);
    });

    test('ghRepo omits github.com but keeps other hosts', () {
      expect(parsePrRef('https://github.com/o/r/pull/7')!.ghRepo, 'o/r');
      expect(parsePrRef('https://git.example.com/o/r/pull/7')!.ghRepo, 'git.example.com/o/r');
    });

    test('url round-trips', () {
      expect(parsePrRef('o/r#7')!.url, 'https://github.com/o/r/pull/7');
    });
  });
}

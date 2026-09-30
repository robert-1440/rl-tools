import 'package:rl_tools/gitty.dart';
import 'package:test/test.dart';

void main() {
  group('parseRemoteUrl', () {
    void expectRepo(String input, String host, String owner, String repo) {
      final parsed = parseRemoteUrl(input);
      expect(parsed, isNotNull, reason: "failed to parse '$input'");
      expect(parsed!.host, host);
      expect(parsed.owner, owner);
      expect(parsed.repo, repo);
    }

    test('parses https urls, with or without .git', () {
      expectRepo('https://github.com/rlibby/rl-tools.git', 'github.com', 'rlibby', 'rl-tools');
      expectRepo('https://github.com/rlibby/rl-tools', 'github.com', 'rlibby', 'rl-tools');
      expectRepo('https://user@github.com/rlibby/rl-tools/', 'github.com', 'rlibby', 'rl-tools');
    });

    test('parses ssh urls, including a port', () {
      expectRepo('ssh://git@github.com/rlibby/rl-tools.git', 'github.com', 'rlibby', 'rl-tools');
      expectRepo('ssh://git@git.example.com:2222/o/r.git', 'git.example.com', 'o', 'r');
    });

    test('parses scp-like urls', () {
      expectRepo('git@github.com:rlibby/rl-tools.git', 'github.com', 'rlibby', 'rl-tools');
      expectRepo('github.com:rlibby/rl-tools', 'github.com', 'rlibby', 'rl-tools');
    });

    test('keeps nested group paths as the owner', () {
      expectRepo('https://gitlab.com/group/sub/repo.git', 'gitlab.com', 'group/sub', 'repo');
    });

    test('rejects urls without an owner and repo', () {
      expect(parseRemoteUrl('https://github.com/rl-tools.git'), isNull);
      expect(parseRemoteUrl('/local/path/repo.git'), isNull);
      expect(parseRemoteUrl('../repo'), isNull);
      expect(parseRemoteUrl('https://github.com/../repo'), isNull);
      expect(parseRemoteUrl(''), isNull);
    });
  });

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

  group('parseSquashArgs', () {
    test('joins message words', () {
      final o = parseSquashArgs(['Fix', 'the', 'thing']);
      expect(o.error, isNull);
      expect(o.message, 'Fix the thing');
      expect(o.base, isNull);
      expect(o.force, isFalse);
    });

    test('ignores commit-style -m and -am', () {
      expect(parseSquashArgs(['-m', 'a message']).message, 'a message');
      expect(parseSquashArgs(['-am', 'a message']).message, 'a message');
    });

    test('reads --base in both forms', () {
      expect(parseSquashArgs(['--base', 'develop', 'msg']).base, 'develop');
      expect(parseSquashArgs(['--base=develop', 'msg']).base, 'develop');
    });

    test('reads the force flag', () {
      expect(parseSquashArgs(['-f', 'msg']).force, isTrue);
      expect(parseSquashArgs(['--force', 'msg']).force, isTrue);
    });

    test('reports help without requiring a message', () {
      expect(parseSquashArgs(['-h']).help, isTrue);
      expect(parseSquashArgs(['--help']).help, isTrue);
      expect(parseSquashArgs(['--help']).error, isNull);
    });

    test('requires a message', () {
      expect(parseSquashArgs([]).error, isNotNull);
      expect(parseSquashArgs(['--base', 'main']).error, isNotNull);
    });

    test('rejects a --base without a value and unknown options', () {
      expect(parseSquashArgs(['msg', '--base']).error, isNotNull);
      expect(parseSquashArgs(['--base=', 'msg']).error, isNotNull);
      expect(parseSquashArgs(['--bogus', 'msg']).error, contains('--bogus'));
    });
  });
}

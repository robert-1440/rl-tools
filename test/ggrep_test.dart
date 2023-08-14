
import 'package:rl_tools/ggrep.dart';

import 'utils_for_tests.dart';

class Suite {

  @Test("Match")
  void matchTest() {
    assertThat(match("*", "hello")).isTrue();
    assertThat(match("h*o", "hello")).isTrue();
    assertThat(match("h*o", "help")).isFalse();
    assertThat(match("?ello", "hello")).isTrue();
  }
}

void main() {
    executeTestSuite(Suite);
}
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import XCTest
@testable import _MatchingEngine
@testable import _StringProcessing

extension Executor {
  func _firstMatch(
    _ regex: String, input: String,
    syntax: SyntaxOptions = .traditional,
    enableTracing: Bool = false
  ) throws -> (match: Substring, captures: [Substring?]) {
    // TODO: This should be a CollectionMatcher API to call...
    // Consumer -> searcher algorithm
    var start = input.startIndex
    while true {
      if let (range, caps) = self.executeFlat(
        input: input,
        in: start..<input.endIndex,
        mode: .partialFromFront
      ) {
        let matched = input[range]
        return (matched, caps.latest(from: input))
      } else if start == input.endIndex {
        throw "match not found for \(regex) in \(input)"
      } else {
        input.formIndex(after: &start)
      }
    }
  }
}

func _firstMatch(
  _ regex: String,
  input: String,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false
) throws -> (String, [String?]) {
  var executor = try _compileRegex(regex, syntax)
  executor.engine.enableTracing = enableTracing
  let (str, caps) = try executor._firstMatch(
    regex, input: input, enableTracing: enableTracing)
  let capStrs = caps.map { $0 == nil ? nil : String($0!) }
  return (String(str), capStrs)
}

// TODO: multiple-capture variant
// TODO: unify with firstMatch below, etc.
func captureTest(
  _ regex: String,
  _ tests: (input: String, expect: [String?]?)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false
) {
  for (test, expect) in tests {
    do {
      guard let (_, caps) = try? _firstMatch(
        regex,
        input: test,
        syntax: syntax,
        enableTracing: enableTracing
      ) else {
        if expect == nil {
          continue
        } else {
          throw "Match failed"
        }
      }
      guard let expect = expect else {
        throw "Match succeeded where failure expected"
      }
      let capStrs = caps.map { $0 == nil ? nil : String($0!) }
      guard expect.count == capStrs.count else {
        throw """
          Capture count mismatch:
            \(expect)
            \(capStrs)
          """
      }

      guard expect.elementsEqual(capStrs) else {
        throw """
          Capture mismatch:
            \(expect)
            \(capStrs)
          """
      }
    } catch {
      if !xfail {
        XCTFail("\(error)")
      }
    }
  }
}

/// Test whether a string matches or not
///
/// TODO: Configuration for whole vs partial string matching...
func matchTest(
  _ regex: String,
  _ tests: (input: String, expect: Bool)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false
) {
  for (test, expect) in tests {
    firstMatchTest(
      regex,
      input: test,
      match: expect ? test : nil,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail)
  }
}

// TODO: Adjust below to also check captures

/// Test the first match in a string, via `firstRange(of:)`
func firstMatchTest(
  _ regex: String,
  input: String,
  match: String?,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false,
  file: StaticString = #filePath,
  line: UInt = #line
) {
  do {
    let (found, _) = try _firstMatch(
      regex,
      input: input,
      syntax: syntax,
      enableTracing: enableTracing)

    if xfail {
      XCTAssertNotEqual(found, match, file: file, line: line)
    } else {
      XCTAssertEqual(found, match, file: file, line: line)
    }
  } catch {
    if !xfail && match != nil {
      XCTFail("\(error)", file: file, line: line)
    }
    return
  }
}

func firstMatchTests(
  _ regex: String,
  _ tests: (input: String, match: String?)...,
  syntax: SyntaxOptions = .traditional,
  enableTracing: Bool = false,
  dumpAST: Bool = false,
  xfail: Bool = false
) {
  for (input, match) in tests {
    firstMatchTest(
      regex,
      input: input,
      match: match,
      syntax: syntax,
      enableTracing: enableTracing,
      dumpAST: dumpAST,
      xfail: xfail)
  }
}

extension RegexTests {
  func testMatch() {
    firstMatchTest(
      "abc", input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+xyz", match: "abc+")
    firstMatchTest(
      #"abc\+d*"#, input: "123abc+dddxyz", match: "abc+ddd")
    firstMatchTest(
      "a(b)", input: "123abcxyz", match: "ab")

    firstMatchTest(
      "(.)*(.*)", input: "123abcxyz", match: "123abcxyz")
    firstMatchTest(
      #"abc\d"#, input: "xyzabc123", match: "abc1")

    // MARK: Alternations

    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdefghijxyz", match: "j")
    firstMatchTest(
      "abc(?:de)+fghi*k|j", input: "123abcdedefghkxyz", match: "abcdedefghk")
    firstMatchTest(
      "a(?:b|c)?d", input: "123adxyz", match: "ad")
    firstMatchTest(
      "a(?:b|c)?d", input: "123abdxyz", match: "abd")
    firstMatchTest(
      "a(?:b|c)?d", input: "123acdxyz", match: "acd")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123abcdefxyz", match: "abcde")
    firstMatchTest(
      "a?b??c+d+?e*f*?", input: "123bcddefxyz", match: "bcd")
    firstMatchTest(
      "a|b?c", input: "123axyz", match: "a")
    firstMatchTest(
      "a|b?c", input: "123bcxyz", match: "bc")
    firstMatchTest(
      "(a|b)c", input: "123abcxyz", match: "bc")

    // Alternations with empty branches are permitted.
    firstMatchTest("|", input: "ab", match: "")
    firstMatchTest("(|)", input: "ab", match: "")
    firstMatchTest("a|", input: "ab", match: "a")
    firstMatchTest("a|", input: "ba", match: "")
    firstMatchTest("|b", input: "ab", match: "")
    firstMatchTest("|b", input: "ba", match: "")
    firstMatchTest("|b|", input: "ab", match: "")
    firstMatchTest("|b|", input: "ba", match: "")
    firstMatchTest("a|b|", input: "ab", match: "a")
    firstMatchTest("a|b|", input: "ba", match: "b")
    firstMatchTest("a|b|", input: "ca", match: "")
    firstMatchTest("||c|", input: "ab", match: "")
    firstMatchTest("||c|", input: "cb", match: "")
    firstMatchTest("|||", input: "ab", match: "")
    firstMatchTest("a|||d", input: "bc", match: "")
    firstMatchTest("a|||d", input: "abc", match: "a")
    firstMatchTest("a|||d", input: "d", match: "")

    // MARK: Unicode scalars

    firstMatchTest(
      #"a\u0065b\u{00000065}c\x65d\U00000065"#,
      input: "123aebecedexyz", match: "aebecede")

    firstMatchTest(
      #"\u{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\x{00000000000000000000000000A}"#,
      input: "123\nxyz", match: "\n")
    firstMatchTest(
      #"\o{000000000000000000000000007}"#,
      input: "123\u{7}xyz", match: "\u{7}")

    firstMatchTest(#"\o{70}"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\0"#, input: "123\0xyz", match: "\0")
    firstMatchTest(#"\01"#, input: "123\u{1}xyz", match: "\u{1}")
    firstMatchTest(#"\070"#, input: "1238xyz", match: "8")
    firstMatchTest(#"\07A"#, input: "123\u{7}Axyz", match: "\u{7}A")
    firstMatchTest(#"\08"#, input: "123\08xyz", match: "\08")
    firstMatchTest(#"\0707"#, input: "12387xyz", match: "87")

    // code point sequence
    firstMatchTest(#"\u{61 62 63}"#, input: "123abcxyz", match: "abc", xfail: true)


    // MARK: Quotes

    firstMatchTest(
      #"a\Q .\Eb"#,
      input: "123a .bxyz", match: "a .b")
    firstMatchTest(
      #"a\Q \Q \\.\Eb"#,
      input: #"123a \Q \\.bxyz"#, match: #"a \Q \\.b"#)
    firstMatchTest(
      #"\d\Q...\E"#,
      input: "Countdown: 3... 2... 1...", match: "3...")

    // MARK: Comments

    firstMatchTest(
      #"a(?#comment)b"#, input: "123abcxyz", match: "ab")
    firstMatchTest(
      #"a(?#. comment)b"#, input: "123abcxyz", match: "ab")
  }

  func testMatchQuantification() {
    // MARK: Quantification

    firstMatchTest(
      #"a{1,2}"#, input: "123aaaxyz", match: "aa")
    firstMatchTest(
      #"a{,2}"#, input: "123aaaxyz", match: "")
    firstMatchTest(
      #"a{,2}x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"a{,2}x"#, input: "123xyz", match: "x")
    firstMatchTest(
      #"a{2,}"#, input: "123aaaxyz", match: "aaa")
    firstMatchTest(
      #"a{1}"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?"#, input: "123aaaxyz", match: "a")
    firstMatchTest(
      #"a{1,2}?x"#, input: "123aaaxyz", match: "aax")
    firstMatchTest(
      #"xa{0}y"#, input: "123aaaxyz", match: "xy")
    firstMatchTest(
      #"xa{0,0}y"#, input: "123aaaxyz", match: "xy")

    firstMatchTest("a.*", input: "dcba", match: "a")

    firstMatchTest("a*", input: "", match: "")
    firstMatchTest("a*", input: "a", match: "a")
    firstMatchTest("a*", input: "aaa", match: "aaa")

    firstMatchTest("a*?", input: "", match: "")
    firstMatchTest("a*?", input: "a", match: "")
    firstMatchTest("a*?a", input: "aaa", match: "a")
    firstMatchTest("xa*?x", input: "_xx__", match: "xx")
    firstMatchTest("xa*?x", input: "_xax__", match: "xax")
    firstMatchTest("xa*?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a+", input: "", match: nil)
    firstMatchTest("a+", input: "a", match: "a")
    firstMatchTest("a+", input: "aaa", match: "aaa")

    firstMatchTest("a+?", input: "", match: nil)
    firstMatchTest("a+?", input: "a", match: "a")
    firstMatchTest("a+?a", input: "aaa", match: "aa")
    firstMatchTest("xa+?x", input: "_xx__", match: nil)
    firstMatchTest("xa+?x", input: "_xax__", match: "xax")
    firstMatchTest("xa+?x", input: "_xaax__", match: "xaax")

    firstMatchTest("a??", input: "", match: "")
    firstMatchTest("a??", input: "a", match: "")
    firstMatchTest("a??a", input: "aaa", match: "a")
    firstMatchTest("xa??x", input: "_xx__", match: "xx")
    firstMatchTest("xa??x", input: "_xax__", match: "xax")
    firstMatchTest("xa??x", input: "_xaax__", match: nil)

    // Possessive .* will consume entire input
    firstMatchTests(
      ".*+x",
      ("abc", nil), ("abcx", nil), ("", nil))

    firstMatchTests(
      "a+b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a++b",
      ("abc", "ab"),
      ("aaabc", "aaab"),
      ("b", nil))
    firstMatchTests(
      "a+?b",
      ("abc", "ab"),
      ("aaabc", "aaab"), // firstRange will match from front
      ("b", nil))

    firstMatchTests(
      "a+a",
      ("babc", nil),
      ("baaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a++a",
      ("babc", nil),
      ("baaabc", nil),
      ("bb", nil))
    firstMatchTests(
      "a+?a",
      ("babc", nil),
      ("baaabc", "aa"),
      ("bb", nil))


    firstMatchTests(
      "a{2,4}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}a",
      ("babc", "a"),
      ("baabc", "aa"),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaaaaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}?a",
      ("babc", "a"),
      ("baabc", "a"),
      ("baaabc", "a"),
      ("baaaaabc", "a"),
      ("baaaaaaaabc", "a"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}?a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", "aaa"),
      ("baaaaabc", "aaa"),
      ("baaaaaaaabc", "aaa"),
      ("bb", nil))

    firstMatchTests(
      "a{2,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{,4}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", "aaaaa"),
      ("baaaaaaaabc", "aaaaa"),
      ("bb", nil))
    firstMatchTests(
      "a{2,}+a",
      ("babc", nil),
      ("baabc", nil),
      ("baaabc", nil),
      ("baaaaabc", nil),
      ("baaaaaaaabc", nil),
      ("bb", nil))


    firstMatchTests(
      "(?:a{2,4}?b)+",
      ("aab", "aab"),
      ("aabaabaab", "aabaabaab"),
      ("aaabaaaabaabab", "aaabaaaabaab")
      // TODO: Nested reluctant reentrant example, xfailed
    )

    // TODO: After captures, easier to test these
  }

  func testMatchCharacterClasses() {
    // MARK: Character classes

    firstMatchTest(#"abc\d"#, input: "xyzabc123", match: "abc1")

    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123(abc)xyz", match: "(")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123-abcxyz", match: "-")
    firstMatchTest(
      "[-|$^:?+*())(*-+-]", input: "123^abcxyz", match: "^")

    firstMatchTest(
      "[a-b-c]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[a-b-c]", input: "123-abcxyz", match: "-")

    firstMatchTest("[-a-]", input: "123abcxyz", match: "a")
    firstMatchTest("[-a-]", input: "123-abcxyz", match: "-")

    firstMatchTest("[a-z]", input: "123abcxyz", match: "a")
    firstMatchTest("[a-z]", input: "123ABCxyz", match: "x")
    firstMatchTest("[a-z]", input: "123-abcxyz", match: "a")

    // Character class subtraction
    firstMatchTest("[a-d--a-c]", input: "123abcdxyz", match: "d")

    firstMatchTest("[-]", input: "123-abcxyz", match: "-")

    // These are metacharacters in certain contexts, but normal characters
    // otherwise.
    firstMatchTest(":-]", input: "123:-]xyz", match: ":-]")

    firstMatchTest(
      "[^abc]", input: "123abcxyz", match: "1")
    firstMatchTest(
      "[a^]", input: "123abcxyz", match: "a")

    firstMatchTest(
      #"\D\S\W"#, input: "123ab-xyz", match: "ab-")

    firstMatchTest(
      #"[\dd]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      #"[\dd]"#, input: "xyzabcd123", match: "d")

    firstMatchTest(
      #"[^[\D]]"#, input: "xyzabc123", match: "1")
    firstMatchTest(
      "[[ab][bc]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab][bc]]", input: "123cbaxyz", match: "c")
    firstMatchTest(
      "[[ab]c[de]]", input: "123abcxyz", match: "a")
    firstMatchTest(
      "[[ab]c[de]]", input: "123cbaxyz", match: "c")

    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "123abcxyz", match: "1")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "xyzabc123", match: "x")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZabc123", match: "a")
    firstMatchTest(
      #"[ab[:space:]\d[:^upper:]cd]"#,
      input: "XYZ abc123", match: " ")

    firstMatchTest("[[[:space:]]]", input: "123 abc xyz", match: " ")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")

    firstMatchTest(
      "[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")

    firstMatchTest(
      "[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      "[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:isALNUM:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:AL_NUM:]]", input: "[[:alnum:]]", match: "a")

    // Unfortunately, scripts are not part of stdlib...
    firstMatchTest(
      "[[:script=Greek:]]", input: "123αβγxyz", match: "α",
      xfail: true)

    // MARK: Operators

    firstMatchTest(
      #"[a[bc]de&&[^bc]\d]+"#, input: "123bcdxyz", match: "d")

    // Empty intersection never matches, should this be a compile time error?
    // matchTest("[a&&b]", input: "123abcxyz", match: "")

    firstMatchTest(
      "[abc--def]", input: "123abcxyz", match: "a")

    // We left-associate for chained operators.
    firstMatchTest(
      "[ab&&b~~cd]", input: "123abcxyz", match: "b")
    firstMatchTest(
      "[ab&&b~~cd]", input: "123acdxyz", match: "c") // this doesn't match NSRegularExpression's behavior

    // Operators are only valid in custom character classes.
    firstMatchTest(
      "a&&b", input: "123a&&bcxyz", match: "a&&b")
    firstMatchTest(
      "&?", input: "123a&&bcxyz", match: "")
    firstMatchTest(
      "&&?", input: "123a&&bcxyz", match: "&&")
    firstMatchTest(
      "--+", input: "123---xyz", match: "---")
    firstMatchTest(
      "~~*", input: "123~~~xyz", match: "~~~")


    // Quotes in character classes.
    firstMatchTest(#"[\Qabc\E]"#, input: "QEa", match: "a")
    firstMatchTest(#"[\Qabc\E]"#, input: "cxx", match: "c")
    firstMatchTest(#"[\Qabc\E]+"#, input: "cba", match: "cba")
    firstMatchTest(#"[\Qa-c\E]+"#, input: "a-c", match: "a-c")

    firstMatchTest(#"["a-c"]+"#, input: "abc", match: "a",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: "cba", match: "cba",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: "abc",
                   syntax: .experimental)
    firstMatchTest(#"["abc"]+"#, input: #""abc""#, match: #""abc""#)
  }

  func testCharacterProperties() {
    // MARK: Character names.

    firstMatchTest(#"\N{ASTERISK}"#, input: "123***xyz", match: "*")
    firstMatchTest(#"[\N{ASTERISK}]"#, input: "123***xyz", match: "*")
    firstMatchTest(
      #"\N{ASTERISK}+"#, input: "123***xyz", match: "***")
    firstMatchTest(
      #"\N {2}"#, input: "123  xyz", match: "3  ")

    firstMatchTest(#"\N{U+2C}"#, input: "123,xyz", match: ",")
    firstMatchTest(#"\N{U+1F4BF}"#, input: "123💿xyz", match: "💿")
    firstMatchTest(#"\N{U+00001F4BF}"#, input: "123💿xyz", match: "💿")

    // MARK: Character properties.

    firstMatchTest(#"\p{L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=L}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{Lu}"#, input: "123abcXYZ", match: "X")

    firstMatchTest(
      #"\P{Cc}"#, input: "\n\n\nXYZ", match: "X")
    firstMatchTest(
      #"\P{Z}"#, input: "   XYZ", match: "X")

    firstMatchTest(#"[\p{C}]"#, input: "123\n\n\nXYZ", match: "\n")
    firstMatchTest(#"\p{C}+"#, input: "123\n\n\nXYZ", match: "\n\n\n")

    // UAX44-LM3 means all of the below are equivalent.
    firstMatchTest(#"\p{ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{gc=ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General_Category=Ll}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{General-Category=isLl}"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ g_ c =-  __l_ l  _ }"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general ca-tegory =  __l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{- general category =  is__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{ general category -=  IS__l_ l  _ }"#,
      input: "123abcXYZ", match: "a")

    firstMatchTest(#"\p{Any}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{Assigned}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{ascii}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\p{isAny}"#, input: "123abcXYZ", match: "1")

    // Unfortunately, scripts are not part of stdlib...
    firstMatchTest(
      #"\p{sc=grek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{sc=isGreek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{Greek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{isGreek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\P{Script=Latn}"#, input: "abcαβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{script=Greek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{ISscript=isGreek}"#, input: "123αβγxyz", match: "α",
      xfail: true)
    firstMatchTest(
      #"\p{scx=bamum}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ",
      xfail: true)
    firstMatchTest(
      #"\p{ISBAMUM}"#, input: "123ꚠꚡꚢxyz", match: "ꚠ",
      xfail: true)

    firstMatchTest(#"\p{alpha}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\P{alpha}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(
      #"\p{alphabetic=True}"#, input: "123abcXYZ", match: "a")

    // This is actually available-ed...
    firstMatchTest(
      #"\p{emoji=t}"#, input: "123💿xyz", match: "a",
      xfail: true)

    firstMatchTest(#"\p{Alpha=no}"#, input: "123abcXYZ", match: "1")
    firstMatchTest(#"\P{Alpha=no}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(#"\p{isAlphabetic}"#, input: "123abcXYZ", match: "a")
    firstMatchTest(
      #"\p{isAlpha=isFalse}"#, input: "123abcXYZ", match: "1")

    // Oniguruma special support not in stdlib
    firstMatchTest(
      #"\p{In_Runic}"#, input: "123ᚠᚡᚢXYZ", match: "ᚠ",
    xfail: true)

    // TODO: PCRE special
    firstMatchTest(
      #"\p{Xan}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)
    firstMatchTest(
      #"\p{Xps}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xsp}"#, input: "123 abc xyz", match: " ",
      xfail: true)
    firstMatchTest(
      #"\p{Xuc}"#, input: "$var", match: "$",
      xfail: true)
    firstMatchTest(
      #"\p{Xwd}"#, input: "[[:alnum:]]", match: "a",
      xfail: true)

    firstMatchTest(#"\p{alnum}"#, input: "[[:alnum:]]", match: "a")
    firstMatchTest(#"\p{is_alnum}"#, input: "[[:alnum:]]", match: "a")

    firstMatchTest(#"\p{blank}"#, input: "123\tabc xyz", match: "\t")
    firstMatchTest(
      #"\p{graph}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest(
      #"\p{print}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest(
      #"\p{word}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest(
      #"\p{xdigit}"#,
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")

    firstMatchTest("[[:alnum:]]", input: "[[:alnum:]]", match: "a")
    firstMatchTest("[[:blank:]]", input: "123\tabc xyz", match: "\t")
    firstMatchTest("[[:graph:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:print:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: " ")
    firstMatchTest("[[:word:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
    firstMatchTest("[[:xdigit:]]",
      input: "\u{7}\u{1b}\u{a}\n\r\t abc", match: "a")
  }

  func testAssertions() {
    // MARK: Assertions
    firstMatchTest(
      #"\d+(?= dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(?= pesos)"#,
      input: "Price: 100 dollars", match: nil)
    firstMatchTest(
      #"(?=\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100",
      xfail: true) // TODO

    firstMatchTest(
      #"\d+(*pla: dollars)"#,
      input: "Price: 100 dollars", match: "100")
    firstMatchTest(
      #"\d+(*positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100")

    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(?! dollars)"#,
      input: "Price: 100 dollars", match: "10")
    firstMatchTest(
      #"(?!\d+ dollars)\d+"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*nla: dollars)"#,
      input: "Price: 100 pesos", match: "100")
    firstMatchTest(
      #"\d+(*negative_lookahead: dollars)"#,
      input: "Price: 100 pesos", match: "100")

    firstMatchTest(
      #"(?<=USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*plb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<=USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    firstMatchTest(
      #"(?<!USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*nlb:USD)\d+"#, input: "Price: JYP100", match: "100", xfail: true)
    firstMatchTest(
      #"(*negative_lookbehind:USD)\d+"#,
      input: "Price: JYP100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<!USD\d{3})"#, input: "Price: JYP100", match: "100", xfail: true)
  }

  func testMatchAnchors() {
    // MARK: Anchors
    firstMatchTests(
      #"^\d+"#,
      ("123", "123"),
      (" 123", nil),
      ("123 456", "123"),
      (" 123 \n456", "456"),
      (" \n123 \n456", "123"))

    firstMatchTests(
      #"\d+$"#,
      ("123", "123"),
      (" 123", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "123"),
      ("123 456", "456"))

    firstMatchTests(
      #"\A\d+"#,
      ("123", "123"),
      (" 123", nil),
      (" 123 \n456", nil),
      (" 123\n456", nil),
      ("123 456", "123"))

    firstMatchTests(
      #"\d+\Z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", "123"),
      (" 123\n", "123"),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", "456"),
      ("123 456", "456"))


    firstMatchTests(
      #"\d+\z"#,
      ("123", "123"),
      (" 123", "123"),
      ("123\n", nil),
      (" 123\n", nil),
      (" 123 \n456", "456"),
      (" 123\n456", "456"),
      (" 123\n456\n", nil),
      ("123 456", "456"))

    firstMatchTests(
      #"\d+\b"#,
      ("123", "123"),
      (" 123", "123"),
      ("123 456", "123"))
    firstMatchTests(
      #"\d+\b\s\b\d+"#,
      ("123", nil),
      (" 123", nil),
      ("123 456", "123 456"))

    firstMatchTests(
      #"\B\d+"#,
      ("123", "23"),
      (" 123", "23"),
      ("123 456", "23"))

    // TODO: \G and \K

    // TODO: Oniguruma \y and \Y

  }

  func testMatchGroups() {
    // MARK: Groups

    // Named captures
    firstMatchTest(
      #"a(?<label>b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?'label'b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      #"a(?P<label>b)c"#, input: "123abcxyz", match: "abc")

    // Other groups
    firstMatchTest(
      #"a(?:b)c"#, input: "123abcxyz", match: "abc")
    firstMatchTest(
      "(?|(a)|(b)|(c))", input: "123abcxyz", match: "a")

    firstMatchTest(
      #"(?:a|.b)c"#, input: "123abcacxyz", match: "abc")
    firstMatchTest(
      #"(?>a|.b)c"#, input: "123abcacxyz", match: "ac", xfail: true)
    firstMatchTest(
      "(*atomic:a|.b)c", input: "123abcacxyz", match: "ac", xfail: true)
    firstMatchTest(
      #"(?:a+)[a-z]c"#, input: "123aacacxyz", match: "aac")
    firstMatchTest(
      #"(?>a+)[a-z]c"#, input: "123aacacxyz", match: "ac", xfail: true)


    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"\d+(?* dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"(?*\d+ dollars)\d+"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*napla: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)
    firstMatchTest(
      #"\d+(*non_atomic_positive_lookahead: dollars)"#,
      input: "Price: 100 dollars", match: "100", xfail: true)

    // TODO: Test example where non-atomic is significant
    firstMatchTest(
      #"(?<*USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*naplb:USD)\d+"#, input: "Price: USD100", match: "100", xfail: true)
    firstMatchTest(
      #"(*non_atomic_positive_lookbehind:USD)\d+"#,
      input: "Price: USD100", match: "100", xfail: true)
    // engines generally enforce that lookbehinds are fixed width
    firstMatchTest(
      #"\d{3}(?<*USD\d{3})"#, input: "Price: USD100", match: "100", xfail: true)

    // https://www.effectiveperlprogramming.com/2019/03/match-only-the-same-unicode-script/
    firstMatchTest(
      #"abc(*sr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

    // TODO: Test example where atomic is significant
    firstMatchTest(
      #"abc(*asr:\d+)xyz"#, input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)
    firstMatchTest(
      #"abc(*atomic_script_run:\d+)xyz"#,
      input: "abc۵۲۸528੫੨੮xyz", match: "۵۲۸", xfail: true)

  }

  func testMatchCaptureBehavior() {
    captureTest(
      #"a(b)c|abe"#,
      ("abc", ["b"]),
      ("abe", [nil]),
      ("axbe", nil))
    captureTest(
      #"a(bc)d|abce"#,
      ("abcd", ["bc"]),
      ("abce", [nil]),
      ("abxce", nil))
    captureTest(
      #"a(bc)+d|abce"#,
      ("abcbcbcd", ["bc"]),
      ("abcbce", nil),
      ("abce", [nil]),
      ("abcbbd", nil))
    captureTest(
      #"a(bc)+d|(a)bce"#,
      ("abcbcbcd", ["bc", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", nil))
    captureTest(
      #"a(b|c)+d|(a)bce"#,
      ("abcbcbcd", ["c", nil]),
      ("abce", [nil, "a"]),
      ("abcbbd", ["b", nil]))
    captureTest(
      #"a(b+|c+)d|(a)bce"#,
      ("abbbd", ["bbb", nil]),
      ("acccd", ["ccc", nil]),
      ("abce", [nil, "a"]),
      ("abbbe", nil),
      ("accce", nil),
      ("abcbbd", nil))
  }

  func testMatchReferences() {
    // TODO: Implement backreference/subpattern matching.
    firstMatchTest(
      #"(.)\1"#,
      input: "112", match: "11")
    firstMatchTest(
      #"(.)(.)(.)(.)(.)(.)(.)(.)(.)(.)\10"#,
      input: "aaaaaaaaabbc", match: "aaaaaaaaabb")
    firstMatchTest(
      #"(.)\10"#,
      input: "a\u{8}b", match: "a\u{8}")

    firstMatchTest(
      #"(.)\g001"#,
      input: "112", match: "11")

    firstMatchTest(#"(.)(.)\g-02"#, input: "abac", match: "aba", xfail: true)
    firstMatchTest(#"(?<a>.)(.)\k<a>"#, input: "abac", match: "aba", xfail: true)
    firstMatchTest(#"\g'+2'(.)(.)"#, input: "abac", match: "aba", xfail: true)
  }
  
  func testMatchExamples() {
    // Backreferences
    matchTest(
      #"(sens|respons)e and \1ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", false),
      ("sense and responsibility", false))
    matchTest(
      #"a(?'name'b(c))d\1\2|abce"#,
      ("abcdbcc", true),
      ("abcdbc", false),
      ("abce", true)
    )

    // Subpatterns
    matchTest(
      #"(sens|respons)e and (?1)ibility"#,
      ("sense and sensibility", true),
      ("response and responsibility", true),
      ("response and sensibility", true),
      ("sense and responsibility", true),
      xfail: true)

    // Palindromes
    matchTest(
      #"(\w)(?:(?R)|\w?)\1"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", true), // OK: Partial match
      ("abc", false),
      ("cat", false),
      xfail: true
    )
    matchTest(
      #"^((\w)(?:(?1)|\w?)\2)$"#,
      ("abccba", true),
      ("abcba", true),
      ("abba", true),
      ("stackcats", true),
      ("racecar", true),
      ("a anna c", false), // FAIL: Not whole line
      ("abc", false),
      ("cat", false),
      xfail: true
    )

    // HTML tags
    matchTest(
      #"<([a-zA-Z][a-zA-Z0-9]*)\b[^>]*>.*?</\1>"#,
      ("<html> a b c </html>", true),
      (#"<table style="float:right"> a b c </table>"#, true),
      ("<html> a b c </htm>", false),
      ("<htm> a b c </html>", false),
      (#"<table style="float:right"> a b c </tab>"#, false)
    )

    // Doubled words
    captureTest(
      #"\b(\w+)\s+\1\b"#,
      ("this does have one one in it", ["one"]),
      ("pass me the the kettle", ["the"]),
      ("this doesn't have any", nil)
    )

    // Floats
    captureTest(
      #"^([-+])?([0-9]*)(?:\.([0-9]+))?(?:[eE]([-+]?[0-9]+))?$"#,
      ("123.45", [nil, "123", "45", nil]),
      ("-123e12", ["-", "123", nil, "12"]),
      ("+123.456E-12", ["+", "123", "456", "-12"]),
      ("-123e1.2", nil)
    )
  }
}

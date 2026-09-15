"""Macify structural validator (runs anywhere with Python 3, no PowerShell needed).

Checks:
  1. PowerShell files: here-strings closed, comments stripped, () {} [] balanced.
  2. Embedded XAML blocks parse as XML.
  3. JSON configs parse.
  4. No PowerShell 7-only syntax (repo targets stock Windows PowerShell 5.1).
  5. UI scripts contain STA guard + single-instance guard.
  6. Files referenced by the installer actually exist.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERRORS, WARNINGS = [], []


def err(msg):
    ERRORS.append(msg)
    print("ERROR:", msg)


def warn(msg):
    WARNINGS.append(msg)
    print("warn:", msg)


def strip_ps(src, fname):
    """Remove here-strings, strings, comments. Return (code_without_noise, here_strings)."""
    out, heredocs = [], []
    i, n = 0, len(src)
    cur_heredoc = None
    while i < n:
        if cur_heredoc is not None:
            q = cur_heredoc
            # heredoc ends with "@ or '@ at start of a line
            if src[i] == "\n":
                out.append("\n")
                i += 1
                if src.startswith(q + "@", i) or (src.startswith(q, i) and i + 1 < n and src[i + 1] == "@"):
                    # closing quote must be followed by end/newline/;/)/etc.
                    j = i + 2
                    cur_heredoc = None
                    heredocs.append(out_heredoc)
                    i = j
                    continue
                continue
            out_heredoc.append(src[i])
            i += 1
            continue
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        # line comment
        if ch == "#":
            while i < n and src[i] != "\n":
                i += 1
            continue
        # block comment <# #>
        if ch == "<" and nxt == "#":
            j = src.find("#>", i + 2)
            if j == -1:
                err("%s: unclosed block comment <# #>" % fname)
                break
            i = j + 2
            continue
        # here-string open @" or @'
        if ch == "@" and nxt in ("\"", "'"):
            cur_heredoc = nxt
            out_heredoc = []
            i += 2
            continue
        # single-quoted string ('' escape)
        if ch == "'":
            i += 1
            while i < n:
                if src[i] == "'" and src[i + 1:i + 2] == "'":
                    i += 2
                    continue
                if src[i] == "'":
                    i += 1
                    break
                i += 1
            out.append("''")
            continue
        # double-quoted string (backtick escape; $() skipped as balanced unit)
        if ch == "\"":
            i += 1
            while i < n:
                c = src[i]
                if c == "`" and i + 1 < n:
                    i += 2
                    continue
                if c == "\"":
                    i += 1
                    break
                if c == "$" and src[i + 1:i + 2] == "(":
                    depth = 0
                    while i < n:
                        if src[i] == "`" and i + 1 < n:
                            i += 2
                            continue
                        if src[i] == "(":
                            depth += 1
                        elif src[i] == ")":
                            depth -= 1
                            if depth == 0:
                                i += 1
                                break
                        elif src[i] == "\"":
                            i += 1
                            while i < n and src[i] != "\"":
                                i += 2 if src[i] == "`" else 1
                            i += 1
                            continue
                        elif src[i] == "'":
                            i += 1
                            while i < n and src[i] != "'":
                                i += 1
                            i += 1
                            continue
                        i += 1
                    continue
                i += 1
            out.append('""')
            continue
        # backtick escape outside strings
        if ch == "`" and i + 1 < n:
            if src[i + 1] in (" ", "\t"):
                warn("%s: backtick-continuation followed by whitespace (line %d)" % (fname, src.count("\n", 0, i) + 1))
            out.append(src[i:i + 2])
            i += 2
            continue
        out.append(ch)
        i += 1
    if cur_heredoc is not None:
        err("%s: unclosed here-string @%s" % (fname, cur_heredoc))
    return "".join(out), ["".join(h) for h in heredocs]


def check_balance(code, fname):
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for ch in code:
        if ch == "\n":
            line += 1
        elif ch in "([{":
            stack.append((ch, line))
        elif ch in ")]}":
            if not stack or stack[-1][0] != pairs[ch]:
                err("%s: unbalanced '%s' at line %d" % (fname, ch, line))
                return
            stack.pop()
    if stack:
        err("%s: unclosed '%s' opened at line %d" % (fname, stack[-1][0], stack[-1][1]))


def check_ps7(code, fname):
    for pat, label in [(r"\?\?", "null-coalescing ??"), (r"\?\.", "null-conditional ?."),
                       (r"-Parallel\b", "ForEach-Object -Parallel"), (r"\?\?=", "??="),
                       (r"\$IsWindows|\$IsMacOS|\$IsLinux", "$Is* automatic var")]:
        m = re.search(pat, code)
        if m:
            # ?? appears in benign contexts? In PS5 code it is a syntax error, so flag it.
            err("%s: PowerShell 7-only syntax (%s) - repo must stay 5.1-compatible" % (fname, label))


def check_xaml(blocks, fname):
    for b in blocks:
        s = b.strip()
        if not s.startswith("<"):
            continue
        try:
            ET.fromstring(s)
        except ET.ParseError as e:
            err("%s: XAML parse error: %s" % (fname, e))


def main():
    ps_files = []
    for dp, _, fns in os.walk(ROOT):
        if ".git" in dp:
            continue
        for f in fns:
            if f.endswith(".ps1"):
                ps_files.append(os.path.join(dp, f))
    if not ps_files:
        err("no .ps1 files found")
    for path in sorted(ps_files):
        fname = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8-sig") as fh:
            src = fh.read()
        code, heredocs = strip_ps(src, fname)
        check_balance(code, fname)
        check_ps7(code, fname)
        check_xaml(heredocs, fname)
        base = os.path.basename(path)
        if base.startswith("Macify") and base not in ("MacifyLib.ps1", "MacifyTweaks.ps1", "Macify.Tests.ps1"):
            if "Confirm-MacifySTA" not in src:
                err("%s: UI script missing Confirm-MacifySTA guard" % fname)
            if "Test-MacifySingleInstance" not in src:
                err("%s: UI script missing single-instance guard" % fname)

    # JSON configs
    for jf in ("config/theme.json", "config/dock-items.json"):
        p = os.path.join(ROOT, jf)
        try:
            with open(p, encoding="utf-8") as fh:
                json.load(fh)
        except Exception as e:
            err("%s: invalid JSON: %s" % (jf, e))

    # Referenced files exist
    must_exist = [
        "src/MacifyLib.ps1", "src/MacifyBar.ps1", "src/MacifyDock.ps1",
        "src/MacifySpotlight.ps1", "src/MacifyControlCenter.ps1",
        "tools/MacifyTweaks.ps1", "tools/Install-Extras.ps1",
        "Install.ps1", "Uninstall.ps1", "Start-Macify.ps1", "Stop-Macify.ps1",
        "Setup.bat", "config/theme.json", "config/dock-items.json",
        "assets/wallpapers/sonoma-dark.jpg", "assets/macify.ico",
        "assets/sounds/chime.wav", "assets/sounds/pop.wav", "assets/sounds/glass.wav",
        "tools/Build-Release.ps1", ".github/workflows/release.yml",
        "config/engines.json", "tools/Set-MacifyEngine.ps1",
        "tools/Install-MyDockFinder.ps1", "tools/Install-RainmeterWidgets.ps1",
        "extras/rainmeter/Macify/Clock/Clock.ini", "extras/rainmeter/Macify/Stats/Stats.ini",
        "docs/ENGINES.md",
    ]
    for f in must_exist:
        if not os.path.exists(os.path.join(ROOT, f)):
            err("missing required file: %s" % f)

    with open(os.path.join(ROOT, "Setup.bat"), encoding="utf-8") as fh:
        if "Install.ps1" not in fh.read():
            err("Setup.bat does not reference Install.ps1")

    print("----")
    print("checked %d PowerShell files, %d errors, %d warnings" % (len(ps_files), len(ERRORS), len(WARNINGS)))
    return 1 if ERRORS else 0


if __name__ == "__main__":
    sys.exit(main())

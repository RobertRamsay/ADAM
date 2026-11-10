# Checks that changes since a git commit only touched comments (and blank lines / indent
# of comment lines): the code itself must be the same.
#   python tools/check_comments_only.py [commit]        (default HEAD)
# GML: // and /* */ comments are dropped (not inside "strings"), then whitespace is
# squeezed. 68000 (.s): ; comments and * comment lines are dropped. Python: the AST is
# compared with docstrings removed (# comments never reach the AST).
# Prints each file whose code changed and exits 1, or 'code unchanged' and exits 0.
import ast, re, subprocess, sys, os

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# GML with its comments dropped (strings kept whole) and the whitespace squeezed
def strip_gml(s):
    out = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '"':                                  # a string: copy it whole
            j = i + 1
            while j < n and s[j] != '"':
                if s[j] == '\\':
                    j += 1
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
        elif s.startswith('//', i):                   # a line comment
            while i < n and s[i] != '\n':
                i += 1
        elif s.startswith('/*', i):                   # a block comment
            j = s.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return ' '.join(''.join(out).split())

# 68000 source with ; comments and * comment lines dropped, one line per instruction
def strip_asm(s):
    lines = []
    for line in s.split('\n'):
        if line.lstrip().startswith('*') and not line.startswith(' '):
            continue
        out = []
        q = None
        for ch in line:
            if q:
                out.append(ch)
                if ch == q:
                    q = None
            elif ch in '"\'':
                q = ch
                out.append(ch)
            elif ch == ';':
                break
            else:
                out.append(ch)
        t = ' '.join(''.join(out).split())
        if t:
            lines.append(t)
    return '\n'.join(lines)

# the Python AST with the docstrings taken out
def strip_py(s):
    tree = ast.parse(s)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
            b = node.body
            if b and isinstance(b[0], ast.Expr) and isinstance(getattr(b[0], 'value', None), ast.Constant) and isinstance(b[0].value.value, str):
                node.body = b[1:] or [ast.Pass()]
    return ast.dump(tree)

# compares each changed .gml / .s / .py file with the base commit
def main():
    base = sys.argv[1] if len(sys.argv) > 1 else 'HEAD'
    names = subprocess.run(['git', 'diff', '--name-only', base, '--'], cwd=REPO, capture_output=True, text=True).stdout.split()
    bad = []
    for f in names:
        ext = os.path.splitext(f)[1].lower()
        if ext not in ('.gml', '.s', '.py'):
            continue
        p = os.path.join(REPO, f)
        if not os.path.exists(p):
            bad.append(f + ' (deleted)')
            continue
        old = subprocess.run(['git', 'show', base + ':' + f], cwd=REPO, capture_output=True).stdout.decode('utf-8', 'replace')
        new = open(p, encoding='utf-8', errors='replace').read()
        fn = {'.gml': strip_gml, '.s': strip_asm, '.py': strip_py}[ext]
        try:
            same = fn(old) == fn(new)
        except SyntaxError as e:
            same = False
            f += ' (syntax error: %s)' % e
        if not same:
            bad.append(f)
    for f in bad:
        print('CODE CHANGED:', f)
    if not bad:
        print('code unchanged (%d files checked)' % len([f for f in names if os.path.splitext(f)[1].lower() in ('.gml', '.s', '.py')]))
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()

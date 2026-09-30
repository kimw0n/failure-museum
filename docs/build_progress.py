#!/usr/bin/env python3
"""진행과정 문서 빌드.

  python3 docs/build_progress.py          # 커밋 기록 갱신 + docs/진행과정.docx 생성
  python3 docs/build_progress.py --check  # 문서가 코드보다 오래됐으면 종료 코드 1 (pre-push 훅용)

필요: git, pandoc (Word 변환)
"""
import os, re, shutil, subprocess, sys, tempfile, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, 'docs')
MD = os.path.join(DOCS, 'PROGRESS.md')
DOCX = os.path.join(DOCS, '진행과정.docx')
FONT = 'Malgun Gothic'   # Windows 기본 한글 글꼴. 없는 환경에서는 Word가 비슷한 한글 글꼴로 대체


def git(*args):
    return subprocess.run(['git', '-C', ROOT, *args], capture_output=True, text=True, check=True).stdout.strip()


def check():
    """코드(docs 밖) 마지막 커밋이 진행과정 문서 마지막 커밋보다 새로우면 1."""
    code_ts = git('log', '-1', '--format=%ct', '--', '.', ':(exclude)docs')
    doc_ts = git('log', '-1', '--format=%ct', '--', 'docs/PROGRESS.md')
    docx_ts = git('log', '-1', '--format=%ct', '--', 'docs/진행과정.docx')
    if not doc_ts or not docx_ts:
        print('진행과정 문서가 아직 커밋되지 않았습니다.'); return 1
    if int(code_ts or 0) > int(doc_ts):
        print('코드가 진행과정 문서(docs/PROGRESS.md)보다 새롭습니다.'); return 1
    if int(doc_ts) > int(docx_ts):
        print('docs/PROGRESS.md가 바뀌었는데 진행과정.docx가 다시 만들어지지 않았습니다.'); return 1
    return 0


def update_commits(md):
    log = git('log', '--date=format:%Y-%m-%d %H:%M', '--format=%ad\t%h\t%s')
    rows = ['| 날짜 | 커밋 | 내용 |', '| -------------------- | --------- | ------------------------------------------------------------- |']
    for line in log.splitlines():
        date, h, subj = line.split('\t', 2)
        rows.append(f'| {date} | `{h}` | {subj.replace("|", "／")} |')
    block = '<!-- COMMITS:START -->\n' + '\n'.join(rows) + '\n<!-- COMMITS:END -->'
    return re.sub(r'<!-- COMMITS:START -->.*?<!-- COMMITS:END -->', lambda _: block, md, flags=re.S)


def reference_docx(path):
    """pandoc 기본 서식에 한글 글꼴을 지정한 reference.docx."""
    subprocess.run(['pandoc', '-o', path, '--print-default-data-file', 'reference.docx'], check=True)
    tmp = path + '.tmp'
    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == 'word/styles.xml':
                xml = data.decode('utf-8')
                xml = re.sub(r'<w:rFonts [^>]*/>', f'<w:rFonts w:ascii="{FONT}" w:hAnsi="{FONT}" w:eastAsia="{FONT}" w:cs="{FONT}"/>', xml)
                data = xml.encode('utf-8')
            zout.writestr(item, data)
    os.replace(tmp, path)


def build_docx(md):
    if not shutil.which('pandoc'):
        sys.exit('pandoc이 없어 Word 파일을 만들 수 없습니다. (brew install pandoc)')
    # Word용: 이미지 폭 지정 (모바일 세로 화면은 좁게), 갱신 방법 절은 GitHub용이라 그대로 둠
    body = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)',
                  lambda m: f'![{m.group(1)}]({m.group(2)}){{width={"2.2in" if "mobile" in m.group(2) else "6.2in"}}}', md)
    with tempfile.TemporaryDirectory() as tmp:
        src, ref = os.path.join(tmp, 'progress.md'), os.path.join(tmp, 'reference.docx')
        open(src, 'w', encoding='utf-8').write(body)
        reference_docx(ref)
        subprocess.run(['pandoc', src, '-f', 'markdown-smart', '-o', DOCX, '--reference-doc', ref, '--resource-path', DOCS,
                        '--shift-heading-level-by=-1', '-M', 'lang=ko-KR'], check=True)


def main():
    if '--check' in sys.argv:
        sys.exit(check())
    md = open(MD, encoding='utf-8').read()
    md = update_commits(md)
    open(MD, 'w', encoding='utf-8').write(md)
    build_docx(md)
    print('갱신:', os.path.relpath(MD, ROOT), '→', os.path.relpath(DOCX, ROOT))


if __name__ == '__main__':
    main()

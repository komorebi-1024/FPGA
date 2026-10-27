"""Make the tutorial title use an explicit Chinese font in WPS."""
from pathlib import Path
import hashlib
import re
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
docx = root / "00_Docs" / "随行视听西湖工程上手与复现教程.docx"
backup = root.parent.parent / "Documents" / "ChatGPT" / "嵌入式大赛" / "research" / "wps_font_fix_backup.docx"
backup.parent.mkdir(parents=True, exist_ok=True)
if not backup.exists():
    shutil.copy2(docx, backup)

font = '<w:rFonts w:ascii="Microsoft YaHei" w:hAnsi="Microsoft YaHei" w:eastAsia="Microsoft YaHei" w:cs="Microsoft YaHei"/>'
tmp = docx.with_suffix(".wpsfix.tmp.docx")
with zipfile.ZipFile(docx, "r") as src, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as dst:
    for entry in src.infolist():
        data = src.read(entry.filename)
        if entry.filename == "word/styles.xml":
            text = data.decode("utf-8")
            for style_id in ("Title", "TitleChar"):
                match = re.search(
                    r'(<w:style\b[^>]*w:styleId="' + style_id + r'".*?</w:style>)',
                    text,
                    flags=re.DOTALL,
                )
                if not match:
                    raise RuntimeError("Missing style: " + style_id)
                block = match.group(1)
                block, count = re.subn(r"<w:rFonts\b[^>]*/>", font, block, count=1)
                if count != 1:
                    raise RuntimeError("Missing font declaration: " + style_id)
                text = text[: match.start(1)] + block + text[match.end(1) :]
            data = text.encode("utf-8")
        elif entry.filename == "word/document.xml":
            text = data.decode("utf-8")
            marker = '<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r>'
            replacement = marker + "<w:rPr>" + font + "</w:rPr>"
            if marker not in text:
                raise RuntimeError("Title paragraph marker not found")
            if replacement not in text:
                text = text.replace(marker, replacement, 1)
            data = text.encode("utf-8")
        dst.writestr(entry, data)

with zipfile.ZipFile(tmp, "r") as check:
    if check.testzip() is not None:
        raise RuntimeError("DOCX archive check failed")
tmp.replace(docx)
report = root / "06_Delivery" / "wps_font_fix.json"
report.write_text(
    '{\n'
    '  "result": "PASS",\n'
    '  "font": "Microsoft YaHei",\n'
    '  "document": "00_Docs/随行视听西湖工程上手与复现教程.docx",\n'
    '  "backup": "research/wps_font_fix_backup.docx",\n'
    '  "sha256": "' + hashlib.sha256(docx.read_bytes()).hexdigest() + '"\n'
    '}\n',
    encoding="utf-8",
)
print("PASS: explicit Microsoft YaHei applied to Title, TitleChar and title run")

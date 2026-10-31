#!/usr/bin/env python3
"""S-08 の検索のエリアで選ぶ市区町村の一覧（Dokogacha/Resources/Municipalities.tsv）を作る。

総務省の「都道府県コード及び市区町村コード」の Excel（https://www.soumu.go.jp/denshijiti/code.html の「Excelファイル」）を
人が落として、そのパスを渡す。Python の標準ライブラリだけで読む。

    python3 -I Tools/make_municipalities.py <落とした .xlsx> > Dokogacha/Resources/Municipalities.tsv

- 使うのは「現在の団体」のシート（団体コード・市区町村名・市区町村名のカナ）。都道府県の行（市区町村名が空）は外す
- 政令指定都市は市全体を 1 行にする（区は別のシートにあり、使わない）。東京の 23 区は特別区なので 1 区ずつ入っている
- 北方領土の 6 村は外す（MapKit の場所検索で、施設を探せないため）
- カナ（半角カタカナ）は、ひらがなにする（S-08 のシートで、よみで絞り込むため）
- 同じ都道府県に同じ名前の市区町村があれば止める（シートでは名前で見分けるため）

出典の書き方（README・仕様・ライセンスの画面）は、公共データ利用規約（第1.0版）に従う。
"""

import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RELATIONSHIP_ID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"

# 北方領土の 6 村（色丹村・泊村・留夜別村・留別村・紗那村・蘂取村）の団体コード
EXCLUDED_CODES = {"016951", "016969", "016977", "016985", "016993", "017001"}

SOURCE_URL = "https://www.soumu.go.jp/denshijiti/code.html"
LICENSE_URL = "https://www.digital.go.jp/resources/open_data/public_data_license_v1.0"


def shared_strings(archive):
    """共有文字列。ふりがな（rPh）は外し、本文（t と r/t）だけをつなぐ"""
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    strings = []
    for item in root.findall(MAIN + "si"):
        parts = []
        for child in item:
            if child.tag == MAIN + "t":
                parts.append(child.text or "")
            elif child.tag == MAIN + "r":
                parts.extend(t.text or "" for t in child.findall(MAIN + "t"))
        strings.append("".join(parts))
    return strings


def sheets(archive):
    """シートの名前と、行（列の文字 → 値）の一覧"""
    strings = shared_strings(archive)
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    relations = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {relation.get("Id"): relation.get("Target") for relation in relations}
    for sheet in workbook.find(MAIN + "sheets"):
        target = targets[sheet.get(RELATIONSHIP_ID)].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        rows = []
        for row in ET.fromstring(archive.read(target)).iter(MAIN + "row"):
            cells = {}
            for cell in row.findall(MAIN + "c"):
                column = re.match(r"[A-Z]+", cell.get("r")).group(0)
                value = cell.find(MAIN + "v")
                if value is None:
                    continue
                cells[column] = strings[int(value.text)] if cell.get("t") == "s" else value.text
            rows.append(cells)
        yield sheet.get("name"), rows


def hiragana(katakana):
    """半角・全角のカタカナを、ひらがなにする（濁点・半濁点は合わせて 1 文字にする）"""
    text = unicodedata.normalize("NFKC", katakana).strip()
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def municipalities(path):
    """（団体コード・名前・よみ）の一覧（団体コードの順）と、シートの名前"""
    with zipfile.ZipFile(path) as archive:
        for name, rows in sheets(archive):
            if not name.endswith("現在の団体"):
                continue
            entries = []
            for cells in rows[1:]:
                code = (cells.get("A") or "").strip()
                city = (cells.get("C") or "").strip()
                if not city or code in EXCLUDED_CODES:
                    continue
                if not re.fullmatch(r"\d{6}", code):
                    sys.exit(f"団体コードの形が違う: {code!r}")
                entries.append((code, city, hiragana(cells.get("E") or "")))
            return entries, name
    sys.exit("「現在の団体」のシートが見つからない")


def check(entries):
    """よみが空・ひらがな以外、同じ都道府県に同じ名前があれば止める"""
    seen = set()
    for code, city, kana in entries:
        if not re.fullmatch(r"[ぁ-ゖー]+", kana):
            sys.exit(f"よみがひらがなでない: {code} {city} {kana!r}")
        key = (code[:2], city)
        if key in seen:
            sys.exit(f"同じ都道府県に同じ名前がある: {code} {city}")
        seen.add(key)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    entries, sheet = municipalities(sys.argv[1])
    check(entries)
    print("# S-08 の検索のエリアで選ぶ市区町村（Tools/make_municipalities.py で作る。手で直さない）")
    print(f"# 出典: 「都道府県コード及び市区町村コード」（総務省）（{SOURCE_URL}）を加工して作成（{sheet}）")
    print(f"# 利用条件: 公共データ利用規約（第1.0版）（PDL1.0）{LICENSE_URL}")
    print("# 加工: 都道府県の行と北方領土の 6 村を除き、よみをひらがなにした")
    print("code\tname\tkana")
    for code, city, kana in entries:
        print(f"{code}\t{city}\t{kana}")


if __name__ == "__main__":
    main()

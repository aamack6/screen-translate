"""Makes synthetic shopping-listing screenshots with known text, for checking OCR, translation and
shopping notes on a device or simulator. All listings are invented; no real listing, seller or
photo is used. Needs Pillow and a Japanese font (IPAGothic by default).

Usage: python3 TestSet/make_screenshots.py [--font PATH]
Writes ScreenTranslateTests/Fixtures/Screenshots/*.png and ground_truth.json, and
TestSet/review_sheet.csv (one row per line, for a Japanese–English reader to fill in).
"""
import argparse, csv, json, os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
# Inside the test target's folder, so the Swift OCR test can load them from its bundle.
OUT = os.path.join(HERE, '..', 'ScreenTranslateTests', 'Fixtures', 'Screenshots')
WIDTH, HEIGHT = 1179, 2556  # iPhone 15/16 Pro screenshot size

# Each listing: title, price, then description lines. "terms" are the phrases the shopping notes
# should explain; "unclear" are the essential questions the screen doesn't answer.
LISTINGS = [
    {
        'id': 'condition-shipping',
        'lines': ['ポケモンカード リーフィアex SAR', '¥12,800', '商品の状態：目立った傷や汚れなし',
                  '配送料の負担：送料込み（出品者負担）', 'スリーブから出してすぐ保管しました。', '他サイトでも出品中のため早い者勝ちです。'],
        'terms': ['目立った傷や汚れなし', '送料込み', '他サイトでも出品中'],
        'unclear': ["what's included"],
    },
    {
        'id': 'one-from-photo',
        'lines': ['アクリルスタンド まとめ', '¥1,500', '写真の中からお好きな1点をお選びください。',
                  'コメントで番号をお知らせください。', '商品の状態：やや傷や汚れあり', '送料別・着払いでお願いします。'],
        'terms': ['写真の中から', 'やや傷や汚れあり', '送料別', '着払い'],
        'unclear': ["what's included"],
    },
    {
        'id': 'box-only',
        'lines': ['ゲーム機 空箱のみ', '¥800', '本体は付属しません。空箱のみの出品です。',
                  '箱に潰れと日焼けがあります。', 'ノークレーム・ノーリターンでお願いします。'],
        'terms': ['空箱のみ', '本体は付属しません', '潰れ', '日焼け', 'ノークレーム・ノーリターン'],
        'unclear': ['shipping and payment'],
    },
    {
        'id': 'preorder-stock-photo',
        'lines': ['【予約】フィギュア 1/7スケール', '¥24,000', '発売日以降の発送となります。',
                  '画像はイメージです。実物とは異なる場合があります。', '新品・未開封', '代引き不可'],
        'terms': ['予約', '発売日', 'イメージ', '未開封', '代引き不可'],
        'unclear': [],
    },
    {
        'id': 'opened-missing',
        'lines': ['カメラ レンズ', '¥18,500', '開封済みですが未使用です。', '付属品欠品：レンズキャップ',
                  '動作未確認のためジャンク扱いでお願いします。', '送料込み'],
        'terms': ['開封済み', '未使用', '欠品', '動作未確認', 'ジャンク'],
        'unclear': [],
    },
    {
        'id': 'authenticity',
        'lines': ['ブランド 財布', '¥9,800', '正規品です。', '鑑定はしていないため真贋不明とさせてください。',
                  '展示品のため小傷あり', '送料無料'],
        'terms': ['正規品', '真贋不明', '展示品', '傷あり', '送料無料'],
        'unclear': ["what's included"],
    },
    {
        'id': 'negation',
        'lines': ['トレカ 10枚セット', '¥3,000', '傷なし・折れなし', 'ジャンクではありません。',
                  '10点セットでの販売です。バラ売り不可', '送料込み'],
        'terms': ['傷なし', '折れなし', 'ジャンクではありません', '点セット', 'バラ売り'],
        'unclear': [],
    },
    {
        'id': 'mixed-english',
        'lines': ['PSA10 鑑定品 Japanese Card', '¥45,000', 'Condition: 新品、未使用',
                  'Ships from Japan 送料別', 'No returns 返品不可'],
        'terms': ['鑑定品', '新品、未使用', '送料別', '返品不可'],
        'unclear': ["what's included"],
    },
]

# Variants that stress OCR: (suffix, text size in px, final scale, vertical)
VARIANTS = [
    ('', 46, 1.0, False),
    ('-small', 26, 1.0, False),
    ('-lowres', 46, 0.35, False),
]


def draw_listing(listing, font_path, size, vertical=False):
    image = Image.new('RGB', (WIDTH, HEIGHT), 'white')
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(font_path, size)
    bold = ImageFont.truetype(font_path, int(size * 1.25))
    # A gray block stands in for the product photo, as on Mercari and Yahoo listings.
    draw.rectangle([0, 160, WIDTH, 1100], fill='#d9d9d9')
    draw.text((60, 600), 'PHOTO', fill='#999999', font=bold)
    if vertical:
        # Columns read top to bottom, right to left, as in printed Japanese.
        x = WIDTH - 120
        for line in listing['lines']:
            y = 1160
            for char in line:
                draw.text((x, y), char, fill='black', font=font)
                y += int(size * 1.15)
                if y > HEIGHT - 120:
                    break
            x -= int(size * 1.6)
        return image
    y = 1160
    for index, line in enumerate(listing['lines']):
        draw.text((60, y), line, fill='#d33' if index == 1 else 'black', font=bold if index < 2 else font)
        y += int(size * 2.0)
    draw.rectangle([60, HEIGHT - 260, WIDTH - 60, HEIGHT - 120], fill='#e83f3f')
    draw.text((WIDTH // 2 - size * 3, HEIGHT - 220), '購入手続きへ', fill='white', font=bold)
    return image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--font', default='/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf')
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    truth, rows = [], []
    for listing in LISTINGS:
        variants = VARIANTS + ([('-vertical', 46, 1.0, True)] if listing['id'] in ('condition-shipping', 'box-only') else [])
        for suffix, size, scale, vertical in variants:
            image = draw_listing(listing, args.font, size, vertical)
            if scale != 1.0:
                image = image.resize((int(WIDTH * scale), int(HEIGHT * scale)), Image.LANCZOS)
            name = f"{listing['id']}{suffix}.png"
            image.save(os.path.join(OUT, name), optimize=True)
            lines = listing['lines'] + ['購入手続きへ'] * (not vertical)
            truth.append({'file': name, 'listing': listing['id'], 'variant': suffix.strip('-') or 'normal',
                          'lines': lines, 'terms': listing['terms'], 'unclear': listing['unclear']})
        for line in listing['lines']:
            rows.append({'listing': listing['id'], 'japanese': line, 'app_translation': '', 'reader_translation': '',
                         'translation_ok (y/n)': '', 'app_notes': '', 'notes_ok (y/n)': '', 'misleading? (describe)': ''})
    with open(os.path.join(OUT, 'ground_truth.json'), 'w', encoding='utf-8') as f:
        json.dump(truth, f, ensure_ascii=False, indent=1)
    with open(os.path.join(HERE, 'review_sheet.csv'), 'w', encoding='utf-8-sig', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f'{len(truth)} screenshots, {len(rows)} review rows')


if __name__ == '__main__':
    main()

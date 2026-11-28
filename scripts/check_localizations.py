#!/usr/bin/env python3
"""Validate translated copy and the localization resources shipped in a built app."""
import argparse
from collections import Counter
import json
from pathlib import Path
import plistlib
import re
from xml.parsers.expat import ExpatError

import names  # architecture/names.json

LANGUAGES = ('en', 'it', 'fr', 'de', 'es', 'pt-BR', 'zh-Hans')
BUNDLE = names.RESOURCE_BUNDLE
PLACEHOLDER = re.compile(r'%(?:(\d+)\$)?(lld|ld|d|@|(?:\.\d+)?f)')
# SF Symbol names are identifiers: translated, they name no symbol and the icon disappears.
TRANSLATED_SYMBOL = re.compile(r'\b(?:systemImage|systemName|systemSymbolName)\s*:\s*L10n\.')
# French speaks to the player with « tu », in the app as on the site, Windows and phones.
FRENCH_FORMAL = re.compile(r'\b(?:vous|votre|vos|vôtres?|faites|dites|êtes|[^\W\d_]+ez)\b', re.IGNORECASE)
# Words the pattern catches that address nobody. Add one only for such a word.
FRENCH_FORMAL_EXCEPTIONS = {'assez', 'chez'}


def placeholders(text):
    matches = PLACEHOLDER.findall(text.replace('%%', ''))
    return Counter((int(position) if position else index + 1, kind) for index, (position, kind) in enumerate(matches))


def formal_french(text):
    return [word for word in FRENCH_FORMAL.findall(text) if word.lower() not in FRENCH_FORMAL_EXCEPTIONS]


def check_catalog(path):
    errors = []
    try:
        catalog = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        return [f'Cannot read catalog: {error}']
    if catalog.get('sourceLanguage') != 'en':
        errors.append('Catalog source language must be en')
    for key, item in catalog.get('strings', {}).items():
        for language in LANGUAGES:
            entry = item.get('localizations', {}).get(language)
            if entry is None:
                errors.append(f'{language}: missing translation for {key!r}')
                continue
            variants = entry.get('variations', {}).get('plural')
            units = [item.get('stringUnit', {}) for item in variants.values()] if variants else [entry.get('stringUnit', {})]
            if variants and not {'one', 'other'}.issubset(variants):
                errors.append(f'{language}: incomplete plurals for {key!r}')
            for unit in units:
                value = unit.get('value', '')
                if not value.strip() or unit.get('state') != 'translated':
                    errors.append(f'{language}: unfinished translation for {key!r}')
                if placeholders(value) != placeholders(key):
                    errors.append(f'{language}: placeholder mismatch for {key!r}')
                if language == 'fr' and formal_french(value):
                    errors.append(f'fr: use « tu », not {", ".join(formal_french(value))}, for {key!r}')
    return errors


def check_achievements(root):
    errors = []
    for path in sorted(root.rglob('achievements-*.json')):
        for item in json.loads(path.read_text(encoding='utf-8'))['achievements']:
            for field in ('title', 'description'):
                words = formal_french(item[field]['fr'])
                if words:
                    errors.append(f'{path.name}: fr: use « tu », not {", ".join(words)}, for {item["id"]} {field}')
    return errors


def check_sources(root):
    errors = []
    for path in sorted(root.rglob('*.swift')):
        for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            if TRANSLATED_SYMBOL.search(line):
                errors.append(f'{path.relative_to(root)}:{number}: symbol name passed through L10n')
    return errors


def check_app(app, catalog):
    """The app declares every language and carries the catalogue it was built with, as written: L10n reads it."""
    errors = []
    try:
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException, ExpatError, UnicodeError):
        return ['App Info.plist missing or invalid']
    if not set(LANGUAGES).issubset(info.get('CFBundleLocalizations', [])):
        errors.append('App Info.plist does not declare every interface language')
    shipped = app / 'Contents/Resources' / BUNDLE / 'Contents/Resources/Localizable.xcstrings'
    if not shipped.is_file():
        return errors + ['String catalogue missing from the app bundle']
    if shipped.read_bytes() != catalog.read_bytes():
        errors.append('The app bundle carries another string catalogue than its source')
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=Path(__file__).resolve().parents[1] / 'core/OortLibrary/Resources/Localizable.xcstrings')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--sources', type=Path, action='append',
                        help='a folder of Swift sources; default: every module of architecture/names.json')
    args = parser.parse_args()
    sources = args.sources or [names.ROOT / module['path'] for module in names.MODULES.values()]
    errors = check_catalog(args.catalog)
    for folder in sources:
        errors += check_sources(folder) + check_achievements(folder)
    if args.app:
        errors += check_app(args.app, args.catalog)
    if errors:
        for error in errors:
            print(error)
        return 1
    print(f'Localization checks passed ({len(LANGUAGES)} languages, placeholders, plurals, symbol names and French « tu »).')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

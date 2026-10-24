#!/usr/bin/env python3
"""Validate L(...) source keys and numbered interpolation placeholders without dependencies."""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGUAGES = {"en", "fr", "es", "ru", "ar"}


def read_string(source, start):
    index = start + 1
    key = ""
    arguments = 0
    while index < len(source):
        if source[index] == '"':
            return index + 1, key
        if source.startswith('\\(', index):
            index += 2
            depth = 1
            while depth:
                if source[index] == '"':
                    index, _ = read_string(source, index)
                    continue
                if source[index] == '(':
                    depth += 1
                if source[index] == ')':
                    depth -= 1
                index += 1
            key += '{' + str(arguments) + '}'
            arguments += 1
        elif source[index] == '\\':
            escaped = source[index:index + 2]
            key += {'\\n': '\n', '\\t': '\t', '\\"': '"', '\\\\': '\\'}.get(escaped, escaped)
            index += 2
        else:
            key += source[index]
            index += 1
    raise ValueError('Unterminated localized string')


def main():
    table = json.loads((ROOT / 'Resources/Translations.json').read_text())
    required = set()
    for path in ROOT.glob('*.swift'):
        if path.name.endswith('Tests.swift'):
            continue
        source = path.read_text()
        for match in re.finditer(r'\bL\(\s*(")', source):
            _, key = read_string(source, match.start(1))
            required.add(key)
    missing = required - table.keys()
    assert not missing, f'Missing translation keys: {sorted(missing)}'
    for key, row in table.items():
        assert set(row) == LANGUAGES, f'Wrong language set: {key}'
        tokens = sorted(re.findall(r'\{\d+\}', key))
        for language, text in row.items():
            assert text and sorted(re.findall(r'\{\d+\}', text)) == tokens, (key, language)
    print(f'Validated {len(required)} source keys and {len(table)} complete translation entries.')


if __name__ == '__main__':
    main()

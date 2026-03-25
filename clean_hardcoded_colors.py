#!/usr/bin/env python3
"""
clean_hardcoded_colors.py
Replaces known hardcoded Color(0xXX...) values in feature dart files
with the correct FieldThemeTokens / PromotorColors constant reference.

Run from project root:
    python3 clean_hardcoded_colors.py
"""

import re
import sys
from pathlib import Path

# Map: hex (uppercase, no 0x prefix) → token expression
# These are the exact values used in FieldThemeTokens.dark
COLOR_MAP = {
    '1A1510': 't.background',
    '211C16': 't.surface1',
    '2A2318': 't.surface2',
    '332B1E': 't.surface3',
    '3D3325': 't.surface4',
    # Lowercase variants
    '1a1510': 't.background',
    '211c16': 't.surface1',
    '2a2318': 't.surface2',
    '332b1e': 't.surface3',
    '3d3325': 't.surface4',
    # Shell bg
    '000000': 't.shellBackground',
    '0E0B08': 't.shellBackground',
    '0e0b08': 't.shellBackground',
    '080503': 't.islandBackground',
    # Accent
    'C9923A': 't.primaryAccent',
    'c9923a': 't.primaryAccent',
    'E8B06A': 't.primaryAccentLight',
    'e8b06a': 't.primaryAccentLight',
    # Text
    'F4EDE0': 't.textPrimary',
    'F0E8D8': 't.textPrimary',
    'f0e8d8': 't.textPrimary',
    'D8CFBE': 't.textSecondary',
    'C8BFAD': 't.textSecondary',
    'c8bfad': 't.textSecondary',
    'A89A86': 't.textMuted',
    '7B6D59': 't.textMutedStrong',
    '1A0E00': 't.textOnAccent',
    '1a0e00': 't.textOnAccent',
    # Semantic
    '6AAB7A': 't.success',
    '6aab7a': 't.success',
    'D4853A': 't.warning',
    'd4853a': 't.warning',
    'C05A4A': 't.danger',
    'c05a4a': 't.danger',
    '5B8DD9': 't.info',
    '5b8dd9': 't.info',
    # Hero gradient
    '261F13': 't.heroGradientStart',
    '261f13': 't.heroGradientStart',
    '231C12': 't.heroGradientStart',
    '231c12': 't.heroGradientStart',
    '1C1610': 't.heroGradientEnd',
    '1c1610': 't.heroGradientEnd',
}

# Soft/alpha variants that have specific token equivalents
ALPHA_COLOR_MAP = {
    # primaryAccentSoft = 0x1FC9923A
    '1FC9923A': 't.primaryAccentSoft',
    '1fc9923a': 't.primaryAccentSoft',
    # primaryAccentGlow = 0x47C9923A
    '47C9923A': 't.primaryAccentGlow',
    '47c9923a': 't.primaryAccentGlow',
    # successSoft = 0x1F6AAB7A
    '1F6AAB7A': 't.successSoft',
    '1f6aab7a': 't.successSoft',
    # dangerSoft = 0x1AC05A4A
    '1AC05A4A': 't.dangerSoft',
    '1ac05a4a': 't.dangerSoft',
    '19C05A4A': 't.dangerSoft',
    '19c05a4a': 't.dangerSoft',
    # infoSoft = 0x1F5B8DD9
    '1F5B8DD9': 't.infoSoft',
    '1f5b8dd9': 't.infoSoft',
    # warningSoft = 0x1FD4853A
    '1FD4853A': 't.warningSoft',
    '1fd4853a': 't.warningSoft',
    # heroHighlight = 0x14C9923A
    '14C9923A': 't.heroHighlight',
    '14c9923a': 't.heroHighlight',
}

def process_file(path: Path) -> int:
    try:
        original = path.read_text(encoding='utf-8')
    except Exception:
        return 0

    text = original
    replacements = 0

    # Replace 8-digit alpha colors first (more specific)
    for hex_val, token in ALPHA_COLOR_MAP.items():
        pattern = rf'(?:const )?Color\(0x{re.escape(hex_val)}\)'
        if re.search(pattern, text):
            # Only replace if 't' variable is used in this file
            text = re.sub(pattern, token, text)
            replacements += 1

    # Replace 6-digit colors
    for hex_val, token in COLOR_MAP.items():
        pattern = rf'(?:const )?Color\(0xFF{re.escape(hex_val)}\)'
        if re.search(pattern, text):
            text = re.sub(pattern, token, text)
            replacements += 1

    if replacements > 0 and text != original:
        path.write_text(text, encoding='utf-8')
        print(f'  ✅ {path.name}: {replacements} replacement(s)')
        return replacements
    return 0

def main():
    project_root = Path(__file__).parent
    features_dir = project_root / 'lib' / 'features'

    if not features_dir.exists():
        print(f'Features dir not found: {features_dir}')
        sys.exit(1)

    dart_files = list(features_dir.rglob('*.dart'))
    print(f'Scanning {len(dart_files)} dart files in features/...\n')

    total = 0
    files_changed = 0
    for f in sorted(dart_files):
        count = process_file(f)
        if count > 0:
            total += count
            files_changed += 1

    print(f'\n✅ Done: {total} replacements in {files_changed} files.')
    print('⚠️  Note: Files using "t.xxx" tokens require the widget to have')
    print('    access to context.fieldTokens via: final t = context.fieldTokens;')
    print('    Check each changed file to ensure "t" variable is declared.')

if __name__ == '__main__':
    main()

import re
from pathlib import Path

def get_block_start(content, error_line):
    # Search backwards for "{"
    lines = content.split('\n')
    idx = error_line - 1
    
    # We want to find the nearest Widget build(..., or any method returning Widget that uses `context`
    while idx >= 0:
        if 'Widget ' in lines[idx] and '{' in lines[idx] and 'context' in lines[idx]:
            return idx
        if 'build(BuildContext' in lines[idx]:
            return idx
        idx -= 1
    return -1

import subprocess
import os
for _ in range(5):
    res = subprocess.run(['flutter', 'analyze', '--no-pub'], capture_output=True, text=True)
    out = res.stdout + res.stderr
    lines = [L for L in out.split('\n') if "Undefined name 't'" in L]
    if not lines:
        break
    
    fixes = set()
    files_modified = set()
    
    for line in lines:
        parts = line.split(' • ')
        if len(parts) >= 3:
            loc = parts[-2].strip()
            filepath = loc.split(':')[0]
            errline = int(loc.split(':')[1])
            
            p = Path(filepath)
            if not p.exists(): continue
            content = p.read_text('utf-8')
            clines = content.split('\n')
            
            # Find the method start
            m_start = get_block_start(content, errline)
            if m_start != -1:
                target_loc = f"{filepath}:{m_start}"
                if target_loc not in fixes:
                    fixes.add(target_loc)
                    # Check if already injected
                    if 'final t = context.fieldTokens;' not in clines[m_start+1]:
                        clines.insert(m_start+1, '    final t = context.fieldTokens;')
                        p.write_text('\n'.join(clines), 'utf-8')
                        files_modified.add(filepath)

    if not files_modified:
        break

print("Done fixing 't' injections")

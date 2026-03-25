import os
import re

def fix_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # Fix double commas
    content = content.replace('context,,', 'context,')
    
    # Fix }).toList(); immediately after showErrorDialog/showSuccessDialog/ErrorHandler
    # Pattern: Dialog(...); followed by whitespace and }).toList();
    pattern = re.compile(r'(showSuccessDialog|showErrorDialog|ErrorHandler\.showErrorDialog)\(.*?\);\s*\}\)\.toList\(\);', re.DOTALL)
    
    def replace_func(match):
        dialog_call = match.group(0).split(';')[0] + ';'
        return dialog_call + '\n    }'
    
    new_content = pattern.sub(replace_func, content)
    
    # Fix the specific broken pattern where the closing brace was missing
    # like: showErrorDialog(...); \n } \n }).toList();
    
    if content != new_content:
        with open(file_path, 'w') as f:
            f.write(new_content)
        return True
    return False

for root, dirs, files in os.walk('lib/features'):
    for file in files:
        if file.endswith('.dart'):
            if fix_file(os.path.join(root, file)):
                print(f"Fixed: {file}")

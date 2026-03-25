import os
import re

def fix_file(file_path):
    with open(file_path, 'r') as f:
        content = f.read()
    
    # 1. Fix double commas (not found by grep but user mentioned it)
    new_content = content.replace(',,', ',')
    
    # 2. Fix broken try-catch patterns caused by SnackBar to Dialog replacement
    # Look for showErrorDialog/showSuccessDialog/SuccessDialog.show/etc.
    # often followed by missing } and catch
    
    # Example:
    # if (mounted) {
    #   showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
    # final ...
    
    # This is hard to regex globally. Let's focus on the most common one:
    # showErrorDialog(...) immediately followed by some variable declaration
    # that belongs to the next method.
    
    # Actually, let's fix the missing catch or finally error.
    # Many files have "A try block must be followed by an 'on', 'catch', or 'finally' clause"
    
    # 3. Fix context,, (user specifically mentioned this)
    new_content = new_content.replace('context,,', 'context,')
    
    if content != new_content:
        with open(file_path, 'w') as f:
            f.write(new_content)
        return True
    return False

# For now, let's just do the double commas and see how many errors remain.
for root, dirs, files in os.walk('lib/features'):
    for file in files:
        if file.endswith('.dart'):
            fix_file(os.path.join(root, file))


import os
import re

def migrate_file(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    if 'showSnackBar' not in content:
        return False

    # More flexible regex
    # Matches: ScaffoldMessenger.of(...) optional ..hideCurrentSnackBar() .showSnackBar( SnackBar(...) );
    # Handles newlines and spaces everywhere
    pattern = re.compile(r'ScaffoldMessenger\s*\.\s*of\s*\(\s*(.*?)\s*\)\s*(?:\.\.\s*hideCurrentSnackBar\s*\(\s*\)\s*)?\.showSnackBar\s*\(\s*(?:const\s*)?SnackBar\s*\(\s*([\s\S]*?)\s*\)\s*\)\s*;', re.MULTILINE)

    def replace_snackbar(match):
        context = match.group(1).strip()
        snackbar_body = match.group(2).strip()

        # Extract message from Text(...)
        # Supports Text('...'), Text("..."), Text('''...'''), etc.
        text_match = re.search(r'content\s*:\s*(?:const\s*)?Text\s*\(\s*(.*?)\s*\)', snackbar_body, re.DOTALL)
        if not text_match:
            return match.group(0)
        
        message = text_match.group(1).strip()
        
        # Determine if it's success or error
        is_success = False
        success_keywords = ['Berhasil', 'Sukses', 'Terkirim', 'Selesai', 'Success', '✅']
        error_keywords = ['Gagal', 'Error', 'Exception', 'Maaf', 'Salah', 'Wajib', 'Belum', 'Tidak', '⚠️', '❌']
        
        # Check by backgroundColor first (higher priority)
        lower_body = snackbar_body.lower()
        if 'success' in lower_body or 'green' in lower_body:
            is_success = True
        elif 'danger' in lower_body or 'error' in lower_body or 'red' in lower_body:
            is_success = False
        else:
            # Check by keywords in message
            lower_message = message.lower()
            for kw in success_keywords:
                if kw.lower() in lower_message:
                    is_success = True
                    break
            
            # Double check for error keywords
            if is_success:
                for kw in error_keywords:
                    if kw.lower() in lower_message:
                        is_success = False
                        break

        if is_success:
            return f"showSuccessDialog({context}, title: 'Berhasil', message: {message});"
        else:
            return f"showErrorDialog({context}, title: 'Gagal', message: {message});"

    new_content = pattern.sub(replace_snackbar, content)

    # Handle the case where context is on multiple lines in ScaffoldMessenger.of
    if new_content == content:
        # Try another pattern for ScaffoldMessenger.of( \n context \n )
        pattern2 = re.compile(r'ScaffoldMessenger\s*\.\s*of\s*\(\s*([\s\S]*?)\s*\)\s*(?:\.\.\s*hideCurrentSnackBar\s*\(\s*\)\s*)?\.showSnackBar\s*\(\s*(?:const\s*)?SnackBar\s*\(\s*([\s\S]*?)\s*\)\s*\)\s*;', re.MULTILINE)
        new_content = pattern2.sub(replace_snackbar, content)

    if new_content != content:
        # Add import if not present
        import_line = "import 'package:vtrack/core/utils/success_dialog.dart';"
        if import_line not in new_content:
            # Insert after the last import
            import_pattern = re.compile(r'^(import .*?;)$', re.MULTILINE)
            imports = list(import_pattern.finditer(new_content))
            if imports:
                last_import_end = imports[-1].end()
                new_content = new_content[:last_import_end] + "\n" + import_line + new_content[last_import_end:]
            else:
                new_content = import_line + "\n" + new_content
        
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True
    
    return False

def main():
    features_dir = '/home/geger/Documents/project APK/project vivo apk/lib/features'
    modified_count = 0
    for root, dirs, files in os.walk(features_dir):
        for file in files:
            if file.endswith('.dart'):
                file_path = os.path.join(root, file)
                if migrate_file(file_path):
                    print(f"Modified: {file_path}")
                    modified_count += 1
    
    print(f"Total files modified: {modified_count}")

if __name__ == "__main__":
    main()

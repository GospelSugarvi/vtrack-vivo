
import re

content = """
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
      );
"""

pattern = re.compile(r'ScaffoldMessenger\s*\.\s*of\s*\(\s*(.*?)\s*\)\s*(?:\.\.\s*hideCurrentSnackBar\s*\(\s*\)\s*)?\.showSnackBar\s*\(\s*(?:const\s*)?SnackBar\s*\(\s*([\s\S]*?)\s*\)\s*\)\s*;', re.MULTILINE)

match = pattern.search(content)
if match:
    print("Match found!")
    print(f"Context: {match.group(1)}")
    print(f"Body: {match.group(2)}")
else:
    print("No match found.")

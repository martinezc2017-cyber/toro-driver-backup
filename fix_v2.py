import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# The file has \u005c\u0022 (backslash-quote) around test and e2e
old = 'metaString.contains(\'\\"test\\"\') ||\n        metaString.contains(\'\\"e2e\\"\')'
new = "metaString.contains('test:') ||\n        metaString.contains('e2e:')"

if old in content:
    content = content.replace(old, new)
    print("1. Fixed string check: \\\"test\\\" -> test:")
else:
    print("1. Pattern not found, trying alternative...")
    # Check what's actually there
    idx = content.find('metaString.contains')
    if idx >= 0:
        print(f"Found at {idx}:")
        print(repr(content[idx:idx+200]))

# Add original_metadata check after the meta is Map block
old2 = """      // Check if any value contains webhook-validation
      final metaStr = meta.values.join(' ').toLowerCase();
      if (metaStr.contains('webhook-validation') ||
          metaStr.contains('e2e') ||
          metaStr.contains('test')) {
        return true;
      }
    }

    // Also check as string"""

new2 = """      // Check if any value contains webhook-validation
      final metaStr = meta.values.join(' ').toLowerCase();
      if (metaStr.contains('webhook-validation') ||
          metaStr.contains('e2e') ||
          metaStr.contains('test')) {
        return true;
      }
      // Check nested 'original_metadata' (backfilled test transactions)
      if (meta.containsKey('original_metadata')) {
        final orig = meta['original_metadata'];
        if (orig is Map) {
          if (orig.containsKey('test') ||
              orig.containsKey('e2e') ||
              orig.containsKey('e2e_audit')) {
            return true;
          }
        }
      }
    }

    // Also check as string"""

if old2 in content:
    content = content.replace(old2, new2)
    print("2. Added original_metadata nested check")
else:
    print("2. Pattern for nested check not found")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("\nDone!")

import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Find the _isTestTransaction method 
old_method = """  bool _isTestTransaction(Map<String, dynamic> tx) {
    final meta = tx['metadata'];
    if (meta == null) return false;

    // metadata is a Map from JSONB column
    if (meta is Map) {
      if (meta.containsKey('test') ||
          meta.containsKey('e2e') ||
          meta.containsKey('e2e_audit')) {
        return true;
      }
      // Check if any value contains webhook-validation
      final metaStr = meta.values.join(' ').toLowerCase();
      if (metaStr.contains('webhook-validation') ||
          metaStr.contains('e2e') ||
          metaStr.contains('test')) {
        return true;
      }
    }

    // Also check as string (for edge cases)
    final metaString = meta.toString().toLowerCase();
    if (metaString.contains('webhook-validation') ||
        metaString.contains('"test"') ||
        metaString.contains('"e2e"')) {
      return true;
    }

    return false;
  }"""

new_method = """  bool _isTestTransaction(Map<String, dynamic> tx) {
    final meta = tx['metadata'];
    if (meta == null) return false;

    // metadata is a Map from JSONB column
    if (meta is Map) {
      if (meta.containsKey('test') ||
          meta.containsKey('e2e') ||
          meta.containsKey('e2e_audit')) {
        return true;
      }
      // Check if any value contains webhook-validation
      final metaStr = meta.values.join(' ').toLowerCase();
      if (metaStr.contains('webhook-validation') ||
          metaStr.contains('e2e') ||
          metaStr.contains('test')) {
        return true;
      }
    }

    // Also check as string (Dart Map.toString() produces {key: value} without quotes)
    final metaString = meta.toString().toLowerCase();
    if (metaString.contains('webhook-validation') ||
        metaString.contains('test:') ||
        metaString.contains('e2e:')) {
      return true;
    }

    return false;
  }"""

if old_method in content:
    content = content.replace(old_method, new_method)
    print("Fixed _isTestTransaction string check: '\"test\"' -> 'test:'")
else:
    print("ERROR: Could not find _isTestTransaction method")
    start = content.find('bool _isTestTransaction')
    if start >= 0:
        print(f"Found at position {start}")
        print(content[start:start+700])

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("\nDONE")

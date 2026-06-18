import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = '''  bool _isTestTransaction(Map<String, dynamic> tx) {
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
  }'''

new = '''  bool _isTestTransaction(Map<String, dynamic> tx) {
    final meta = tx['metadata'];
    if (meta == null) return false;

    // Check as string FIRST (catches all patterns including nested)
    final metaString = meta.toString().toLowerCase();
    if (metaString.contains('webhook-validation') ||
        metaString.contains('test:') ||
        metaString.contains('e2e:')) {
      return true;
    }

    // metadata is a Map from JSONB column
    if (meta is Map) {
      if (meta.containsKey('test') ||
          meta.containsKey('e2e') ||
          meta.containsKey('e2e_audit')) {
        return true;
      }
      // Check if any value contains test indicators
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

    return false;
  }'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('OK: _isTestTransaction UPDATED - now detects nested original_metadata and fixed string check')
else:
    print('ERROR: Could not find old method pattern')
    idx = content.find('bool _isTestTransaction')
    if idx >= 0:
        print(f'Found at {idx}:')
        print(content[idx:idx+700])
    else:
        print('Method not found!')

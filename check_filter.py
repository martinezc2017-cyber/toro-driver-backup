import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

print(f'_isTestTransaction(m) count: {content.count("_isTestTransaction(m)")}')
print(f'_isTestTransaction method: {content.count("_isTestTransaction")}')
print(f'has metadata in select: {"created_at, metadata" in content}')
print(f'has old select (no metadata): {"created_at\"," in content}')

# Check if the method exists
if 'bool _isTestTransaction' in content:
    start = content.find('bool _isTestTransaction')
    end = content.find('// =========', start)
    if end == -1:
        end = content.find('}', start)
        if end >= 0:
            end += 1
    print(f'\n_isTestTransaction method found at position {start}:')
    print(content[start:start+600])
else:
    print('\nERROR: _isTestTransaction method NOT FOUND!')
    # Find all metadata references
    for i, line in enumerate(content.split('\n')):
        if 'metadata' in line.lower():
            print(f'  Line {i+1}: {line.strip()[:120]}')

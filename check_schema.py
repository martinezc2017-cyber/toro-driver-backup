import requests, json

url = 'https://tqebwkbvdokqtyennbwl.supabase.co/rest/v1/information_schema.columns'
params = {
    'table_name': 'eq.transactions',
    'select': 'column_name,data_type,is_nullable'
}
headers = {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRxZWJ3a2J2ZG9rcXR5ZW5uYndsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MjAyNzY5NjgsImV4cCI6MjAzNTg1Mjk2OH0.bPYCUkGlJFW3rCPJPmgmQVCF0XHY_NZJMXR5LrO63-s',
    'Content-Type': 'application/json'
}

r = requests.get(url, params=params, headers=headers)
if r.status_code == 200:
    cols = r.json()
    print('TRANSACTIONS TABLE COLUMNS:')
    for c in cols:
        print(f'  {c["column_name"]:30s} {c["data_type"]:20s} nullable={c["is_nullable"]}')
else:
    print(f'Error: {r.status_code} {r.text}')

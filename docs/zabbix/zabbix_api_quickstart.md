Zabbix API quickstart (curl + Python)

Endpoint
- URL: https://<zabbix-host>/zabbix/api_jsonrpc.php
- Content-Type: application/json or application/json-rpc

1) Authenticate (user.login)

curl example:

curl --request POST \
  --url 'https://example.com/zabbix/api_jsonrpc.php' \
  --header 'Content-Type: application/json-rpc' \
  --data '{"jsonrpc":"2.0","method":"user.login","params":{"username":"Admin","password":"zabbix"},"id":1}'

Python (requests):

import requests
import json

url = "https://example.com/zabbix/api_jsonrpc.php"
headers = {"Content-Type": "application/json-rpc"}

payload = {
    "jsonrpc": "2.0",
    "method": "user.login",
    "params": {"username": "Admin", "password": "zabbix"},
    "id": 1
}

resp = requests.post(url, headers=headers, data=json.dumps(payload), verify=True)
auth_token = resp.json().get('result')
print('Auth token:', auth_token)

2) Example: call host.get (use the auth token)

payload = {
    "jsonrpc": "2.0",
    "method": "host.get",
    "params": {"output": ["hostid","host","name"]},
    "auth": auth_token,
    "id": 2
}
resp = requests.post(url, headers=headers, data=json.dumps(payload))
print(resp.json())

3) Example: create an item (item.create)

payload = {
    "jsonrpc": "2.0",
    "method": "item.create",
    "params": {
        "name": "Free disk space on /home/joe/",
        "key_": "vfs.fs.size[/home/joe/,free]",
        "hostid": "10105",
        "type": 0,
        "value_type": 3
    },
    "auth": auth_token,
    "id": 3
}
resp = requests.post(url, headers=headers, data=json.dumps(payload))
print(resp.json())

4) Python convenience library (pyzabbix)
- pip install pyzabbix

from pyzabbix import ZabbixAPI
zapi = ZabbixAPI('https://example.com/zabbix')
zapi.login('Admin','zabbix')
hosts = zapi.host.get(output=['hostid','host','name'])
print(hosts)

Notes
- Use HTTPS and verify certificates in production.
- The API methods and params are documented in the full Zabbix manual (see zabbix_doc.txt).
- For large imports or templates the manual shows curl usages and example scripts (see api_jsonrpc_context.txt).
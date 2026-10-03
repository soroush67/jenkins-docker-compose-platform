#!/usr/bin/env python3
"""Tiny GitLab API helper for tests/e2e.sh (lab CD repo platform/cd).

  gitlab.py raw <path>                     print file content at main
  gitlab.py exists <path>                  exit 0 if the file exists
  gitlab.py last <path>                    print "<sha>\\n<author>\\n<message>" of the last commit touching path
  gitlab.py count                          number of commits on main
  gitlab.py put <path> <local-file> <msg>  create/update a file directly (a "teammate" pushing)
  gitlab.py rm <path> <msg>                delete a file directly
"""
import json, os, sys, urllib.error, urllib.parse, urllib.request

API = "http://localhost:8929/api/v4/projects/" + urllib.parse.quote("platform/cd", safe="")
TOKEN = open(os.path.join(os.path.dirname(__file__), "../lab/secrets/gitlab-bot-token")).read().strip()


def call(method, path, body=None, raw=False):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={"PRIVATE-TOKEN": TOKEN, "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        data = r.read()
        return data.decode() if raw else json.loads(data or b"null")


def q(p):
    return urllib.parse.quote(p, safe="")


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "raw":
    sys.stdout.write(call("GET", f"/repository/files/{q(args[0])}/raw?ref=main", raw=True))
elif cmd == "exists":
    try:
        call("GET", f"/repository/files/{q(args[0])}?ref=main")
    except urllib.error.HTTPError:
        sys.exit(1)
elif cmd == "last":
    c = call("GET", f"/repository/commits?ref_name=main&path={q(args[0])}&per_page=1")[0]
    print(c["id"]); print(c["author_name"]); print(c["message"])
elif cmd == "count":
    print(len(call("GET", "/repository/commits?ref_name=main&per_page=100")))
elif cmd in ("put", "rm"):
    path = args[0]
    try:
        call("GET", f"/repository/files/{q(path)}?ref=main"); exists = True
    except urllib.error.HTTPError:
        exists = False
    if cmd == "put":
        action = {"action": "update" if exists else "create", "file_path": path, "content": open(args[1]).read()}
        msg = args[2]
    else:
        if not exists:
            sys.exit(0)
        action = {"action": "delete", "file_path": path}
        msg = args[1]
    call("POST", "/repository/commits", {"branch": "main", "commit_message": msg, "actions": [action]})
else:
    sys.exit(f"unknown command {cmd}")

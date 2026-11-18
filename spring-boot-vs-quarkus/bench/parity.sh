#!/usr/bin/env bash
# Same requests against one running app on :18080; prints status + normalized body for comparison.
B=http://127.0.0.1:18080
req(){ printf '%s %s -> ' "$1" "$2"; curl -s -o /tmp/r.json -w '%{http_code} ' -X "$1" -H 'Content-Type: application/json' ${3:+-d "$3"} "$B$2"; python3 -c "
import json,re;t=open('/tmp/r.json').read()
try: d=json.loads(t)
except: print(repr(t[:80])); raise SystemExit
def n(x): return {k:(re.sub(r'\d','9',v) if k=='createdAt' else v) for k,v in x.items()} if isinstance(x,dict) and 'title' in x else x
print(json.dumps([n(i) for i in d] if isinstance(d,list) else n(d) if isinstance(d,dict) else d, sort_keys=True)[:200])"; }
req POST /notes '{"title":"Hello Java","body":"b","tag":"java"}'
req POST /notes '{"title":"hello quarkus","body":"b","tag":"java"}'
req POST /notes '{"title":"","body":"b","tag":"java"}'
req GET /notes/1
req GET /notes/999
req GET '/notes?tag=java'
req GET '/notes/search?q=HELLO'
req PUT /notes/1 '{"title":"Updated","body":"b2","tag":"spring"}'
req PUT /notes/999 '{"title":"x","body":"y","tag":"z"}'
req DELETE /notes/2
req DELETE /notes/2

#!/usr/bin/env python3
import json, time, urllib.request

BASE = "http://127.0.0.1:8001"
TARGET = 40000
UNIT = "这是Hermes主任务长上下文压力测试。需要分析代码、工具调用、任务规划、错误恢复、数据整理与多步骤推理，并保持长上下文中的信息一致性。"

def post(path, obj, timeout=3600):
    data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(BASE + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())

def count_tokens(text):
    r = post("/tokenize", {"content": text}, timeout=600)
    toks = r.get("tokens", r.get("ids", [])) if isinstance(r, dict) else r
    return len(toks)

lo, hi = 1, 60000
while lo < hi:
    mid = (lo + hi) // 2
    if count_tokens(UNIT * mid) < TARGET:
        lo = mid + 1
    else:
        hi = mid

text = UNIT * lo
n = count_tokens(text)
print("========================================")
print("68K TEST / MAIN slot = 1")
print("prompt tokens        =", n)
print("Now send a real Vision CS request in a NEW browser chat.")
print("========================================", flush=True)

payload = {
    "id_slot": 1,
    "cache_prompt": False,
    "messages": [{"role": "user", "content": text + "\n请基于以上长上下文进行系统分析，至少1200字，分为任务拆解、风险、调度策略、稳定性策略、最终建议，不要过早结束回答。"}],
    "reasoning_effort": "high",
    "temperature": 0.7,
    "top_p": 0.8,
    "max_tokens": 2048,
}

t0 = time.time()
try:
    r = post("/v1/chat/completions", payload, timeout=3600)
    print("\n===== MAIN RESULT =====")
    print("elapsed_s =", round(time.time() - t0, 2))
    print("finish_reason =", r["choices"][0].get("finish_reason"))
    print("usage =", json.dumps(r.get("usage", {}), ensure_ascii=False))
    print("timings =", json.dumps(r.get("timings", {}), ensure_ascii=False))
except Exception as e:
    print("\n===== MAIN FAILED =====")
    print("elapsed_s =", round(time.time() - t0, 2))
    print("error =", repr(e))
    raise

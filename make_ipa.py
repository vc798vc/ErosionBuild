#!/usr/bin/env python3
"""Push the Erosion source to GitHub, build it on Actions, and pull the IPA.

Usage: python3 make_ipa.py --token ghp_xxx
"""
import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.request
import urllib.error
import zipfile

API = "https://api.github.com"
UA = {"User-Agent": "erosion-build", "Accept": "application/vnd.github+json"}
REPO = "ErosionBuild"
BRANCH = "main"
ARTIFACT_NAME = "Erosion-unsigned-ipa"
OUT_IPA = "Erosion.ipa"

SKIP_DIRS = {".git", "dist", "build", "Payload", ".workbuddy"}
SKIP_EXT = {".ipa"}


def api(method, path, token, data=None, retries=5):
    url = API + path
    for attempt in range(retries):
        req = urllib.request.Request(url, method=method)
        req.add_header("Authorization", f"Bearer {token}")
        for k, v in UA.items():
            req.add_header(k, v)
        if data is not None:
            req.add_header("Content-Type", "application/json")
            req.data = json.dumps(data).encode("utf-8")
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                body = r.read().decode("utf-8", "replace")
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            if e.code in (403, 429) and attempt < retries - 1:
                wait = 2 ** (attempt + 1) * 5
                print(f"[api] {e.code} {path} — 退避 {wait}s: {body[:120]}")
                time.sleep(wait)
                continue
            if e.code in (404, 409) and method == "GET":
                return None
            print(f"[api] ERROR {e.code} {method} {path}\n{body[:800]}", file=sys.stderr)
            raise SystemExit(f"GitHub API {e.code}")
        except Exception as e:  # noqa
            if attempt < retries - 1:
                time.sleep(5 * (attempt + 1))
                continue
            raise


def get_owner(token):
    return api("GET", "/user", token)["login"]


def repo_exists(owner, token):
    return api("GET", f"/repos/{owner}/{REPO}", token) is not None


def create_repo(owner, token):
    if repo_exists(owner, token):
        print(f"[repo] {owner}/{REPO} 已存在，复用")
        return
    api("POST", "/user/repos", token,
        {"name": REPO, "private": False, "auto_init": False,
         "description": "Erosion (bad_query) unsigned IPA build"})
    print(f"[repo] 已创建 {owner}/{REPO}")


def collect_files(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if os.path.splitext(fn)[1] in SKIP_EXT:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            with open(full, "rb") as f:
                raw = f.read()
            try:
                out.append((rel, raw.decode("utf-8"), None))
            except UnicodeDecodeError:
                import base64
                out.append((rel, None, base64.b64encode(raw).decode("ascii")))
    out.sort()
    return out


def seed_initial_commit(owner, token):
    """GitHub refuses Git Data API blobs on a repo with zero commits.
    Seed it with one file via the contents API (which creates a commit)."""
    ref = api("GET", f"/repos/{owner}/{REPO}/git/ref/heads/{BRANCH}", token)
    if ref is not None:
        return
    # also try default branch
    r = api("GET", f"/repos/{owner}/{REPO}", token)
    db = r.get("default_branch", BRANCH) if r else BRANCH
    dref = api("GET", f"/repos/{owner}/{REPO}/git/ref/heads/{db}", token)
    if dref is not None:
        return
    payload = {"message": "init", "content": base64.b64encode(b"seed\n").decode("ascii")}
    api("PUT", f"/repos/{owner}/{REPO}/contents/.gitkeep", token, payload)
    print("[repo] 已种入初始提交")


def push_files(owner, token, files):
    print(f"[push] 提交 {len(files)} 个文件…")
    blobs = []
    for rel, text, b64 in files:
        if text is not None:
            blobs.append({"path": rel, "mode": "100644", "type": "blob",
                          "text": text})
        else:
            blobs.append({"path": rel, "mode": "100644", "type": "blob",
                          "b64": b64})
    # create blobs via the multipart-ish endpoint: use the "create blob" per item
    tree = []
    for b in blobs:
        if b.get("text") is not None:
            resp = api("POST", f"/repos/{owner}/{REPO}/git/blobs", token,
                       {"content": b["text"], "encoding": "utf-8"})
        else:
            resp = api("POST", f"/repos/{owner}/{REPO}/git/blobs", token,
                       {"content": b["b64"], "encoding": "base64"})
        tree.append({"path": b["path"], "mode": "100644",
                     "type": "blob", "sha": resp["sha"]})

    # base tree
    ref = api("GET", f"/repos/{owner}/{REPO}/git/ref/heads/{BRANCH}", token)
    base_tree = None
    parents = []
    if ref:
        sha = ref["object"]["sha"]
        parents = [sha]
        base_tree = api("GET", f"/repos/{owner}/{REPO}/git/commits/{sha}", token)["tree"]["sha"]
    else:
        # try the default branch ref
        r2 = api("GET", f"/repos/{owner}/{REPO}", token)
        if r2 and r2.get("default_branch"):
            dref = api("GET", f"/repos/{owner}/{REPO}/git/ref/heads/{r2['default_branch']}", token)
            if dref:
                sha = dref["object"]["sha"]
                parents = [sha]
                base_tree = api("GET", f"/repos/{owner}/{REPO}/git/commits/{sha}", token)["tree"]["sha"]

    payload = {"tree": tree}
    if base_tree:
        payload["base_tree"] = base_tree
    tree_sha = api("POST", f"/repos/{owner}/{REPO}/git/trees", token, payload)["sha"]

    msg = f"build: Erosion source @ {time.strftime('%Y-%m-%d %H:%M')}"
    commit = api("POST", f"/repos/{owner}/{REPO}/git/commits", token,
                 {"message": msg, "tree": tree_sha, "parents": parents})
    commit_sha = commit["sha"]

    if ref or parents:
        api("PATCH", f"/repos/{owner}/{REPO}/git/refs/heads/{BRANCH}", token,
            {"sha": commit_sha, "force": True})
    else:
        api("POST", f"/repos/{owner}/{REPO}/git/refs", token,
            {"ref": f"refs/heads/{BRANCH}", "sha": commit_sha})
    print(f"[push] 完成 {commit_sha}")
    return commit_sha


def wait_build(owner, token, head_sha):
    print("[build] 等待 GitHub Actions 构建…")
    run_id = None
    for _ in range(120):  # up to ~30 min
        runs = api("GET",
                   f"/repos/{owner}/{REPO}/actions/runs?branch={BRANCH}&per_page=20",
                   token)
        for run in runs.get("workflow_runs", []):
            if run["head_sha"] == head_sha:
                run_id = run["id"]
                break
        if run_id is None:
            time.sleep(15)
            continue
        status = api("GET", f"/repos/{owner}/{REPO}/actions/runs/{run_id}", token)
        st = status["status"]
        if st == "completed":
            concl = status["conclusion"]
            print(f"[build] 结果: {concl}  ({status['html_url']})")
            if concl != "success":
                dump_logs(owner, token, run_id)
                raise SystemExit("构建失败")
            return run_id
        print(f"         …{st}")
        time.sleep(15)
    raise SystemExit("构建超时")


def dump_logs(owner, token, run_id):
    try:
        logs = api("GET", f"/repos/{owner}/{REPO}/actions/runs/{run_id}/logs", token)
        print("[build] 日志:", logs)
    except Exception as e:  # noqa
        print("[build] 无法拉取日志:", e)


def download_artifact(owner, token, run_id):
    arts = api("GET", f"/repos/{owner}/{REPO}/actions/runs/{run_id}/artifacts", token)
    aid = None
    for a in arts.get("artifacts", []):
        if a["name"] == ARTIFACT_NAME:
            aid = a["id"]
            break
    if aid is None:
        raise SystemExit(f"未找到 artifact {ARTIFACT_NAME}")
    url = f"{API}/repos/{owner}/{REPO}/actions/artifacts/{aid}/zip"


    class _R(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            n = super().redirect_request(req, fp, code, msg, headers, newurl)
            for k in ("Authorization", "authorization"):
                n.headers.pop(k.capitalize(), None)
                n.unredirected_hdrs.pop(k.capitalize(), None)
            return n

    opener = urllib.request.build_opener(_R)
    req = urllib.request.Request(url, headers={**UA, "Authorization": f"Bearer {token}"})
    data = opener.open(req, timeout=240).read()
    z = zipfile.ZipFile(io.BytesIO(data))
    os.makedirs("dist", exist_ok=True)
    found = None
    for n in z.namelist():
        if n.endswith(".ipa"):
            out = z.read(n)
            with open(os.path.join("dist", OUT_IPA), "wb") as f:
                f.write(out)
            found = n
            break
    if not found:
        raise SystemExit("artifact 内无 .ipa")
    print(f"[artifact] 已写出 dist/{OUT_IPA}  ({len(out)} bytes, from {found})")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--token", required=True)
    args = ap.parse_args()
    token = args.token

    owner = get_owner(token)
    create_repo(owner, token)
    seed_initial_commit(owner, token)
    root = os.path.dirname(os.path.abspath(__file__))
    files = collect_files(root)
    head = push_files(owner, token, files)
    run_id = wait_build(owner, token, head)
    download_artifact(owner, token, run_id)
    print("\n============================================================")
    print(f"完成: {os.path.join(root, 'dist', OUT_IPA)}")
    print("这是未签名（ad-hoc）包，安装前需用 Sideloadly / 巨魔 / 自签 重签名。")
    print("============================================================")


if __name__ == "__main__":
    main()

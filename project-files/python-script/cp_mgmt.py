#!/usr/bin/env python3
from __future__ import annotations
import json, time, ipaddress
from typing import Dict, Any, Optional, Tuple
import requests, urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

class CPMgmt:
    """
    Light wrapper for Check Point Management API with task-wait helpers.
    Covers simple-gateway and simple-cluster operations.
    """

    _TERMINAL_SUCCESS = {"succeeded"}
    _TERMINAL_FAILURE = {"failed", "stopped", "canceled", "cancelled", "aborted", "partially succeeded"}

    def __init__(
        self,
        base_url: str,
        user: Optional[str] = None,
        password: Optional[str] = None,
        domain: Optional[str] = None,
        verify_ssl: bool = True,
        api_key: Optional[str] = None,
    ):
        self.base_url = base_url.rstrip("/")
        self.user = user
        self.password = password
        self.domain = domain
        self.verify_ssl = verify_ssl
        self.api_key = api_key
        self.sid: Optional[str] = None
        self.s = requests.Session()

    def _url(self, path: str) -> str:
        return f"{self.base_url}/web_api/{path.lstrip('/')}"

    # --- Core auth ---
    def login(self) -> Dict[str, Any]:
        payload = {"api-key": self.api_key} if self.api_key else {"user": self.user, "password": self.password}
        if self.domain:
            payload["domain"] = self.domain
        r = self.s.post(self._url("login"), json=payload, verify=self.verify_ssl)
        r.raise_for_status()
        data = r.json()
        self.sid = data.get("sid")
        if not self.sid:
            raise RuntimeError(f"Login failed: {data}")
        return data

    def logout(self) -> None:
        try:
            self.s.post(self._url("logout"), headers=self._hdr(), json={}, verify=self.verify_ssl)
        except Exception:
            pass

    def _hdr(self) -> Dict[str, str]:
        if not self.sid:
            raise RuntimeError("Not logged in")
        return {"X-chkp-sid": self.sid}

    def _maybe_dump_error(self, r: requests.Response, call: str) -> None:
        if r.status_code >= 400:
            try:
                print(f"[ERROR] {call}:", json.dumps(r.json(), indent=2))
            except Exception:
                print(f"[ERROR] {call}:", r.text)

    def _ip_family_ok(ipver: str, nh: str) -> bool:
        try:
            ip = ipaddress.ip_address(nh)
            return (ipver == "ipv4" and ip.version == 4) or (ipver == "ipv6" and ip.version == 6)
        except Exception:
            return False

    # --- Simple Gateway ---
    def add_simple_gateway(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        r = self.s.post(self._url("add-simple-gateway"), headers=self._hdr(), json=payload, verify=self.verify_ssl)
        self._maybe_dump_error(r, "add-simple-gateway")
        r.raise_for_status()
        return r.json()

    def set_simple_gateway(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        body = {"name": name, **payload}
        r = self.s.post(self._url("set-simple-gateway"), headers=self._hdr(), json=body, verify=self.verify_ssl)
        self._maybe_dump_error(r, "set-simple-gateway")
        r.raise_for_status()
        return r.json()

    def show_simple_gateway(self, name: str) -> Dict[str, Any]:
        r = self.s.post(self._url("show-simple-gateway"), headers=self._hdr(),
                        json={"name": name, "details-level": "full"}, verify=self.verify_ssl)
        r.raise_for_status()
        return r.json()

    # --- Simple Cluster ---
    def add_simple_cluster(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        r = self.s.post(self._url("add-simple-cluster"), headers=self._hdr(), json=payload, verify=self.verify_ssl)
        self._maybe_dump_error(r, "add-simple-cluster")
        r.raise_for_status()
        return r.json()

    def set_simple_cluster(self, name: str, payload: Dict[str, Any]) -> Dict[str, Any]:
        body = {"name": name, **payload}
        r = self.s.post(self._url("set-simple-cluster"), headers=self._hdr(), json=body, verify=self.verify_ssl)
        self._maybe_dump_error(r, "set-simple-cluster")
        r.raise_for_status()
        return r.json()

    # --- Generic objects ---
    def show_generic_objects(self, name: Optional[str] = None, filter_: Optional[str] = None) -> Dict[str, Any]:
        body: Dict[str, Any] = {"details-level": "full"}
        if name:
            body["name"] = name
        if filter_:
            body["filter"] = filter_
        r = self.s.post(self._url("show-generic-objects"), headers=self._hdr(), json=body, verify=self.verify_ssl)
        r.raise_for_status()
        return r.json()

    def set_generic_object(self, uid: str, **fields) -> Dict[str, Any]:
        body = {"uid": uid, **fields}
        r = self.s.post(self._url("set-generic-object"), headers=self._hdr(), json=body, verify=self.verify_ssl)
        self._maybe_dump_error(r, "set-generic-object")
        r.raise_for_status()
        return r.json()

    # --- Publish & Tasks ---
    def publish(self) -> Dict[str, Any]:
        r = self.s.post(self._url("publish"), headers=self._hdr(), json={}, verify=self.verify_ssl)
        r.raise_for_status()
        return r.json()

    def show_task(self, task_id: str) -> Dict[str, Any]:
        r = self.s.post(self._url("show-task"), headers=self._hdr(),
                        json={"task-id": task_id, "details-level": "full"}, verify=self.verify_ssl)
        r.raise_for_status()
        return r.json()

    def _extract_task_id(self, pub: Dict[str, Any]) -> Optional[str]:
        tid = pub.get("task-id")
        if tid:
            return tid
        tasks = pub.get("tasks") or []
        if tasks and isinstance(tasks, list) and "task-id" in tasks[0]:
            return tasks[0]["task-id"]
        return None

    def publish_and_wait(self, timeout: int = 900, poll_interval: float = 2.0) -> Tuple[bool, Dict[str, Any]]:
        pub = self.publish()
        print("[OK] publish:", json.dumps(pub, indent=2))
        task_id = self._extract_task_id(pub)
        if not task_id:
            print("[WARN] publish returned no task-id; cannot track completion.")
            return True, pub
        ok = self.wait_for_task_success(task_id, timeout=timeout, poll_interval=poll_interval)
        return ok, pub

    def wait_for_task_success(self, task_id: str, timeout: int = 900, poll_interval: float = 2.0) -> bool:
        deadline = time.monotonic() + timeout
        last_status, last_progress = None, None
        while time.monotonic() < deadline:
            try:
                doc = self.show_task(task_id)
            except requests.HTTPError as e:
                print(f"[WARN] show-task error: {e}")
                time.sleep(poll_interval)
                continue

            status, progress, msg = self._derive_overall_status(doc)
            if status != last_status or progress != last_progress:
                pct = f"{progress}%" if progress is not None else "n/a"
                print(f"[TASK {task_id}] status={status}, progress={pct}, msg={msg}")
                last_status, last_progress = status, progress

            if status in self._TERMINAL_SUCCESS:
                return True
            if status in self._TERMINAL_FAILURE:
                try:
                    print(json.dumps(doc, indent=2))
                except Exception:
                    pass
                return False
            time.sleep(poll_interval)
        print("[ERROR] Timeout waiting for task to finish.")
        return False

    def _derive_overall_status(self, task_doc: Dict[str, Any]) -> Tuple[str, Optional[int], str]:
        tasks = task_doc.get("tasks") or []
        if isinstance(tasks, list) and tasks:
            statuses, progresses, msgs = [], [], []
            for t in tasks:
                st = (t.get("status") or "").lower()
                statuses.append(st)
                pr = t.get("progress-percentage")
                try:
                    progresses.append(int(pr))
                except Exception:
                    progresses.append(0)
                msgs.append(t.get("status-description") or t.get("task-name") or "")
            if any(s in self._TERMINAL_FAILURE for s in statuses):
                return "failed", max(progresses) if progresses else None, "; ".join([m for m in msgs if m])
            if all(s in self._TERMINAL_SUCCESS for s in statuses):
                return "succeeded", 100, "; ".join([m for m in msgs if m])
            return "in progress", max(progresses) if progresses else None, "; ".join([m for m in msgs if m])
        status = (task_doc.get("status") or "").lower() or "in progress"
        progress = task_doc.get("progress-percentage")
        try:
            progress = int(progress) if progress is not None else None
        except Exception:
            progress = None
        msg = task_doc.get("status-description") or task_doc.get("task-name") or ""
        return status, progress, msg

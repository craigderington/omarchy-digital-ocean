#!/usr/bin/env python3
"""Safe doctl adapter and data normalization for the Omarchy widget."""

from __future__ import annotations

import json
import math
import re
import subprocess
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from typing import Any


class DigitalOceanError(RuntimeError):
    """A user-facing doctl or response error."""


Runner = Callable[[list[str], int], tuple[int, str, str]]


def _doctl_error(stdout: str, stderr: str, code: int) -> str:
    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        payload = None
    if isinstance(payload, dict) and isinstance(payload.get("errors"), list):
        for item in payload["errors"]:
            if isinstance(item, dict) and item.get("detail"):
                return str(item["detail"]).splitlines()[0]
    summary = stderr.strip().splitlines()
    return summary[0] if summary else f"doctl exited with status {code}"


def subprocess_runner(command: list[str], timeout: int) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as error:
        raise DigitalOceanError("doctl is not installed or is not on PATH.") from error
    except subprocess.TimeoutExpired as error:
        raise DigitalOceanError(f"doctl timed out after {timeout} seconds.") from error
    return completed.returncode, completed.stdout, completed.stderr


class DigitalOceanClient:
    def __init__(
        self,
        context: str = "",
        runner: Runner = subprocess_runner,
        timeout: int = 20,
    ) -> None:
        self.context = context.strip()
        self.runner = runner
        self.timeout = timeout

    def command(self, arguments: Sequence[str]) -> list[str]:
        command = ["doctl"]
        if self.context:
            command.extend(["--context", self.context])
        command.append("--interactive=false")
        command.extend(arguments)
        return command

    def json_request(self, arguments: Sequence[str], retry_max: int | None = None) -> Any:
        request_arguments = list(arguments)
        if retry_max is not None:
            request_arguments.extend(["--http-retry-max", str(max(0, retry_max))])
        command = self.command([*request_arguments, "--output", "json"])
        code, stdout, stderr = self.runner(command, self.timeout)
        if code != 0:
            raise DigitalOceanError(_doctl_error(stdout, stderr, code))
        try:
            return json.loads(stdout)
        except json.JSONDecodeError as error:
            raise DigitalOceanError("doctl returned invalid JSON.") from error


def _object(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _rows(payload: Any, key: str = "") -> list[dict[str, Any]]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    if isinstance(payload, dict):
        value = payload.get(key) if key else None
        if isinstance(value, list):
            return [item for item in value if isinstance(item, dict)]
        return [payload]
    return []


def _number(value: Any) -> float:
    try:
        number = float(value or 0)
    except (TypeError, ValueError):
        return 0.0
    # inf/NaN would crash int() conversion with OverflowError and make
    # json.dumps emit non-standard Infinity/NaN tokens the panel cannot parse.
    return number if math.isfinite(number) else 0.0


def _region(value: Any) -> str:
    if isinstance(value, dict):
        return str(value.get("slug") or value.get("name") or "")
    return str(value or "")


def _ip(droplet: dict[str, Any], address_type: str, version: str) -> str:
    networks = _object(droplet.get("networks"))
    entries = networks.get(version)
    for entry in entries or []:
        if isinstance(entry, dict) and entry.get("type") == address_type:
            return str(entry.get("ip_address") or "")
    return ""


def _droplets(payload: Any) -> list[dict[str, Any]]:
    result = []
    for item in _rows(payload, "droplets"):
        image = _object(item.get("image"))
        size = _object(item.get("size"))
        result.append({
            "id": str(item.get("id") or ""),
            "name": str(item.get("name") or "Unnamed Droplet"),
            "status": str(item.get("status") or "unknown").lower(),
            "region": _region(item.get("region")),
            "publicIpv4": _ip(item, "public", "v4"),
            "privateIpv4": _ip(item, "private", "v4"),
            "publicIpv6": _ip(item, "public", "v6"),
            "vcpus": int(_number(item.get("vcpus") or size.get("vcpus"))),
            "memoryMb": int(_number(item.get("memory") or size.get("memory"))),
            "diskGb": int(_number(item.get("disk") or size.get("disk"))),
            "image": str(image.get("distribution") or image.get("slug") or ""),
            "size": str(item.get("size_slug") or size.get("slug") or ""),
            "tags": [str(tag) for tag in (item.get("tags") or []) if tag],
            "createdAt": str(item.get("created_at") or ""),
        })
    return result


def _kubernetes(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed cluster"),
        "status": str(_object(item.get("status")).get("state") or item.get("status") or "unknown").lower(),
        "region": _region(item.get("region")),
        "version": str(item.get("version") or ""),
        "nodePools": len(item.get("node_pools") or []),
        "endpoint": str(item.get("endpoint") or ""),
        "ipv4": str(item.get("ipv4") or ""),
        "autoUpgrade": bool(item.get("auto_upgrade", False)),
        "createdAt": str(item.get("created_at") or ""),
    } for item in _rows(payload, "kubernetes_clusters")]


def _databases(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed database"),
        "status": str(item.get("status") or "unknown").lower(),
        "engine": str(item.get("engine") or ""),
        "version": str(item.get("version") or ""),
        "region": _region(item.get("region")),
        "size": str(item.get("size") or ""),
        "nodes": int(_number(item.get("num_nodes"))),
        "createdAt": str(item.get("created_at") or ""),
    } for item in _rows(payload, "databases")]


def _apps(payload: Any) -> list[dict[str, Any]]:
    result = []
    for item in _rows(payload, "apps"):
        spec = _object(item.get("spec"))
        deployment = _object(item.get("active_deployment"))
        result.append({
            "id": str(item.get("id") or ""),
            "name": str(spec.get("name") or item.get("name") or "Unnamed app"),
            "status": str(deployment.get("phase") or item.get("phase") or "unknown").lower(),
            "region": _region(spec.get("region") or item.get("region")),
            "ingress": str(item.get("default_ingress") or ""),
            "tier": str(item.get("tier_slug") or ""),
            "createdAt": str(item.get("created_at") or ""),
            "updatedAt": str(item.get("updated_at") or ""),
        })
    return result


def _load_balancers(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed load balancer"),
        "status": str(item.get("status") or "unknown").lower(),
        "ip": str(item.get("ip") or ""),
        "region": _region(item.get("region")),
        "size": str(item.get("size") or item.get("size_unit") or ""),
        "algorithm": str(item.get("algorithm") or ""),
        "dropletIds": [str(value) for value in (item.get("droplet_ids") or [])],
        "createdAt": str(item.get("created_at") or ""),
    } for item in _rows(payload, "load_balancers")]


def _volumes(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed volume"),
        "region": _region(item.get("region")),
        "sizeGb": _number(item.get("size_gigabytes")),
        "description": str(item.get("description") or ""),
        "dropletIds": [str(value) for value in (item.get("droplet_ids") or [])],
        "createdAt": str(item.get("created_at") or ""),
    } for item in _rows(payload, "volumes")]


def _snapshots(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed snapshot"),
        "resourceType": str(item.get("resource_type") or ""),
        "sizeGb": _number(item.get("size_gigabytes")),
        "minDiskSizeGb": int(_number(item.get("min_disk_size"))),
        "regions": [str(value) for value in (item.get("regions") or [])],
        "createdAt": str(item.get("created_at") or ""),
    } for item in _rows(payload, "snapshots")]


def _domains(payload: Any) -> list[dict[str, Any]]:
    return [{"name": str(item.get("name") or ""), "ttl": int(_number(item.get("ttl")))} for item in _rows(payload, "domains")]


def _projects(payload: Any) -> list[dict[str, Any]]:
    return [{
        "id": str(item.get("id") or ""),
        "name": str(item.get("name") or "Unnamed project"),
        "description": str(item.get("description") or ""),
        "purpose": str(item.get("purpose") or ""),
        "environment": str(item.get("environment") or ""),
        "isDefault": bool(item.get("is_default", False)),
        "createdAt": str(item.get("created_at") or ""),
        "updatedAt": str(item.get("updated_at") or ""),
    } for item in _rows(payload, "projects")]


def _billing(payload: Any) -> dict[str, Any]:
    rows = _rows(payload, "balance")
    item = rows[0] if rows else {}
    return {
        "monthToDateBalance": _number(item.get("month_to_date_balance")),
        "accountBalance": _number(item.get("account_balance")),
        "monthToDateUsage": _number(item.get("month_to_date_usage")),
        "generatedAt": str(item.get("generated_at") or ""),
    }


def _account(payload: Any) -> dict[str, Any]:
    rows = _rows(payload, "account")
    item = rows[0] if rows else {}
    return {
        "email": str(item.get("email") or ""),
        "status": str(item.get("status") or ""),
        "dropletLimit": int(_number(item.get("droplet_limit"))),
        "floatingIpLimit": int(_number(item.get("floating_ip_limit"))),
        "emailVerified": bool(item.get("email_verified", False)),
    }


_RESOURCE_SPECS: dict[str, tuple[list[str], Callable[[Any], Any]]] = {
    "account": (["account", "get"], _account),
    "droplets": (["compute", "droplet", "list"], _droplets),
    "kubernetes": (["kubernetes", "cluster", "list"], _kubernetes),
    "databases": (["databases", "list"], _databases),
    "apps": (["apps", "list"], _apps),
    "loadBalancers": (["compute", "load-balancer", "list"], _load_balancers),
    "volumes": (["compute", "volume", "list"], _volumes),
    "snapshots": (["compute", "snapshot", "list"], _snapshots),
    "domains": (["compute", "domain", "list"], _domains),
    "projects": (["projects", "list"], _projects),
    "billing": (["balance", "get"], _billing),
}


def build_dashboard(client: DigitalOceanClient) -> dict[str, Any]:
    data: dict[str, Any] = {}
    errors: dict[str, str] = {}

    def fetch(entry: tuple[str, tuple[list[str], Callable[[Any], Any]]]) -> tuple[str, Any, str]:
        name, (arguments, normalizer) = entry
        try:
            return name, normalizer(client.json_request(arguments)), ""
        except DigitalOceanError as error:
            empty = {} if name in {"account", "billing"} else []
            return name, empty, str(error)
        except (KeyError, TypeError, ValueError):
            empty = {} if name in {"account", "billing"} else []
            return name, empty, f"DigitalOcean returned an unexpected {name} response."

    with ThreadPoolExecutor(max_workers=6, thread_name_prefix="doctl") as executor:
        for name, value, error in executor.map(fetch, _RESOURCE_SPECS.items()):
            data[name] = value
            if error:
                errors[name] = error

    droplets = data["droplets"]
    kubernetes = data["kubernetes"]
    databases = data["databases"]
    apps = data["apps"]
    load_balancers = data["loadBalancers"]
    data["summary"] = {
        "totalDroplets": len(droplets),
        "runningDroplets": sum(item["status"] == "active" for item in droplets),
        "healthyKubernetes": sum(item["status"] in {"running", "provisioned"} for item in kubernetes),
        "totalKubernetes": len(kubernetes),
        "healthyDatabases": sum(item["status"] in {"online", "running"} for item in databases),
        "totalDatabases": len(databases),
        "activeApps": sum(item["status"] in {"active", "deployed"} for item in apps),
        "failedApps": sum(item["status"] in {"error", "failed", "canceled"} for item in apps),
        "totalApps": len(apps),
        "healthyLoadBalancers": sum(item["status"] == "active" for item in load_balancers),
        "totalLoadBalancers": len(load_balancers),
        "errorCount": len(errors),
    }
    data["errors"] = errors
    data["state"] = "error" if len(errors) == len(_RESOURCE_SPECS) else "ready"
    data["message"] = next(iter(errors.values()), "") if data["state"] == "error" else ""
    return data


_DROPLET_ACTIONS = {"power-on", "shutdown", "power-off", "reboot"}
_DROPLET_ACTION_STATES = {
    "power-on": {"off"},
    "shutdown": {"active"},
    "power-off": {"active"},
    "reboot": {"active"},
}


def run_droplet_action(client: DigitalOceanClient, action: str, droplet_id: str) -> dict[str, Any]:
    if action not in _DROPLET_ACTIONS:
        raise DigitalOceanError(f"Unsupported Droplet action: {action}")
    if not re.fullmatch(r"[1-9][0-9]*", droplet_id):
        raise DigitalOceanError("Droplet ID is invalid.")

    rows = _rows(client.json_request(["compute", "droplet", "get", droplet_id]), "droplets")
    if not rows:
        raise DigitalOceanError("Droplet no longer exists or is unavailable.")
    current_state = str(rows[0].get("status") or "unknown").lower()
    allowed_states = _DROPLET_ACTION_STATES[action]
    if current_state not in allowed_states:
        expected = " or ".join(sorted(allowed_states))
        raise DigitalOceanError(f"Action {action} requires state {expected}; current state is {current_state}.")

    response = client.json_request(
        ["compute", "droplet-action", action, droplet_id],
        retry_max=0,
    )
    return {
        "success": True,
        "action": action,
        "dropletId": droplet_id,
        "dropletName": str(rows[0].get("name") or ""),
        "previousState": current_state,
        "result": response,
    }


def list_contexts(client: DigitalOceanClient) -> list[dict[str, Any]]:
    payload = client.json_request(["auth", "list"])
    contexts = []
    for item in _rows(payload, "contexts"):
        name = str(item.get("name") or "")
        if not re.fullmatch(r"[A-Za-z0-9._-]{1,128}", name):
            continue
        contexts.append({"name": name, "current": item.get("current") is True})
    return contexts

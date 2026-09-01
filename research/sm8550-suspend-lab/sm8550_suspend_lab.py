#!/usr/bin/env python3
"""Empirical SM8550 suspend lab runner.

The host side uses SSH only to install this file, launch a detached systemd
unit, poll its small status file, and retrieve the resulting run directory.
The device side is deliberately self-contained and uses only Python's
standard library plus the Armada/systemd commands already present on the
target image.

This tool is an experiment recorder, not a suspend policy. It never unbinds
devices, changes firmware, flashes partitions, or applies kernel patches.
"""

from __future__ import annotations

import argparse
import contextlib
import dataclasses
import datetime as dt
import hashlib
import json
import os
import platform
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


SCHEMA_VERSION = 2
DEFAULT_DEVICE_ROOT = "/var/lib/sm8550-suspend-lab"
RUN_ID_RE = re.compile(r"^[0-9]{8}T[0-9]{6}Z-[0-9a-f]{12}$")
SAFE_NAME_RE = re.compile(r"[^A-Za-z0-9_.-]+")
SUSPEND_SERVICE = "systemd-suspend.service"
MIN_CLOCK_PROVEN_SUSPEND_SECONDS = 0.5
RUNTIME_KEYWORDS = (
    "dwc3",
    "usb",
    "phy",
    "ufs",
    "ufshc",
    "mmc",
    "sdhci",
    "pci",
    "ath12k",
    "wlan",
    "bluetooth",
    "bluetooth",
    "remoteproc",
    "rproc",
)
RUNTIME_FIELDS = (
    "control",
    "runtime_status",
    "runtime_usage",
    "runtime_active_time",
    "runtime_suspended_time",
    "autosuspend_delay_ms",
    "wakeup",
)
POWER_FIELDS = (
    "type",
    "status",
    "online",
    "present",
    "health",
    "capacity",
    "charge_counter",
    "energy_now",
    "current_now",
    "voltage_now",
    "power_now",
    "temp",
    "usb_type",
    "scope",
    "model_name",
    "manufacturer",
)
CPUIDLE_FIELDS = (
    "name",
    "disable",
    "usage",
    "time",
    "residency",
    "target_residency",
    "entry_latency",
    "exit_latency",
)
QCOM_STAT_DIRS = (
    "/sys/kernel/debug/qcom_stats",
    "/sys/kernel/debug/qcom_sleep_stats",
)
TRACEFS_DIRS = (
    "/sys/kernel/tracing",
    "/sys/kernel/debug/tracing",
)
TRACE_PROFILE_CHOICES = ("none", "ufs-irq", "rpmh-aoss", "rsc-success")
TRACE_IRQ_NUMBER = 169
TRACE_REQUIRED_EVENTS = (
    "irq:irq_handler_entry",
    "irq:irq_handler_exit",
)
TRACE_RPMH_REQUIRED_EVENTS = (
    "rpmh:rpmh_send_msg",
    "rpmh:rpmh_tx_done",
    "qcom_aoss:aoss_send",
    "qcom_aoss:aoss_send_done",
)
TRACE_RPMH_SUCCESS_REQUIRED_EVENTS = TRACE_RPMH_REQUIRED_EVENTS + (
    "rpmh:rpmh_rsc_snapshot",
)
TRACE_RPMH_OPTIONAL_EVENTS = (
    "interconnect:icc_set_bw",
    "interconnect:icc_set_bw_end",
)
TRACE_PM_EVENTS = (
    "power:device_pm_callback_start",
    "power:device_pm_callback_end",
)


class LabError(RuntimeError):
    """A safe, user-actionable lab error."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def monotonic_seconds() -> float:
    return time.monotonic()


def default_output_root() -> Path:
    configured = os.environ.get("SM8550_LAB_OUTPUT")
    if configured:
        return Path(configured).expanduser()
    # Keep large raw runs beside, rather than inside, the Armada checkout by
    # default, regardless of the directory from which the command is invoked.
    script_path = Path(__file__).resolve()
    if len(script_path.parents) > 2:
        return script_path.parents[2].parent / "sm8550-suspend-lab-runs"
    return Path.cwd() / "sm8550-suspend-lab-runs"


def validate_run_id(run_id: str) -> str:
    if not RUN_ID_RE.fullmatch(run_id):
        raise LabError(
            "run ID must have the form YYYYMMDDTHHMMSSZ-<12 lowercase hex chars>"
        )
    return run_id


def new_run_id() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(6)


def safe_name(value: str) -> str:
    cleaned = SAFE_NAME_RE.sub("_", value)
    return cleaned[:160] or "unnamed"


def json_value(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def atomic_write_bytes(destination: Path, data: bytes, mode: int = 0o600) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(
        ".%s.%s.%s.tmp" % (destination.name, os.getpid(), secrets.token_hex(4))
    )
    try:
        with open(temporary, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, destination)
    finally:
        if temporary.exists():
            temporary.unlink()


def atomic_write_text(destination: Path, text: str, mode: int = 0o600) -> None:
    atomic_write_bytes(destination, text.encode("utf-8"), mode=mode)


def write_json(destination: Path, value: Any, mode: int = 0o600) -> None:
    atomic_write_text(
        destination,
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False, default=json_value) + "\n",
        mode=mode,
    )


def read_bytes(source: Path) -> Optional[bytes]:
    try:
        return source.read_bytes()
    except (OSError, ValueError):
        return None


def read_text(source: Path) -> Optional[str]:
    data = read_bytes(source)
    if data is None:
        return None
    return data.decode("utf-8", errors="replace").rstrip("\n")


def write_kernel_control(destination: Path, text: str) -> None:
    """Write a sysfs/debugfs/procfs control directly.

    Atomic rename is correct for regular evidence files but does not work for
    pseudo-files such as wakealarm, pm_debug_messages, and dynamic-debug's
    control file.
    """
    with open(destination, "w", encoding="utf-8") as handle:
        handle.write(text)
        handle.flush()


def numeric_or_text(value: Optional[str]) -> Any:
    if value is None:
        return None
    stripped = value.strip()
    if re.fullmatch(r"-?[0-9]+", stripped):
        try:
            return int(stripped)
        except ValueError:
            pass
    if re.fullmatch(r"-?[0-9]+\.[0-9]+", stripped):
        try:
            return float(stripped)
        except ValueError:
            pass
    return stripped


def parse_cmd_db_dump(text: str) -> Dict[str, Any]:
    """Parse the read-only debugfs Command DB rendering.

    The dump is a descriptor database, not live vote state. Preserve duplicate
    addresses because aliases in the firmware database are meaningful.
    """
    resources: List[Dict[str, Any]] = []
    accelerator: Optional[str] = None
    versions: Dict[str, str] = {}
    for line in text.splitlines():
        header = re.match(r"^Slave (\S+) \(v([^\)]+)\)$", line)
        if header:
            accelerator = header.group(1)
            versions[accelerator] = header.group(2)
            continue
        entry = re.match(r"^(0x[0-9A-Fa-f]+): (\S+)(?: \[([0-9A-Fa-f ]+)\])?$", line)
        if not entry or accelerator is None:
            continue
        resource: Dict[str, Any] = {
            "address": int(entry.group(1), 16),
            "address_hex": entry.group(1).lower(),
            "accelerator": accelerator,
            "name": entry.group(2),
        }
        if entry.group(3) is not None:
            resource["aux_bytes"] = [int(item, 16) for item in entry.group(3).split()]
        resources.append(resource)
    return {
        "available": bool(resources) or text.strip() == "Command DB DUMP",
        "resource_count": len(resources),
        "accelerators": versions,
        "resources": resources,
    }


def parse_interconnect_summary(text: str) -> Dict[str, Any]:
    """Parse the current Qualcomm interconnect summary without losing raw data."""
    aggregates: List[Dict[str, Any]] = []
    consumers: List[Dict[str, Any]] = []
    parent: Optional[str] = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("-") or line.strip().startswith("node "):
            continue
        aggregate = re.match(r"^(\S+)\s+(\d+)\s+(\d+)\s*$", line)
        if aggregate:
            parent = aggregate.group(1)
            aggregates.append(
                {
                    "node": parent,
                    "avg_bw": int(aggregate.group(2)),
                    "peak_bw": int(aggregate.group(3)),
                }
            )
            continue
        consumer = re.match(r"^\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$", line)
        if consumer:
            consumers.append(
                {
                    "parent": parent,
                    "node": consumer.group(1),
                    "tag": int(consumer.group(2)),
                    "avg_bw": int(consumer.group(3)),
                    "peak_bw": int(consumer.group(4)),
                }
            )
    return {
        "available": bool(aggregates or consumers),
        "aggregate_count": len(aggregates),
        "consumer_count": len(consumers),
        "aggregates": aggregates,
        "consumers": consumers,
    }


def parse_interconnect_graph(text: str) -> Dict[str, Any]:
    """Parse node values and edges from the DOT-style interconnect graph."""
    nodes: List[Dict[str, Any]] = []
    edges: List[Dict[str, str]] = []
    clusters: List[Tuple[int, int, str]] = []
    for cluster in re.finditer(
        r"(?ms)^\s*subgraph\s+cluster_\d+\s*\{\s*\n\s*label\s*=\s*\"([^\"]+)\"",
        text,
    ):
        close = text.find("\n\t}", cluster.end())
        if close < 0:
            close = len(text)
        clusters.append((cluster.start(), close, cluster.group(1)))
    node_pattern = re.compile(
        r'(?ms)^\s*"([^"]+)" \[label="([^"\n]+)\n\s*\|avg_bw=(\d+)kBps\n\s*\|peak_bw=(\d+)kBps"\]'
    )
    for node in node_pattern.finditer(text):
        node_id, node_name = node.group(1).split(":", 1)
        cluster_name = next(
            (label for start, end, label in clusters if start <= node.start() < end),
            None,
        )
        nodes.append(
            {
                "id": node_id,
                "name": node_name,
                "cluster": cluster_name,
                "avg_bw": int(node.group(3)),
                "peak_bw": int(node.group(4)),
            }
        )
    for edge in re.finditer(r'(?m)^\s*"([^"]+)" -> "([^"]+)"$', text):
        edges.append({"source": edge.group(1), "destination": edge.group(2)})
    return {
        "available": bool(nodes or edges),
        "node_count": len(nodes),
        "edge_count": len(edges),
        "nodes": nodes,
        "edges": edges,
    }


def parse_pm_genpd_summary(text: str) -> Dict[str, Any]:
    """Parse domain and child-device rows from pm_genpd_summary."""
    domains: List[Dict[str, Any]] = []
    devices: List[Dict[str, Any]] = []
    current_domain: Optional[str] = None
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("-") or line.strip().startswith("domain "):
            continue
        domain = re.match(r"^(\S+)\s+(\S+)\s+(\d+)\s*$", line)
        if domain:
            current_domain = domain.group(1)
            domains.append(
                {
                    "domain": current_domain,
                    "status": domain.group(2),
                    "performance": int(domain.group(3)),
                }
            )
            continue
        device = re.match(r"^\s+(\S+)\s+(\S+)\s+(\d+)\s+(\S+)\s*$", line)
        if device:
            devices.append(
                {
                    "domain": current_domain,
                    "device": device.group(1),
                    "runtime_status": device.group(2),
                    "usage": int(device.group(3)),
                    "managed_by": device.group(4),
                }
            )
    return {
        "available": bool(domains or devices),
        "domain_count": len(domains),
        "device_count": len(devices),
        "domains": domains,
        "devices": devices,
    }


@dataclasses.dataclass
class CommandResult:
    command: List[str]
    returncode: Optional[int]
    stdout: bytes
    stderr: bytes
    timed_out: bool
    duration_seconds: float

    def as_json(self) -> Dict[str, Any]:
        return {
            "command": self.command,
            "returncode": self.returncode,
            "timed_out": self.timed_out,
            "duration_seconds": round(self.duration_seconds, 6),
            "stdout_bytes": len(self.stdout),
            "stderr_bytes": len(self.stderr),
        }


def run_command(
    command: Sequence[str],
    *,
    env: Optional[Dict[str, str]] = None,
    timeout: Optional[float] = 30,
    input_bytes: Optional[bytes] = None,
) -> CommandResult:
    command_list = [str(part) for part in command]
    started = monotonic_seconds()
    try:
        completed = subprocess.run(
            command_list,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=timeout,
            check=False,
        )
        return CommandResult(
            command=command_list,
            returncode=completed.returncode,
            stdout=completed.stdout,
            stderr=completed.stderr,
            timed_out=False,
            duration_seconds=monotonic_seconds() - started,
        )
    except FileNotFoundError as exc:
        return CommandResult(
            command=command_list,
            returncode=127,
            stdout=b"",
            stderr=str(exc).encode("utf-8"),
            timed_out=False,
            duration_seconds=monotonic_seconds() - started,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
        if isinstance(stdout, str):
            stdout = stdout.encode("utf-8", errors="replace")
        if isinstance(stderr, str):
            stderr = stderr.encode("utf-8", errors="replace")
        return CommandResult(
            command=command_list,
            returncode=None,
            stdout=stdout,
            stderr=stderr,
            timed_out=True,
            duration_seconds=monotonic_seconds() - started,
        )


def parse_shell_assignments(text: str) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line in text.splitlines():
        if not line.startswith("ARMADA_") or "=" not in line:
            continue
        key, encoded = line.split("=", 1)
        try:
            tokens = shlex.split(encoded)
            values[key] = tokens[0] if tokens else ""
        except ValueError:
            values[key] = encoded
    return values


def parse_interrupts(text: str) -> Dict[str, Dict[str, Any]]:
    result: Dict[str, Dict[str, Any]] = {}
    for line in text.splitlines():
        match = re.match(r"^\s*([0-9]+):\s+(.*)$", line)
        if not match:
            continue
        irq = match.group(1)
        tokens = match.group(2).split()
        counts: List[int] = []
        while tokens and re.fullmatch(r"[0-9]+", tokens[0]):
            counts.append(int(tokens.pop(0)))
        result[irq] = {
            "counts": counts,
            "total": sum(counts),
            "details": " ".join(tokens),
            "raw": line,
        }
    return result


def parse_wakeup_sources(text: str) -> Dict[str, Dict[str, Any]]:
    rows: Dict[str, Dict[str, Any]] = {}
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return rows
    header = lines[0].split()
    for line in lines[1:]:
        fields = line.split()
        if not fields:
            continue
        row: Dict[str, Any] = {"name": fields[0], "raw": line}
        for index, value in enumerate(fields[1:], start=1):
            key = header[index] if index < len(header) else "field_%d" % index
            row[key] = numeric_or_text(value)
        rows[fields[0]] = row
    return rows


def parse_qcom_stat(text: str) -> Dict[str, Any]:
    parsed: Dict[str, Any] = {}
    for line in text.splitlines():
        match = re.match(r"^([^:]+):\s*(.*)$", line)
        if not match:
            continue
        key = safe_name(match.group(1).strip()).lower()
        parsed[key] = numeric_or_text(match.group(2))
    return parsed


def parse_trace_events(text: str) -> List[str]:
    events: List[str] = []
    for line in text.splitlines():
        value = line.strip()
        if re.fullmatch(r"[^:\s]+:[^:\s]+", value):
            events.append(value)
    return sorted(set(events))


def parse_rpmh_rsc_snapshots(text: str) -> Dict[str, Any]:
    """Parse the diagnostic RSC snapshot tracepoint while retaining raw trace separately."""
    events: List[Dict[str, Any]] = []
    for line in text.splitlines():
        marker = re.search(r"\brpmh_rsc_snapshot:\s+(\S+):\s+(.*)$", line)
        if not marker:
            continue
        fields = dict(re.findall(r"([A-Za-z0-9_]+)=([^\s]+)", marker.group(2)))
        if not fields.get("phase") or not fields.get("group"):
            continue
        event: Dict[str, Any] = {
            "controller": marker.group(1),
            "phase": fields.pop("phase"),
            "group": fields.pop("group"),
        }
        for name, value in fields.items():
            if name == "version" or name == "resource":
                event[name] = value
                continue
            try:
                event[name] = int(value, 0)
            except ValueError:
                event[name] = value
        events.append(event)
    phases: Dict[str, int] = {}
    groups: Dict[str, int] = {}
    for event in events:
        phases[event["phase"]] = phases.get(event["phase"], 0) + 1
        groups[event["group"]] = groups.get(event["group"], 0) + 1
    return {
        "available": bool(events),
        "event_count": len(events),
        "phase_counts": phases,
        "group_counts": groups,
        "events": events,
    }


def trace_event_parts(event: str) -> Tuple[str, str]:
    system, name = event.split(":", 1)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", system) or not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
        raise LabError("invalid trace event name: %s" % event)
    return system, name


def trace_event_file(instance: Path, event: str, filename: str) -> Path:
    system, name = trace_event_parts(event)
    return instance / "events" / system / name / filename


def trace_file_label(prefix: str, source: Path) -> str:
    return "%s.%s" % (prefix, safe_name(str(source).lstrip("/")))


def trace_pm_filter(format_text: Optional[str]) -> Optional[str]:
    if not format_text or not re.search(r"\bdevice\b", format_text):
        return None
    return 'device ~ ".*ufs.*"'


def parse_clock_file(source: Path) -> Optional[Dict[str, Any]]:
    data = read_bytes(source)
    if data is None:
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None


def number(value: Any) -> Optional[float]:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and re.fullmatch(r"-?[0-9]+(?:\.[0-9]+)?", value.strip()):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


def int_number(value: Any) -> Optional[int]:
    parsed = number(value)
    return int(parsed) if parsed is not None and parsed.is_integer() else None


def difference(after: Any, before: Any) -> Optional[float]:
    after_number = number(after)
    before_number = number(before)
    if after_number is None or before_number is None:
        return None
    return after_number - before_number


def list_sorted_cpu_paths(root: Path) -> List[Path]:
    values = [item for item in root.glob("cpu[0-9]*") if item.is_dir()]
    return sorted(values, key=lambda item: int(re.search(r"[0-9]+$", item.name).group(0)))


class DeviceRun:
    def __init__(self, root: Path, run_id: str):
        validate_run_id(run_id)
        self.root = root
        self.run_id = run_id
        self.run_dir = root / "runs" / run_id

    @property
    def status_file(self) -> Path:
        return self.run_dir / "status.json"

    @property
    def config_file(self) -> Path:
        return self.run_dir / "config.json"

    def create(self, config: Dict[str, Any]) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        with contextlib.suppress(OSError):
            os.chmod(self.root, 0o700)
        (self.root / "runs").mkdir(parents=True, exist_ok=True)
        with contextlib.suppress(OSError):
            os.chmod(self.root / "runs", 0o700)
        try:
            self.run_dir.mkdir(mode=0o700)
        except FileExistsError as exc:
            raise LabError("run directory already exists; run IDs are immutable: %s" % self.run_id) from exc
        for name in ("pre", "post", "raw", "derived", "cleanup", "meta"):
            (self.run_dir / name).mkdir(mode=0o700)
        write_json(self.config_file, config)
        self.update_status(
            state="created",
            run_id=self.run_id,
            created_at=utc_now(),
            unit=config.get("unit"),
        )

    def load_config(self) -> Dict[str, Any]:
        data = read_bytes(self.config_file)
        if data is None:
            raise LabError("missing run configuration: %s" % self.config_file)
        return json.loads(data.decode("utf-8"))

    def load_status(self) -> Dict[str, Any]:
        data = read_bytes(self.status_file)
        if data is None:
            raise LabError("missing run status: %s" % self.status_file)
        return json.loads(data.decode("utf-8"))

    def update_status(self, **changes: Any) -> Dict[str, Any]:
        current: Dict[str, Any] = {}
        if self.status_file.exists():
            try:
                current = self.load_status()
            except (LabError, ValueError, UnicodeDecodeError):
                current = {}
        current.update(changes)
        current["updated_at"] = utc_now()
        write_json(self.status_file, current)
        return current

    def log(self, message: str) -> None:
        with open(self.run_dir / "raw" / "agent.log", "a", encoding="utf-8") as handle:
            handle.write("%s %s\n" % (utc_now(), message))


def record_command(run: DeviceRun, name: str, result: CommandResult) -> None:
    destination = run.run_dir / "raw" / "commands" / safe_name(name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    atomic_write_bytes(destination.with_suffix(".stdout"), result.stdout)
    atomic_write_bytes(destination.with_suffix(".stderr"), result.stderr)
    write_json(destination.with_suffix(".json"), result.as_json())


def capture_command(
    run: DeviceRun,
    name: str,
    command: Sequence[str],
    *,
    env: Optional[Dict[str, str]] = None,
    timeout: Optional[float] = 30,
    input_bytes: Optional[bytes] = None,
) -> CommandResult:
    result = run_command(command, env=env, timeout=timeout, input_bytes=input_bytes)
    record_command(run, name, result)
    return result


def snapshot_file(run: DeviceRun, phase: str, source: Path, relative: Optional[str] = None) -> bool:
    data = read_bytes(source)
    if data is None:
        missing = run.run_dir / phase / "missing.tsv"
        with open(missing, "a", encoding="utf-8") as handle:
            handle.write("%s\tunreadable\n" % source)
        return False
    relative_name = relative or str(source).lstrip("/")
    destination = run.run_dir / phase / "files" / relative_name
    atomic_write_bytes(destination, data)
    return True


def tracefs_root() -> Optional[Path]:
    for candidate in TRACEFS_DIRS:
        root = Path(candidate)
        if root.is_dir() and (root / "instances").is_dir():
            return root
    return None


def trace_capture_file(run: DeviceRun, label: str, source: Path) -> Dict[str, Any]:
    data = read_bytes(source)
    result: Dict[str, Any] = {
        "path": str(source),
        "available": data is not None,
    }
    if data is None:
        return result
    destination = run.run_dir / "raw" / "trace" / label
    atomic_write_bytes(destination, data)
    result.update(
        {
            "archive_path": str(destination.relative_to(run.run_dir)),
            "bytes": len(data),
        }
    )
    return result


def trace_instance_from_info(run: DeviceRun, info: Dict[str, Any]) -> Optional[Path]:
    instance_value = info.get("instance")
    root_value = info.get("root")
    if not isinstance(instance_value, str) or not isinstance(root_value, str):
        return None
    try:
        root = Path(root_value).resolve()
        instance = Path(instance_value).resolve()
    except OSError:
        return None
    expected_name = "sm8550-suspend-lab-%s" % run.run_id
    if instance.parent != (root / "instances").resolve() or instance.name != expected_name:
        return None
    return instance


def trace_control_snapshot(run: DeviceRun, info: Dict[str, Any], prefix: str) -> Dict[str, Any]:
    instance = trace_instance_from_info(run, info)
    if instance is None:
        return {}
    controls = (
        "trace_clock",
        "buffer_size_kb",
        "buffer_total_size_kb",
        "current_tracer",
        "tracing_on",
    )
    captured: Dict[str, Any] = {}
    for name in controls:
        source = instance / name
        captured[name] = trace_capture_file(run, "controls/%s.%s" % (prefix, name), source)
    info.setdefault("control_snapshots", {})[prefix] = captured
    return captured


def trace_optional_event_error(info: Dict[str, Any], event: str, exc: BaseException) -> None:
    info.setdefault("optional_event_errors", []).append(
        {
            "event": event,
            "error_type": type(exc).__name__,
            "error": str(exc),
        }
    )


def trace_configure_event(
    run: DeviceRun,
    info: Dict[str, Any],
    event: str,
    *,
    event_filter: Optional[str] = None,
) -> Dict[str, Any]:
    instance = trace_instance_from_info(run, info)
    if instance is None:
        raise LabError("trace instance ownership validation failed")
    event_dir = trace_event_file(instance, event, "enable").parent
    if not event_dir.is_dir():
        raise LabError("trace event is not present in the new instance: %s" % event)
    event_info: Dict[str, Any] = {
        "event": event,
        "event_dir": str(event_dir),
        "format": trace_capture_file(
            run,
            "formats/%s.format" % safe_name(event.replace(":", "__")),
            event_dir / "format",
        ),
    }
    filter_path = event_dir / "filter"
    enable_path = event_dir / "enable"
    event_info["filter_before"] = trace_capture_file(
        run,
        "controls/%s.filter.before" % safe_name(event.replace(":", "__")),
        filter_path,
    )
    if event_filter is not None:
        write_kernel_control(filter_path, event_filter + "\n")
        filter_after = read_text(filter_path)
        if filter_after is None or filter_after.strip() != event_filter.strip():
            raise LabError("trace filter was not retained for %s" % event)
        event_info["filter"] = event_filter
    else:
        event_info["filter"] = None
    event_info["filter_after"] = trace_capture_file(
        run,
        "controls/%s.filter.after" % safe_name(event.replace(":", "__")),
        filter_path,
    )
    event_info["enable_before"] = trace_capture_file(
        run,
        "controls/%s.enable.before" % safe_name(event.replace(":", "__")),
        enable_path,
    )
    write_kernel_control(enable_path, "1\n")
    enabled = read_text(enable_path)
    if enabled is None or enabled.strip() != "1":
        raise LabError("trace event did not enable: %s" % event)
    event_info["enable_after"] = trace_capture_file(
        run,
        "controls/%s.enable.after" % safe_name(event.replace(":", "__")),
        enable_path,
    )
    return event_info


def trace_prepare(run: DeviceRun, profile: str) -> Dict[str, Any]:
    if profile not in TRACE_PROFILE_CHOICES:
        raise LabError("unsupported trace profile: %s" % profile)
    if profile == "none":
        info = {
            "profile": "none",
            "enabled": False,
            "state": "disabled",
            "created_at": utc_now(),
        }
        write_json(run.run_dir / "meta" / "trace.json", info)
        return info

    root = tracefs_root()
    if root is None:
        raise LabError("tracefs with an instances directory is unavailable")
    available_source = root / "available_events"
    available_bytes = read_bytes(available_source)
    if available_bytes is None:
        raise LabError("tracefs available_events is unreadable")
    available_text = available_bytes.decode("utf-8", errors="replace")
    available = parse_trace_events(available_text)
    required_events = (
        TRACE_REQUIRED_EVENTS
        if profile == "ufs-irq"
        else TRACE_RPMH_SUCCESS_REQUIRED_EVENTS
        if profile == "rsc-success"
        else TRACE_RPMH_REQUIRED_EVENTS
        if profile == "rpmh-aoss"
        else ()
    )
    missing = [event for event in required_events if event not in available]
    instance = root / "instances" / ("sm8550-suspend-lab-%s" % run.run_id)
    info: Dict[str, Any] = {
        "profile": profile,
        "enabled": True,
        "state": "creating",
        "root": str(root),
        "instance": str(instance),
        "created_at": utc_now(),
        "available_events_count": len(available),
        "required_events": list(required_events),
        "missing_required_events": missing,
        "selected_events": [],
        "optional_event_errors": [],
        "raw_available_events": trace_capture_file(run, "available_events.txt", available_source),
    }
    write_json(run.run_dir / "meta" / "trace.json", info)
    if instance.exists():
        info["state"] = "refused-existing-instance"
        write_json(run.run_dir / "meta" / "trace.json", info)
        raise LabError("run-scoped trace instance already exists: %s" % instance)
    if missing:
        info["state"] = "missing-required-events"
        write_json(run.run_dir / "meta" / "trace.json", info)
        raise LabError("tracefs is missing required IRQ handler events: %s" % ", ".join(missing))
    try:
        instance.mkdir()
        info["state"] = "created"
        trace_control_snapshot(run, info, "before")
        write_kernel_control(instance / "tracing_on", "0\n")
        if (read_text(instance / "tracing_on") or "").strip() != "0":
            raise LabError("new trace instance could not be held stopped during setup")
        trace_control_snapshot(run, info, "prepared")

        if profile == "ufs-irq":
            irq_entry = trace_configure_event(
                run,
                info,
                "irq:irq_handler_entry",
                event_filter="irq == %d" % TRACE_IRQ_NUMBER,
            )
            irq_exit = trace_configure_event(
                run,
                info,
                "irq:irq_handler_exit",
                event_filter="irq == %d" % TRACE_IRQ_NUMBER,
            )
            info["selected_events"].extend([irq_entry, irq_exit])

            for event in TRACE_PM_EVENTS:
                if event not in available:
                    info.setdefault("optional_unavailable_events", []).append(event)
                    continue
                format_text = read_text(trace_event_file(instance, event, "format"))
                event_filter = trace_pm_filter(format_text)
                try:
                    configured = trace_configure_event(run, info, event, event_filter=event_filter)
                    if event_filter is None:
                        configured["focus_note"] = "enabled without a device filter; retain only UFS paths during analysis"
                    info["selected_events"].append(configured)
                except BaseException as exc:
                    trace_optional_event_error(info, event, exc)
                    with contextlib.suppress(OSError):
                        write_kernel_control(trace_event_file(instance, event, "enable"), "0\n")

            ufs_events = [
                event
                for event in available
                if re.match(r"(?i)^(?:ufs|ufshcd):", event)
                and re.search(r"(?i)(command|request|runtime|pm|hibern|exception|error|uic|clock)", event)
            ]
            if not ufs_events:
                ufs_events = [
                    event
                    for event in available
                    if event in (
                        "scsi:scsi_dispatch_cmd_start",
                        "scsi:scsi_dispatch_cmd_done",
                        "scsi:scsi_dispatch_cmd_error",
                    )
                ]
                info["ufs_event_fallback"] = "standard SCSI dispatch tracepoints"
            info["candidate_ufs_request_events"] = ufs_events
            for event in ufs_events:
                try:
                    info["selected_events"].append(trace_configure_event(run, info, event))
                except BaseException as exc:
                    trace_optional_event_error(info, event, exc)
                    with contextlib.suppress(OSError):
                        write_kernel_control(trace_event_file(instance, event, "enable"), "0\n")
        else:
            profile_events = list(required_events) + list(TRACE_RPMH_OPTIONAL_EVENTS)
            info["candidate_rpmh_events"] = profile_events
            for event in profile_events:
                if event not in available:
                    info.setdefault("optional_unavailable_events", []).append(event)
                    continue
                try:
                    info["selected_events"].append(trace_configure_event(run, info, event))
                except BaseException as exc:
                    if event in required_events:
                        raise
                    trace_optional_event_error(info, event, exc)
                    with contextlib.suppress(OSError):
                        write_kernel_control(trace_event_file(instance, event, "enable"), "0\n")
        info["state"] = "ready"
        write_json(run.run_dir / "meta" / "trace.json", info)
        return info
    except BaseException as exc:
        info["state"] = "prepare-failed"
        info["error_type"] = type(exc).__name__
        info["error"] = str(exc)
        write_json(run.run_dir / "meta" / "trace.json", info)
        trace_remove_instance(run, info)
        raise


def trace_start(run: DeviceRun) -> Dict[str, Any]:
    info = read_phase_json(run, "meta", "trace.json", {})
    if info.get("profile") == "none":
        return info
    if info.get("state") != "ready":
        raise LabError("trace profile is not ready: %s" % info.get("state"))
    instance = trace_instance_from_info(run, info)
    if instance is None or not instance.is_dir():
        raise LabError("trace instance disappeared before suspend")
    tracing_on = instance / "tracing_on"
    write_kernel_control(tracing_on, "1\n")
    if (read_text(tracing_on) or "").strip() != "1":
        raise LabError("trace instance did not start")
    marker = instance / "trace_marker"
    marker_result: Dict[str, Any] = {"path": str(marker), "written": False}
    try:
        write_kernel_control(marker, "sm8550-suspend-lab run=%s phase=before-dispatch\n" % run.run_id)
        marker_result["written"] = True
    except OSError as exc:
        marker_result["error"] = str(exc)
    info["state"] = "running"
    info["started_at"] = utc_now()
    info["marker"] = marker_result
    trace_control_snapshot(run, info, "started")
    write_json(run.run_dir / "meta" / "trace.json", info)
    return info


def trace_stop(run: DeviceRun) -> Dict[str, Any]:
    info = read_phase_json(run, "meta", "trace.json", {})
    if info.get("profile") == "none" or info.get("state") in ("disabled", "cleaned", "stopped"):
        return info
    instance = trace_instance_from_info(run, info)
    if instance is None or not instance.is_dir():
        info["state"] = "instance-missing"
        info["stopped_at"] = utc_now()
        write_json(run.run_dir / "meta" / "trace.json", info)
        return info
    actions: List[Dict[str, Any]] = []
    try:
        write_kernel_control(instance / "tracing_on", "0\n")
        actions.append({"path": str(instance / "tracing_on"), "result": "disabled"})
    except OSError as exc:
        actions.append({"path": str(instance / "tracing_on"), "result": "failed", "error": str(exc)})
    trace_control_snapshot(run, info, "stopped")
    trace_files: Dict[str, Any] = {}
    for name in ("trace", "trace_stat", "buffer_total_size_kb", "buffer_size_kb"):
        trace_files[name] = trace_capture_file(run, "%s.txt" % name, instance / name)
    per_cpu = instance / "per_cpu"
    if per_cpu.is_dir():
        for cpu in sorted(per_cpu.glob("cpu*")):
            if not cpu.is_dir():
                continue
            trace_files["%s/stats" % cpu.name] = trace_capture_file(
                run,
                "per_cpu/%s.stats" % cpu.name,
                cpu / "stats",
            )
    info["trace_files"] = trace_files
    info["stop_actions"] = actions
    info["tracing_on_after_stop"] = read_text(instance / "tracing_on")
    info["stopped_at"] = utc_now()
    info["state"] = "stopped" if (info["tracing_on_after_stop"] or "").strip() == "0" else "stop-failed"
    write_json(run.run_dir / "meta" / "trace.json", info)
    return info


def trace_remove_instance(run: DeviceRun, info: Dict[str, Any]) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    if info.get("profile") == "none":
        return actions
    instance = trace_instance_from_info(run, info)
    if instance is None:
        actions.append({"result": "refused-unowned-instance", "instance": info.get("instance")})
        return actions
    if not instance.exists():
        actions.append({"result": "already-absent", "instance": str(instance)})
        return actions
    with contextlib.suppress(OSError):
        write_kernel_control(instance / "tracing_on", "0\n")
    for selected in info.get("selected_events", []):
        event = selected.get("event") if isinstance(selected, dict) else None
        if not event:
            continue
        try:
            write_kernel_control(trace_event_file(instance, event, "enable"), "0\n")
            actions.append({"event": event, "result": "disabled"})
        except OSError as exc:
            actions.append({"event": event, "result": "disable-failed", "error": str(exc)})
    try:
        instance.rmdir()
        actions.append({"result": "instance-removed", "instance": str(instance)})
    except OSError as exc:
        actions.append({"result": "instance-remove-failed", "instance": str(instance), "error": str(exc)})
    return actions


def trace_cleanup(run: DeviceRun) -> Dict[str, Any]:
    info = read_phase_json(run, "meta", "trace.json", {})
    if info.get("profile") == "none":
        result = {"changed": False, "profile": "none"}
        write_json(run.run_dir / "cleanup" / "trace.json", result)
        return result
    if info.get("state") not in ("stopped", "cleaned", "instance-missing"):
        info = trace_stop(run)
    actions = trace_remove_instance(run, info)
    if any(action.get("result") == "instance-removed" for action in actions):
        info["state"] = "cleaned"
        write_json(run.run_dir / "meta" / "trace.json", info)
    result = {
        "changed": True,
        "profile": info.get("profile"),
        "state": info.get("state"),
        "actions": actions,
    }
    write_json(run.run_dir / "cleanup" / "trace.json", result)
    return result


def binary_strings(source: Path) -> List[str]:
    data = read_bytes(source)
    if data is None:
        return []
    return [part.decode("utf-8", errors="replace") for part in data.split(b"\0") if part]


def selected_mem_sleep(raw: Optional[str]) -> Optional[str]:
    if not raw:
        return None
    match = re.search(r"\[([^]]+)\]", raw)
    return match.group(1) if match else None


def clock_separation_state(seconds: Optional[float]) -> str:
    if seconds is None:
        return "unavailable"
    if seconds < -MIN_CLOCK_PROVEN_SUSPEND_SECONDS:
        return "negative"
    if seconds < MIN_CLOCK_PROVEN_SUSPEND_SECONDS:
        return "unexpectedly_absent"
    return "observed"


def expected_wake_text_matches(text: Optional[str], expected: Optional[str]) -> bool:
    """Match one wake-source/IRQ field to the requested source.

    The expected RTC is recorded as rtc0, while kernel IRQ and wakeup-source
    names commonly contain a longer device path such as pm8xxx_rtc_alarm or
    ...rtc@6100. Match within the individual field only; never concatenate
    unrelated fields before deciding that a wake source matched.
    """
    if not text or not expected:
        return False
    haystack = text.lower()
    needle = expected.lower()
    if needle in haystack:
        return True
    short_needle = re.sub(r"[0-9]+$", "", needle)
    return len(short_needle) >= 3 and short_needle in haystack


def find_command(name: str) -> Optional[str]:
    for candidate in (name, "/usr/bin/" + name, "/usr/libexec/armada/" + name):
        if os.path.isabs(candidate) and os.access(candidate, os.X_OK):
            return candidate
        if not os.path.isabs(candidate):
            resolved = shutil.which(candidate)
            if resolved:
                return resolved
    return None


def capture_provenance(run: DeviceRun, phase: str, system: Dict[str, Any]) -> None:
    provenance: Dict[str, Any] = {
        "captured_at": utc_now(),
        "kernel_release": system.get("kernel_release"),
        "armada_version_file": read_text(Path("/usr/lib/armada/version")),
        "module_releases": [],
    }
    for command_name, command in (
        ("uname-a", ["uname", "-a"]),
        ("cat-proc-version", ["cat", "/proc/version"]),
        ("os-release", ["cat", "/etc/os-release"]),
        ("bootc-status-json", ["bootc", "status", "--json"]),
        (
            "rpm-packages",
            ["rpm", "-qa", "--qf", "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\\n"],
        ),
        ("findmnt-root", ["findmnt", "-no", "SOURCE,TARGET,FSTYPE,OPTIONS", "/"]),
        ("lsblk-f", ["lsblk", "-o", "NAME,PATH,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS,UUID"]),
    ):
        result = capture_command(run, "provenance-" + command_name, command, timeout=45)
        provenance[command_name] = result.as_json()
        if command_name == "rpm-packages":
            packages = result.stdout.decode("utf-8", errors="replace").splitlines()
            provenance["kernel_packages"] = [line for line in packages if "kernel" in line.lower()]
    for source in (
        Path("/etc/os-release"),
        Path("/usr/lib/armada/version"),
        Path("/usr/lib/armada/bootimg-args"),
    ):
        snapshot_file(run, phase, source)
    modules = Path("/usr/lib/modules")
    if modules.is_dir():
        for module_dir in sorted(item for item in modules.iterdir() if item.is_dir()):
            provenance["module_releases"].append(module_dir.name)
            module_provenance = module_dir / "PROVENANCE"
            if module_provenance.is_file():
                snapshot_file(
                    run,
                    phase,
                    module_provenance,
                    "usr/lib/modules/%s/PROVENANCE" % module_dir.name,
                )
    write_json(run.run_dir / phase / "provenance.json", provenance)


def capture_sleep_configuration(run: DeviceRun, phase: str) -> List[str]:
    sources: List[Path] = []
    for candidate in (
        Path("/etc/systemd/sleep.conf"),
        Path("/etc/systemd/sleep.conf.d"),
        Path("/run/systemd/sleep.conf.d"),
        Path("/usr/lib/systemd/sleep.conf.d"),
    ):
        if candidate.is_file():
            sources.append(candidate)
        elif candidate.is_dir():
            sources.extend(sorted(item for item in candidate.iterdir() if item.is_file()))
    copied: List[str] = []
    for source in sources:
        if snapshot_file(run, phase, source):
            copied.append(str(source))
    write_json(run.run_dir / phase / "sleep-configuration.json", copied)
    return copied


def capture_systemd_sleep_hooks(run: DeviceRun, phase: str) -> Dict[str, str]:
    hooks: Dict[str, str] = {}
    for directory in (Path("/etc/systemd/system-sleep"), Path("/usr/lib/systemd/system-sleep")):
        if not directory.is_dir():
            continue
        for source in sorted(item for item in directory.iterdir() if item.is_file()):
            data = read_bytes(source)
            if data is None:
                continue
            hooks[str(source)] = hashlib.sha256(data).hexdigest()
            snapshot_file(run, phase, source)
    write_json(run.run_dir / phase / "systemd-sleep-hooks.json", hooks)
    return hooks


def capture_system(run: DeviceRun, phase: str) -> Dict[str, Any]:
    proc = Path("/proc")
    sys_root = Path("/sys")
    model_source = sys_root / "firmware/devicetree/base/model"
    compatible_source = sys_root / "firmware/devicetree/base/compatible"
    if not model_source.exists():
        model_source = proc / "device-tree/model"
    if not compatible_source.exists():
        compatible_source = proc / "device-tree/compatible"
    mem_sleep = read_text(sys_root / "power/mem_sleep")
    cmdline = read_text(proc / "cmdline")
    boot_id = read_text(proc / "sys/kernel/random/boot_id")
    system: Dict[str, Any] = {
        "captured_at": utc_now(),
        "kernel_release": read_text(proc / "sys/kernel/osrelease"),
        "kernel_version": read_text(proc / "version"),
        "armada_version_file": read_text(Path("/usr/lib/armada/version")),
        "lab_agent_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "boot_id": boot_id,
        "cmdline": cmdline,
        "dt_model": binary_strings(model_source),
        "dt_compatible": binary_strings(compatible_source),
        "mem_sleep_raw": mem_sleep,
        "mem_sleep_selected": selected_mem_sleep(mem_sleep),
        "power_state_raw": read_text(sys_root / "power/state"),
        "sleep_config": read_text(Path("/etc/armada/sleep.conf")),
        "uptime_raw": read_text(proc / "uptime"),
        "pm_wakeup_irq": numeric_or_text(read_text(sys_root / "power/pm_wakeup_irq")),
    }
    sleep_configuration = capture_sleep_configuration(run, phase)
    system["systemd_sleep_configuration_files"] = sleep_configuration
    system["systemd_sleep_hooks"] = capture_systemd_sleep_hooks(run, phase)
    for source in (
        proc / "cmdline",
        proc / "sys/kernel/random/boot_id",
        proc / "uptime",
        sys_root / "power/mem_sleep",
        sys_root / "power/state",
        sys_root / "power/pm_wakeup_irq",
        model_source,
        compatible_source,
        Path("/etc/armada/sleep.conf"),
    ):
        snapshot_file(run, phase, source)
    device_env = find_command("device-env")
    if device_env:
        result = capture_command(run, "device-env-" + phase, [device_env], timeout=15)
        system["device_env_raw"] = result.stdout.decode("utf-8", errors="replace")
        system["device_env"] = parse_shell_assignments(system["device_env_raw"])
        system["device_env_command"] = result.as_json()
    else:
        system["device_env_raw"] = None
        system["device_env"] = {}
        system["device_env_command"] = {"returncode": 127, "missing": True}
    systemd_unit = capture_command(run, "systemd-suspend-unit-" + phase, ["systemctl", "cat", "systemd-suspend.service"], timeout=15)
    system["systemd_suspend_unit_command"] = systemd_unit.as_json()
    system["systemd_suspend_unit_raw"] = systemd_unit.stdout.decode("utf-8", errors="replace")
    capture_provenance(run, phase, system)
    write_json(run.run_dir / phase / "system.json", system)
    return system


def capture_suspend_stats(run: DeviceRun, phase: str) -> Dict[str, Any]:
    directory = Path("/sys/power/suspend_stats")
    values: Dict[str, Any] = {}
    if directory.is_dir():
        for source in sorted(directory.iterdir()):
            if not source.is_file():
                continue
            value = read_text(source)
            values[source.name] = numeric_or_text(value)
            snapshot_file(run, phase, source)
    write_json(run.run_dir / phase / "suspend_stats.json", values)
    return values


def capture_qcom_stats(run: DeviceRun, phase: str) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for directory_name in QCOM_STAT_DIRS:
        directory = Path(directory_name)
        if not directory.is_dir():
            continue
        namespace = directory.name
        entries: Dict[str, Any] = {}
        for source in sorted(directory.iterdir()):
            if not source.is_file():
                continue
            text = read_text(source) or ""
            entries[source.name] = parse_qcom_stat(text)
            entries[source.name]["raw"] = text
            relative = str(source).lstrip("/")
            snapshot_file(run, phase, source, relative)
        result[namespace] = entries
    write_json(run.run_dir / phase / "qcom_stats.json", result)
    return result


def capture_cpuidle(run: DeviceRun, phase: str) -> List[Dict[str, Any]]:
    root = Path("/sys/devices/system/cpu")
    entries: List[Dict[str, Any]] = []
    for cpu in list_sorted_cpu_paths(root):
        cpuidle = cpu / "cpuidle"
        if not cpuidle.is_dir():
            continue
        states = sorted(
            (item for item in cpuidle.glob("state[0-9]*") if item.is_dir()),
            key=lambda item: int(re.search(r"[0-9]+$", item.name).group(0)),
        )
        for state in states:
            entry: Dict[str, Any] = {
                "cpu": cpu.name,
                "state": state.name,
            }
            for field in CPUIDLE_FIELDS:
                source = state / field
                value = read_text(source)
                entry[field] = numeric_or_text(value)
                if source.is_file():
                    snapshot_file(run, phase, source)
            s2idle: Dict[str, Any] = {}
            for field in ("usage", "time"):
                source = state / "s2idle" / field
                value = read_text(source)
                s2idle[field] = numeric_or_text(value)
                if source.is_file():
                    snapshot_file(run, phase, source)
            entry["s2idle"] = s2idle
            entries.append(entry)
    write_json(run.run_dir / phase / "cpuidle.json", entries)
    return entries


def capture_interrupts(run: DeviceRun, phase: str) -> Dict[str, Dict[str, Any]]:
    source = Path("/proc/interrupts")
    text = read_text(source) or ""
    snapshot_file(run, phase, source)
    parsed = parse_interrupts(text)
    write_json(run.run_dir / phase / "interrupts.json", parsed)
    return parsed


def capture_wakeup_sources(run: DeviceRun, phase: str) -> Dict[str, Dict[str, Any]]:
    source = Path("/sys/kernel/debug/wakeup_sources")
    text = read_text(source)
    if text is None:
        parsed: Dict[str, Dict[str, Any]] = {}
    else:
        snapshot_file(run, phase, source)
        parsed = parse_wakeup_sources(text)
    write_json(run.run_dir / phase / "wakeup_sources.json", parsed)
    return parsed


def classify_runtime_device(identity: str) -> str:
    lowered = identity.lower()
    if "dwc3" in lowered or ".usb" in lowered:
        return "dwc3-usb"
    if "phy" in lowered:
        return "usb-phy"
    if "ufs" in lowered or "ufshc" in lowered:
        return "ufs"
    if "mmc" in lowered or "sdhci" in lowered:
        return "mmc-sdhci"
    if "pcie" in lowered or "pci" in lowered:
        return "pcie"
    if "ath12k" in lowered or "wlan" in lowered:
        return "wlan-ath12k"
    if "bluetooth" in lowered or re.search(r"(^|[/_.-])bt([/_.-]|$)", lowered):
        return "bluetooth"
    if "remoteproc" in lowered or "rproc" in lowered:
        return "remoteproc"
    return "other"


def runtime_record(run: DeviceRun, phase: str, device: Path) -> Optional[Dict[str, Any]]:
    identity = str(device)
    fields: Dict[str, Any] = {}
    for field in RUNTIME_FIELDS:
        source = device / "power" / field
        value = read_text(source)
        if value is not None:
            fields[field] = numeric_or_text(value)
            snapshot_file(run, phase, source)
    for field in ("modalias", "uevent", "state", "operstate", "address", "carrier"):
        source = device / field
        value = read_text(source)
        if value is not None:
            fields[field] = numeric_or_text(value)
            snapshot_file(run, phase, source)
    if not fields:
        return None
    driver = None
    try:
        driver = os.path.realpath(device / "driver") if (device / "driver").exists() else None
    except OSError:
        driver = None
    return {
        "path": identity,
        "realpath": os.path.realpath(device),
        "name": device.name,
        "category": classify_runtime_device(identity),
        "driver": driver,
        "fields": fields,
    }


def capture_runtime_pm(run: DeviceRun, phase: str) -> Dict[str, Any]:
    records: List[Dict[str, Any]] = []
    seen: set = set()
    roots = [Path("/sys/devices"), Path("/sys/bus/usb/devices")]
    for root in roots:
        if not root.is_dir():
            continue
        for directory, dirnames, _filenames in os.walk(root, followlinks=False):
            dirnames[:] = [name for name in dirnames if name not in ("power", "subsystem", "driver")]
            device = Path(directory)
            identity = str(device).lower()
            if not any(keyword in identity for keyword in RUNTIME_KEYWORDS):
                continue
            realpath = os.path.realpath(device)
            if realpath in seen:
                continue
            record = runtime_record(run, phase, device)
            if record is not None:
                seen.add(realpath)
                records.append(record)
    class_records: List[Dict[str, Any]] = []
    for class_name in ("remoteproc", "bluetooth", "net", "phy", "rfkill", "typec", "usb_role"):
        directory = Path("/sys/class") / class_name
        if not directory.is_dir():
            continue
        for device in sorted(directory.iterdir()):
            record = runtime_record(run, phase, device)
            if record is not None:
                record["class"] = class_name
                class_records.append(record)
    result = {"devices": records, "class_entries": class_records}
    write_json(run.run_dir / phase / "runtime_pm.json", result)
    return result


def capture_power_supplies(run: DeviceRun, phase: str) -> Dict[str, Any]:
    supplies: Dict[str, Any] = {}
    directory = Path("/sys/class/power_supply")
    if directory.is_dir():
        for supply in sorted(directory.iterdir()):
            if not supply.is_dir():
                continue
            values: Dict[str, Any] = {}
            uevent = read_text(supply / "uevent")
            if uevent is not None:
                values["uevent"] = uevent
                snapshot_file(run, phase, supply / "uevent")
            for field in POWER_FIELDS:
                source = supply / field
                value = read_text(source)
                if value is None:
                    continue
                values[field] = numeric_or_text(value)
                snapshot_file(run, phase, source)
            supplies[supply.name] = values
    write_json(run.run_dir / phase / "power_supplies.json", supplies)
    return supplies


def capture_audio(run: DeviceRun, phase: str, qcom_stats: Dict[str, Any]) -> Dict[str, Any]:
    open_pcm: List[Dict[str, Any]] = []
    asound = Path("/proc/asound")
    if asound.is_dir():
        for directory, _dirnames, filenames in os.walk(asound, followlinks=False):
            for filename in filenames:
                if filename not in ("status", "hw_params", "info"):
                    continue
                source = Path(directory) / filename
                value = read_text(source)
                if value is None:
                    continue
                snapshot_file(run, phase, source)
                if filename == "status" and value.splitlines()[0:1] != ["closed"]:
                    open_pcm.append({"path": str(source), "state": value.splitlines()[0] if value else ""})
    dapm: List[Dict[str, Any]] = []
    asoc = Path("/sys/kernel/debug/asoc")
    if asoc.is_dir():
        for source in asoc.glob("**/bias_level"):
            value = read_text(source)
            if value is None:
                continue
            snapshot_file(run, phase, source)
            dapm.append({"path": str(source), "bias_level": value})
    adsp: Dict[str, Any] = {}
    for namespace, entries in qcom_stats.items():
        if "adsp" in entries:
            adsp[namespace] = entries["adsp"]
    result = {"open_pcm": open_pcm, "dapm_bias": dapm, "adsp_qcom_stats": adsp}
    write_json(run.run_dir / phase / "audio.json", result)
    return result


def capture_regulator_and_clock_summaries(run: DeviceRun, phase: str) -> Dict[str, Any]:
    candidates = (
        Path("/sys/kernel/debug/regulator/regulator_summary"),
        Path("/sys/kernel/debug/regulator_summary"),
        Path("/sys/kernel/debug/clk/clk_summary"),
        Path("/sys/kernel/debug/clk_summary"),
        Path("/sys/kernel/debug/interconnect/interconnect_summary"),
        Path("/sys/kernel/debug/interconnect/interconnect_graph"),
        Path("/sys/kernel/debug/pm_genpd/pm_genpd_summary"),
        Path("/sys/kernel/debug/cmd-db"),
    )
    result: Dict[str, Any] = {}
    for source in candidates:
        value = read_text(source)
        if value is None:
            continue
        if "regulator" in source.name or "regulator" in str(source.parent):
            key = "regulator_summary"
        elif source.name == "clk_summary":
            key = "clk_summary"
        elif source.name == "interconnect_summary":
            key = "interconnect_summary"
        elif source.name == "interconnect_graph":
            key = "interconnect_graph"
        elif source.name == "pm_genpd_summary":
            key = "pm_genpd_summary"
        elif source.name == "cmd-db":
            key = "cmd_db"
        else:
            continue
        entry: Dict[str, Any] = {
            "path": str(source),
            "available": True,
            "bytes": len(value.encode("utf-8")),
        }
        if key == "cmd_db":
            entry["parsed"] = parse_cmd_db_dump(value)
        elif key == "interconnect_summary":
            entry["parsed"] = parse_interconnect_summary(value)
        elif key == "interconnect_graph":
            entry["parsed"] = parse_interconnect_graph(value)
        elif key == "pm_genpd_summary":
            entry["parsed"] = parse_pm_genpd_summary(value)
        result[key] = entry
        snapshot_file(run, phase, source)
    for key in (
        "regulator_summary",
        "clk_summary",
        "interconnect_summary",
        "interconnect_graph",
        "pm_genpd_summary",
        "cmd_db",
    ):
        result.setdefault(key, {"available": False})
    write_json(run.run_dir / phase / "regulator-clock-summaries.json", result)
    return result


def capture_input_and_display(run: DeviceRun, phase: str) -> Dict[str, Any]:
    inputs: List[Dict[str, Any]] = []
    input_root = Path("/sys/class/input")
    if input_root.is_dir():
        for event in sorted(input_root.glob("event*")):
            name = read_text(event / "device/name")
            if name is None:
                continue
            inputs.append({"event": event.name, "name": name})
            snapshot_file(run, phase, event / "device/name")
    displays: List[Dict[str, Any]] = []
    drm_root = Path("/sys/class/drm")
    if drm_root.is_dir():
        for connector in sorted(drm_root.iterdir()):
            if not connector.is_dir():
                continue
            values: Dict[str, Any] = {"connector": connector.name}
            for field in ("status", "enabled", "dpms", "modes"):
                value = read_text(connector / field)
                if value is None:
                    continue
                values[field] = value
                snapshot_file(run, phase, connector / field)
            if len(values) > 1:
                displays.append(values)
    result = {"inputs": inputs, "displays": displays}
    write_json(run.run_dir / phase / "input-display.json", result)
    return result


def capture_thermal(run: DeviceRun, phase: str) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for zone in sorted(Path("/sys/class/thermal").glob("thermal_zone*")):
        if not zone.is_dir():
            continue
        record: Dict[str, Any] = {"zone": zone.name}
        for field in ("type", "temp", "mode", "policy"):
            value = read_text(zone / field)
            if value is None:
                continue
            record[field] = numeric_or_text(value)
            snapshot_file(run, phase, zone / field)
        if len(record) > 1:
            records.append(record)
    write_json(run.run_dir / phase / "thermal.json", records)
    return records


def capture_rtc(run: DeviceRun, phase: str) -> List[Dict[str, Any]]:
    records: List[Dict[str, Any]] = []
    for rtc in sorted(Path("/sys/class/rtc").glob("rtc*")):
        if not rtc.is_dir():
            continue
        record: Dict[str, Any] = {"name": rtc.name}
        for field in ("wakealarm", "hctosys", "name", "date", "time", "max_user_freq"):
            source = rtc / field
            value = read_text(source)
            if value is None:
                continue
            record[field] = numeric_or_text(value)
            snapshot_file(run, phase, source)
        wakeup = rtc / "device/power/wakeup"
        wakeup_value = read_text(wakeup)
        if wakeup_value is not None:
            record["device_power_wakeup"] = wakeup_value
            snapshot_file(run, phase, wakeup)
        if len(record) > 1:
            records.append(record)
    write_json(run.run_dir / phase / "rtc.json", records)
    return records


def parse_wifi_state(text: str) -> Optional[str]:
    value = text.strip().splitlines()[-1].strip() if text.strip() else ""
    return value if value in ("enabled", "disabled") else None


def parse_bluetooth_power(text: str) -> Optional[str]:
    match = re.search(r"^\s*Powered:\s+(yes|no)\s*$", text, re.MULTILINE)
    return match.group(1) if match else None


def parse_rfkill_state(text: str) -> Dict[str, Optional[str]]:
    soft = re.search(r"^\s*Soft blocked:\s+(yes|no)\s*$", text, re.MULTILINE)
    hard = re.search(r"^\s*Hard blocked:\s+(yes|no)\s*$", text, re.MULTILINE)
    return {"soft": soft.group(1) if soft else None, "hard": hard.group(1) if hard else None}


def capture_radio_state(run: DeviceRun, label: str = "before") -> Dict[str, Any]:
    wifi_result = capture_command(run, "radio-%s-wifi" % label, ["nmcli", "-t", "-f", "WIFI", "radio"], timeout=15)
    bluetooth_result = capture_command(run, "radio-%s-bluetooth" % label, ["bluetoothctl", "show"], timeout=20)
    rfkill_result = capture_command(run, "radio-%s-rfkill" % label, ["rfkill", "list", "bluetooth"], timeout=15)
    bluetooth_text = bluetooth_result.stdout.decode("utf-8", errors="replace")
    rfkill_text = rfkill_result.stdout.decode("utf-8", errors="replace")
    state = {
        "captured_at": utc_now(),
        "wifi": parse_wifi_state(wifi_result.stdout.decode("utf-8", errors="replace")),
        "bluetooth_powered": parse_bluetooth_power(bluetooth_text),
        "bluetooth_rfkill": parse_rfkill_state(rfkill_text),
        "commands": {
            "wifi": wifi_result.as_json(),
            "bluetooth": bluetooth_result.as_json(),
            "rfkill": rfkill_result.as_json(),
        },
    }
    write_json(run.run_dir / "meta" / ("radio-%s.json" % safe_name(label)), state)
    return state


def apply_radio_policy(run: DeviceRun, config: Dict[str, Any]) -> Dict[str, Any]:
    wifi_requested = config.get("wifi_state", "preserve")
    bluetooth_requested = config.get("bluetooth_state", "preserve")
    before = capture_radio_state(run, "before")
    actions: List[Dict[str, Any]] = []
    if wifi_requested != "preserve":
        current = before.get("wifi")
        desired = "enabled" if wifi_requested == "on" else "disabled"
        if current is None:
            raise LabError("cannot apply Wi-Fi policy because nmcli did not report a radio state")
        if current != desired:
            command_state = "on" if desired == "enabled" else "off"
            result = capture_command(run, "radio-apply-wifi-%s" % desired, ["nmcli", "radio", "wifi", command_state], timeout=30)
            actions.append({"radio": "wifi", "requested": desired, **result.as_json()})
            if result.returncode != 0:
                raise LabError("could not apply requested Wi-Fi state")
    if bluetooth_requested != "preserve":
        current_power = before.get("bluetooth_powered")
        rfkill = before.get("bluetooth_rfkill") or {}
        if current_power is None and rfkill.get("hard") is None:
            raise LabError("cannot apply Bluetooth policy because the adapter state is unavailable")
        desired = "on" if bluetooth_requested == "on" else "off"
        if desired == "off":
            if rfkill.get("hard") != "yes" and rfkill.get("soft") != "yes":
                result = capture_command(run, "radio-apply-bluetooth-block", ["rfkill", "block", "bluetooth"], timeout=20)
                actions.append({"radio": "bluetooth", "requested": desired, **result.as_json()})
                if result.returncode != 0:
                    raise LabError("could not block Bluetooth for the requested baseline")
        else:
            if rfkill.get("hard") == "yes":
                raise LabError("Bluetooth is hard-blocked and cannot be enabled for this run")
            if rfkill.get("soft") == "yes":
                result = capture_command(run, "radio-apply-bluetooth-unblock", ["rfkill", "unblock", "bluetooth"], timeout=20)
                actions.append({"radio": "bluetooth", "requested": desired, **result.as_json()})
                if result.returncode != 0:
                    raise LabError("could not unblock Bluetooth for the requested policy")
            result = capture_command(run, "radio-apply-bluetooth-power-on", ["bluetoothctl", "power", "on"], timeout=30)
            actions.append({"radio": "bluetooth", "requested": desired, **result.as_json()})
            if result.returncode != 0:
                raise LabError("could not power Bluetooth on for the requested policy")
    policy = {
        "wifi_requested": wifi_requested,
        "bluetooth_requested": bluetooth_requested,
        "before": before,
        "actions": actions,
    }
    write_json(run.run_dir / "meta" / "radio-policy.json", policy)
    return policy


def restore_radios(run: DeviceRun) -> Dict[str, Any]:
    data = read_bytes(run.run_dir / "meta/radio-policy.json")
    if data is None:
        return {"changed": False}
    policy = json.loads(data.decode("utf-8"))
    before = policy.get("before", {})
    current = capture_radio_state(run, "cleanup-current")
    actions: List[Dict[str, Any]] = []
    wifi_requested = policy.get("wifi_requested", "preserve")
    original_wifi = before.get("wifi")
    desired_wifi = "enabled" if wifi_requested == "on" else "disabled"
    if wifi_requested != "preserve" and original_wifi in ("enabled", "disabled") and original_wifi != desired_wifi:
        if current.get("wifi") != desired_wifi:
            actions.append({"radio": "wifi", "result": "conflict-left-unchanged", "current": current.get("wifi"), "expected": desired_wifi})
        else:
            result = capture_command(run, "radio-restore-wifi-%s" % original_wifi, ["nmcli", "radio", "wifi", "on" if original_wifi == "enabled" else "off"], timeout=30)
            actions.append({"radio": "wifi", "result": "restore", **result.as_json()})
    bluetooth_requested = policy.get("bluetooth_requested", "preserve")
    before_rfkill = before.get("bluetooth_rfkill") or {}
    current_rfkill = current.get("bluetooth_rfkill") or {}
    original_soft = before_rfkill.get("soft")
    desired_soft = "no" if bluetooth_requested == "on" else "yes"
    if bluetooth_requested != "preserve" and original_soft in ("yes", "no") and original_soft != desired_soft:
        if current_rfkill.get("soft") != desired_soft:
            actions.append({"radio": "bluetooth", "result": "conflict-left-unchanged", "current": current_rfkill.get("soft"), "expected": desired_soft})
        elif original_soft == "no":
            result = capture_command(run, "radio-restore-bluetooth-unblock", ["rfkill", "unblock", "bluetooth"], timeout=20)
            actions.append({"radio": "bluetooth", "result": "restore-rfkill", **result.as_json()})
        else:
            result = capture_command(run, "radio-restore-bluetooth-block", ["rfkill", "block", "bluetooth"], timeout=20)
            actions.append({"radio": "bluetooth", "result": "restore-rfkill", **result.as_json()})
    original_power = before.get("bluetooth_powered")
    desired_power = "yes" if bluetooth_requested == "on" else "no"
    if bluetooth_requested != "preserve" and original_power in ("yes", "no") and original_power != desired_power:
        if current.get("bluetooth_powered") != desired_power:
            actions.append({"radio": "bluetooth", "result": "conflict-left-unchanged", "current": current.get("bluetooth_powered"), "expected": desired_power})
        else:
            result = capture_command(
                run,
                "radio-restore-bluetooth-power-%s" % original_power,
                ["bluetoothctl", "power", "on" if original_power == "yes" else "off"],
                timeout=30,
            )
            actions.append({"radio": "bluetooth", "result": "restore-power", **result.as_json()})
    restored = {"changed": bool(policy.get("actions")), "actions": actions}
    write_json(run.run_dir / "cleanup/radios.json", restored)
    return restored


def capture_persistent_logs(run: DeviceRun, phase: str) -> List[str]:
    sources: List[Path] = []
    pstore = Path("/sys/fs/pstore")
    if pstore.is_dir():
        sources.extend(sorted(item for item in pstore.iterdir() if item.is_file()))
    last_kmsg = Path("/proc/last_kmsg")
    if last_kmsg.is_file():
        sources.append(last_kmsg)
    copied: List[str] = []
    for source in sources:
        if snapshot_file(run, phase, source):
            copied.append(str(source))
    write_json(run.run_dir / phase / "persistent-logs.json", copied)
    return copied


def capture_logs(run: DeviceRun, phase: str, since: str) -> Dict[str, Any]:
    logs_dir = run.run_dir / phase / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    result: Dict[str, Any] = {}
    for name, command in (
        (
            "journal",
            ["journalctl", "-b", "0", "--since", since, "--no-pager", "-o", "short-monotonic", "-n", "2000"],
        ),
        (
            "journal-kernel",
            ["journalctl", "-k", "-b", "0", "--since", since, "--no-pager", "-o", "short-monotonic", "-n", "2000"],
        ),
        ("dmesg", ["dmesg", "--color=never", "--time-format=iso"]),
    ):
        command_result = capture_command(run, "%s-%s" % (name, phase), command, timeout=45)
        output = command_result.stdout.decode("utf-8", errors="replace")
        if name == "dmesg":
            output = "\n".join(output.splitlines()[-2000:])
        atomic_write_text(logs_dir / (name + ".txt"), output)
        result[name] = command_result.as_json()
    if phase == "post":
        before_text = read_text(run.run_dir / "pre/logs/dmesg.txt") or ""
        after_text = read_text(logs_dir / "dmesg.txt") or ""
        before_lines = before_text.splitlines()
        remaining = list(before_lines)
        new_lines: List[str] = []
        for line in after_text.splitlines():
            if line in remaining:
                remaining.remove(line)
            else:
                new_lines.append(line)
        atomic_write_text(logs_dir / "dmesg-run.txt", "\n".join(new_lines[-2000:]))
        result["dmesg_run_delta"] = {"lines": len(new_lines), "bounded_lines": min(len(new_lines), 2000)}
    write_json(run.run_dir / phase / "logs.json", result)
    return result


def capture_phase(run: DeviceRun, phase: str, since: str) -> Dict[str, Any]:
    system = capture_system(run, phase)
    suspend_stats = capture_suspend_stats(run, phase)
    qcom_stats = capture_qcom_stats(run, phase)
    cpuidle = capture_cpuidle(run, phase)
    interrupts = capture_interrupts(run, phase)
    wakeup_sources = capture_wakeup_sources(run, phase)
    runtime_pm = capture_runtime_pm(run, phase)
    power_supplies = capture_power_supplies(run, phase)
    audio = capture_audio(run, phase, qcom_stats)
    summaries = capture_regulator_and_clock_summaries(run, phase)
    input_display = capture_input_and_display(run, phase)
    thermal = capture_thermal(run, phase)
    rtc = capture_rtc(run, phase)
    persistent_logs = capture_persistent_logs(run, phase)
    logs = capture_logs(run, phase, since)
    snapshot = {
        "phase": phase,
        "captured_at": utc_now(),
        "system": system,
        "suspend_stats": suspend_stats,
        "qcom_stats": qcom_stats,
        "cpuidle_count": len(cpuidle),
        "interrupt_count": len(interrupts),
        "wakeup_source_count": len(wakeup_sources),
        "runtime_pm_count": len(runtime_pm["devices"]),
        "power_supply_count": len(power_supplies),
        "audio": audio,
        "regulator_clock_summaries": summaries,
        "input_display": input_display,
        "thermal_count": len(thermal),
        "rtc_count": len(rtc),
        "persistent_log_count": len(persistent_logs),
        "logs": logs,
    }
    write_json(run.run_dir / phase / "snapshot.json", snapshot)
    return snapshot


def capture_clock(run: DeviceRun, label: str) -> Optional[Dict[str, Any]]:
    try:
        values = {
            "captured_at": utc_now(),
            "clock_realtime_ns": time.clock_gettime_ns(time.CLOCK_REALTIME),
            "clock_boottime_ns": time.clock_gettime_ns(time.CLOCK_BOOTTIME),
            "clock_monotonic_ns": time.clock_gettime_ns(time.CLOCK_MONOTONIC),
        }
    except (AttributeError, OSError):
        values = None
    if values is not None:
        write_json(run.run_dir / "meta" / (safe_name(label) + ".clock.json"), values)
    return values


def capture_mutation_baseline(run: DeviceRun) -> Dict[str, Any]:
    values: Dict[str, Any] = {}
    for name, source in (
        ("pm_debug_messages", Path("/sys/power/pm_debug_messages")),
        ("pm_print_times", Path("/sys/power/pm_print_times")),
        ("mem_sleep", Path("/sys/power/mem_sleep")),
    ):
        value = read_text(source)
        values[name] = {"path": str(source), "value": value, "writable": os.access(source, os.W_OK)}
    dynamic = Path("/sys/kernel/debug/dynamic_debug/control")
    dynamic_text = read_text(dynamic)
    values["tsens_dynamic_debug"] = {
        "path": str(dynamic),
        "available": dynamic_text is not None,
        "writable": os.access(dynamic, os.W_OK),
        "tsens_lines": [line for line in (dynamic_text or "").splitlines() if "drivers/thermal/qcom/tsens.c" in line],
    }
    write_json(run.run_dir / "meta" / "mutations-before.json", values)
    return values


def dynamic_debug_has_print(lines: Iterable[str]) -> bool:
    for line in lines:
        if "drivers/thermal/qcom/tsens.c" not in line:
            continue
        match = re.search(r"=([^ ]+)", line)
        if match and "p" in match.group(1):
            return True
    return False


def restore_mutations(run: DeviceRun) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = []
    baseline_file = run.run_dir / "meta/mutations-before.json"
    data = read_bytes(baseline_file)
    if data is None:
        return actions
    baseline = json.loads(data.decode("utf-8"))
    for name in ("pm_debug_messages", "pm_print_times"):
        info = baseline.get(name, {})
        source = Path(info.get("path", ""))
        original = info.get("value")
        current = read_text(source)
        if original is None or current is None or current == original or not os.access(source, os.W_OK):
            continue
        if current.strip() != "1":
            actions.append(
                {
                    "action": "restore",
                    "path": str(source),
                    "result": "conflict-left-unchanged",
                    "original": original,
                    "current": current,
                }
            )
            continue
        try:
            write_kernel_control(source, original + "\n")
            actions.append({"action": "restore", "path": str(source), "result": "restored"})
        except OSError as exc:
            actions.append({"action": "restore", "path": str(source), "result": "failed", "error": str(exc)})
    config = run.load_config()
    if config.get("mode") != "policy":
        info = baseline.get("mem_sleep", {})
        source = Path(info.get("path", "/sys/power/mem_sleep"))
        original = selected_mem_sleep(info.get("value"))
        current = selected_mem_sleep(read_text(source))
        requested_mode = str(config.get("mode", ""))
        if original and current and original != current and os.access(source, os.W_OK):
            if current != requested_mode:
                actions.append(
                    {
                        "action": "restore",
                        "path": str(source),
                        "result": "conflict-left-unchanged",
                        "original": original,
                        "current": current,
                        "requested": requested_mode,
                    }
                )
            else:
                try:
                    write_kernel_control(source, original + "\n")
                    actions.append({"action": "restore", "path": str(source), "result": "mem-sleep-restored"})
                except OSError as exc:
                    actions.append({"action": "restore", "path": str(source), "result": "failed", "error": str(exc)})
    dynamic_info = baseline.get("tsens_dynamic_debug", {})
    before_lines = dynamic_info.get("tsens_lines", [])
    control = Path(dynamic_info.get("path", "/sys/kernel/debug/dynamic_debug/control"))
    after_lines = [line for line in (read_text(control) or "").splitlines() if "drivers/thermal/qcom/tsens.c" in line]
    if (
        dynamic_info.get("available")
        and dynamic_info.get("writable")
        and not dynamic_debug_has_print(before_lines)
        and dynamic_debug_has_print(after_lines)
    ):
        try:
            write_kernel_control(control, "file drivers/thermal/qcom/tsens.c -p\n")
            actions.append({"action": "restore", "path": str(control), "result": "tsens-debug-disabled"})
        except OSError as exc:
            actions.append({"action": "restore", "path": str(control), "result": "failed", "error": str(exc)})
    write_json(run.run_dir / "cleanup" / "debug-mutations.json", actions)
    return actions


def parse_systemd_environment(text: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key in ("ARMADA_SUSPEND_MODE", "ARMADA_SLEEP_CONFIG"):
            result[key] = value
    return result


def configure_transient_mode(run: DeviceRun, mode: str) -> Dict[str, Any]:
    if mode == "policy":
        return {"mode": "policy", "changed": False}
    override = run.run_dir / "meta" / "sleep.conf.override"
    atomic_write_text(override, "suspend_mode=%s\n" % mode)
    info = {
        "mode": mode,
        "changed": True,
        "override": str(override),
        "environment": {
            "ARMADA_SUSPEND_MODE": mode,
            "ARMADA_SLEEP_CONFIG": str(override),
        },
    }
    write_json(run.run_dir / "meta" / "transient-mode.json", info)
    return info


def restore_transient_mode(run: DeviceRun) -> Dict[str, Any]:
    data = read_bytes(run.run_dir / "meta/systemd-environment-before.json")
    if data is None:
        return {"changed": False}
    before = json.loads(data.decode("utf-8"))
    keys = ("ARMADA_SUSPEND_MODE", "ARMADA_SLEEP_CONFIG")
    actions: List[Dict[str, Any]] = []
    to_unset = [key for key in keys if key not in before]
    if to_unset:
        result = capture_command(run, "systemd-restore-unset-environment", ["systemctl", "unset-environment"] + to_unset, timeout=15)
        actions.append({"operation": "unset", "keys": to_unset, **result.as_json()})
    to_set = ["%s=%s" % (key, before[key]) for key in keys if key in before]
    if to_set:
        result = capture_command(run, "systemd-restore-set-environment", ["systemctl", "set-environment"] + to_set, timeout=15)
        actions.append({"operation": "set", "keys": list(before), **result.as_json()})
    restored = {"changed": True, "actions": actions}
    write_json(run.run_dir / "cleanup" / "transient-mode.json", restored)
    return restored


def rtc_candidates() -> List[Path]:
    return sorted(Path("/sys/class/rtc").glob("rtc*/wakealarm"))


def arm_rtc(run: DeviceRun, sleep_seconds: int, allow_existing: bool) -> Dict[str, Any]:
    if sleep_seconds < 10 or sleep_seconds > 86400:
        raise LabError("sleep duration must be between 10 and 86400 seconds")
    candidates = [source for source in rtc_candidates() if os.access(source, os.W_OK)]
    if not candidates:
        raise LabError("no writable /sys/class/rtc/rtc*/wakealarm was found")
    busy: List[Dict[str, Any]] = []
    selected: Optional[Path] = None
    original = ""
    for source in candidates:
        value = read_text(source) or ""
        item = {"path": str(source), "original": value}
        if value.strip() not in ("", "0"):
            busy.append(item)
        elif selected is None:
            selected = source
            original = value
    if selected is None and busy and not allow_existing:
        raise LabError(
            "an RTC wake alarm is already armed; refusing to overwrite it. "
            "Use the explicit allow-existing-rtc-wakealarm option only when that alarm is disposable."
        )
    if selected is None:
        selected = candidates[0]
        original = read_text(selected) or ""
    target = int(time.time()) + sleep_seconds
    wakeup_path = selected.parent / "device/power/wakeup"
    wakeup_original = read_text(wakeup_path)
    wakeup_changed = False
    if wakeup_original is not None and wakeup_original.strip() != "enabled" and os.access(wakeup_path, os.W_OK):
        write_kernel_control(wakeup_path, "enabled\n")
        wakeup_changed = True
    try:
        write_kernel_control(selected, "0\n")
        write_kernel_control(selected, "%d\n" % target)
    except OSError:
        with contextlib.suppress(OSError):
            write_kernel_control(selected, "0\n")
            if original.strip() not in ("", "0"):
                write_kernel_control(selected, original + "\n")
        if wakeup_changed:
            with contextlib.suppress(OSError):
                write_kernel_control(wakeup_path, str(wakeup_original) + "\n")
        raise
    actual = read_text(selected) or ""
    actual_wakeup = read_text(wakeup_path)
    if actual.strip() != str(target) or (actual_wakeup is not None and actual_wakeup.strip() != "enabled"):
        with contextlib.suppress(OSError):
            write_kernel_control(selected, "0\n")
            if original.strip() not in ("", "0"):
                write_kernel_control(selected, original + "\n")
        if wakeup_changed:
            with contextlib.suppress(OSError):
                write_kernel_control(wakeup_path, str(wakeup_original) + "\n")
        if actual.strip() != str(target):
            raise LabError("RTC rejected the requested wake alarm; no suspend was started")
        raise LabError("RTC wake control is not enabled; refusing a non-guaranteed wake")
    info = {
        "path": str(selected),
        "rtc": selected.parent.name,
        "original": original,
        "target_epoch": target,
        "sleep_seconds_requested": sleep_seconds,
        "armed_at": utc_now(),
        "wakeup_path": str(wakeup_path),
        "wakeup_original": wakeup_original,
        "wakeup_verified": actual_wakeup is None or actual_wakeup.strip() == "enabled",
        "wakeup_changed": wakeup_changed,
        "other_busy_rtc_alarms": busy,
    }
    write_json(run.run_dir / "meta/rtc-alarm.json", info)
    return info


def restore_rtc(run: DeviceRun) -> Dict[str, Any]:
    data = read_bytes(run.run_dir / "meta/rtc-alarm.json")
    if data is None:
        return {"changed": False}
    info = json.loads(data.decode("utf-8"))
    alarm = Path(info["path"])
    current = read_text(alarm) or ""
    target = str(info["target_epoch"])
    original = str(info.get("original", ""))
    actions: List[Dict[str, Any]] = []
    if current.strip() in ("", "0", target):
        try:
            write_kernel_control(alarm, "0\n")
            if original.strip() not in ("", "0"):
                write_kernel_control(alarm, original + "\n")
            actions.append({"path": str(alarm), "result": "restored", "original": original})
        except OSError as exc:
            actions.append({"path": str(alarm), "result": "failed", "error": str(exc)})
    else:
        actions.append(
            {
                "path": str(alarm),
                "result": "conflict-left-unchanged",
                "current": current,
                "original": original,
            }
        )
    if info.get("wakeup_changed"):
        wakeup = Path(info["wakeup_path"])
        current_wakeup = read_text(wakeup)
        if current_wakeup is not None and current_wakeup.strip() == "enabled":
            try:
                write_kernel_control(wakeup, str(info.get("wakeup_original", "disabled")) + "\n")
                actions.append({"path": str(wakeup), "result": "restored"})
            except OSError as exc:
                actions.append({"path": str(wakeup), "result": "failed", "error": str(exc)})
        else:
            actions.append({"path": str(wakeup), "result": "conflict-left-unchanged", "current": current_wakeup})
    result = {"changed": True, "actions": actions}
    write_json(run.run_dir / "cleanup/rtc-alarm.json", result)
    return result


def sleep_debug_prepare(run: DeviceRun) -> Dict[str, Any]:
    binary = find_command("armada-sleep-debug")
    if not binary:
        result = {"available": False, "reason": "armada-sleep-debug not found"}
        write_json(run.run_dir / "meta/sleep-debug.json", result)
        return result
    state_dir = run.run_dir / "raw/armada-sleep-debug"
    environment = os.environ.copy()
    environment["ARMADA_SLEEP_DEBUG_STATE_DIR"] = str(state_dir)
    # The stock collector's automatic charger-log helper may load a module
    # that is intentionally documented as unsafe to unload. Suppress only that
    # nested optional helper; the Armada sleep-debug output itself is retained.
    environment["ARMADA_SLEEP_DEBUG_CHARGE_DEBUG"] = str(run.run_dir / "meta/charger-debug-suppressed")
    result = capture_command(run, "armada-sleep-debug-prepare", [binary, "prepare"], env=environment, timeout=45)
    info = {"available": True, "binary": binary, **result.as_json()}
    write_json(run.run_dir / "meta/sleep-debug-prepare.json", info)
    return info


def sleep_debug_collect(run: DeviceRun) -> Dict[str, Any]:
    binary = find_command("armada-sleep-debug")
    if not binary:
        result = {"available": False, "reason": "armada-sleep-debug not found"}
        write_json(run.run_dir / "meta/sleep-debug-collect.json", result)
        return result
    state_dir = run.run_dir / "raw/armada-sleep-debug"
    environment = os.environ.copy()
    environment["ARMADA_SLEEP_DEBUG_STATE_DIR"] = str(state_dir)
    environment["ARMADA_SLEEP_DEBUG_CHARGE_DEBUG"] = str(run.run_dir / "meta/charger-debug-suppressed")
    result = capture_command(run, "armada-sleep-debug-collect", [binary, "collect"], env=environment, timeout=120)
    info = {"available": True, "binary": binary, **result.as_json()}
    write_json(run.run_dir / "meta/sleep-debug-collect.json", info)
    return info


def read_phase_json(run: DeviceRun, phase: str, name: str, default: Any) -> Any:
    data = read_bytes(run.run_dir / phase / name)
    if data is None:
        return default
    try:
        return json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return default


def command_json(run: DeviceRun, name: str) -> Dict[str, Any]:
    data = read_bytes(run.run_dir / "raw/commands" / (safe_name(name) + ".json"))
    if data is None:
        return {}
    try:
        return json.loads(data.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return {}


def qcom_delta(before: Dict[str, Any], after: Dict[str, Any], key: str) -> Dict[str, Any]:
    def find_stat(stats: Dict[str, Any], name: str) -> Optional[Dict[str, Any]]:
        for entries in stats.values():
            if name in entries:
                return entries[name]
        return None

    old = find_stat(before, key.lower()) or find_stat(before, key.upper())
    new = find_stat(after, key.lower()) or find_stat(after, key.upper())
    if old is None or new is None:
        return {"available": False}
    return {
        "available": True,
        "count_delta": difference(new.get("count"), old.get("count")),
        "duration_delta": difference(new.get("accumulated_duration"), old.get("accumulated_duration")),
        "before": old,
        "after": new,
    }


def cpuidle_deltas(before: List[Dict[str, Any]], after: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    old = {(item.get("cpu"), item.get("state")): item for item in before}
    result: List[Dict[str, Any]] = []
    for item in after:
        key = (item.get("cpu"), item.get("state"))
        previous = old.get(key, {})
        row = {"cpu": item.get("cpu"), "state": item.get("state"), "name": item.get("name")}
        for field in ("usage", "time", "disable", "residency"):
            row[field + "_delta"] = difference(item.get(field), previous.get(field))
        current_s2idle = item.get("s2idle") or {}
        previous_s2idle = previous.get("s2idle") or {}
        row["s2idle_usage_delta"] = difference(current_s2idle.get("usage"), previous_s2idle.get("usage"))
        row["s2idle_time_delta"] = difference(current_s2idle.get("time"), previous_s2idle.get("time"))
        result.append(row)
    return result


def interrupt_deltas(before: Dict[str, Any], after: Dict[str, Any]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for irq, current in after.items():
        old = before.get(irq, {})
        delta = difference(current.get("total"), old.get("total"))
        if delta is None or delta == 0:
            continue
        rows.append(
            {
                "irq": irq,
                "delta": int(delta),
                "total_after": current.get("total"),
                "details": current.get("details", ""),
            }
        )
    return sorted(rows, key=lambda row: (-abs(row["delta"]), int(row["irq"])))


def wakeup_source_deltas(before: Dict[str, Any], after: Dict[str, Any]) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    for name, current in after.items():
        old = before.get(name, {})
        deltas: Dict[str, Any] = {}
        for field in ("active_count", "event_count", "wakeup_count", "expire_count"):
            delta = difference(current.get(field), old.get(field))
            if delta is not None and delta != 0:
                deltas[field + "_delta"] = int(delta)
        if deltas:
            rows.append({"name": name, **deltas})
    return sorted(rows, key=lambda row: row["name"])


def suspend_log_observation(run: DeviceRun) -> Dict[str, Any]:
    """Find kernel suspend markers after the waited systemd job returns."""
    sources = (
        run.run_dir / "post/logs/journal-kernel.txt",
        run.run_dir / "post/logs/dmesg-run.txt",
        run.run_dir / "post/logs/dmesg.txt",
    )
    entry_modes: List[str] = []
    entry_lines: List[str] = []
    exit_lines: List[str] = []
    for source in sources:
        text = read_text(source) or ""
        for line in text.splitlines():
            match = re.search(r"PM: suspend entry \(([^)]+)\)", line)
            if match:
                mode = match.group(1)
                if mode not in entry_modes:
                    entry_modes.append(mode)
                if line not in entry_lines:
                    entry_lines.append(line)
            if re.search(r"PM: suspend exit\b", line):
                if line not in exit_lines:
                    exit_lines.append(line)
    return {
        "entry_modes": entry_modes,
        "entry_observed": bool(entry_lines),
        "exit_observed": bool(exit_lines),
        "entry_lines": entry_lines[-10:],
        "exit_lines": exit_lines[-10:],
    }


def battery_metrics(before: Dict[str, Any], after: Dict[str, Any], seconds: Optional[float]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for name in sorted(set(before) | set(after)):
        old = before.get(name, {})
        new = after.get(name, {})
        row: Dict[str, Any] = {}
        for field in ("capacity", "charge_counter", "energy_now", "current_now", "voltage_now", "power_now"):
            delta = difference(new.get(field), old.get(field))
            if delta is not None:
                row[field + "_delta"] = delta
        if seconds and seconds > 0:
            charge_delta = row.get("charge_counter_delta")
            if charge_delta is not None:
                row["average_battery_current_mA"] = -charge_delta * 3.6 / seconds
                row["charge_consumed_uAh"] = -charge_delta
            energy_delta = row.get("energy_now_delta")
            if energy_delta is not None:
                row["energy_consumed_uWh"] = -energy_delta
                voltage_values = [number(old.get("voltage_now")), number(new.get("voltage_now"))]
                voltage_values = [value for value in voltage_values if value is not None and value > 0]
                if voltage_values:
                    average_voltage = sum(voltage_values) / len(voltage_values) / 1000000.0
                    row["average_battery_power_mW"] = -energy_delta * 3.6 / seconds
                    row["average_battery_current_from_energy_mA"] = row["average_battery_power_mW"] / average_voltage
        if row:
            result[name] = row
    return result


def capture_health(run: DeviceRun, pre_snapshot: Dict[str, Any], post_snapshot: Dict[str, Any]) -> Dict[str, Any]:
    commands: Dict[str, Any] = {}
    command_specs = (
        ("health-systemd-failed", ["systemctl", "--failed", "--no-legend", "--plain"]),
        ("health-network-links", ["ip", "-br", "link"]),
        ("health-rfkill", ["rfkill", "list"]),
        ("health-bluetooth", ["bluetoothctl", "show"]),
        ("health-nmcli-radio", ["nmcli", "-t", "-f", "WIFI", "radio"]),
        ("health-usb", ["lsusb"]),
        ("health-steam-gamescope", ["pgrep", "-af", "steam|gamescope"]),
    )
    for name, command in command_specs:
        result = capture_command(run, name, command, timeout=30)
        commands[name] = {
            **result.as_json(),
            "stdout_text": result.stdout.decode("utf-8", errors="replace"),
            "stderr_text": result.stderr.decode("utf-8", errors="replace"),
        }
    pre_inputs = (pre_snapshot.get("input_display") or {}).get("inputs", [])
    post_inputs = (post_snapshot.get("input_display") or {}).get("inputs", [])
    pre_names = {item.get("name") for item in pre_inputs}
    post_names = {item.get("name") for item in post_inputs}
    missing_inputs = sorted(name for name in pre_names - post_names if name)
    errors: List[str] = []
    for log_name in ("journal.txt", "journal-kernel.txt", "dmesg.txt"):
        source = run.run_dir / "post/logs" / log_name
        text = read_text(source) or ""
        for line in text.splitlines():
            if re.search(r"nobody cared|spurious|disabled irq|BUG:|Oops:|kernel panic|watchdog|ufs.*error|mmc.*error|pcie.*error", line, re.I):
                errors.append(line)
    result = {
        "captured_at": utc_now(),
        "input_inventory": {
            "pre_count": len(pre_inputs),
            "post_count": len(post_inputs),
            "missing_names": missing_inputs,
            "observed_ok": not missing_inputs,
        },
        "display_inventory": (post_snapshot.get("input_display") or {}).get("displays", []),
        "new_error_like_log_lines": errors[-100:],
        "commands": commands,
        "functional_checks": {
            "gamepad": "not_run_by_harness",
            "display_touch": "not_run_by_harness",
            "audio_playback": "not_run_by_harness",
            "wifi_recovery": "not_run_by_harness",
            "bluetooth_recovery": "not_run_by_harness",
            "usb_host_and_charging": "not_run_by_harness",
            "steam_gamescope_suspend_resume": "not_run_by_harness",
        },
    }
    write_json(run.run_dir / "derived/post-resume-health.json", result)
    return result


def derive_summary(run: DeviceRun, *, command_returncode: Optional[int]) -> Dict[str, Any]:
    pre_system = read_phase_json(run, "pre", "system.json", {})
    post_system = read_phase_json(run, "post", "system.json", {})
    pre_stats = read_phase_json(run, "pre", "suspend_stats.json", {})
    post_stats = read_phase_json(run, "post", "suspend_stats.json", {})
    pre_qcom = read_phase_json(run, "pre", "qcom_stats.json", {})
    post_qcom = read_phase_json(run, "post", "qcom_stats.json", {})
    pre_cpuidle = read_phase_json(run, "pre", "cpuidle.json", [])
    post_cpuidle = read_phase_json(run, "post", "cpuidle.json", [])
    pre_interrupts = read_phase_json(run, "pre", "interrupts.json", {})
    post_interrupts = read_phase_json(run, "post", "interrupts.json", {})
    pre_wakeup = read_phase_json(run, "pre", "wakeup_sources.json", {})
    post_wakeup = read_phase_json(run, "post", "wakeup_sources.json", {})
    pre_power = read_phase_json(run, "pre", "power_supplies.json", {})
    post_power = read_phase_json(run, "post", "power_supplies.json", {})
    trace_info = read_phase_json(run, "meta", "trace.json", {})
    trace_text = read_text(run.run_dir / "raw" / "trace" / "trace.txt") or ""
    rsc_snapshots = parse_rpmh_rsc_snapshots(trace_text)
    write_json(run.run_dir / "derived" / "rpmh-rsc-snapshots.json", rsc_snapshots)
    status = run.load_status()
    config = run.load_config()
    sleep_command = command_json(run, "suspend-command")
    suspend_log = suspend_log_observation(run)
    requested_mode = str(config.get("mode", "policy"))
    observed_modes = suspend_log.get("entry_modes", [])
    observed_mode = observed_modes[-1] if observed_modes else None
    suspend_job_duration = number(sleep_command.get("duration_seconds"))
    before_clock = parse_clock_file(run.run_dir / "meta/suspend-start.clock.json")
    after_clock = parse_clock_file(run.run_dir / "meta/resume-return.clock.json")
    if pre_system.get("boot_id") and post_system.get("boot_id"):
        boot_same: Optional[bool] = pre_system.get("boot_id") == post_system.get("boot_id")
    else:
        boot_same = None
    boot_delta = None
    monotonic_delta = None
    suspended_seconds = None
    resume_realtime_delta = None
    if before_clock and after_clock and boot_same is True:
        boot_delta = (after_clock["clock_boottime_ns"] - before_clock["clock_boottime_ns"]) / 1_000_000_000.0
        monotonic_delta = (after_clock["clock_monotonic_ns"] - before_clock["clock_monotonic_ns"]) / 1_000_000_000.0
        suspended_seconds = boot_delta - monotonic_delta
        resume_realtime_delta = after_clock["clock_realtime_ns"] / 1_000_000_000.0 - float(config.get("wake_epoch", after_clock["clock_realtime_ns"] / 1_000_000_000.0))
    success_delta = difference(post_stats.get("success"), pre_stats.get("success")) if boot_same is True else None
    fail_delta = difference(post_stats.get("fail"), pre_stats.get("fail")) if boot_same is True else None
    expected_rtc = read_phase_json(run, "meta", "rtc-alarm.json", {})
    pre_irq = pre_system.get("pm_wakeup_irq")
    actual_irq = post_system.get("pm_wakeup_irq")
    actual_irq_text = str(actual_irq) if actual_irq is not None else None
    irq_name = None
    if actual_irq_text and actual_irq_text in post_interrupts:
        irq_name = post_interrupts[actual_irq_text].get("details")
    expected_rtc_name = expected_rtc.get("rtc")
    pm_irq_changed = None
    if pre_irq is not None and actual_irq is not None:
        pm_irq_changed = pre_irq != actual_irq
    pm_wakeup_irq_match = bool(
        pm_irq_changed is True and expected_wake_text_matches(irq_name, expected_rtc_name)
    )
    pm_wakeup_irq_conflict = bool(
        pm_irq_changed is True
        and expected_rtc_name
        and not expected_wake_text_matches(irq_name, expected_rtc_name)
    )
    interrupt_rows = interrupt_deltas(pre_interrupts, post_interrupts)
    expected_rtc_interrupt_deltas = [
        row
        for row in interrupt_rows
        if expected_wake_text_matches(row.get("details"), expected_rtc_name)
    ]
    rtc_interrupt_event = bool(expected_rtc_interrupt_deltas)
    wakeup_source_rows = wakeup_source_deltas(pre_wakeup, post_wakeup)
    expected_rtc_wakeup_sources = [
        row
        for row in wakeup_source_rows
        if expected_wake_text_matches(row.get("name"), expected_rtc_name)
    ]
    wakeup_source_match = bool(expected_rtc_wakeup_sources)
    expected_rtc_evidence = bool(pm_wakeup_irq_match or rtc_interrupt_event or wakeup_source_match)
    if pm_wakeup_irq_conflict:
        wake_class = "conflicting-pm-wakeup-irq"
    elif pm_wakeup_irq_match:
        wake_class = "expected-source-pm-wakeup-irq"
    elif expected_rtc_evidence and pm_irq_changed is False:
        wake_class = "expected-source-with-unchanged-pm-wakeup-irq"
    elif expected_rtc_evidence:
        wake_class = "expected-source-event"
    else:
        wake_class = "unknown"
    actual_wake = {
        "pm_wakeup_irq_before": pre_irq,
        "pm_wakeup_irq_after": actual_irq,
        "pm_wakeup_irq_changed": pm_irq_changed,
        "pm_wakeup_irq_match": pm_wakeup_irq_match,
        "pm_wakeup_irq_conflict": pm_wakeup_irq_conflict,
        "interrupt_details": irq_name,
        "expected_rtc_interrupt_deltas": expected_rtc_interrupt_deltas,
        "rtc_interrupt_event": rtc_interrupt_event,
        "expected_rtc_wakeup_sources": expected_rtc_wakeup_sources,
        "wakeup_sources": wakeup_source_rows,
        "wakeup_source_match": wakeup_source_match,
        "expected_rtc_evidence": expected_rtc_evidence,
        "wake_class": wake_class,
    }
    actual_wake["expected_rtc"] = expected_rtc_name
    actual_wake["matches_expected_rtc"] = bool(expected_rtc_evidence and not pm_wakeup_irq_conflict)
    qcom = {name: qcom_delta(pre_qcom, post_qcom, name) for name in ("aosd", "cxsd", "ddr", "adsp")}
    health = read_phase_json(run, "derived", "post-resume-health.json", {})
    suspend_attempted = before_clock is not None
    kernel_suspend_success = bool(success_delta is not None and success_delta > 0)
    suspend_markers_observed = bool(
        suspend_log.get("entry_observed") and suspend_log.get("exit_observed")
    )
    if observed_mode == "deep":
        sleep_observed_basis = "CLOCK_BOOTTIME-minus-CLOCK_MONOTONIC"
        sleep_observed = bool(
            suspend_markers_observed
            and suspended_seconds is not None
            and suspended_seconds >= MIN_CLOCK_PROVEN_SUSPEND_SECONDS
        )
    elif observed_mode == "s2idle":
        sleep_observed_basis = "kernel-s2idle-markers-plus-waited-dispatcher-job"
        sleep_observed = bool(
            suspend_markers_observed
            and suspend_job_duration is not None
            and suspend_job_duration >= MIN_CLOCK_PROVEN_SUSPEND_SECONDS
        )
    else:
        sleep_observed_basis = "kernel-markers-plus-waited-dispatcher-job"
        sleep_observed = bool(
            suspend_markers_observed
            and suspend_job_duration is not None
            and suspend_job_duration >= MIN_CLOCK_PROVEN_SUSPEND_SECONDS
        )
    measurement_interval = boot_delta if boot_delta and boot_delta > 0 else suspend_job_duration
    clock_separation_status = clock_separation_state(suspended_seconds)
    suspend_success = bool(
        boot_same is True
        and kernel_suspend_success
        and sleep_observed
        and command_returncode == 0
    )
    metrics = {
        "real_suspended_seconds": round(suspended_seconds, 6) if suspended_seconds is not None else None,
        "suspend_clock_separation_seconds": round(suspended_seconds, 6) if suspended_seconds is not None else None,
        "suspend_clock_separation_status": clock_separation_status,
        "unexpected_lack_of_clock_separation": clock_separation_status in ("unexpectedly_absent", "negative"),
        "clock_boottime_delta_seconds": round(boot_delta, 6) if boot_delta is not None else None,
        "clock_monotonic_delta_seconds": round(monotonic_delta, 6) if monotonic_delta is not None else None,
        "suspend_job_duration_seconds": round(suspend_job_duration, 6) if suspend_job_duration is not None else None,
        "suspend_mode_requested": requested_mode,
        "suspend_mode_observed": observed_mode,
        "suspend_markers_observed": suspend_markers_observed,
        "suspend_log_observation": suspend_log,
        "sleep_observed_basis": sleep_observed_basis,
        "battery_measurement_interval_seconds": round(measurement_interval, 6) if measurement_interval is not None else None,
        "rtc_target_to_suspend_return_seconds": round(resume_realtime_delta, 6) if resume_realtime_delta is not None else None,
        "resume_latency_seconds": round(max(0.0, resume_realtime_delta), 6) if resume_realtime_delta is not None else None,
        "suspend_success_delta": int(success_delta) if success_delta is not None else None,
        "suspend_failure_delta": int(fail_delta) if fail_delta is not None else None,
        "boot_survived_without_reset": boot_same,
        "suspend_command_returncode": command_returncode,
        "trace_profile": config.get("trace_profile", "none"),
        "trace_state": trace_info.get("state"),
        "trace_selected_event_count": len(trace_info.get("selected_events", [])),
        "trace_bytes": ((trace_info.get("trace_files") or {}).get("trace") or {}).get("bytes"),
        "rpmh_rsc_snapshots": rsc_snapshots,
        "suspend_attempted": suspend_attempted,
        "kernel_suspend_success": kernel_suspend_success,
        "clock_proven_sleep_threshold_seconds": MIN_CLOCK_PROVEN_SUSPEND_SECONDS,
        "sleep_observed": sleep_observed,
        "suspend_success": suspend_success,
        "suspend_failure": bool(suspend_attempted and not suspend_success),
        "expected_vs_actual_wake": actual_wake,
        "qcom_sleep_deltas": qcom,
        "cpuidle_residency_deltas": cpuidle_deltas(pre_cpuidle, post_cpuidle),
        "top_interrupt_deltas": interrupt_rows[:40],
        "wakeup_source_deltas": actual_wake["wakeup_sources"],
        "battery_metrics": battery_metrics(pre_power, post_power, measurement_interval),
        "post_resume_subsystem_health": health,
    }
    summary = {
        "schema": "sm8550-suspend-lab/%d" % SCHEMA_VERSION,
        "run_id": run.run_id,
        "generated_at": utc_now(),
        "config": config,
        "status": status,
        "provenance": {
            "boot_id_before": pre_system.get("boot_id"),
            "boot_id_after": post_system.get("boot_id"),
            "kernel_release_before": pre_system.get("kernel_release"),
            "kernel_release_after": post_system.get("kernel_release"),
            "dt_model_before": pre_system.get("dt_model"),
            "dt_compatible_before": pre_system.get("dt_compatible"),
            "cmdline_before": pre_system.get("cmdline"),
            "mem_sleep_before": pre_system.get("mem_sleep_raw"),
            "mem_sleep_after": post_system.get("mem_sleep_raw"),
            "device_env_before": pre_system.get("device_env"),
            "device_env_after": post_system.get("device_env"),
            "armada_version_file": pre_system.get("armada_version_file"),
            "lab_agent_sha256": pre_system.get("lab_agent_sha256"),
        },
        "metrics": metrics,
        "evidence": {
            "raw_root": "raw/",
            "pre_snapshot": "pre/snapshot.json",
            "post_snapshot": "post/snapshot.json",
            "sleep_debug_prepare": "raw/commands/armada-sleep-debug-prepare.stdout",
            "sleep_debug_collect": "raw/commands/armada-sleep-debug-collect.stdout",
            "clocks": "meta/",
            "trace_metadata": "meta/trace.json",
            "trace_raw": "raw/trace/",
            "rpmh_rsc_snapshots": "derived/rpmh-rsc-snapshots.json",
            "result_document": "result.md",
            "checksums": "checksums.sha256",
        },
        "provenance_receipts": [
            "pre/provenance.json",
            "pre/raw/commands/provenance-bootc-status-json.stdout",
            "pre/raw/commands/provenance-rpm-packages.stdout",
            "host-manifest.json",
        ],
    }
    write_json(run.run_dir / "derived/summary.json", summary)
    return summary


def write_device_result(run: DeviceRun, summary: Dict[str, Any]) -> None:
    config = summary.get("config", {})
    metrics = summary.get("metrics", {})
    lines = [
        "# SM8550 suspend lab run %s" % run.run_id,
        "",
        "- Hypothesis: %s" % config.get("hypothesis", "Measure the current Armada suspend path without making a kernel change."),
        "- Single changed variable: %s" % config.get("changed_variable", "RTC wake alarm and requested sleep mode; no kernel or firmware change."),
        "- Exact build identifiers/hashes: kernel `%s`; Armada version `%s`; image/package receipts are in `pre/provenance.json` and host source hashes are in the retrieved `host-manifest.json`." % (
            summary.get("provenance", {}).get("kernel_release_before", "unavailable"),
            summary.get("provenance", {}).get("armada_version_file", "unavailable"),
        ),
        "- Exact commands: raw command receipts are under `raw/commands/`; the autonomous root-owned agent invoked `/usr/libexec/armada/suspend-dispatch` directly and wrote the post-resume snapshot after it returned.",
        "- Trace profile: `%s`; scoped trace metadata is in `meta/trace.json` and raw trace/configuration files are under `raw/trace/`." % metrics.get("trace_profile", "none"),
        "- Raw evidence path: `raw/`, with before/after snapshots in `pre/` and `post/`.",
        "- Derived metrics: `derived/summary.json`; requested/observed mode = `%s`/`%s`; waited job seconds = `%s`; suspend-clock separation = `%s` seconds (`%s`); sleep observed = `%s`; AOSD delta = `%s`; CXSD delta = `%s`." % (
            metrics.get("suspend_mode_requested"),
            metrics.get("suspend_mode_observed"),
            metrics.get("suspend_job_duration_seconds"),
            metrics.get("suspend_clock_separation_seconds"),
            metrics.get("suspend_clock_separation_status"),
            metrics.get("sleep_observed"),
            metrics.get("qcom_sleep_deltas", {}).get("aosd", {}).get("count_delta"),
            metrics.get("qcom_sleep_deltas", {}).get("cxsd", {}).get("count_delta"),
        ),
        "- Conclusion: suspend success requires clock-proven sleep, an unchanged boot ID, a kernel success increment, and a zero-return suspend job; this receipt does not by itself establish causality or a safe optimization.",
        "- Confidence: %s" % config.get("confidence", "single-cycle evidence; repeat identical clean cycles before drawing a platform conclusion"),
        "- Recommended next experiment: %s" % config.get("recommendation", "Repeat the exact same mode and physical-cable state for an independent clean cycle."),
        "",
    ]
    atomic_write_text(run.run_dir / "result.md", "\n".join(lines))


def write_checksums(run: DeviceRun) -> None:
    lines: List[str] = []
    checksum_name = "checksums.sha256"
    for source in sorted(item for item in run.run_dir.rglob("*") if item.is_file()):
        if source.name == checksum_name:
            continue
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        lines.append("%s  %s" % (digest, source.relative_to(run.run_dir).as_posix()))
    atomic_write_text(run.run_dir / checksum_name, "\n".join(lines) + ("\n" if lines else ""))


def cleanup_run(run: DeviceRun) -> Dict[str, Any]:
    result = {
        "completed_at": utc_now(),
        "trace": trace_cleanup(run),
        "rtc": restore_rtc(run),
        "radios": restore_radios(run),
        "transient_mode": restore_transient_mode(run),
        "debug_mutations": restore_mutations(run),
    }
    write_json(run.run_dir / "cleanup/summary.json", result)
    return result


def device_execute(args: argparse.Namespace) -> int:
    run = DeviceRun(Path(args.root), args.run_id)
    config = run.load_config()
    run.log("detached device execution started")
    run.update_status(state="preparing", boot_id_before=read_text(Path("/proc/sys/kernel/random/boot_id")))
    command_returncode: Optional[int] = None
    try:
        started_at = utc_now()
        config["device_started_at"] = started_at
        write_json(run.config_file, config)
        capture_mutation_baseline(run)
        capture_clock(run, "device-start")
        pre_snapshot = capture_phase(run, "pre", started_at)
        apply_radio_policy(run, config)
        sleep_debug_prepare(run)
        configure_transient_mode(run, config.get("mode", "policy"))
        rtc_info = arm_rtc(
            run,
            int(config.get("sleep_seconds", 45)),
            bool(config.get("allow_existing_rtc_wakealarm", False)),
        )
        config["wake_epoch"] = rtc_info["target_epoch"]
        write_json(run.config_file, config)
        trace_prepare(run, str(config.get("trace_profile", "none")))
        run.update_status(
            state="armed",
            expected_wake_source=rtc_info["rtc"],
            rtc_target_epoch=rtc_info["target_epoch"],
            boot_id_before=pre_snapshot.get("system", {}).get("boot_id"),
        )
        logger = find_command("logger")
        if logger:
            capture_command(
                run,
                "run-marker",
                [logger, "--tag", "sm8550-suspend-lab", "run=%s phase=before-suspend" % run.run_id],
                timeout=15,
            )
        trace_start(run)
        capture_clock(run, "suspend-start")
        run.update_status(state="suspending")
        suspend_env = os.environ.copy()
        requested_mode = str(config.get("mode", "policy"))
        if requested_mode == "policy":
            suspend_env.pop("ARMADA_SUSPEND_MODE", None)
            suspend_env.pop("ARMADA_SLEEP_CONFIG", None)
        else:
            mode_info = read_phase_json(run, "meta", "transient-mode.json", {})
            suspend_env.update(mode_info.get("environment", {}))
        dispatch = Path("/usr/libexec/armada/suspend-dispatch")
        if not os.access(dispatch, os.X_OK):
            raise LabError("Armada suspend-dispatch is not executable; no suspend was started")
        write_json(
            run.run_dir / "meta" / "suspend-dispatch.json",
            {
                "command": [str(dispatch)],
                "environment_overrides": {
                    key: suspend_env[key]
                    for key in ("ARMADA_SUSPEND_MODE", "ARMADA_SLEEP_CONFIG")
                    if key in suspend_env
                },
                "invoked_by": "autonomous root-owned sm8550-suspend-lab systemd unit",
            },
        )
        try:
            suspend_result = capture_command(
                run,
                "suspend-command",
                [str(dispatch)],
                env=suspend_env,
                timeout=None,
            )
        finally:
            trace_stop(run)
        command_returncode = suspend_result.returncode
        capture_clock(run, "resume-return")
        run.update_status(state="resumed", suspend_command=suspend_result.as_json())
        post_snapshot = capture_phase(run, "post", started_at)
        sleep_debug_collect(run)
        health = capture_health(run, pre_snapshot, post_snapshot)
        write_json(run.run_dir / "derived/post-resume-health.json", health)
        cleanup_run(run)
        summary = derive_summary(run, command_returncode=command_returncode)
        write_device_result(run, summary)
        run.update_status(
            state="complete" if summary["metrics"]["suspend_success"] else "failed",
            boot_id_after=post_snapshot.get("system", {}).get("boot_id"),
            metrics=summary["metrics"],
        )
        write_checksums(run)
        return 0 if summary["metrics"]["suspend_success"] else 1
    except BaseException as exc:
        run.log("device execution exception: %s" % exc)
        run.update_status(state="failed", error=str(exc), error_type=type(exc).__name__)
        # If RTC or systemd environment setup happened before the failure,
        # restore it. Cleanup is idempotent and leaves conflicts untouched.
        with contextlib.suppress(BaseException):
            cleanup_run(run)
        with contextlib.suppress(BaseException):
            summary = derive_summary(run, command_returncode=command_returncode)
            write_device_result(run, summary)
        with contextlib.suppress(BaseException):
            write_checksums(run)
        return 1


def device_start(args: argparse.Namespace) -> int:
    run_id = validate_run_id(args.run_id)
    root = Path(args.root)
    unit = "sm8550-suspend-lab-%s" % run_id
    config = {
        "schema": "sm8550-suspend-lab/%d" % SCHEMA_VERSION,
        "run_id": run_id,
        "label": args.label,
        "mode": args.mode,
        "sleep_seconds": args.sleep_seconds,
        "allow_existing_rtc_wakealarm": args.allow_existing_rtc_wakealarm,
        "wifi_state": args.wifi_state,
        "bluetooth_state": args.bluetooth_state,
        "trace_profile": args.trace_profile,
        "unit": unit,
        "requested_at": utc_now(),
        "hypothesis": args.hypothesis,
        "changed_variable": args.changed_variable,
        "recommendation": args.recommendation,
        "confidence": args.confidence,
    }
    run = DeviceRun(root, run_id)
    run.create(config)
    script = str(Path(__file__).resolve())
    command = [
        "systemd-run",
        "--quiet",
        "--collect",
        "--no-block",
        "--unit=%s" % unit,
        "--property=Type=oneshot",
        "--property=TimeoutStartSec=infinity",
        sys.executable,
        script,
        "device",
        "execute",
        "--root",
        str(root),
        "--run-id",
        run_id,
    ]
    result = capture_command(run, "systemd-run-launch", command, timeout=30)
    if result.returncode != 0:
        run.update_status(state="failed", error="systemd-run could not launch detached unit", launch=result.as_json())
        print(json.dumps(run.load_status(), sort_keys=True))
        return 1
    run.update_status(state="launched", unit=unit)
    print(json.dumps(run.load_status(), sort_keys=True))
    return 0


def device_status(args: argparse.Namespace) -> int:
    run = DeviceRun(Path(args.root), args.run_id)
    status = run.load_status()
    status["current_boot_id"] = read_text(Path("/proc/sys/kernel/random/boot_id"))
    unit = status.get("unit")
    if unit and status.get("state") == "launched":
        unit_result = run_command(
            ["systemctl", "show", unit, "--property=ActiveState", "--property=SubState", "--property=Result"],
            timeout=15,
        )
        unit_text = unit_result.stdout.decode("utf-8", errors="replace")
        status["unit_state"] = unit_text
        launched_long_ago = False
        try:
            launched_at = dt.datetime.fromisoformat(str(status.get("updated_at", "")).replace("Z", "+00:00"))
            launched_long_ago = (dt.datetime.now(dt.timezone.utc) - launched_at).total_seconds() > 10
        except (TypeError, ValueError):
            pass
        if unit_result.returncode != 0 and launched_long_ago:
            status = run.update_status(
                state="failed",
                error="detached systemd unit disappeared before the device agent reported progress",
                unit_state=unit_text,
            )
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


def device_recover(args: argparse.Namespace) -> int:
    run = DeviceRun(Path(args.root), args.run_id)
    config = run.load_config()
    status = run.load_status()
    if status.get("state") == "complete":
        print(json.dumps(status, sort_keys=True))
        return 0
    current_boot = read_text(Path("/proc/sys/kernel/random/boot_id"))
    run.update_status(state="recovering", recovery_boot_id=current_boot)
    try:
        started_at = config.get("device_started_at") or config.get("requested_at") or utc_now()
        recovery_dir = run.run_dir / "post-recovery"
        if recovery_dir.exists():
            raise LabError("recovery snapshot already exists; refusing to overwrite it")
        (run.run_dir / "post").rename(recovery_dir)
        (run.run_dir / "post").mkdir(mode=0o700)
        if not (run.run_dir / "meta/resume-return.clock.json").exists():
            capture_clock(run, "resume-return")
        capture_clock(run, "recovery-return")
        post_snapshot = capture_phase(run, "post", started_at)
        sleep_debug_collect(run)
        pre_snapshot = read_phase_json(run, "pre", "snapshot.json", {})
        capture_health(run, pre_snapshot, post_snapshot)
        cleanup_run(run)
        command_returncode = command_json(run, "suspend-command").get("returncode")
        summary = derive_summary(run, command_returncode=command_returncode)
        summary["recovery"] = {
            "used": True,
            "current_boot_id": current_boot,
            "pre_boot_id": summary["provenance"].get("boot_id_before"),
        }
        write_json(run.run_dir / "derived/summary.json", summary)
        write_device_result(run, summary)
        state = "recovered" if summary["provenance"].get("boot_id_before") != current_boot else "failed"
        run.update_status(state=state, boot_id_after=current_boot, metrics=summary["metrics"])
        write_checksums(run)
        print(json.dumps(run.load_status(), sort_keys=True))
        return 0 if state == "recovered" else 1
    except BaseException as exc:
        run.update_status(state="failed", error="recovery failed: %s" % exc)
        print(json.dumps(run.load_status(), sort_keys=True))
        return 1


def device_cancel(args: argparse.Namespace) -> int:
    run = DeviceRun(Path(args.root), args.run_id)
    status = run.load_status()
    if status.get("state") in ("suspending", "resumed", "complete", "recovered"):
        raise LabError("refusing to cancel after the suspend command began")
    cleanup_run(run)
    run.update_status(state="cancelled")
    write_checksums(run)
    print(json.dumps(run.load_status(), sort_keys=True))
    return 0


def device_install_agent(args: argparse.Namespace) -> int:
    source = Path(args.source)
    if not str(source).startswith("/tmp/") or not re.fullmatch(r"/tmp/sm8550-suspend-lab-[A-Za-z0-9_.-]+\.py", str(source)):
        raise LabError("bootstrap source must be an explicit temporary lab file under /tmp")
    if not source.is_file():
        raise LabError("bootstrap source does not exist: %s" % source)
    root = Path(args.root)
    destination = root / "bin/sm8550_suspend_lab.py"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    os.chmod(destination, 0o755)
    (root / "runs").mkdir(parents=True, exist_ok=True)
    with contextlib.suppress(OSError):
        os.chmod(root, 0o700)
        os.chmod(root / "runs", 0o700)
    source.unlink()
    print(json.dumps({"installed": str(destination), "root": str(root)}, sort_keys=True))
    return 0


def device_hash_agent(args: argparse.Namespace) -> int:
    print(
        json.dumps(
            {
                "agent": str(Path(__file__).resolve()),
                "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            },
            sort_keys=True,
        )
    )
    return 0


def device_preflight(args: argparse.Namespace) -> int:
    commands = (
        ("uname-a", ["uname", "-a"], 15),
        ("proc-version", ["cat", "/proc/version"], 15),
        ("os-release", ["cat", "/etc/os-release"], 15),
        ("boot-id", ["cat", "/proc/sys/kernel/random/boot_id"], 15),
        ("dt-model", ["cat", "/sys/firmware/devicetree/base/model"], 15),
        ("dt-compatible", ["cat", "/sys/firmware/devicetree/base/compatible"], 15),
        ("cmdline", ["cat", "/proc/cmdline"], 15),
        ("mem-sleep", ["cat", "/sys/power/mem_sleep"], 15),
        ("power-state", ["cat", "/sys/power/state"], 15),
        ("sleep-config", ["cat", "/etc/armada/sleep.conf"], 15),
        ("armada-version", ["cat", "/usr/lib/armada/version"], 15),
        ("device-env", ["/usr/libexec/armada/device-env"], 15),
        ("bootc-status-json", ["bootc", "status", "--json"], 60),
        ("rpm-ostree-status-json", ["rpm-ostree", "status", "--json"], 60),
        (
            "rpm-packages",
            ["rpm", "-qa", "--qf", "%{NAME}-%{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\\n"],
            60,
        ),
        ("findmnt-root", ["findmnt", "-no", "SOURCE,TARGET,FSTYPE,OPTIONS", "/"], 15),
        ("lsblk", ["lsblk", "-o", "NAME,PATH,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS,UUID"], 30),
        ("systemd-suspend-unit", ["systemctl", "cat", "systemd-suspend.service"], 15),
        ("suspend-dispatch", ["sed", "-n", "1,140p", "/usr/libexec/armada/suspend-dispatch"], 15),
        ("radio-wifi", ["nmcli", "-t", "-f", "WIFI", "radio"], 15),
        ("radio-rfkill", ["rfkill", "list"], 15),
        ("radio-bluetooth", ["bluetoothctl", "show"], 20),
        ("powerd-unit", ["systemctl", "cat", "armada-powerd.service"], 15),
        ("powerd-state", ["systemctl", "show", "armada-powerd.service", "-p", "ActiveState", "-p", "SubState", "-p", "Result", "-p", "NRestarts"], 15),
        ("debugfs-root-diagnostic-files", ["find", "/sys/kernel/debug", "-maxdepth", "2", "-type", "f", "-print"], 30),
        ("debugfs-root-diagnostic-directories", ["find", "/sys/kernel/debug", "-maxdepth", "2", "-type", "d", "-print"], 30),
        ("firmware-diagnostic-files", ["find", "/sys/firmware", "-maxdepth", "3", "-type", "f", "-print"], 30),
        (
            "rsc-sysfs-metadata",
            [
                "bash",
                "-c",
                "for device in /sys/bus/platform/devices/*rsc; do [ -d \"$device\" ] || continue; printf '%s\\n' \"--- $device ---\"; printf '%s\\n' '--driver--'; [ -L \"$device/driver\" ] && readlink -f \"$device/driver\"; printf '%s\\n' '--uevent--'; [ -r \"$device/uevent\" ] && cat \"$device/uevent\"; done",
            ],
            30,
        ),
        (
            "rsc-device-tree-metadata",
            [
                "bash",
                "-c",
                "device=/sys/firmware/devicetree/base/soc@0/rsc@17a00000; [ -d \"$device\" ] || exit 0; for property in compatible label name reg-names reg qcom,drv-id qcom,tcs-offset qcom,tcs-config; do [ -r \"$device/$property\" ] || continue; printf '%s\\n' \"--- $property ---\"; case \"$property\" in compatible|label|name|reg-names) tr '\\0' ' ' < \"$device/$property\"; printf '\\n' ;; *) od -An -tx4 -v \"$device/$property\" ;; esac; done",
            ],
            30,
        ),
        ("qcom-socinfo-files", ["find", "/sys/kernel/debug/qcom_socinfo", "-maxdepth", "3", "-type", "f", "-print"], 30),
        (
            "qcom-socinfo-values",
            [
                "bash",
                "-c",
                "find /sys/kernel/debug/qcom_socinfo -maxdepth 3 -type f -print0 | sort -z | while IFS= read -r -d '' source; do printf '%s\\n' \"--- $source ---\"; cat \"$source\"; printf '\\n'; done",
            ],
            60,
        ),
        (
            "device-tree-aop-paths",
            ["find", "/sys/firmware/devicetree/base", "-maxdepth", "6", "-iname", "*aop*", "-print"],
            30,
        ),
        (
            "firmware-aop-paths",
            [
                "find",
                "/usr/lib/firmware",
                "-maxdepth",
                "6",
                "(",
                "-iname",
                "*aop*",
                "-o",
                "-iname",
                "*aoss*",
                "-o",
                "-iname",
                "*rpmh*",
                ")",
                "-print",
            ],
            30,
        ),
        ("qcom-aoss-prevent-ddr", ["cat", "/sys/kernel/debug/qcom_aoss/prevent_ddr_collapse"], 15),
        ("qcom-aoss-prevent-cx", ["cat", "/sys/kernel/debug/qcom_aoss/prevent_cx_collapse"], 15),
        ("qcom-aoss-prevent-aoss", ["cat", "/sys/kernel/debug/qcom_aoss/prevent_aoss_sleep"], 15),
        ("qcom-aoss-ddr-frequency", ["cat", "/sys/kernel/debug/qcom_aoss/ddr_frequency_mhz"], 15),
        ("interconnect-summary", ["cat", "/sys/kernel/debug/interconnect/interconnect_summary"], 60),
        ("interconnect-graph", ["cat", "/sys/kernel/debug/interconnect/interconnect_graph"], 60),
        ("pm-genpd-summary", ["cat", "/sys/kernel/debug/pm_genpd/pm_genpd_summary"], 60),
        ("cmd-db-stat", ["stat", "-c", "%A %U %G %s %n", "/sys/kernel/debug/cmd-db"], 15),
        ("cmd-db-dump", ["cat", "/sys/kernel/debug/cmd-db"], 60),
    )
    captured: Dict[str, Any] = {}
    for name, command, timeout in commands:
        result = run_command(command, timeout=timeout)
        entry = result.as_json()
        entry["stdout_text"] = result.stdout.decode("utf-8", errors="replace")
        entry["stderr_text"] = result.stderr.decode("utf-8", errors="replace")
        captured[name] = entry
    for name, parser in (
        ("cmd-db-dump", parse_cmd_db_dump),
        ("interconnect-summary", parse_interconnect_summary),
        ("interconnect-graph", parse_interconnect_graph),
        ("pm-genpd-summary", parse_pm_genpd_summary),
    ):
        captured[name]["parsed"] = parser(captured[name]["stdout_text"])
    print(
        json.dumps(
            {
                "schema": "sm8550-suspend-lab-preflight/%d" % SCHEMA_VERSION,
                "captured_at": utc_now(),
                "agent_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                "root": str(Path(args.root)),
                "commands": captured,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


def device_supported_update(args: argparse.Namespace) -> int:
    if args.action == "apply":
        unit = "armada-lab-update-apply-%s" % secrets.token_hex(6)
        command = [
            "systemd-run",
            "--quiet",
            "--no-block",
            "--unit=%s" % unit,
            "--property=Type=oneshot",
            "/usr/bin/bootc",
            "upgrade",
            "--apply",
            "--from-downloaded",
        ]
    else:
        command = ["/usr/bin/steamos-update"]
        if args.action == "check":
            command.append("check")
    result = run_command(command, timeout=1800)
    print(
        json.dumps(
            {
                "schema": "sm8550-suspend-lab-supported-update/%d" % SCHEMA_VERSION,
                "captured_at": utc_now(),
                "action": args.action,
                "command": result.command,
                "result": result.as_json(),
                "stdout_text": result.stdout.decode("utf-8", errors="replace"),
                "stderr_text": result.stderr.decode("utf-8", errors="replace"),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return result.returncode if result.returncode is not None else 1


def device_supported_channel(args: argparse.Namespace) -> int:
    result = run_command(["/usr/bin/steamos-select-branch", args.channel], timeout=60)
    print(
        json.dumps(
            {
                "schema": "sm8550-suspend-lab-supported-channel/%d" % SCHEMA_VERSION,
                "captured_at": utc_now(),
                "channel": args.channel,
                "command": result.command,
                "result": result.as_json(),
                "stdout_text": result.stdout.decode("utf-8", errors="replace"),
                "stderr_text": result.stderr.decode("utf-8", errors="replace"),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return result.returncode if result.returncode is not None else 1


def device_archive(args: argparse.Namespace) -> int:
    run = DeviceRun(Path(args.root), args.run_id)
    if not run.run_dir.is_dir():
        raise LabError("run directory does not exist: %s" % run.run_dir)
    # stdout is reserved for the gzip stream; diagnostics go to stderr so the
    # host can safely consume this through the narrow agent sudo rule.
    with tarfile.open(fileobj=sys.stdout.buffer, mode="w|gz") as archive:
        archive.add(str(run.run_dir), arcname=run.run_id, recursive=True)
    return 0


def host_git_manifest(repo_root: Path) -> Dict[str, Any]:
    def git_output(command: Sequence[str]) -> Dict[str, Any]:
        result = run_command(["git", "-C", str(repo_root)] + list(command), timeout=30)
        return {
            **result.as_json(),
            "stdout": result.stdout.decode("utf-8", errors="replace"),
            "stderr": result.stderr.decode("utf-8", errors="replace"),
        }

    source_file = Path(__file__).resolve()
    source_bytes = source_file.read_bytes()
    file_hashes: Dict[str, str] = {}
    for relative in (
        "Containerfile",
        "system_files/usr/bin/armada-sleep-debug",
        "system_files/usr/libexec/armada/suspend-dispatch",
        "research/sm8550-suspend-lab/upstream-state.md",
    ):
        candidate = repo_root / relative
        if candidate.is_file():
            file_hashes[relative] = hashlib.sha256(candidate.read_bytes()).hexdigest()
    return {
        "root": str(repo_root),
        "branch": git_output(["branch", "--show-current"]),
        "head": git_output(["rev-parse", "HEAD"]),
        "status": git_output(["status", "--short", "--branch", "--untracked-files=all"]),
        "remotes": git_output(["remote", "-v"]),
        "source_digest": git_output(["ls-files", "-s", "research/sm8550-suspend-lab"]),
        "runner_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "working_tree_file_sha256": file_hashes,
    }


class Remote:
    def __init__(self, target: str, device_root: str):
        if not target:
            raise LabError("set --target or SM8550_SSH_TARGET to the Nova SSH target")
        self.target = target
        self.device_root = device_root
        self.agent = device_root.rstrip("/") + "/bin/sm8550_suspend_lab.py"
        self.ssh_base = [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=5",
            "-o",
            "ServerAliveInterval=5",
            "-o",
            "ServerAliveCountMax=1",
        ]

    def ssh(self, command: Sequence[str], timeout: Optional[float] = 30) -> CommandResult:
        remote_command = shlex.join([str(item) for item in command])
        return run_command(self.ssh_base + [self.target, remote_command], timeout=timeout)

    def sudo_agent(self, command: Sequence[str], timeout: Optional[float] = 30) -> CommandResult:
        return self.ssh(["sudo", "-n", self.agent] + list(command), timeout=timeout)

    def bootstrap(self, local_source: Path) -> None:
        temporary = "/tmp/sm8550-suspend-lab-%s.py" % secrets.token_hex(6)
        copy_result = run_command(
            [
                "scp",
                "-q",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=5",
                str(local_source),
                "%s:%s" % (self.target, temporary),
            ],
            timeout=45,
        )
        if copy_result.returncode != 0:
            raise LabError("scp bootstrap failed: %s" % copy_result.stderr.decode("utf-8", errors="replace"))
        # Once the agent exists, refresh it through the agent itself. This is
        # the command covered by the narrow lab sudoers entry; it avoids
        # granting passwordless execution to an arbitrary /tmp interpreter.
        existing_agent = self.ssh(
            [
                "sudo",
                "-n",
                self.agent,
                "device",
                "install-agent",
                "--root",
                self.device_root,
                "--source",
                temporary,
            ],
            timeout=45,
        )
        if existing_agent.returncode == 0:
            return
        result = self.ssh(
            [
                "sudo",
                "-n",
                "/usr/bin/python3",
                temporary,
                "device",
                "install-agent",
                "--root",
                self.device_root,
                "--source",
                temporary,
            ],
            timeout=45,
        )
        if result.returncode != 0:
            raise LabError("device agent install failed: %s" % result.stderr.decode("utf-8", errors="replace"))

    def ensure_agent(self, local_source: Path) -> None:
        # Bootstrap every time so the run is tied to the exact host checkout
        # source that was recorded in host-manifest.json.
        self.bootstrap(local_source)


def host_run_directory(output_root: Path, run_id: str) -> Path:
    validate_run_id(run_id)
    destination = output_root / run_id
    if destination.exists():
        raise LabError("local run directory already exists: %s" % destination)
    destination.mkdir(parents=True, mode=0o700)
    return destination


def host_start(args: argparse.Namespace) -> Tuple[str, Path]:
    if not args.target:
        raise LabError("set --target or SM8550_SSH_TARGET to the Nova SSH target")
    run_id = validate_run_id(args.run_id or new_run_id())
    output_root = Path(args.output).expanduser().resolve()
    local_run = host_run_directory(output_root, run_id)
    repo_root = Path(__file__).resolve().parents[2]
    host_manifest = {
        "schema": "sm8550-suspend-lab-host/%d" % SCHEMA_VERSION,
        "run_id": run_id,
        "generated_at": utc_now(),
        "host": {
            "hostname": platform.node(),
            "platform": platform.platform(),
            "python": sys.version,
        },
        "ssh_target": args.target,
        "device_root": args.device_root,
        "requested": {
            "label": args.label,
            "mode": args.mode,
            "sleep_seconds": args.sleep_seconds,
            "allow_existing_rtc_wakealarm": args.allow_existing_rtc_wakealarm,
            "wifi_state": args.wifi_state,
            "bluetooth_state": args.bluetooth_state,
            "trace_profile": args.trace_profile,
        },
        "checkout": host_git_manifest(repo_root),
        "upstream_state_document": str(repo_root / "research/sm8550-suspend-lab/upstream-state.md"),
    }
    write_json(local_run / "host-manifest.json", host_manifest)
    remote = Remote(args.target, args.device_root)
    remote.ensure_agent(Path(__file__).resolve())
    command = [
        "device",
        "start",
        "--root",
        args.device_root,
        "--run-id",
        run_id,
        "--label",
        args.label,
        "--mode",
        args.mode,
        "--sleep-seconds",
        str(args.sleep_seconds),
        "--wifi-state",
        args.wifi_state,
        "--bluetooth-state",
        args.bluetooth_state,
        "--trace-profile",
        args.trace_profile,
        "--hypothesis",
        args.hypothesis,
        "--changed-variable",
        args.changed_variable,
        "--recommendation",
        args.recommendation,
        "--confidence",
        args.confidence,
    ]
    if args.allow_existing_rtc_wakealarm:
        command.append("--allow-existing-rtc-wakealarm")
    result = remote.sudo_agent(command, timeout=45)
    if result.returncode != 0:
        raise LabError("remote run launch failed: %s" % result.stderr.decode("utf-8", errors="replace"))
    output = result.stdout.decode("utf-8", errors="replace").strip()
    print("run_id=%s" % run_id)
    print("local_output=%s" % local_run)
    if output:
        print(output)
    return run_id, local_run


def parse_remote_json(result: CommandResult) -> Dict[str, Any]:
    text = result.stdout.decode("utf-8", errors="replace").strip()
    if not text:
        return {}
    try:
        return json.loads(text)
    except ValueError:
        for line in reversed(text.splitlines()):
            try:
                return json.loads(line)
            except ValueError:
                continue
    return {"raw": text}


def host_status(args: argparse.Namespace) -> Dict[str, Any]:
    remote = Remote(args.target, args.device_root)
    result = remote.sudo_agent(["device", "status", "--root", args.device_root, "--run-id", args.run_id], timeout=15)
    if result.returncode != 0:
        raise LabError(result.stderr.decode("utf-8", errors="replace") or "remote status failed")
    status = parse_remote_json(result)
    print(json.dumps(status, indent=2, sort_keys=True))
    return status


def host_preflight(args: argparse.Namespace) -> Path:
    remote = Remote(args.target, args.device_root)
    remote.ensure_agent(Path(__file__).resolve())
    result = remote.sudo_agent(["device", "preflight", "--root", args.device_root], timeout=180)
    if result.returncode != 0:
        raise LabError(result.stderr.decode("utf-8", errors="replace") or "remote preflight failed")
    device = parse_remote_json(result)
    output_root = Path(args.output).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    name = "preflight-%s-%s.json" % (
        dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        secrets.token_hex(6),
    )
    destination = output_root / name
    write_json(
        destination,
        {
            "schema": "sm8550-suspend-lab-host-preflight/%d" % SCHEMA_VERSION,
            "captured_at": utc_now(),
            "ssh_target": args.target,
            "device_root": args.device_root,
            "checkout": host_git_manifest(Path(__file__).resolve().parents[2]),
            "device": device,
        },
    )
    print("preflight=%s" % destination)
    print(json.dumps(device, indent=2, sort_keys=True))
    return destination


def host_supported_update(args: argparse.Namespace) -> int:
    remote = Remote(args.target, args.device_root)
    remote.ensure_agent(Path(__file__).resolve())
    result = remote.sudo_agent(
        [
            "device",
            "supported-update",
            "--root",
            args.device_root,
            "--action",
            args.action,
        ],
        timeout=1860,
    )
    receipt = parse_remote_json(result)
    output_root = Path(args.output).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    name = "supported-update-%s-%s.json" % (
        dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        secrets.token_hex(6),
    )
    destination = output_root / name
    write_json(
        destination,
        {
            "schema": "sm8550-suspend-lab-host-supported-update/%d" % SCHEMA_VERSION,
            "captured_at": utc_now(),
            "ssh_target": args.target,
            "device_root": args.device_root,
            "action": args.action,
            "checkout": host_git_manifest(Path(__file__).resolve().parents[2]),
            "remote_returncode": result.returncode,
            "remote_stderr": result.stderr.decode("utf-8", errors="replace"),
            "device": receipt,
        },
    )
    print("supported_update=%s" % destination)
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return result.returncode if result.returncode is not None else 1


def host_supported_channel(args: argparse.Namespace) -> int:
    remote = Remote(args.target, args.device_root)
    remote.ensure_agent(Path(__file__).resolve())
    result = remote.sudo_agent(
        [
            "device",
            "supported-channel",
            "--root",
            args.device_root,
            "--channel",
            args.channel,
        ],
        timeout=90,
    )
    receipt = parse_remote_json(result)
    output_root = Path(args.output).expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    name = "supported-channel-%s-%s.json" % (
        dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        secrets.token_hex(6),
    )
    destination = output_root / name
    write_json(
        destination,
        {
            "schema": "sm8550-suspend-lab-host-supported-channel/%d" % SCHEMA_VERSION,
            "captured_at": utc_now(),
            "ssh_target": args.target,
            "device_root": args.device_root,
            "channel": args.channel,
            "checkout": host_git_manifest(Path(__file__).resolve().parents[2]),
            "remote_returncode": result.returncode,
            "remote_stderr": result.stderr.decode("utf-8", errors="replace"),
            "device": receipt,
        },
    )
    print("supported_channel=%s" % destination)
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return result.returncode if result.returncode is not None else 1


def host_recover(args: argparse.Namespace) -> Dict[str, Any]:
    remote = Remote(args.target, args.device_root)
    result = remote.sudo_agent(["device", "recover", "--root", args.device_root, "--run-id", args.run_id], timeout=180)
    if result.returncode != 0:
        raise LabError(result.stderr.decode("utf-8", errors="replace") or "remote recovery failed")
    status = parse_remote_json(result)
    print(json.dumps(status, indent=2, sort_keys=True))
    return status


def safe_extract_stream(stream: Any, destination: Path, run_id: str) -> None:
    destination.mkdir(parents=True, mode=0o700)
    prefix = run_id + "/"
    with tarfile.open(fileobj=stream, mode="r|gz") as archive:
        for member in archive:
            if member.name.rstrip("/") == run_id:
                continue
            if not member.name.startswith(prefix):
                raise LabError("retrieved archive contained an unexpected member")
            relative = Path(member.name[len(prefix) :])
            if not relative.parts:
                continue
            target = destination.joinpath(*relative.parts)
            resolved_destination = destination.resolve()
            try:
                target.resolve().relative_to(resolved_destination)
            except ValueError as exc:
                raise LabError("retrieved archive path escaped output directory") from exc
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            if not member.isfile():
                raise LabError("retrieved archive contained an unsupported non-file member")
            target.parent.mkdir(parents=True, exist_ok=True)
            extracted = archive.extractfile(member)
            if extracted is None:
                raise LabError("retrieved archive file could not be read")
            with open(target, "wb") as handle:
                shutil.copyfileobj(extracted, handle)
            os.chmod(target, member.mode & 0o777 or 0o600)


def verify_checksums(destination: Path) -> Dict[str, Any]:
    checksum_file = destination / "checksums.sha256"
    data = read_text(checksum_file)
    if data is None:
        return {"available": False}
    checked = 0
    mismatches: List[Dict[str, Any]] = []
    for line in data.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]):
            mismatches.append({"line": line, "error": "malformed checksum entry"})
            continue
        relative = Path(parts[1].lstrip("*"))
        if relative.is_absolute() or ".." in relative.parts:
            mismatches.append({"path": parts[1], "error": "unsafe checksum path"})
            continue
        source = destination.joinpath(*relative.parts)
        if not source.is_file():
            mismatches.append({"path": parts[1], "error": "missing"})
            continue
        checked += 1
        actual = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual != parts[0]:
            mismatches.append({"path": parts[1], "expected": parts[0], "actual": actual})
    return {"available": True, "checked": checked, "mismatches": mismatches, "ok": not mismatches}


def host_retrieve(args: argparse.Namespace) -> Path:
    run_id = validate_run_id(args.run_id)
    output_root = Path(args.output).expanduser().resolve()
    local_run = output_root / run_id
    if not local_run.is_dir():
        raise LabError("local host manifest directory does not exist: %s" % local_run)
    destination = local_run / "device"
    if destination.exists():
        raise LabError("device evidence already retrieved at %s" % destination)
    partial = local_run / "device.partial"
    if partial.exists():
        raise LabError("partial retrieval exists at %s; inspect or remove it before retrying")
    remote = Remote(args.target, args.device_root)
    status_result = remote.sudo_agent(["device", "status", "--root", args.device_root, "--run-id", run_id], timeout=15)
    if status_result.returncode != 0:
        raise LabError(status_result.stderr.decode("utf-8", errors="replace") or "could not read remote run status")
    remote_status = parse_remote_json(status_result)
    if remote_status.get("state") not in ("complete", "failed", "recovered", "cancelled"):
        raise LabError("refusing to retrieve a run that is still active; current state is %s" % remote_status.get("state"))
    remote_command = shlex.join(
        [
            "sudo",
            "-n",
            remote.agent,
            "device",
            "archive",
            "--root",
            args.device_root,
            "--run-id",
            run_id,
        ]
    )
    process = subprocess.Popen(remote.ssh_base + [args.target, remote_command], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert process.stdout is not None
    try:
        safe_extract_stream(process.stdout, partial, run_id)
    except BaseException:
        with contextlib.suppress(OSError):
            process.kill()
        process.wait()
        raise
    stderr = process.stderr.read().decode("utf-8", errors="replace") if process.stderr is not None else ""
    returncode = process.wait()
    if returncode != 0:
        raise LabError("evidence retrieval failed: %s" % stderr)
    os.replace(partial, destination)
    verification = verify_checksums(destination)
    write_json(local_run / "checksum-verification.json", verification)
    if verification.get("available") and not verification.get("ok"):
        raise LabError("retrieved evidence failed checksum verification; see checksum-verification.json")
    summary = read_bytes(destination / "derived/summary.json")
    if summary is not None:
        write_host_result(local_run, json.loads(summary.decode("utf-8")))
    print("retrieved=%s" % local_run)
    return local_run


def write_host_result(local_run: Path, summary: Dict[str, Any]) -> None:
    host_manifest = read_bytes(local_run / "host-manifest.json")
    host_data = json.loads(host_manifest.decode("utf-8")) if host_manifest else {}
    metrics = summary.get("metrics", {})
    config = summary.get("config", {})
    checkout = host_data.get("checkout", {})
    lines = [
        "# SM8550 suspend lab run %s" % summary.get("run_id"),
        "",
        "- Hypothesis: %s" % config.get("hypothesis", "Measure the current Armada suspend path without making a kernel change."),
        "- Single changed variable: %s" % config.get("changed_variable", "RTC wake alarm and requested sleep mode; no kernel or firmware change."),
        "- Exact build identifiers/hashes: host HEAD `%s`; runner SHA is in `host-manifest.json`; kernel release `%s`; Armada version `%s`; image/package receipts are in `device/pre/provenance.json`." % (
            (checkout.get("head", {}) or {}).get("stdout", "").strip(),
            summary.get("provenance", {}).get("kernel_release_before", "unavailable"),
            summary.get("provenance", {}).get("armada_version_file", "unavailable"),
        ),
        "- Exact commands: see `device/raw/commands/`; the autonomous agent invoked `/usr/libexec/armada/suspend-dispatch` after arming the RTC, not `rtcwake -m freeze` or a direct systemd suspend service start.",
        "- Raw evidence path: `device/raw/`; before/after snapshots are `device/pre/` and `device/post/`.",
        "- Derived metrics: sleep observed = `%s`; suspend-clock separation = `%s` seconds (`%s`); suspend success = `%s`; wake = `%s`; AOSD count delta = `%s`; CXSD count delta = `%s`." % (
            metrics.get("sleep_observed"),
            metrics.get("suspend_clock_separation_seconds"),
            metrics.get("suspend_clock_separation_status"),
            metrics.get("suspend_success"),
            metrics.get("expected_vs_actual_wake"),
            metrics.get("qcom_sleep_deltas", {}).get("aosd", {}).get("count_delta"),
            metrics.get("qcom_sleep_deltas", {}).get("cxsd", {}).get("count_delta"),
        ),
        "- Conclusion: this run is an observation receipt; it does not by itself establish causality or a safe optimization.",
        "- Confidence: %s" % config.get("confidence", "single-cycle evidence; repeat identical clean cycles before drawing a platform conclusion"),
        "- Recommended next experiment: %s" % config.get("recommendation", "Repeat the exact same mode and physical-cable state for an independent clean cycle."),
        "",
    ]
    atomic_write_text(local_run / "result.md", "\n".join(lines))


def host_wait_and_retrieve(args: argparse.Namespace, run_id: str) -> int:
    started = monotonic_seconds()
    offline_reported = False
    recovered = False
    timeout = max(180, args.sleep_seconds + 180)
    while monotonic_seconds() - started < timeout:
        try:
            status = host_status(
                argparse.Namespace(
                    target=args.target,
                    device_root=args.device_root,
                    run_id=run_id,
                )
            )
            offline_reported = False
            before = status.get("boot_id_before")
            current = status.get("current_boot_id")
            state = status.get("state")
            if before and current and before != current and not recovered and state not in ("complete", "failed", "recovered"):
                recovered = True
                host_recover(
                    argparse.Namespace(target=args.target, device_root=args.device_root, run_id=run_id)
                )
                state = "recovered"
            if state in ("complete", "failed", "recovered", "cancelled"):
                host_retrieve(
                    argparse.Namespace(
                        target=args.target,
                        device_root=args.device_root,
                        run_id=run_id,
                        output=args.output,
                    )
                )
                # "recovered" means the evidence was recovered after a reset;
                # the summary deliberately keeps that suspend attempt failed.
                return 0 if state == "complete" else 1
        except (LabError, OSError) as exc:
            if not offline_reported:
                print("device temporarily unreachable; SSH loss is expected during suspend: %s" % exc, file=sys.stderr)
                offline_reported = True
        time.sleep(max(1, min(30, args.poll_seconds)))
    print(
        "wait timeout; run remains on the device. Use status/recover/retrieve with run_id=%s" % run_id,
        file=sys.stderr,
    )
    return 2


def self_test() -> int:
    valid = new_run_id()
    assert RUN_ID_RE.fullmatch(valid)
    for invalid in ("bad", "20260901T000000Z-ABCDEF123456", "20260901T000000Z-1234"):
        try:
            validate_run_id(invalid)
        except LabError:
            pass
        else:
            raise AssertionError("invalid run ID accepted: %s" % invalid)
    interrupts = parse_interrupts("           CPU0       CPU1\n  170:          3          4 mmc0\n  171:          2          0 rtc0")
    assert interrupts["170"]["total"] == 7
    assert interrupts["171"]["details"] == "rtc0"
    stats = parse_qcom_stat("Count: 3\nAccumulated Duration: 42\n")
    assert stats["count"] == 3 and stats["accumulated_duration"] == 42
    events = parse_trace_events("irq:irq_handler_entry\npower:device_pm_callback_start\nnot-an-event\n")
    assert events == ["irq:irq_handler_entry", "power:device_pm_callback_start"]
    rsc_snapshots = parse_rpmh_rsc_snapshots(
        "  suspend-1 [000] .... 1.0: rpmh_rsc_snapshot: apps_rsc: "
        "phase=pre-suspend group=sleep tcs=3 cmd=0 version=3.0 "
        "tcs_in_use=0 irq_status=0x0 tcs_status=0x1 control=0x0 "
        "cmd_enable=0x1 command_enabled=1 msgid=0x0 addr=0x50000 "
        "resource=MC0 data=0x1 cmd_status=0x0 resp_data=0x0\n"
    )
    assert rsc_snapshots["event_count"] == 1
    assert rsc_snapshots["events"][0]["addr"] == 0x50000
    assert rsc_snapshots["events"][0]["resource"] == "MC0"
    assert trace_pm_filter("field:__data_loc char[] device;\n") == 'device ~ ".*ufs.*"'
    assert trace_pm_filter("field:int event;\n") is None
    sources = parse_wakeup_sources("name active_count event_count wakeup_count expire_count\nrtc0 0 2 1 0\n")
    assert sources["rtc0"]["wakeup_count"] == 1
    cmd_db = parse_cmd_db_dump(
        "Command DB DUMP\n"
        "Slave BCM (v16.0)\n"
        "-------------------------\n"
        "0x50000: MC0 [40 16 40 00 10 00 00 00]\n"
        "Slave VRM (v1.0)\n"
        "-------------------------\n"
        "0x41500: ldob8 [01 4b 00 00]\n"
    )
    assert cmd_db["resource_count"] == 2
    assert cmd_db["resources"][0]["accelerator"] == "BCM"
    assert cmd_db["resources"][1]["name"] == "ldob8"
    interconnect = parse_interconnect_summary(
        " node tag avg peak\n"
        "----------------\n"
        "llcc_mc@interconnect-1 10 20\n"
        "  1d84000.ufshc 7 0 0\n"
    )
    assert interconnect["aggregate_count"] == 1
    assert interconnect["consumers"][0]["parent"] == "llcc_mc@interconnect-1"
    graph = parse_interconnect_graph(
        "digraph {\n"
        "\tsubgraph cluster_1 {\n"
        "\t\tlabel = \"interconnect-1\"\n"
        "\t\t\"100008:llcc_mc@interconnect-1\" [label=\"llcc_mc@interconnect-1\n"
        "\t\t\t|avg_bw=10kBps\n"
        "\t\t\t|peak_bw=20kBps\"]\n"
        "\t}\n"
        "}\n"
    )
    assert graph["node_count"] == 1
    assert graph["nodes"][0]["cluster"] == "interconnect-1"
    genpd = parse_pm_genpd_summary(
        "domain status children performance\n"
        "cx on 64\n"
        "    1d84000.ufshc active 64 SW\n"
    )
    assert genpd["domain_count"] == 1
    assert genpd["devices"][0]["usage"] == 64
    assert expected_wake_text_matches("pm8xxx_rtc_alarm", "rtc0")
    assert expected_wake_text_matches("c400000.spmi:rtc@6100", "rtc0")
    assert not expected_wake_text_matches("pmic_pwrkey", "rtc0")
    with tempfile.TemporaryDirectory(prefix="sm8550-suspend-lab-test-") as temporary:
        root = Path(temporary)
        run = DeviceRun(root, valid)
        run.create({"run_id": valid, "unit": "test", "mode": "s2idle"})
        run.update_status(state="testing")
        assert run.load_status()["state"] == "testing"
        fake_pm_debug = root / "pm_debug_messages"
        fake_pm_times = root / "pm_print_times"
        fake_mem_sleep = root / "mem_sleep"
        atomic_write_text(fake_pm_debug, "1\n")
        atomic_write_text(fake_pm_times, "1\n")
        atomic_write_text(fake_mem_sleep, "[s2idle] deep\n")
        write_json(
            run.run_dir / "meta/mutations-before.json",
            {
                "pm_debug_messages": {"path": str(fake_pm_debug), "value": "0", "writable": True},
                "pm_print_times": {"path": str(fake_pm_times), "value": "0", "writable": True},
                "mem_sleep": {"path": str(fake_mem_sleep), "value": "[deep] s2idle", "writable": True},
                "tsens_dynamic_debug": {"available": False, "writable": False, "tsens_lines": []},
            },
        )
        actions = restore_mutations(run)
        assert read_text(fake_pm_debug) == "0"
        assert read_text(fake_pm_times) == "0"
        assert read_text(fake_mem_sleep) == "deep"
        assert len(actions) == 3
        write_json(run.run_dir / "meta/suspend-start.clock.json", {"clock_boottime_ns": 30_000_000_000, "clock_monotonic_ns": 10_000_000_000})
        write_json(run.run_dir / "meta/resume-return.clock.json", {"clock_boottime_ns": 50_000_000_000, "clock_monotonic_ns": 11_000_000_000})
    print("sm8550 suspend lab self-test passed")
    return 0


def add_device_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--root", default=DEFAULT_DEVICE_ROOT)


def add_host_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--target", default=os.environ.get("SM8550_SSH_TARGET"))
    parser.add_argument("--device-root", default=DEFAULT_DEVICE_ROOT)
    parser.add_argument("--output", default=str(default_output_root()))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sides = parser.add_subparsers(dest="side", required=True)
    host = sides.add_parser("host", help="run from the Mac control host")
    host_commands = host.add_subparsers(dest="command", required=True)
    start_defaults = {
        "label": "sm8550-suspend-lab",
        "hypothesis": "On current Armada, characterize whether the Nova can enter its selected real-suspend mode and reach Qualcomm deep-state counters.",
        "changed_variable": "No kernel or firmware change; only a run-scoped RTC alarm and requested sleep mode.",
        "recommendation": "Repeat the exact same mode and physical-cable state for an independent clean cycle.",
        "confidence": "single-cycle evidence; repeat identical clean cycles before drawing a platform conclusion",
    }
    for command_name in ("start", "run"):
        command = host_commands.add_parser(command_name, help="launch a detached run" if command_name == "start" else "launch, wait, and retrieve")
        add_host_common(command)
        command.add_argument("--run-id")
        command.add_argument("--label", default=start_defaults["label"])
        command.add_argument("--mode", choices=("s2idle", "deep", "policy"), default="s2idle")
        command.add_argument("--sleep-seconds", type=int, default=45)
        command.add_argument("--poll-seconds", type=int, default=5)
        command.add_argument("--wifi-state", choices=("preserve", "off", "on"), default="preserve")
        command.add_argument("--bluetooth-state", choices=("preserve", "off", "on"), default="preserve")
        command.add_argument("--trace-profile", choices=TRACE_PROFILE_CHOICES, default="none")
        command.add_argument("--allow-existing-rtc-wakealarm", action="store_true")
        command.add_argument("--hypothesis", default=start_defaults["hypothesis"])
        command.add_argument("--changed-variable", default=start_defaults["changed_variable"])
        command.add_argument("--recommendation", default=start_defaults["recommendation"])
        command.add_argument("--confidence", default=start_defaults["confidence"])
    for command_name, help_text in (
        ("status", "read remote run status"),
        ("retrieve", "retrieve a completed run"),
        ("recover", "finalize a run after a reboot or lost detached unit"),
        ("cancel", "cancel a run before suspend begins"),
    ):
        command = host_commands.add_parser(command_name, help=help_text)
        add_host_common(command)
        command.add_argument("run_id")
    preflight = host_commands.add_parser("preflight", help="run a fresh read-only device inventory")
    add_host_common(preflight)
    supported_update = host_commands.add_parser("supported-update", help="run Armada's shipped steamos-update hook")
    add_host_common(supported_update)
    supported_update.add_argument("--action", choices=("check", "stage", "apply"), required=True)
    supported_channel = host_commands.add_parser("supported-channel", help="select a channel through Armada's shipped selector")
    add_host_common(supported_channel)
    supported_channel.add_argument("--channel", choices=("rel", "beta", "main", "preview"), required=True)
    host_commands.add_parser("self-test", help="run host-only parser and storage tests")

    device = sides.add_parser("device", help="run on the Armada target")
    device_commands = device.add_subparsers(dest="command", required=True)
    install = device_commands.add_parser("install-agent")
    add_device_common(install)
    install.add_argument("--source", required=True)
    hash_agent = device_commands.add_parser("hash-agent")
    add_device_common(hash_agent)
    preflight = device_commands.add_parser("preflight")
    add_device_common(preflight)
    supported_update = device_commands.add_parser("supported-update")
    add_device_common(supported_update)
    supported_update.add_argument("--action", choices=("check", "stage", "apply"), required=True)
    supported_channel = device_commands.add_parser("supported-channel")
    add_device_common(supported_channel)
    supported_channel.add_argument("--channel", choices=("rel", "beta", "main", "preview"), required=True)
    archive = device_commands.add_parser("archive")
    add_device_common(archive)
    archive.add_argument("--run-id", required=True)
    start = device_commands.add_parser("start")
    add_device_common(start)
    start.add_argument("--run-id", required=True)
    start.add_argument("--label", required=True)
    start.add_argument("--mode", choices=("s2idle", "deep", "policy"), required=True)
    start.add_argument("--sleep-seconds", type=int, required=True)
    start.add_argument("--wifi-state", choices=("preserve", "off", "on"), required=True)
    start.add_argument("--bluetooth-state", choices=("preserve", "off", "on"), required=True)
    start.add_argument("--trace-profile", choices=TRACE_PROFILE_CHOICES, required=True)
    start.add_argument("--hypothesis", required=True)
    start.add_argument("--changed-variable", required=True)
    start.add_argument("--recommendation", required=True)
    start.add_argument("--confidence", required=True)
    start.add_argument("--allow-existing-rtc-wakealarm", action="store_true")
    execute = device_commands.add_parser("execute")
    add_device_common(execute)
    execute.add_argument("--run-id", required=True)
    for command_name in ("status", "recover", "cancel"):
        command = device_commands.add_parser(command_name)
        add_device_common(command)
        command.add_argument("--run-id", required=True)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.side == "host":
            if args.command == "self-test":
                return self_test()
            if args.command == "start":
                host_start(args)
                return 0
            if args.command == "run":
                run_id, _local_run = host_start(args)
                return host_wait_and_retrieve(args, run_id)
            if args.command == "status":
                host_status(args)
                return 0
            if args.command == "preflight":
                host_preflight(args)
                return 0
            if args.command == "supported-update":
                return host_supported_update(args)
            if args.command == "supported-channel":
                return host_supported_channel(args)
            if args.command == "recover":
                host_recover(args)
                return 0
            if args.command == "retrieve":
                host_retrieve(args)
                return 0
            if args.command == "cancel":
                remote = Remote(args.target, args.device_root)
                result = remote.sudo_agent(["device", "cancel", "--root", args.device_root, "--run-id", args.run_id], timeout=30)
                if result.returncode != 0:
                    raise LabError(result.stderr.decode("utf-8", errors="replace") or "remote cancellation failed")
                print(result.stdout.decode("utf-8", errors="replace"), end="")
                return 0
        if args.side == "device":
            if args.command == "install-agent":
                return device_install_agent(args)
            if args.command == "hash-agent":
                return device_hash_agent(args)
            if args.command == "preflight":
                return device_preflight(args)
            if args.command == "supported-update":
                return device_supported_update(args)
            if args.command == "supported-channel":
                return device_supported_channel(args)
            if args.command == "archive":
                return device_archive(args)
            if args.command == "start":
                return device_start(args)
            if args.command == "execute":
                return device_execute(args)
            if args.command == "status":
                return device_status(args)
            if args.command == "recover":
                return device_recover(args)
            if args.command == "cancel":
                return device_cancel(args)
    except LabError as exc:
        print("sm8550-suspend-lab: %s" % exc, file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("sm8550-suspend-lab: interrupted", file=sys.stderr)
        return 130
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

"""Operator QA: decode real subscriber channels through POTV's signed proxy.

Read-only to production. Requires a configured VPS, FFmpeg (or an isolated
container running it), and a valid private NOVA snapshot. Never prints stream
URLs, signing keys, account data, or provider credentials.

Example:
  python qa_signed_stream_decode.py --env-file /opt/potv-bot/.env \
    --ffmpeg-command "docker exec potv-qa-ffmpeg ffmpeg" --workers 3
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from urllib.parse import unquote, urlsplit

from content_gateway import ContentGateway

SAMPLES = (
    ("TUDN", "TUDN"),
    ("NFL Network", "NFL Network"),
    ("Las Estrellas", "Las Estrellas"),
    ("Animal Planet", "ANIMAL PLANET"),
    ("History 2", "History 2"),
    ("Nickelodeon", "Nickelodeon Clásico"),
    ("ESPN 2", "ESPN 2 Latin America (1080p)"),
    ("Canal 5", "Canal 5 (Mexico) XET-TDT"),
    ("Universal", "TV Universal"),
)
_DENIED = {401, 403, 404, 429}


def load_env(path):
    """Load a root-owned systemd-style EnvironmentFile without shell eval."""
    if not path:
        return
    with open(path, encoding="utf-8") as stream:
        for raw in stream:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                os.environ[key] = value.strip().strip('"').strip("'")


def classify(stderr, code):
    if code < 0 or code >= 128:
        return "DECODER_CRASH"
    match = re.search(r"server returned (4[0-9]{2}|5[0-9]{2})", stderr.lower())
    if match:
        return "HTTP_" + match.group(1)
    if "invalid data" in stderr.lower():
        return "INVALID_MEDIA"
    return "DECODE_FAILED"


def choose(rows, name):
    matches = [
        row for row in rows
        if isinstance(row, dict) and
        str(row.get("name") or "").casefold() == name.casefold()
    ]
    matches.sort(key=lambda row: not str(row.get("id") or "").startswith("nova:"))
    return matches[0] if matches else None


def run_qa(*, env_file, ffmpeg_command, seconds, timeout, workers, backups):
    load_env(env_file)
    gateway = ContentGateway()

    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            parsed = urlsplit(self.path)
            prefix = "/api/v1/content/stream/"
            if not parsed.path.startswith(prefix):
                self.send_error(404)
                return
            gateway.serve_target(
                self, unquote(parsed.path[len(prefix):]), parsed.query
            )

    server = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
    server.daemon_threads = True
    Thread(target=server.serve_forever, daemon=True).start()
    gateway.public_base = f"http://127.0.0.1:{server.server_port}"

    def decode(label, channel):
        if channel is None:
            return {"channel": label, "status": "NOT_IN_CATALOG", "attempts": 0}
        candidates = [channel.get("hls_url")]
        candidates.extend(channel.get("backup_urls") or [])
        outcomes = []
        for index, url in enumerate(candidates[: 1 + backups]):
            if not isinstance(url, str) or not url:
                continue
            command = [
                *shlex.split(ffmpeg_command), "-hide_banner", "-nostdin",
                "-loglevel", "error", "-nostats", "-probesize", "700000",
                "-analyzeduration", "2000000", "-rw_timeout", "12000000",
                "-i", url, "-t", str(seconds), "-progress", "pipe:1",
                "-f", "null", "-",
            ]
            start = time.monotonic()
            try:
                proc = subprocess.run(
                    command, capture_output=True, text=True, timeout=timeout,
                    check=False,
                )
                frames = [
                    int(x) for x in re.findall(r"(?m)^frame=\s*([0-9]+)", proc.stdout)
                ]
                timestamps = [
                    int(x) for x in re.findall(r"(?m)^out_time_ms=([0-9]+)", proc.stdout)
                ]
                frame_count = max(frames, default=0)
                played_us = max(timestamps, default=0)
                status = (
                    "DECODED" if proc.returncode == 0
                    and frame_count > 0 and played_us >= 500000
                    else classify(proc.stderr, proc.returncode)
                )
            except subprocess.TimeoutExpired:
                frame_count, played_us, status = 0, 0, "TIMEOUT"
            except OSError:
                frame_count, played_us, status = 0, 0, "FFMPEG_NOT_FOUND"
            outcomes.append({
                "source_index": index,
                "status": status,
                "frames": frame_count,
                "seconds_decoded": round(played_us / 1000000, 2),
                "elapsed_seconds": round(time.monotonic() - start, 2),
            })
            if status == "DECODED" or status == "FFMPEG_NOT_FOUND":
                break
            if status.startswith("HTTP_") and int(status[5:]) in _DENIED:
                break
        passed = next((x for x in outcomes if x["status"] == "DECODED"), None)
        return {
            "channel": label,
            "status": "DECODED" if passed else
                      (outcomes[-1]["status"] if outcomes else "NO_STREAM"),
            "attempts": len(outcomes),
            "source_index": passed["source_index"] if passed else None,
            "frames": passed["frames"] if passed else 0,
            "seconds_decoded": passed["seconds_decoded"] if passed else 0,
        }

    try:
        rows = gateway.catalog_for_subscriber()["data"]["channels"]
        with ThreadPoolExecutor(max_workers=workers) as executor:
            futures = [
                executor.submit(decode, label, choose(rows, exact))
                for label, exact in SAMPLES
            ]
            results = [future.result() for future in as_completed(futures)]
        results.sort(key=lambda row: [x[0] for x in SAMPLES].index(row["channel"]))
        return {
            "tested": len(results),
            "decoded": sum(x["status"] == "DECODED" for x in results),
            "results": results,
        }
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", default="")
    parser.add_argument("--ffmpeg-command", default="ffmpeg")
    parser.add_argument("--seconds", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=25)
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--backups", type=int, default=2)
    args = parser.parse_args()
    if not (1 <= args.seconds <= 10 and 1 <= args.workers <= 9
            and 5 <= args.timeout <= 60 and 0 <= args.backups <= 4):
        parser.error("invalid QA limits")
    report = run_qa(
        env_file=args.env_file, ffmpeg_command=args.ffmpeg_command,
        seconds=args.seconds, timeout=args.timeout, workers=args.workers,
        backups=args.backups,
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))

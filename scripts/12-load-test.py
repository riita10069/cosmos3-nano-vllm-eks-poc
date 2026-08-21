#!/usr/bin/env python3
"""Send a fixed chat-completions payload with controlled client concurrency."""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import math
import statistics
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


@dataclass
class Result:
    latency_seconds: float
    error: Optional[str]


def percentile(values: List[float], fraction: float) -> float:
    if not values:
        raise ValueError("cannot calculate a percentile of no values")
    if len(values) == 1:
        return values[0]

    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def invoke(endpoint: str, body: bytes, timeout_seconds: float) -> Result:
    started = time.perf_counter()
    request = Request(
        endpoint,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            response.read()
            if response.status != 200:
                return Result(
                    latency_seconds=time.perf_counter() - started,
                    error=f"unexpected HTTP status {response.status}",
                )
    except (HTTPError, URLError, TimeoutError) as error:
        return Result(
            latency_seconds=time.perf_counter() - started,
            error=str(error),
        )

    return Result(latency_seconds=time.perf_counter() - started, error=None)


def run_requests(
    executor: concurrent.futures.ThreadPoolExecutor,
    request_count: int,
    concurrency: int,
    endpoint: str,
    body: bytes,
    timeout_seconds: float,
) -> List[Result]:
    pending = {
        executor.submit(invoke, endpoint, body, timeout_seconds)
        for _ in range(min(request_count, concurrency))
    }
    submitted = len(pending)
    results: List[Result] = []

    while pending:
        completed, pending = concurrent.futures.wait(
            pending, return_when=concurrent.futures.FIRST_COMPLETED
        )
        for future in completed:
            results.append(future.result())
            if submitted < request_count:
                pending.add(
                    executor.submit(invoke, endpoint, body, timeout_seconds)
                )
                submitted += 1

    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Measure vLLM continuous batching with a fixed request payload."
    )
    parser.add_argument(
        "--payload",
        type=Path,
        required=True,
        help="Path to one OpenAI chat-completions JSON payload.",
    )
    parser.add_argument(
        "--endpoint",
        default="http://127.0.0.1:8000/v1/chat/completions",
        help="OpenAI-compatible chat-completions endpoint.",
    )
    parser.add_argument(
        "--requests",
        type=int,
        default=40,
        help="Total number of requests to send.",
    )
    parser.add_argument(
        "--concurrency",
        type=int,
        default=4,
        help="Maximum simultaneous in-flight requests. The validated default is 4.",
    )
    parser.add_argument(
        "--warmup-requests",
        type=int,
        default=4,
        help="Requests sent before measurement to warm the serving path.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=float,
        default=300.0,
        help="Per-request HTTP timeout.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.requests < 1:
        raise SystemExit("--requests must be at least 1")
    if args.concurrency < 1:
        raise SystemExit("--concurrency must be at least 1")
    if args.warmup_requests < 0:
        raise SystemExit("--warmup-requests cannot be negative")
    if args.timeout_seconds <= 0:
        raise SystemExit("--timeout-seconds must be greater than zero")

    try:
        payload = json.loads(args.payload.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"cannot read --payload: {error}") from error
    if not isinstance(payload, dict):
        raise SystemExit("--payload must contain one JSON object")

    body = json.dumps(
        payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    payload_sha256 = hashlib.sha256(body).hexdigest()

    with concurrent.futures.ThreadPoolExecutor(
        max_workers=args.concurrency
    ) as executor:
        warmup_results = run_requests(
            executor,
            args.warmup_requests,
            args.concurrency,
            args.endpoint,
            body,
            args.timeout_seconds,
        )
        warmup_errors = [
            result.error for result in warmup_results if result.error is not None
        ]
        if warmup_errors:
            report = {
                "endpoint": args.endpoint,
                "concurrency": args.concurrency,
                "warmup_requests": args.warmup_requests,
                "warmup_failed_requests": len(warmup_errors),
                "requests": args.requests,
                "successful_requests": 0,
                "failed_requests": 0,
                "payload_sha256": payload_sha256,
                "payload_bytes": len(body),
                "wall_seconds": 0,
                "throughput_requests_per_second": 0,
                "latency_seconds": None,
                "warmup_errors": warmup_errors,
                "errors": [],
            }
            print(json.dumps(report, indent=2))
            return 1
        started = time.perf_counter()
        results = run_requests(
            executor,
            args.requests,
            args.concurrency,
            args.endpoint,
            body,
            args.timeout_seconds,
        )

    wall_seconds = time.perf_counter() - started
    latencies = [result.latency_seconds for result in results if result.error is None]
    errors = [result.error for result in results if result.error is not None]
    report = {
        "endpoint": args.endpoint,
        "concurrency": args.concurrency,
        "warmup_requests": args.warmup_requests,
        "warmup_failed_requests": len(warmup_errors),
        "requests": args.requests,
        "successful_requests": len(latencies),
        "failed_requests": len(errors),
        "payload_sha256": payload_sha256,
        "payload_bytes": len(body),
        "wall_seconds": wall_seconds,
        "throughput_requests_per_second": len(latencies) / wall_seconds,
        "latency_seconds": None
        if not latencies
        else {
            "mean": statistics.fmean(latencies),
            "p50": percentile(latencies, 0.50),
            "p95": percentile(latencies, 0.95),
            "max": max(latencies),
            "p95_definition": "linear interpolation of the inclusive ordered sample at p=0.95",
        },
        "warmup_errors": warmup_errors,
        "errors": errors,
    }
    print(json.dumps(report, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())

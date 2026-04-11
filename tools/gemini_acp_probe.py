#!/usr/bin/env python3
import argparse
import json
import queue
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Any


@dataclass
class ACPEvent:
    stream: str
    line: str | None
    timestamp: float


class GeminiACPProbe:
    def __init__(self, model: str, cwd: str) -> None:
        self.model = model
        self.cwd = cwd
        self.process: subprocess.Popen[str] | None = None
        self.stdout_queue: queue.Queue[ACPEvent] = queue.Queue()
        self.stderr_queue: queue.Queue[ACPEvent] = queue.Queue()
        self.request_id = 1

    def start(self) -> None:
        cmd = ["gemini", "--acp", "-m", self.model]
        self.process = subprocess.Popen(
            cmd,
            cwd=self.cwd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

        assert self.process.stdout is not None
        assert self.process.stderr is not None

        threading.Thread(
            target=self._pump,
            args=(self.process.stdout, self.stdout_queue, "stdout"),
            daemon=True,
        ).start()
        threading.Thread(
            target=self._pump,
            args=(self.process.stderr, self.stderr_queue, "stderr"),
            daemon=True,
        ).start()

    def stop(self) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)

    def initialize(self) -> dict[str, Any]:
        return self.send_request(
            "initialize",
            {
                "protocolVersion": 1,
                "clientCapabilities": {
                    "fs": {
                        "readTextFile": False,
                        "writeTextFile": False,
                    },
                    "terminal": False,
                },
                "clientInfo": {
                    "name": "gemini-acp-probe",
                    "version": "0.1",
                },
            },
            timeout=60,
        )

    def new_session(self) -> dict[str, Any]:
        return self.send_request(
            "session/new",
            {
                "cwd": self.cwd,
                "mcpServers": [],
            },
            timeout=60,
        )

    def prompt(self, session_id: str, text: str) -> tuple[dict[str, Any], str]:
        request_id = self.request_id
        self.request_id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": "session/prompt",
            "params": {
                "sessionId": session_id,
                "prompt": [
                    {
                        "type": "text",
                        "text": text,
                    }
                ],
            },
        }
        self._write(payload)

        assistant_chunks: list[str] = []
        deadline = time.time() + 180
        while time.time() < deadline:
            event = self._next_event(timeout=0.5)
            if event is None:
                self._check_process()
                continue

            if event.stream == "stderr":
                self._print_event(event)
                continue

            assert event.line is not None
            self._print_event(event)
            obj = self._parse_json(event.line)
            if obj is None:
                continue

            if obj.get("method") == "session/update":
                params = obj.get("params", {})
                update = params.get("update", {})
                if update.get("sessionUpdate") == "agent_message_chunk":
                    content = update.get("content", {})
                    text_chunk = content.get("text")
                    if isinstance(text_chunk, str):
                        assistant_chunks.append(text_chunk)
                continue

            if obj.get("id") == request_id:
                if "error" in obj:
                    raise RuntimeError(str(obj["error"]))
                result = obj.get("result", {})
                return result, "".join(assistant_chunks).strip()

        raise TimeoutError(f"session/prompt timed out for request id {request_id}")

    def send_request(self, method: str, params: dict[str, Any], timeout: int) -> dict[str, Any]:
        request_id = self.request_id
        self.request_id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": request_id,
            "method": method,
            "params": params,
        }
        self._write(payload)

        deadline = time.time() + timeout
        while time.time() < deadline:
            event = self._next_event(timeout=0.5)
            if event is None:
                self._check_process()
                continue

            self._print_event(event)
            if event.stream != "stdout" or event.line is None:
                continue

            obj = self._parse_json(event.line)
            if obj is None:
                continue

            if obj.get("id") != request_id:
                continue

            if "error" in obj:
                raise RuntimeError(str(obj["error"]))

            result = obj.get("result", {})
            if not isinstance(result, dict):
                raise RuntimeError(f"Unexpected result payload for {method}: {result!r}")
            return result

        raise TimeoutError(f"{method} timed out after {timeout}s")

    def _check_process(self) -> None:
        if self.process is None:
            raise RuntimeError("Process not started")
        if self.process.poll() is not None:
            raise RuntimeError(f"gemini ACP exited with status {self.process.returncode}")

    def _next_event(self, timeout: float) -> ACPEvent | None:
        try:
            return self.stdout_queue.get(timeout=timeout)
        except queue.Empty:
            pass

        try:
            return self.stderr_queue.get_nowait()
        except queue.Empty:
            return None

    def _write(self, payload: dict[str, Any]) -> None:
        if self.process is None or self.process.stdin is None:
            raise RuntimeError("Process stdin is not available")
        encoded = json.dumps(payload)
        print(f"[send {self._clock()}] {encoded}", flush=True)
        self.process.stdin.write(encoded + "\n")
        self.process.stdin.flush()

    @staticmethod
    def _pump(
        stream: Any,
        destination: queue.Queue[ACPEvent],
        name: str,
    ) -> None:
        for line in stream:
            destination.put(ACPEvent(name, line.rstrip("\n"), time.time()))
        destination.put(ACPEvent(name, None, time.time()))

    @staticmethod
    def _parse_json(line: str) -> dict[str, Any] | None:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            return None
        return obj if isinstance(obj, dict) else None

    @staticmethod
    def _clock() -> str:
        return time.strftime("%H:%M:%S")

    def _print_event(self, event: ACPEvent) -> None:
        print(f"[{event.stream} {time.strftime('%H:%M:%S', time.localtime(event.timestamp))}] {event.line}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Gemini CLI ACP with repeated prompts.")
    parser.add_argument("--model", default="gemini-3-flash-preview")
    parser.add_argument("--cwd", required=True)
    args = parser.parse_args()

    probe = GeminiACPProbe(model=args.model, cwd=args.cwd)
    probe.start()

    try:
        initialize = probe.initialize()
        print(f"\ninitialize agent={initialize.get('agentInfo')} loadSession={initialize.get('agentCapabilities', {}).get('loadSession')}", flush=True)

        session = probe.new_session()
        session_id = session.get("sessionId")
        print(f"session_id={session_id}", flush=True)
        if not isinstance(session_id, str):
            raise RuntimeError("session/new did not return a sessionId")

        prompts = [
            "Reply with exactly: FIRST_OK",
            "Reply with exactly: SECOND_OK",
            "Reply with exactly: THIRD_OK",
        ]

        for index, prompt_text in enumerate(prompts, start=1):
            print(f"\n--- prompt {index} ---", flush=True)
            result, text = probe.prompt(session_id, prompt_text)
            print(f"stop_reason={result.get('stopReason')} text={text!r}", flush=True)

        return 0
    finally:
        probe.stop()


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
import uuid
from dataclasses import dataclass, field


PROTOCOL_VERSION = 1


@dataclass
class SessionState:
    session_id: str
    cwd: str
    history: list[dict[str, str]] = field(default_factory=list)


class ACPError(Exception):
    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


class CodexACPAdapter:
    def __init__(self, model: str) -> None:
        self.model = model
        self.sessions: dict[str, SessionState] = {}

    def serve(self) -> int:
        for raw_line in sys.stdin:
            line = raw_line.strip()
            if not line:
                continue

            try:
                request = json.loads(line)
            except json.JSONDecodeError:
                continue

            if not isinstance(request, dict):
                continue

            request_id = request.get("id")
            method = request.get("method")
            params = request.get("params", {})

            try:
                if not isinstance(method, str):
                    raise ACPError(-32600, "Invalid request")

                result = self.handle_request(method, params)
                if request_id is not None:
                    self.send({"jsonrpc": "2.0", "id": request_id, "result": result})
            except ACPError as error:
                if request_id is not None:
                    self.send(
                        {
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "error": {"code": error.code, "message": error.message},
                        }
                    )
            except Exception as error:  # pragma: no cover
                if request_id is not None:
                    self.send(
                        {
                            "jsonrpc": "2.0",
                            "id": request_id,
                            "error": {"code": -32000, "message": str(error)},
                        }
                    )

        return 0

    def handle_request(self, method: str, params: object) -> dict:
        if not isinstance(params, dict):
            raise ACPError(-32602, "Invalid params")

        if method == "initialize":
            return self.handle_initialize()
        if method == "session/new":
            return self.handle_session_new(params)
        if method == "session/load":
            return self.handle_session_load(params)
        if method == "session/prompt":
            return self.handle_session_prompt(params)

        raise ACPError(-32601, f"Unsupported ACP method {method}")

    def handle_initialize(self) -> dict:
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "agentInfo": {
                "name": "codex-acp-adapter",
                "title": "Codex ACP Adapter",
                "version": "0.1",
            },
            "agentCapabilities": {
                "loadSession": False,
                "promptCapabilities": {
                    "image": False,
                    "audio": False,
                    "embeddedContext": False,
                },
                "mcpCapabilities": {
                    "http": False,
                    "sse": False,
                },
            },
            "authMethods": [],
        }

    def handle_session_new(self, params: dict) -> dict:
        cwd = params.get("cwd")
        if not isinstance(cwd, str) or not cwd:
            raise ACPError(-32602, "session/new requires cwd")

        session_id = f"codex-{uuid.uuid4()}"
        self.sessions[session_id] = SessionState(session_id=session_id, cwd=cwd)
        return {"sessionId": session_id}

    def handle_session_load(self, params: dict) -> dict:
        session_id = params.get("sessionId")
        if not isinstance(session_id, str) or session_id not in self.sessions:
            raise ACPError(-32001, "Unknown sessionId")
        return {"sessionId": session_id}

    def handle_session_prompt(self, params: dict) -> dict:
        session_id = params.get("sessionId")
        if not isinstance(session_id, str):
            raise ACPError(-32602, "session/prompt requires sessionId")

        session = self.sessions.get(session_id)
        if session is None:
            raise ACPError(-32001, "Unknown sessionId")

        prompt_items = params.get("prompt")
        if not isinstance(prompt_items, list):
            raise ACPError(-32602, "session/prompt requires prompt array")

        prompt_text = "\n".join(
            item.get("text", "")
            for item in prompt_items
            if isinstance(item, dict) and item.get("type") == "text"
        ).strip()
        if not prompt_text:
            raise ACPError(-32602, "session/prompt requires text content")

        session.history.append({"role": "user", "content": prompt_text})
        assistant_text = self.run_codex(session)
        session.history.append({"role": "assistant", "content": assistant_text})

        self.send(
            {
                "jsonrpc": "2.0",
                "method": "session/update",
                "params": {
                    "sessionId": session_id,
                    "update": {
                        "sessionUpdate": "agent_message_chunk",
                        "content": {"type": "text", "text": assistant_text},
                    },
                },
            }
        )
        return {"stopReason": "end_turn", "content": assistant_text}

    def run_codex(self, session: SessionState) -> str:
        transcript = []
        for message in session.history:
            role = message["role"].upper()
            transcript.append(f"{role}:\n{message['content']}")
        prompt = "\n\n".join(transcript)

        command = [
            "codex",
            "exec",
            "-",
            "--skip-git-repo-check",
            "--json",
            "--ephemeral",
            "--color",
            "never",
            "--full-auto",
            "-m",
            self.model,
            "-C",
            session.cwd,
        ]

        env = dict(os.environ)
        process = subprocess.run(
            command,
            input=prompt,
            text=True,
            capture_output=True,
            env=env,
        )

        if process.returncode != 0:
            stderr = process.stderr.strip() or process.stdout.strip() or "Codex exec failed."
            raise ACPError(-32010, stderr)

        assistant_text = self.extract_assistant_text(process.stdout)
        if not assistant_text:
            stderr = process.stderr.strip()
            raise ACPError(-32011, stderr or "Codex exec returned an empty response.")
        return assistant_text

    @staticmethod
    def extract_assistant_text(stdout: str) -> str:
        assistant_text = ""
        for raw_line in stdout.splitlines():
            line = raw_line.strip()
            if not line or not line.startswith("{"):
                continue

            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            if event.get("type") != "item.completed":
                continue

            item = event.get("item", {})
            if isinstance(item, dict) and item.get("type") == "agent_message":
                text = item.get("text")
                if isinstance(text, str) and text.strip():
                    assistant_text = text.strip()

        return assistant_text

    @staticmethod
    def send(payload: dict) -> None:
        encoded = json.dumps(payload, separators=(",", ":"))
        sys.stdout.write(encoded + "\n")
        sys.stdout.flush()


def main() -> int:
    parser = argparse.ArgumentParser(description="ACP adapter for Codex CLI.")
    parser.add_argument("--model", required=True)
    args = parser.parse_args()
    adapter = CodexACPAdapter(model=args.model)
    return adapter.serve()


if __name__ == "__main__":
    raise SystemExit(main())

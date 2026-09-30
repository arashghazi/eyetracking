"""Run a Python module as a background server that writes its own log file.

Used by run-local.ps1: `python run_server.py <log file> <module> [args...]`. The process points its
stdout and stderr at the log file itself, so it keeps working after the PowerShell window that
started it has closed.
"""
import os
import runpy
import sys


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit("usage: run_server.py <log file> <module> [args...]")
    log_path, module, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    log = open(log_path, "a", buffering=1, encoding="utf-8", errors="replace")
    os.dup2(log.fileno(), 1)
    os.dup2(log.fileno(), 2)
    sys.stdout = sys.stderr = log
    sys.stdin = open(os.devnull)
    sys.argv = [module, *args]
    runpy.run_module(module, run_name="__main__", alter_sys=True)


if __name__ == "__main__":
    main()

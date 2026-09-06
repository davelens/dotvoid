#!/usr/bin/env python3
"""Drive a Void live ISO login and installation over QEMU's serial console."""

import os
import selectors
import subprocess
import sys
import time


LOGIN_PROMPT = b"void-live login:"
PASSWORD_PROMPT = b"Password:"
SHELL_PROMPT = b"# "
SUCCESS_MARKER = b"__DOTVOID_INSTALL_SUCCEEDED__"
FAILURE_MARKER = b"__DOTVOID_INSTALL_FAILED__"
TIMEOUT_SECONDS = 45 * 60


def stop_process(process: subprocess.Popen) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <qemu command...>", file=sys.stderr)
        return 2

    process = subprocess.Popen(
        sys.argv[1:],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    assert process.stdin is not None
    assert process.stdout is not None

    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    buffer = b""
    state = "login"
    succeeded = False
    deadline = time.monotonic() + TIMEOUT_SECONDS

    install_command = (
        "mkdir -p /media/repo && "
        "mount -t 9p -o trans=virtio,version=9p2000.L repo /media/repo && "
        "FORCE=1 /media/repo/scripts/install.sh /media/repo/config/vm.env; "
        "rc=$?; "
        "if [ $rc -eq 0 ]; then "
        "printf '%s%s\\n' '__DOTVOID_INSTALL_' 'SUCCEEDED__'; sync; poweroff; "
        "else "
        "printf '%s%s:%s\\n' '__DOTVOID_INSTALL_' 'FAILED__' \"$rc\"; "
        "fi\n"
    ).encode()
    status_buffer = b""
    stdout_open = True

    try:
        while stdout_open or process.poll() is None:
            if process.poll() is None and time.monotonic() > deadline:
                print("\nerror: automated install timed out", file=sys.stderr)
                return 1

            events = selector.select(timeout=1)
            if not events and process.poll() is not None:
                break

            for key, _ in events:
                install_started = False
                chunk = os.read(key.fd, 4096)
                if not chunk:
                    stdout_open = False
                    selector.unregister(key.fileobj)
                    continue
                os.write(sys.stdout.fileno(), chunk)
                buffer = (buffer + chunk)[-8192:]

                if state == "login" and LOGIN_PROMPT in buffer:
                    process.stdin.write(b"root\n")
                    process.stdin.flush()
                    buffer = b""
                    state = "password"
                elif state == "password" and PASSWORD_PROMPT in buffer:
                    process.stdin.write(b"voidlinux\n")
                    process.stdin.flush()
                    buffer = b""
                    state = "shell"
                elif state == "shell" and SHELL_PROMPT in buffer:
                    process.stdin.write(install_command)
                    process.stdin.flush()
                    buffer = b""
                    status_buffer = b""
                    state = "installing"
                    install_started = True

                if state == "installing" and not install_started:
                    status_buffer += chunk
                    while b"\n" in status_buffer:
                        line, status_buffer = status_buffer.split(b"\n", 1)
                        line = line.rstrip(b"\r")
                        if line == SUCCESS_MARKER:
                            succeeded = True
                            state = "poweroff"
                            break
                        failure_prefix = FAILURE_MARKER + b":"
                        failure_status = line[len(failure_prefix):]
                        if (
                            line.startswith(failure_prefix)
                            and failure_status
                            and failure_status.isdigit()
                        ):
                            print("\nerror: guest installer failed", file=sys.stderr)
                            return 1
    except KeyboardInterrupt:
        return 130
    finally:
        selector.close()
        stop_process(process)

    exit_code = process.wait()
    if not succeeded:
        print("\nerror: VM exited before installation completed", file=sys.stderr)
        return 1
    if exit_code != 0:
        print(f"\nerror: VM exited with status {exit_code}", file=sys.stderr)
        return 1

    print("\n==> Automated installation completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

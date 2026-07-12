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
        f"echo {SUCCESS_MARKER.decode()}; sync; poweroff; "
        "else "
        f"echo {FAILURE_MARKER.decode()}:$rc; "
        "fi\n"
    ).encode()

    try:
        while process.poll() is None:
            if time.monotonic() > deadline:
                print("\nerror: automated install timed out", file=sys.stderr)
                process.terminate()
                return 1

            for key, _ in selector.select(timeout=1):
                chunk = os.read(key.fd, 4096)
                if not chunk:
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
                    state = "installing"
                elif state == "installing" and SUCCESS_MARKER in buffer:
                    succeeded = True
                    state = "poweroff"
                elif state == "installing" and FAILURE_MARKER in buffer:
                    print("\nerror: guest installer failed; VM left at shell", file=sys.stderr)
                    process.terminate()
                    return 1
    except KeyboardInterrupt:
        process.terminate()
        return 130
    finally:
        if process.poll() is None:
            process.wait(timeout=10)

    if not succeeded:
        print("\nerror: VM exited before installation completed", file=sys.stderr)
        return 1

    print("\n==> Automated installation completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Run without QEMU: python3 vm/test-auto-install.py."""

import runpy
import subprocess
import sys
from pathlib import Path
from unittest.mock import Mock


driver = Path(__file__).with_name("auto-install.py")
stop_process = runpy.run_path(str(driver))["stop_process"]

process = Mock()
process.poll.return_value = None
process.wait.side_effect = [subprocess.TimeoutExpired("qemu", 10), -9]
stop_process(process)
process.terminate.assert_called_once_with()
process.kill.assert_called_once_with()
assert process.wait.call_count == 2

process.reset_mock()
process.poll.return_value = 0
stop_process(process)
process.terminate.assert_not_called()
process.wait.assert_not_called()


def run_guest(body: str) -> subprocess.CompletedProcess[str]:
    guest = f"""
import sys
print('void-live login:', flush=True)
assert input() == 'root'
print('Password:', flush=True)
assert input() == 'voidlinux'
print('# ', end='', flush=True)
command = input()
assert 'scripts/install.sh' in command
{body}
"""
    return subprocess.run(
        [sys.executable, str(driver), sys.executable, "-u", "-c", guest],
        capture_output=True,
        text=True,
        timeout=15,
    )


result = run_guest("print('echo __DOTVOID_INSTALL_SUCCEEDED__', flush=True)")
assert result.returncode == 1, result.stdout + result.stderr

result = run_guest(
    """
assert '__DOTVOID_INSTALL_SUCCEEDED__' not in command
assert '__DOTVOID_INSTALL_FAILED__' not in command
print(command, flush=True)
print('__DOTVOID_INSTALL_FAILED__:1', flush=True)
"""
)
assert result.returncode == 1, result.stdout + result.stderr
assert "guest installer failed" in result.stderr
assert "VM left at shell" not in result.stderr

result = run_guest("print('__DOTVOID_INSTALL_SUCCEEDED__', flush=True)")
assert result.returncode == 0, result.stdout + result.stderr

result = run_guest(
    """
sys.stdout.write('__DOTVOID_INSTALL_')
sys.stdout.flush()
sys.stdout.write('SUCCEEDED__\\n')
sys.stdout.flush()
"""
)
assert result.returncode == 0, result.stdout + result.stderr

result = run_guest("print('__DOTVOID_INSTALL_FAILED__:1', flush=True)")
assert result.returncode == 1, result.stdout + result.stderr
assert "guest installer failed" in result.stderr

# Closing the console can precede process exit during a normal shutdown.
result = run_guest(
    """
import os
import time
print('__DOTVOID_INSTALL_SUCCEEDED__', flush=True)
os.close(1)
os.close(2)
time.sleep(0.2)
os._exit(0)
"""
)
assert result.returncode == 0, result.stdout + result.stderr

result = run_guest(
    """
print('__DOTVOID_INSTALL_SUCCEEDED__', flush=True)
sys.exit(7)
"""
)
assert result.returncode == 1, result.stdout + result.stderr
assert "VM exited with status 7" in result.stderr

print("Serial automation and shutdown checks passed")

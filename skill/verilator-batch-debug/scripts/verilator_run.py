#!/usr/bin/env python
"""Shim -> fpga/verilator/scripts/verilator_run.py (canonical runner)."""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
# Walk up to the repo root that holds fpga/verilator/scripts, so the same shim
# works from its canonical home under skill/verilator-batch-debug.
_dir = _HERE
while not os.path.isdir(os.path.join(_dir, "fpga", "verilator", "scripts")):
    _parent = os.path.dirname(_dir)
    if _parent == _dir:
        sys.exit("verilator-batch-debug: cannot locate fpga/verilator/scripts")
    _dir = _parent
sys.path.insert(0, os.path.join(_dir, "fpga", "verilator", "scripts"))

from verilator_run import main  # noqa: E402

if __name__ == "__main__":
    main()

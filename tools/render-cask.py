#!/usr/bin/env python3
"""Compatibility entry point: generate all release metadata, including the cask."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name("release-metadata.py")), run_name="__main__")

"""Regenerate every character GLB:  blender --background --python tools/blender/make_all.py [-- --render <dir>]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_common import run  # noqa: E402

for character in ("player", "soldier", "heavy", "elite", "warden"):
    run(character)

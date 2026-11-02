"""Regenerate assets/characters/player.glb:  blender --background --python tools/blender/make_player.py [-- --render <dir>]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_common import run  # noqa: E402

run("player")

#!/usr/bin/env python3
"""
Calradia Online — Deterministic Python 3 Module System Compiler & WSE2 Lua Header Exporter.
Compiles all 29 Warband 1.174 + WSE2 Module System stages and syncs header_*.py / ID_*.py -> lua/msfiles/.
"""

import glob
import os
import shutil
import subprocess
import sys

COMPILER_STEPS = [
    "process_init.py",
    "process_global_variables.py",
    "process_strings.py",
    "process_skills.py",
    "process_music.py",
    "process_animations.py",
    "process_meshes.py",
    "process_sounds.py",
    "process_skins.py",
    "process_map_icons.py",
    "process_factions.py",
    "process_items.py",
    "process_scenes.py",
    "process_troops.py",
    "process_particle_sys.py",
    "process_scene_props.py",
    "process_tableau_materials.py",
    "process_presentations.py",
    "process_party_tmps.py",
    "process_parties.py",
    "process_quests.py",
    "process_info_pages.py",
    "process_scripts.py",
    "process_mission_tmps.py",
    "process_game_menus.py",
    "process_simple_triggers.py",
    "process_dialogs.py",
    "process_global_variables_unused.py",
    "process_postfx.py",
]


def build_all(ms_dir: str | None = None, sync_lua_msfiles: bool = True) -> dict:
    ms_dir = os.path.abspath(ms_dir or os.path.dirname(__file__))
    export_dir = os.path.join(ms_dir, "export")
    os.makedirs(export_dir, exist_ok=True)

    # Run two passes if ID_*.py changes on first pass (guarantees freshly added factions/troops/scripts resolve!)
    for pass_idx in (1, 2):
        for step in COMPILER_STEPS:
            proc = subprocess.run(
                [sys.executable, step],
                cwd=ms_dir,
                capture_output=True,
                text=True,
                check=False,
            )
            combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
            if proc.returncode != 0:
                raise RuntimeError(f"[{step} pass {pass_idx}] exited with {proc.returncode}:\n{combined}")
            # On pass 2, ZERO unresolved symbol / syntax errors may exist!
            if pass_idx == 2:
                for line in combined.splitlines():
                    low = line.lower()
                    if "error" in low or "traceback" in low:
                        raise RuntimeError(f"[{step}] compiler error detected: {line}")

    exported_txt = sorted(os.path.basename(p) for p in glob.glob(os.path.join(export_dir, "*.txt")))

    synced_msfiles = 0
    if sync_lua_msfiles:
        repo_root = os.path.dirname(ms_dir)
        msfiles_dir = os.path.join(repo_root, "lua", "msfiles")
        os.makedirs(msfiles_dir, exist_ok=True)
        for pattern in ("header_*.py", "ID_*.py"):
            for src in sorted(glob.glob(os.path.join(ms_dir, pattern))):
                shutil.copy2(src, os.path.join(msfiles_dir, os.path.basename(src)))
                synced_msfiles += 1

    return {
        "export_dir": export_dir,
        "txt_count": len(exported_txt),
        "txt_files": exported_txt,
        "synced_msfiles": synced_msfiles,
    }


if __name__ == "__main__":
    summary = build_all()
    print(
        f"[CalradiaOnline] Compiled {summary['txt_count']} .txt files into {summary['export_dir']} "
        f"and synced {summary['synced_msfiles']} WSE2 msfiles headers!"
    )

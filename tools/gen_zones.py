"""Generates the story's open zones as map files (maps/<id>.json, listed in maps/index.json), for
fine-tuning in the map editor afterwards. Each zone is a seeded layout: a wide open area with rock
outcrops (walls), roads carved between its landmarks so everything is reachable, the landmarks'
props, NPCs, quest objects and triggers, and monster packs spread through it (themed by area).

Usage:  python tools/gen_zones.py            (rewrites every zone below; edits made in the editor
                                               to those maps are lost, so copy a map first)
"""
import json
import math
import os
import random
from collections import deque

ROOT = os.path.join(os.path.dirname(__file__), "..")
MAPS = os.path.join(ROOT, "maps")
CELL = 128


def cell_pos(c, dx=0.5, dy=0.5):
    return int((c[0] + dx) * CELL), int((c[1] + dy) * CELL)


class Zone:
    def __init__(self, zid, name, cols, rows, seed):
        self.id, self.name, self.cols, self.rows = zid, name, cols, rows
        self.rng = random.Random(seed)
        self.wall = [[False] * cols for _ in range(rows)]
        self.objects = []
        self.keep_clear = []  # (cell, radius): no outcrops here

    # ---- terrain ----
    def outcrops(self, count, rmin, rmax):
        for _ in range(count):
            cx, cy = self.rng.randrange(self.cols), self.rng.randrange(self.rows)
            rx, ry = self.rng.uniform(rmin, rmax), self.rng.uniform(rmin, rmax) * 0.8
            for y in range(int(cy - ry - 2), int(cy + ry + 3)):
                for x in range(int(cx - rx - 2), int(cx + rx + 3)):
                    if 0 <= x < self.cols and 0 <= y < self.rows:
                        d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                        if d < 1.0 + self.rng.uniform(-0.35, 0.25):
                            self.wall[y][x] = True

    def border(self, thick=2):
        for y in range(self.rows):
            for x in range(self.cols):
                t = thick + (1 if self.rng.random() < 0.35 else 0)
                if x < t or y < t or x >= self.cols - t or y >= self.rows - t:
                    self.wall[y][x] = True

    def smooth(self, rounds=2):
        for _ in range(rounds):
            new = [row[:] for row in self.wall]
            for y in range(1, self.rows - 1):
                for x in range(1, self.cols - 1):
                    n = sum(self.wall[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)) - self.wall[y][x]
                    if n >= 5:
                        new[y][x] = True
                    elif n <= 2:
                        new[y][x] = False
            self.wall = new

    def clear(self, c, r):
        for y in range(c[1] - r, c[1] + r + 1):
            for x in range(c[0] - r, c[0] + r + 1):
                if 1 <= x < self.cols - 1 and 1 <= y < self.rows - 1 and (x - c[0]) ** 2 + (y - c[1]) ** 2 <= r * r + 1:
                    self.wall[y][x] = False

    def road(self, a, b, width=1):
        """A wandering road from a to b (cells), `width` cells to each side of its middle."""
        x, y = a
        while (x, y) != tuple(b):
            self.clear((x, y), width)
            dx, dy = b[0] - x, b[1] - y
            if self.rng.random() < 0.25:  # wander
                step = self.rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
            elif abs(dx) > abs(dy):
                step = (1 if dx > 0 else -1, 0)
            else:
                step = (0, 1 if dy > 0 else -1)
            x = min(max(x + step[0], 2), self.cols - 3)
            y = min(max(y + step[1], 2), self.rows - 3)
        self.clear(b, width)

    def reachable_only(self, start):
        seen = [[False] * self.cols for _ in range(self.rows)]
        q = deque([start])
        seen[start[1]][start[0]] = True
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < self.cols and 0 <= ny < self.rows and not self.wall[ny][nx] and not seen[ny][nx]:
                    seen[ny][nx] = True
                    q.append((nx, ny))
        for y in range(self.rows):
            for x in range(self.cols):
                if not self.wall[y][x] and not seen[y][x]:
                    self.wall[y][x] = True
        return seen

    def open_around(self, c, r=1):
        return all(not self.wall[y][x] for y in range(c[1] - r, c[1] + r + 1) for x in range(c[0] - r, c[0] + r + 1)
                   if 0 <= x < self.cols and 0 <= y < self.rows)

    # ---- objects ----
    def add(self, type_, c, dx=0.5, dy=0.5, **kw):
        x, y = cell_pos(c, dx, dy)
        o = {"type": type_, "x": x, "y": y}
        o.update(kw)
        self.objects.append(o)
        return o

    def prop(self, sprite, c, dx=0.5, dy=0.5, scale=0.5, solid=False):
        return self.add("prop", c, dx, dy, sprite=sprite, scale=scale, solid=solid)

    def packs(self, count, avoid, themes, min_gap=7, min_start=10, start=None):
        """`themes`: [(cell, radius, kind)]; a pack in one of those circles is that kind."""
        placed = []
        tries = 0
        while len(placed) < count and tries < 6000:
            tries += 1
            c = (self.rng.randrange(3, self.cols - 3), self.rng.randrange(3, self.rows - 3))
            if not self.open_around(c, 1):
                continue
            if start and math.dist(c, start) < min_start:
                continue
            if any(math.dist(c, p) < min_gap for p in placed) or any(math.dist(c, a) < r for a, r in avoid):
                continue
            kind = ""
            for tc, tr, tk in themes:
                if math.dist(c, tc) < tr:
                    kind = tk
                    break
            placed.append(c)
            o = {"min": 3, "max": 5}
            if kind:
                o["kind"] = kind
            self.add("pack", c, **o)
        return placed

    def save(self, area_name_kind="story"):
        grid = ["".join("#" if w else "." for w in row) for row in self.wall]
        data = {"format": 1, "id": self.id, "name": self.name, "kind": area_name_kind, "theme": "desert",
                "cell": CELL, "auto_decorate": True, "grid": grid, "objects": self.objects}
        with open(os.path.join(MAPS, self.id + ".json"), "w") as f:
            json.dump(data, f, indent="\t")
        idx_path = os.path.join(MAPS, "index.json")
        idx = json.load(open(idx_path))
        idx["maps"][self.id] = {"kind": area_name_kind, "name": self.name}
        with open(idx_path, "w") as f:
            json.dump(idx, f, indent="\t", sort_keys=True)
        print("wrote", self.id, "%dx%d" % (self.cols, self.rows), sum(o["type"] == "pack" for o in self.objects), "packs")


def dune_wastes():
    z = Zone("dune_wastes", "The Dune Wastes", 70, 46, seed=1101)
    start = (4, 23)
    waypoint = (19, 27)
    wreck = (35, 22)
    camp = (57, 9)
    oasis = (31, 38)
    ruins = (12, 37)
    landmarks = [(start, 4), (waypoint, 3), (wreck, 5), (camp, 6), (oasis, 5), (ruins, 5)]

    z.outcrops(85, 1.5, 5.0)
    z.border(2)
    z.smooth(2)
    for c, r in landmarks:
        z.clear(c, r)
    z.road(start, waypoint, 1)
    z.road(waypoint, wreck, 1)
    z.road(wreck, camp, 1)
    z.road(wreck, oasis, 1)
    z.road(waypoint, ruins, 1)
    z.road(oasis, ruins, 1)
    z.reachable_only(start)

    # The road from Ashfall comes in on the west edge
    z.add("start", start)
    z.add("portal", (start[0] - 2, start[1]), target="town")
    z.clear((start[0] - 2, start[1]), 1)
    z.add("waypoint", waypoint)
    z.prop("decor_3", (start[0] + 2, start[1] - 2), scale=0.5)  # signpost

    # The caravan wreck: wagons on their sides, a dead campfire, a survivor
    z.add("trigger", wreck, radius=420, id="caravan_wreck",
          text="Hesk's caravan... or what's left of it.")
    z.prop("decor_8", (wreck[0] - 2, wreck[1] - 1), scale=0.55, solid=True)
    z.prop("decor_8", (wreck[0] + 2, wreck[1] + 1), scale=0.5, solid=True)
    z.prop("decor_4", (wreck[0], wreck[1] + 2), scale=0.5)
    z.prop("decor_6", (wreck[0] - 1, wreck[1] + 2), scale=0.45)
    z.prop("decor_6", (wreck[0] + 3, wreck[1] - 2), scale=0.4)
    z.add("npc", (wreck[0] + 1, wreck[1] - 1), id="caravan_guard", facing=-1)

    # The raider camp: tents round a fire, Vesh, and the strongbox
    for i, (dx, dy) in enumerate([(-3, -2), (2, -3), (4, 1), (-4, 2)]):
        z.prop("decor_2", (camp[0] + dx, camp[1] + dy), scale=0.55, solid=True)
    z.prop("decor_7", camp, scale=0.5)
    z.prop("decor_8", (camp[0] - 1, camp[1] + 3), scale=0.5, solid=True)
    z.add("boss", (camp[0] + 1, camp[1] + 1), id="raider_captain", name="Vesh, the Raider Captain",
          kind="bandit_archer", skin="archer_guy", hp=9.0, size=1.45)
    z.add("quest_object", (camp[0] + 2, camp[1] - 1), id="strongbox", sprite="", prompt="Take the strongbox",
          text="You recover Hesk's strongbox.")

    # The oasis and the ruins
    z.prop("lake", oasis, scale=0.8)
    for dx, dy in [(-4, -1), (4, -1), (-2, 2), (3, 2)]:
        z.prop("tree_" + str(z.rng.choice([1, 2, 3, 5])), (oasis[0] + dx, oasis[1] + dy), scale=0.55)
    z.prop("building_3", (ruins[0] - 2, ruins[1] - 1), scale=0.55, solid=True)
    z.prop("building_2", (ruins[0] + 3, ruins[1] - 2), scale=0.5, solid=True)
    z.prop("decor_6", (ruins[0], ruins[1] + 2), scale=0.45)

    themes = [(camp, 13, "bandit_archer"), (ruins, 10, "skeleton"), (oasis, 8, "ghoul"),
              (wreck, 9, "villager")]
    avoid = [(start, 9), (waypoint, 4), (wreck, 3), (camp, 3)]
    z.packs(24, avoid, themes, min_gap=7, start=start)
    # The camp is guarded: bandit archers and their melee friends close to Vesh
    for dx, dy in [(-6, 3), (5, 5), (-2, 6)]:
        c = (camp[0] + dx, camp[1] + dy)
        z.clear(c, 1)
        z.add("pack", c, min=3, max=4, kind="bandit_archer" if dx < 0 else "goblin")
    z.save()


if __name__ == "__main__":
    dune_wastes()

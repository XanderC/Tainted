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
    def __init__(self, zid, name, cols, rows, seed, theme):
        self.id, self.name, self.cols, self.rows, self.theme = zid, name, cols, rows, theme
        self.rng = random.Random(seed)
        self.wall = [[False] * cols for _ in range(rows)]
        self.objects = []
        self.keep_clear = []  # (cell, radius): no outcrops here
        self.roads = [["."] * cols for _ in range(rows)]  # the roads layer: "." none, "d" dirt path, "s" cobblestone
        self.lamp_cells = []  # cells of painted paths, in order, for lamp posts along them
        self.water = [["."] * cols for _ in range(rows)]  # the water layer: "." none, "~" river, "=" bridge

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

    def paint(self, c, ch):
        if 0 <= c[0] < self.cols and 0 <= c[1] < self.rows and not self.wall[c[1]][c[0]]:
            self.roads[c[1]][c[0]] = ch

    def plaza(self, c, r, ch="s"):
        """A square of paving (cobblestone by default), `r` cells to each side of c."""
        for y in range(c[1] - r, c[1] + r + 1):
            for x in range(c[0] - r, c[0] + r + 1):
                self.paint((x, y), ch)

    def route(self, a, b, ch="d"):
        """Lays a path on the ground (the roads layer) from a to b over open floor: the shortest way with few turns,
        and a cheap one over a path already laid, so paths that head the same way share their line and the network
        reads as roads, not a tangle. Call it once the terrain is final."""
        import heapq
        start, goal = tuple(a), tuple(b)
        best = {(start, None): 0.0}
        prev = {}
        heap = [(0.0, start, None)]
        end = None
        while heap:
            cost, cur, d = heapq.heappop(heap)
            if cost > best.get((cur, d), 1e9):
                continue
            if cur == goal:
                end = (cur, d)
                break
            for nd in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cur[0] + nd[0], cur[1] + nd[1]
                if not (1 <= nx < self.cols - 1 and 1 <= ny < self.rows - 1) or self.wall[ny][nx]:
                    continue
                step = 0.35 if self.roads[ny][nx] != "." else 1.0
                if d is not None and nd != d:
                    step += 0.9  # a turn
                nc = cost + step
                if nc < best.get(((nx, ny), nd), 1e9):
                    best[((nx, ny), nd)] = nc
                    prev[((nx, ny), nd)] = (cur, d)
                    heapq.heappush(heap, (nc, (nx, ny), nd))
        trail = []
        node = end
        while node is not None:
            trail.append(node[0])
            node = prev.get(node)
        trail.reverse()
        for c in trail:
            if self.roads[c[1]][c[0]] == ".":
                self.paint(c, ch)
        self.lamp_cells.append(trail)
        return trail

    def road(self, a, b, width=1):
        """A wandering road from a to b (cells), `width` cells to each side of its middle: the corridor is cleared of
        outcrops (the path itself is laid by route() afterwards)."""
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

    def river(self, points):
        """A river a cell wide along straight segments between the (col, row) `points`, edge to edge for a map: its
        cells are water in the water layer and walls in the grid (a bridge() makes a crossing)."""
        cells = []
        for a, b in zip(points, points[1:]):
            x, y = a
            while (x, y) != tuple(b):
                cells.append((x, y))
                x += (b[0] > x) - (b[0] < x)
                y += (b[1] > y) - (b[1] < y)
        cells.append(tuple(points[-1]))
        for x, y in cells:
            self.wall[y][x] = True
            self.water[y][x] = "~"
            self.roads[y][x] = "."
        return cells

    def bridge_near(self, cells, wanted):
        """Makes a bridge of the river cell nearest `wanted` (col, row) where open ground lies on both banks, two cells deep, so
        a road already carved there leads onto it. Returns the cell."""
        best = None
        for x, y in cells:
            if 3 <= x < self.cols - 3 and not self.wall[y][x - 1] and not self.wall[y][x + 1] and not self.wall[y][x - 2] and not self.wall[y][x + 2] and not self.wall[y][x - 3] and not self.wall[y][x + 3]:
                if self.wall[y - 1][x] and self.wall[y + 1][x] and self.water[y - 1][x] == "~" and self.water[y + 1][x] == "~":
                    if best is None or math.dist((x, y), wanted) < math.dist(best, wanted):
                        best = (x, y)
        assert best is not None, "no place for a bridge near %s" % (wanted,)
        self.bridge(best)
        return best

    def bridge(self, c):
        """A river cell made a bridge: floor you can cross, with a deck over the water."""
        assert self.water[c[1]][c[0]] == "~", c
        self.wall[c[1]][c[0]] = False
        self.water[c[1]][c[0]] = "="

    def terrace(self, c, w, h, stairs, trees=True):
        """Raised ground you can walk on (MazeMap._add_terraces): a footprint of w x h cells from c, a ring of wall (left,
        right, top) round the floor, its bottom row the cliff face, with the columns `stairs` (counted from the footprint's
        left) as steps down. The ring is lined with trees and rocks, so you see why you can't walk off the edge."""
        x0, y0 = c
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.wall[y][x] = True
                self.roads[y][x] = "."
        for y in range(y0 + 1, y0 + h - 1):
            for x in range(x0 + 1, x0 + w - 1):
                self.wall[y][x] = False
        for s in stairs:
            self.wall[y0 + h - 1][x0 + s] = False
        self.objects.append({"type": "terrace", "x": x0, "y": y0, "w": w, "h": h, "stairs": list(stairs)})
        if trees:
            ring = [(x, y0) for x in range(x0, x0 + w)] + [(x0, y) for y in range(y0 + 1, y0 + h - 1)] + [(x0 + w - 1, y) for y in range(y0 + 1, y0 + h - 1)]
            for i, (x, y) in enumerate(ring):
                if i % 2 == 0 or y == y0:
                    self.prop("tree_" + str(self.rng.choice([1, 2, 3, 4, 6, 7, 8, 9, 10])), (x, y), dx=self.rng.uniform(0.3, 0.7), dy=self.rng.uniform(0.6, 0.95), scale=self.rng.uniform(0.5, 0.65))
                else:
                    self.prop("stones_" + str(self.rng.choice([1, 2, 3, 4, 5, 6])), (x, y), dx=0.5, dy=0.8, scale=0.45)

    def lamps(self, every=6, scale=0.45, sprite="decor_4"):
        """A lamp post at the edge of each painted path, every `every` cells along it, on whichever side is open."""
        for trail in self.lamp_cells:
            for i in range(3, len(trail), every):
                x, y = trail[i]
                for dx, dy in ((0, -1), (0, 1), (1, 0), (-1, 0)):
                    nx, ny = x + dx, y + dy
                    if 1 <= nx < self.cols - 1 and 1 <= ny < self.rows - 1 and not self.wall[ny][nx] and self.roads[ny][nx] == ".":
                        self.prop(sprite, (nx, ny), dx=0.5 + dx * 0.0, dy=0.9, scale=scale)
                        break

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
        data = {"format": 1, "id": self.id, "name": self.name, "kind": area_name_kind, "theme": self.theme,
                "cell": CELL, "auto_decorate": True, "grid": grid, "objects": self.objects}
        if any(ch != "." for row in self.roads for ch in row):
            data["roads"] = ["".join(row) for row in self.roads]
        if any(ch != "." for row in self.water for ch in row):
            data["water"] = ["".join(row) for row in self.water]
        with open(os.path.join(MAPS, self.id + ".json"), "w") as f:
            json.dump(data, f, indent="\t")
        idx_path = os.path.join(MAPS, "index.json")
        idx = json.load(open(idx_path))
        idx["maps"][self.id] = {"kind": area_name_kind, "name": self.name}
        with open(idx_path, "w") as f:
            json.dump(idx, f, indent="\t", sort_keys=True)
        print("wrote", self.id, "%dx%d" % (self.cols, self.rows), sum(o["type"] == "pack" for o in self.objects), "packs")


def dune_wastes():
    """Act 1's first zone, the Blackroot Wilds (Act I: The Bleeding Veil, see ACT1_DESIGN.md): mist-choked woodland
    west of Oakhaven Outpost, its oaks dead, thorn barricades across the paths on, tainted beasts about. The id is
    from when it was a desert, kept so saved waypoints and zone ids still find it. A hunting lodge where Scout
    Captain Dennis is pinned by the briarwolves and their alpha (Chapter 1), a ruined manor with the merchant's
    lockbox (The Lost Heirloom), and a waypoint. Dead trees, stumps and tainted pools are the woodland's own
    props; skulls and wagons are borrowed from the desert theme ("desert/...")."""
    z = Zone("dune_wastes", "Blackroot Wilds", 70, 46, seed=2207, theme="woodland")
    start = (4, 23)
    waypoint = (16, 25)
    lodge = (46, 11)
    manor = (53, 34)
    gate_a, gate_b, gate_c = (10, 17), (11, 30), (17, 21)  # the packs by the road from the outpost (Chapter 1: clear the gate)
    glade = (30, 27)
    fungus = (24, 10)
    landmarks = [(start, 4), (waypoint, 3), (lodge, 6), (manor, 5), (glade, 4), (fungus, 4), (gate_a, 2), (gate_b, 2), (gate_c, 2)]

    z.outcrops(90, 1.5, 5.0)
    z.border(2)
    z.smooth(2)
    for c, r in landmarks:
        z.clear(c, r)
    z.road(start, waypoint, 1)
    z.road(waypoint, gate_c, 1)
    z.road(gate_c, glade, 1)
    z.road(glade, manor, 1)
    z.road(glade, lodge, 1)
    z.road(waypoint, gate_a, 1)
    z.road(waypoint, gate_b, 1)
    z.road(lodge, fungus, 1)
    # A river down the Wilds between the glade and the lodge and manor, crossed by two bridges (the roads use them)
    river = z.river([(36, 0), (36, 20), (38, 20), (38, 45)])
    bridge_a = z.bridge_near(river, (36, 14))
    bridge_b = z.bridge_near(river, (38, 31))
    z.reachable_only(start)

    # The paths on the ground: one dirt road network (shared where it heads the same way), cobblestone where it
    # reaches somewhere: the gate, the waypoint, the lodge's yard and the manor's forecourt
    for a, b in [(start, waypoint), (waypoint, gate_c), (gate_c, glade), (glade, manor), (glade, lodge),
                 (waypoint, gate_a), (waypoint, gate_b), (lodge, fungus)]:
        z.route(a, b, "d")
    z.plaza(start, 1)
    z.plaza(waypoint, 1)
    z.plaza((lodge[0], lodge[1] + 1), 1)
    z.plaza((manor[0], manor[1] + 1), 1)
    z.lamps()

    # The road from Oakhaven comes in on the west edge
    z.add("start", start)
    z.add("portal", (start[0] - 2, start[1]), target="town")
    z.clear((start[0] - 2, start[1]), 1)
    z.add("waypoint", waypoint)
    z.prop("decor_9", (start[0] + 2, start[1] - 2), scale=0.5)  # signpost
    z.prop("decor_15", (start[0] + 2, start[1] + 2), scale=0.5, solid=True)  # the gate's last palisade
    z.prop("decor_12", (36, 6), dx=0.5, dy=0.7, scale=0.4)  # a rotting boat on the river, and signposts at its bridges
    z.prop("decor_12", (38, 38), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_9", (35, 14), dx=0.5, scale=0.5)
    z.prop("decor_9", (37, 31), dx=0.5, scale=0.5)
    z.prop("decor_4", (start[0] + 1, start[1] - 1), dx=0.2, scale=0.45)  # lamp posts at the gate and the waypoint
    z.prop("decor_4", (start[0] + 1, start[1] + 1), dx=0.2, scale=0.45)
    z.prop("decor_4", (waypoint[0] - 1, waypoint[1] - 1), dx=0.3, scale=0.45)
    z.prop("decor_4", (waypoint[0] + 1, waypoint[1] + 1), dx=0.7, scale=0.45)

    # The hunting lodge: Dennis pinned inside, the alpha and its pack round it, the rift shard where it falls
    z.add("trigger", lodge, radius=420, id="hunting_lodge",
          text="A hunting lodge, its door barred from outside. Something inside is shouting.")
    z.prop("building_5", (lodge[0] - 1, lodge[1] - 3), scale=0.5, solid=True)
    z.prop("decor_15", (lodge[0] - 4, lodge[1] - 1), scale=0.5, solid=True)  # thorn barricade across the path
    z.prop("decor_15", (lodge[0] + 3, lodge[1] - 1), scale=0.5, solid=True)
    z.prop("decor_8", (lodge[0] + 4, lodge[1] - 3), scale=0.45, solid=True)  # woodpile
    z.prop("decor_1", (lodge[0] - 2, lodge[1] - 2), scale=0.45)  # a hanging lantern at the door
    z.prop("decor_5", (lodge[0], lodge[1] + 2), scale=0.5)  # tainted pool
    z.prop("tree_11", (lodge[0] - 5, lodge[1] - 3), scale=0.7)
    z.prop("tree_12", (lodge[0] + 5, lodge[1] + 1), scale=0.7)
    z.prop("desert/decor_6", (lodge[0] + 2, lodge[1] + 3), scale=0.4)  # bones
    z.add("npc", (lodge[0] - 1, lodge[1] - 1), id="dennis", facing=1)
    z.add("boss", (lodge[0] + 2, lodge[1] + 1), id="briar_alpha", name="The Briarwolf Alpha",
          kind="briarwolf", skin="gnoll", hp=5.0, size=1.5)
    z.add("quest_object", (lodge[0] + 3, lodge[1] + 2), id="rift_shard", sprite="", prompt="Take the Coagulated Rift Shard",
          text="You pry the Coagulated Rift Shard from the alpha's flank. It is cold, oily and faintly red, and it hums.")
    for dx, dy in [(-4, 3), (5, 3), (0, 5)]:
        c = (lodge[0] + dx, lodge[1] + dy)
        z.clear(c, 1)
        z.add("pack", c, min=3, max=4, kind="briarwolf")

    # The ruined manor: a family lockbox, and what was done to keep it
    z.add("trigger", manor, radius=420, id="ruined_manor",
          text="A manor, roofless and black with rot. Someone hid something in here.")
    z.prop("building_3", (manor[0], manor[1] - 3), scale=0.55, solid=True)
    z.prop("building_4", (manor[0] + 4, manor[1] - 2), scale=0.5, solid=True)  # its tower
    z.prop("decor_15", (manor[0] - 4, manor[1] + 1), scale=0.5, solid=True)
    z.prop("decor_16", (manor[0] - 2, manor[1] + 2), scale=0.5)  # scarecrow
    z.prop("decor_4", (manor[0] - 1, manor[1] + 3), dx=0.2, scale=0.45)  # the forecourt's lamp posts, one still lit
    z.prop("decor_4", (manor[0] + 2, manor[1] + 3), dx=0.8, scale=0.45)
    z.prop("decor_7", (manor[0] + 1, manor[1] + 1), scale=0.5)
    z.prop("tree_12", (manor[0] - 5, manor[1] - 2), scale=0.7)
    z.prop("tree_11", (manor[0] + 6, manor[1] + 2), scale=0.7)
    z.prop("desert/decor_6", (manor[0] + 2, manor[1] + 3), scale=0.4)
    z.add("quest_object", (manor[0] + 1, manor[1] - 1), id="lockbox", sprite="", prompt="Open the lockbox",
          text="Inside the lockbox: a merchant's ledger, and a diary. 'The servants were slow to die, but the thing in the "
               "cellar was patient, and it let us through the Wilds untouched. Corwin' ... He fed his own household to the "
               "Taint, and took his gem and walked away.")

    # The glade and the fungus hollow: dead oaks, stumps, tainted pools
    for dx, dy in [(-3, -2), (3, -2), (-2, 3), (4, 2), (0, -4)]:
        z.prop("tree_" + str(z.rng.choice([11, 12, 11, 12, 5])), (glade[0] + dx, glade[1] + dy), scale=0.65)
    z.prop("decor_6", (glade[0], glade[1]), scale=0.55)
    z.prop("tree_14", (glade[0] - 1, glade[1] + 2), scale=0.55)
    for dx, dy in [(-3, 0), (2, 2), (3, -2), (-1, -3)]:
        z.prop("decor_14", (fungus[0] + dx, fungus[1] + dy), scale=0.4)  # fungal blooms
    z.prop("tree_13", (fungus[0] + 1, fungus[1]), scale=0.55)
    # The paths on are choked with thorn barricades (the Weeping Hollow and the Sunken Fen come later)
    for dy in range(-1, 2):
        z.prop("decor_15", (66, 22 + dy), scale=0.5, solid=True)
    for dx in range(-1, 2):
        z.prop("decor_15", (46 + dx, 42), scale=0.5, solid=True)

    themes = [(gate_a, 6, "briarwolf"), (gate_b, 6, "briarwolf"), (gate_c, 6, "briarwolf"), (lodge, 13, "briarwolf"),
              (manor, 10, "ghoul"), (glade, 8, "villager"), (fungus, 7, "zombie")]
    avoid = [(start, 9), (waypoint, 4), (lodge, 3), (manor, 3)]
    z.packs(24, avoid, themes, min_gap=7, start=start)
    for c in (gate_a, gate_b, gate_c):  # the packs the first chapter clears from round the gate road
        z.add("pack", c, min=3, max=4, kind="briarwolf")
    z.save()


def oakhaven():
    """Oakhaven Outpost, the town (maps/oakhaven.json, read by scripts/town.gd): spread out, with room between its people.
    A cobbled square in the middle with the campfire and the waypoint, dirt roads to each part: the west gate (the road
    to the Blackroot Wilds), the smith, the sage and the dyer in the west, the market and the shrine between the square
    and the river, a raised terrace in the north (up its stairs: the Battlemaster, the stash and the jeweler), and across
    the river by the bridge the Rift Gate and the captain. The NPCs and the exits are markers (town.gd makes them); the
    houses, lamps, trees and the rest are props. No monsters."""
    z = Zone("oakhaven", "Oakhaven Outpost", 40, 30, seed=7123, theme="woodland")
    spawn = (17, 21)
    plaza = (17, 17)
    z.border(2)
    z.smooth(1)
    z.clear((3, 17), 2)  # the west gate
    for c, r in [(plaza, 6), (spawn, 3), (( 8, 14), 3), ((8, 22), 3), ((12, 25), 3), ((26, 14), 3), ((25, 21), 3), ((25, 26), 3),
                 ((35, 15), 4), ((18, 7), 2), ((6, 18), 2)]:
        z.clear(c, r)
    # The river, edge to edge, with two bridges; the terrace in the north
    z.river([(29, 0), (29, 13), (31, 13), (31, 29)])
    z.bridge((31, 17))
    z.terrace((11, 3), 15, 8, stairs=[6, 7])  # footprint x 11..25, y 3..10; steps at (17, 10) and (18, 10)
    z.reachable_only(spawn)

    # Roads and paths: dirt between the parts of the town, cobblestone where people stand
    for a, b in [((3, 17), (13, 17)), ((20, 17), (30, 17)), ((32, 17), (34, 17)), ((34, 17), (35, 14)), ((17, 14), (17, 9)),
                 ((17, 20), (17, 21)), ((10, 17), (8, 14)), ((10, 17), (8, 22)), ((10, 22), (12, 25)), ((23, 17), (26, 14)),
                 ((22, 18), (25, 21)), ((22, 20), (25, 26)), ((17, 9), (13, 8)), ((17, 9), (23, 8)), ((29, 17), (31, 17))]:
        z.route(a, b, "d")
    z.plaza(plaza, 2)  # the square: 5 x 5 cobblestones, the rest dirt
    z.plaza((35, 14), 1)  # the Rift Gate
    z.plaza((3, 17), 1)  # the west gate
    z.lamps(every=5)

    # Markers: where the town's people stand and its exits (town.gd makes them)
    for name, c in [("spawn", spawn), ("west_exit", (3, 17)), ("waypoint", (22, 18)), ("tp", (14, 21)), ("gate", (35, 14)),
                    ("npc_blacksmith", (8, 14)), ("npc_dyer", (8, 22)), ("npc_sage", (12, 25)), ("npc_corwin", (7, 18)),
                    ("npc_merchant", (26, 14)), ("npc_gambler", (25, 21)), ("npc_althea", (25, 26)),
                    ("npc_stash", (18, 8)), ("npc_brom", (13, 8)), ("npc_jeweler", (23, 8)), ("npc_captain", (34, 17))]:
        z.add("marker", c, id=name)

    # The square: the fire, the banner, a signpost, lamps at the corners
    z.prop("desert/decor_7", plaza, scale=0.6)
    z.prop("decor_3", (15, 15), dx=0.3, scale=0.5)
    z.prop("decor_9", (19, 20), scale=0.5)
    z.prop("decor_10", (20, 15), dx=0.7, scale=0.42)
    for c in [(13, 14), (21, 14), (13, 20), (21, 20)]:
        z.prop("decor_4", c, dx=0.5, scale=0.45)
    # The north terrace: the stash keeper's house, the jeweler's cottage, the Battlemaster's banner and a woodpile
    z.prop("building_3", (18, 5), dy=0.95, scale=0.55, solid=True)
    z.prop("building_6", (23, 5), dy=0.95, scale=0.45, solid=True)
    z.prop("decor_3", (13, 6), dx=0.3, scale=0.5)
    z.prop("decor_8", (14, 5), dx=0.6, scale=0.42, solid=True)
    z.prop("decor_1", (16, 7), dx=0.5, scale=0.45)
    z.prop("decor_1", (20, 7), dx=0.5, scale=0.45)
    # The west: the smithy and its forge, a woodpile and rocks; the wagon by the gate road; the well and the pond
    z.prop("building_5", (7, 12), dy=0.95, scale=0.55, solid=True)
    z.prop("desert/decor_7", (10, 14), scale=0.45)
    z.prop("decor_8", (5, 13), dx=0.5, scale=0.42, solid=True)
    z.prop("stones_1", (5, 15), dx=0.5, scale=0.45)
    z.prop("desert/decor_8", (6, 19), dx=0.5, scale=0.45, solid=True)
    z.prop("decor_10", (8, 19), dx=0.3, scale=0.42)
    z.prop("decor_10", (10, 23), dx=0.5, scale=0.4)
    z.prop("building_7", (14, 26), dx=0.5, scale=0.5, solid=True)
    z.prop("desert/lake", (4, 25), scale=0.75)
    for dx, dy in [(-2, -1), (2, -1), (-1, 2), (3, 1)]:
        z.prop("tree_" + str(z.rng.choice([2, 3, 5, 9])), (4 + dx, 25 + dy), scale=0.55)
    # Between the square and the river: the merchant's house and stall, the gambler's tent, Althea's shrine of braziers
    z.prop("building_1", (26, 11), dy=0.95, scale=0.5, solid=True)
    z.prop("desert/decor_2", (23, 14), scale=0.42, solid=True)
    z.prop("decor_4", (28, 15), dx=0.5, scale=0.45)
    z.prop("desert/decor_2", (27, 22), scale=0.45, solid=True)
    z.prop("desert/decor_8", (23, 23), scale=0.42, solid=True)
    for dx, dy in [(-2, -1), (2, -1), (-2, 1), (2, 1)]:
        z.prop("decor_4", (25 + dx, 26 + dy), dx=0.5, scale=0.45)
    z.prop("stones_2", (25, 28), scale=0.5)
    # Across the river: the watchtower by the Rift Gate, and lamps
    z.prop("building_4", (37, 12), dy=0.95, scale=0.45, solid=True)
    z.prop("decor_4", (33, 15), dx=0.5, scale=0.45)
    z.prop("decor_4", (37, 16), dx=0.5, scale=0.45)
    # Boats on the river, a signpost at the bridge, a few trees and rocks on the open ground (room to walk, not a thicket)
    z.prop("decor_12", (29, 4), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_12", (31, 24), dx=0.5, dy=0.7, scale=0.4)
    z.prop("decor_9", (32, 16), dx=0.4, scale=0.5)
    keep = [plaza, spawn, (8, 14), (8, 22), (12, 25), (26, 14), (25, 21), (25, 26), (35, 14), (3, 17), (18, 8), (13, 8), (23, 8),
            (7, 18), (22, 18), (14, 21), (34, 17), (4, 25), (7, 12), (26, 11), (37, 12)]
    placed = 0
    tries = 0
    while placed < 34 and tries < 4000:
        tries += 1
        c = (z.rng.randrange(3, z.cols - 3), z.rng.randrange(3, z.rows - 3))
        if not z.open_around(c, 1) or z.roads[c[1]][c[0]] != "." or z.water[c[1]][c[0]] != ".":
            continue
        if any(math.dist(c, k) < 5.5 for k in keep) or any(math.dist(c, (t["x"] // CELL, t["y"] // CELL)) < 1.2 for t in z.objects if t["type"] == "prop"):
            continue
        if any(t["type"] == "terrace" and t["x"] - 1 <= c[0] <= t["x"] + t["w"] and t["y"] - 1 <= c[1] <= t["y"] + t["h"] for t in z.objects):
            continue
        if z.rng.random() < 0.65:
            z.prop("tree_" + str(z.rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])), c, dx=z.rng.uniform(0.3, 0.7), dy=z.rng.uniform(0.6, 0.95), scale=0.6)
        else:
            z.prop("stones_" + str(z.rng.choice([1, 2, 3, 4, 5, 6])), c, dx=0.5, dy=0.8, scale=0.45)
        placed += 1
    z.add("start", spawn)
    z.save("special")


if __name__ == "__main__":
    dune_wastes()
    oakhaven()

#!/usr/bin/env python3
"""Conduce el simulador de la Puerta del Sol al Bernabéu fijando una posición por segundo.

Uso: drive.py <UDID> [velocidad en m/s]
"""
import math
import subprocess
import sys
import time

udid = sys.argv[1]
speed = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0

# Sol → Alcalá → Cibeles → Recoletos → Castellana → Concha Espina.
waypoints = [
    (40.4168, -3.7038), (40.4190, -3.6975), (40.4193, -3.6931), (40.4250, -3.6900),
    (40.4335, -3.6880), (40.4460, -3.6915), (40.4513, -3.6913), (40.4519, -3.6880), (40.4522, -3.6860),
]


def meters(a, b):
    dlat = (b[0] - a[0]) * 111_320
    dlon = (b[1] - a[1]) * 111_320 * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlon)


count = 0
for a, b in zip(waypoints, waypoints[1:]):
    steps = max(1, round(meters(a, b) / speed))
    for i in range(1, steps + 1):
        t = i / steps
        point = f"{a[0] + (b[0] - a[0]) * t:.6f},{a[1] + (b[1] - a[1]) * t:.6f}"
        started = time.time()
        result = subprocess.run(["xcrun", "simctl", "location", udid, "set", point], capture_output=True, text=True)
        if result.returncode != 0:
            print("fallo:", result.stderr.strip(), flush=True)
        count += 1
        time.sleep(max(0, 1 - (time.time() - started)))
print(f"posiciones enviadas: {count}", flush=True)

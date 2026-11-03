#!/usr/bin/env python3
"""Validate adaptive asset coverage and WCAG text contrast; no Apple tooling required."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "MovieTracker/Resources/Assets.xcassets"
MODES = {
    frozenset(): "light",
    frozenset({("luminosity", "dark")}): "dark",
    frozenset({("contrast", "high")}): "light increased contrast",
    frozenset({("luminosity", "dark"), ("contrast", "high")}): "dark increased contrast",
}
NAMES = ["CanvasColor", "SurfaceColor", "RaisedSurfaceColor", "PrimaryTextColor", "SecondaryTextColor",
         "AccentColor", "PressedAccentColor", "OnAccentColor", "DividerColor"]


def luminance(rgb):
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return sum(c * weight for c, weight in zip(linear, [0.2126, 0.7152, 0.0722]))


def contrast(foreground, background):
    low, high = sorted([luminance(foreground), luminance(background)])
    return (high + 0.05) / (low + 0.05)


def main():
    palette = {}
    for name in NAMES:
        entries = json.loads((ROOT / (name + ".colorset") / "Contents.json").read_text())["colors"]
        values = {}
        for entry in entries:
            mode = frozenset((a["appearance"], a["value"]) for a in entry.get("appearances", []))
            assert mode in MODES and mode not in values, (name, "missing/duplicate appearance")
            assert entry["idiom"] == "universal" and entry["color"]["color-space"] == "srgb"
            components = entry["color"]["components"]
            assert float(components["alpha"]) == 1, (name, "contrast assumes opaque tokens")
            rgb = tuple(float(components[c]) for c in ["red", "green", "blue"])
            assert all(0 <= c <= 1 for c in rgb)
            values[mode] = rgb
        assert values.keys() == MODES.keys(), (name, "requires all four appearances")
        palette[name] = values
    for mode, label in MODES.items():
        results = []
        pairs = [(fg, bg) for fg in ["PrimaryTextColor", "SecondaryTextColor", "AccentColor"]
                 for bg in ["CanvasColor", "SurfaceColor", "RaisedSurfaceColor"]]
        pairs += [("OnAccentColor", bg) for bg in ["AccentColor", "PressedAccentColor"]]
        for foreground, background in pairs:
            ratio = contrast(palette[foreground][mode], palette[background][mode])
            assert ratio >= 4.5, (label, foreground, background, ratio)
            results.append(ratio)
        print(f"PASS: {label}: 11 intended text pairs >= 4.5:1; minimum {min(results):.2f}:1")
    print("PASS: nine semantic assets each define four opaque adaptive sRGB variants.")


if __name__ == "__main__":
    main()

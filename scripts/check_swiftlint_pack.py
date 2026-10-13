#!/usr/bin/env python3
"""Checks the SwiftLint rule pack's regexes against positive and negative fixtures.

SwiftLint uses NSRegularExpression; the constructs used here (\\b, alternation, (?!...))
behave the same in Python's `re`. Run: python3 scripts/check_swiftlint_pack.py
"""
import pathlib
import re
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
RULES = yaml.safe_load((ROOT / "swiftlint" / "duo-rules.yml").read_text())["custom_rules"]

CASES = {
    "duo_uiscreen_main": (["let s = UIScreen.main.scale"], ["let s = traitCollection.displayScale", "let mainScreen = 1"]),
    "duo_screen_bounds": (["let w = window.screen.bounds.width", "let w = screen!.nativeBounds"], ["let w = view.bounds.width"]),
    "duo_idiom_branching": (["if UIDevice.current.userInterfaceIdiom == .pad {}"], ["if sizeClass == .regular {}"]),
    "duo_orientation_branching": (["scene.interfaceOrientation", "UIDevice.current.orientation", "UIDevice.orientationDidChangeNotification"], ["stack.axis = layout.orientation"]),
    "duo_standalone_bar": (["let t = UIToolbar()", "UITabBar.init()", "UINavigationBar(frame: .zero)"], ["let c = UITabBarController()"]),
    "duo_app_wide_window": (["UIApplication.shared.keyWindow", "UIApplication.shared.windows.first", "UIApplication.shared.connectedScenes.first"], ["view.window"]),
    "duo_video_mirroring": (["connection.isVideoMirrored = true"], ["if connection.isVideoMirrored == true {}", "let m = connection.isVideoMirrored"]),
    "duo_front_camera": (["if device.position == .front {}", "camera.position != AVCaptureDevice.Position.front", ".front == device.position"],
                         ["AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)"]),
    "duo_camera_discovery": (["AVCaptureDevice.default(.builtInOuterUltraWideCamera, for: .video, position: .front)",
                              "AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInInnerUltraWideCamera, for: .video, position: .front)"],
                             ["AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInOuterUltraWideCamera], mediaType: .video, position: .unspecified)"]),
}

failures = []
if set(CASES) != set(RULES):
    failures.append(f"fixtures and rules differ: {sorted(set(CASES) ^ set(RULES))}")
for rule_id, (positives, negatives) in CASES.items():
    pattern = re.compile(RULES[rule_id]["regex"])
    failures += [f"{rule_id}: should match: {s}" for s in positives if not pattern.search(s)]
    failures += [f"{rule_id}: should not match: {s}" for s in negatives if pattern.search(s)]

if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"OK: {len(RULES)} rules, {sum(len(p) + len(n) for p, n in CASES.values())} cases")

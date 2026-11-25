#!/usr/bin/env python3
"""Check an unsigned Oort NX IPA: what AltStore and SideStore need is there, and nothing else is."""
import plistlib
import re
import struct
import sys
import zipfile

VERSION = "0.1.0-alpha.2"
EXPECTED = {"CFBundleIdentifier": "io.github.sofianbll.oortnx.mobile", "CFBundleName": "Oort NX", "CFBundleDisplayName": "Oort NX",
            "CFBundleExecutable": "Oort NX", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "2",
            "OortVersion": VERSION, "MinimumOSVersion": "26.0", "UIDeviceFamily": [1, 2], "CFBundleSupportedPlatforms": ["iPhoneOS"]}
# Google, only once the player turns the cloud library on; GitHub, when they ask for the app's page.
HOSTS = {"accounts.google.com", "oauth2.googleapis.com", "www.googleapis.com", "github.com"}
CODE_SIGNATURE, SEGMENT_64, BUILD_VERSION = 0x1D, 0x19, 0x32


def check_code(data):
    issues = []
    magic, cpu, _, kind, commands, _, flags, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x100000C or kind != 2:
        return ["The code is not one arm64 program."]
    at, first, names, platform = 32, len(data), [], None
    for _ in range(commands):
        command, size = struct.unpack_from("<2I", data, at)
        if command == CODE_SIGNATURE:
            issues.append("The code is signed.")
        if command == BUILD_VERSION:
            platform = struct.unpack_from("<I", data, at + 8)[0]
        if command == SEGMENT_64:
            count = struct.unpack_from("<I", data, at + 64)[0]
            for index in range(count):
                section = at + 72 + index * 80
                names.append(data[section:section + 16].rstrip(b"\0").decode())
                offset = struct.unpack_from("<I", data, section + 48)[0]
                if offset:
                    first = min(first, offset)
        at += size
    if platform != 2:
        issues.append("The code is not for a device.")
    # A signer adds one 16-byte command after the others.
    if first - at < 16:
        issues.append(f"No room for a signature: {first - at} bytes.")
    if re.search(rb"/Users/(?!runner/)[^/\0]+/|/private/tmp/|/var/folders/", data):
        issues.append("The code names a folder of the machine that built it.")
    return issues


def main(path):
    issues = []
    with zipfile.ZipFile(path) as ipa:
        names = [n for n in ipa.namelist() if not n.endswith("/")]
        app = "Payload/Oort NX.app/"
        if any(not n.startswith(app) for n in names):
            issues.append("Something is outside " + app)
        inside = {n[len(app):] for n in names}
        info = plistlib.loads(ipa.read(app + "Info.plist"))
        issues += [f"{key} is {info.get(key)!r}" for key, value in EXPECTED.items() if info.get(key) != value]
        if "NSAppTransportSecurity" in info:
            issues.append("A network exception is declared.")
        if not info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName"):
            issues.append("No icon.")
        for name in sorted(inside):
            if re.search(r"(^|/)(_CodeSignature/|embedded\.mobileprovision|SC_Info/)|\.(framework|dylib|appex|xctest|xcent|nsp|xci|nca|nro|keys|p12)(/|$)", name):
                issues.append("Must not be there: " + name)
        issues += ["Missing: " + n for n in ("LICENSE", "NOTICE", "NOTICE.txt", "Assets.car", "Oort NX") if n not in inside]
        if b"LNPANDY" not in ipa.read(app + "NOTICE"):
            issues.append("NX2Apple is not credited.")
        if not ipa.getinfo(app + "Oort NX").external_attr >> 16 & 0o111:
            issues.append("The code cannot run.")
        code = ipa.read(app + "Oort NX")
        issues += check_code(code)
        if b"127.0.0.1" in code or b"OortFake" in code:
            issues.append("The stand-in for Google is in the app.")
        hosts = {h.decode() for h in re.findall(rb"https://([a-z0-9.-]+)", code)}
        issues += ["An unexpected host: " + h for h in sorted(hosts - HOSTS)]
        extensions = [n for n in inside if n.startswith(("PlugIns/", "Extensions/", "Watch/"))]
        print(f"{path}: {len(names)} files, {sum(i.file_size for i in ipa.infolist()) >> 10} KB unpacked, arm64, iOS {info['MinimumOSVersion']} or later, "
              f"{1 + len(extensions)} App ID, unsigned")
    for issue in issues:
        print("- " + issue)
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

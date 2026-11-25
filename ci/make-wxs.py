#!/usr/bin/env python3
"""Generate a WiX source (.wxs) for wixl (msitools) from a portable bundle.

Usage: make-wxs.py <bundle-dir> <version> <output.wxs>
"""
import os
import sys
import uuid

NS = uuid.UUID("6f1a3c2e-9d4b-5c7a-8e10-2b3c4d5e6f70")
UPGRADE_CODE = "B7C2E1A4-3F6D-4E89-9A12-5C6D7E8F9A01"


def safe_version(v):
    parts = []
    for p in v.replace("-", ".").split("."):
        num = "".join(ch for ch in p if ch.isdigit())
        parts.append(int(num) if num else 0)
    while len(parts) < 3:
        parts.append(0)
    parts = parts[:3]
    parts[0] = min(parts[0], 255)
    parts[1] = min(parts[1], 255)
    parts[2] = min(parts[2], 65535)
    return "%d.%d.%d" % tuple(parts)


def gid(seed):
    return "{%s}" % str(uuid.uuid5(NS, seed)).upper()


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace('"', "&quot;"))


def main():
    bundle, version, out = sys.argv[1], sys.argv[2], sys.argv[3]
    bundle = os.path.abspath(bundle)

    # collect files
    files = []
    for root, _dirs, fs in os.walk(bundle):
        for f in fs:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, bundle).replace(os.sep, "/")
            files.append(rel)
    files.sort()
    if not files:
        sys.exit("bundle is empty")

    # build directory tree: node = {name, dirs:{}, files:[rel]}
    tree = {"dirs": {}, "files": []}
    for rel in files:
        parts = rel.split("/")
        node = tree
        for d in parts[:-1]:
            node = node["dirs"].setdefault(d, {"dirs": {}, "files": []})
        node["files"].append(rel)

    def dir_id(relpath):
        return "d_" + uuid.uuid5(NS, "dir:" + relpath).hex[:12]

    comps = []
    body = []

    def emit(node, relpath, indent):
        pad = "  " * indent
        for f in node["files"]:
            # wixl wants paths relative to its working directory
            src = os.path.join(os.path.basename(bundle), f)
            cid = "c_" + uuid.uuid5(NS, "file:" + f).hex[:12]
            fid = "f_" + uuid.uuid5(NS, "fileid:" + f).hex[:12]
            body.append('%s<Component Id="%s" Guid="%s" Win64="yes">' % (pad, cid, gid("file:" + f)))
            body.append('%s  <File Id="%s" Name="%s" Source="%s" KeyPath="yes" />'
                        % (pad, fid, esc(os.path.basename(f)), esc(src)))
            body.append('%s</Component>' % pad)
            comps.append(cid)
        for name in sorted(node["dirs"]):
            child = node["dirs"][name]
            cid = dir_id((relpath + "/" + name).lstrip("/"))
            body.append('%s<Directory Id="%s" Name="%s">' % (pad, cid, esc(name)))
            emit(child, (relpath + "/" + name).lstrip("/"), indent + 1)
            body.append('%s</Directory>' % pad)

    emit(tree, "", 4)

    # main executable (ardour-<ver>.exe, not the vst scanners)
    main_exe = None
    for f in files:
        base = os.path.basename(f).lower()
        if base.startswith("ardour-") and base.endswith(".exe") and "scanner" not in base:
            main_exe = f
            break
    if not main_exe:
        sys.exit("main ardour executable not found in bundle")
    main_rel = main_exe.replace("/", "\\")
    libdir_rel = "lib/ardour9"
    libdir_id = dir_id(libdir_rel)
    if not any(f.startswith(libdir_rel + "/") for f in files):
        libdir_id = "INSTALLDIR"

    # start menu component
    sm_comp = "c_startmenu"
    sm_lines = [
        '<Component Id="%s" Guid="%s" Win64="yes">' % (sm_comp, gid("startmenu")),
        '  <Shortcut Id="sc_ardour" Name="Ardour" Target="[INSTALLDIR]%s" WorkingDirectory="%s" />'
        % (esc(main_rel), libdir_id),
        '  <RemoveFolder Id="rf_ardourmenu" On="uninstall" />',
        '  <RegistryValue Root="HKCU" Key="Software\\Ardour" Name="startmenu" Type="integer" Value="1" KeyPath="yes" />',
        '</Component>',
    ]
    comps.append(sm_comp)

    product_guid = gid("product:" + version)
    xml = []
    xml.append('<?xml version="1.0" encoding="utf-8"?>')
    xml.append('<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">')
    xml.append('  <Product Id="%s" Name="Ardour" Language="1033" Version="%s"'
               % (product_guid, safe_version(version)))
    xml.append('           Manufacturer="Ardour Project" UpgradeCode="%s">' % UPGRADE_CODE)
    xml.append('    <Package InstallerVersion="500" Compressed="yes" />')
    xml.append('    <Media Id="1" Cabinet="ardour.cab" EmbedCab="yes" />')
    xml.append('    <Directory Id="TARGETDIR" Name="SourceDir">')
    xml.append('      <Directory Id="ProgramFiles64Folder">')
    xml.append('        <Directory Id="INSTALLDIR" Name="Ardour">')
    xml.extend(body)
    xml.append('        </Directory>')
    xml.append('      </Directory>')
    xml.append('      <Directory Id="ProgramMenuFolder">')
    xml.append('        <Directory Id="ArdourMenu" Name="Ardour">')
    xml.extend(sm_lines)
    xml.append('        </Directory>')
    xml.append('      </Directory>')
    xml.append('    </Directory>')
    xml.append('    <UIRef Id="WixUI_InstallDir" />')
    xml.append('    <Property Id="WIXUI_INSTALLDIR" Value="INSTALLDIR" />')
    xml.append('    <WixVariable Id="WixUILicenseRtf" Value="License.rtf" />')
    xml.append('    <Feature Id="MainFeature" Title="Ardour" Level="1">')
    for c in comps:
        xml.append('      <ComponentRef Id="%s" />' % c)
    xml.append('    </Feature>')
    xml.append('  </Product>')
    xml.append('</Wix>')
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(xml) + "\n")
    print("wrote %s (%d files, %d components)" % (out, len(files), len(comps)))


if __name__ == "__main__":
    main()

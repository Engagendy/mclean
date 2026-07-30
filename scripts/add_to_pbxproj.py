#!/usr/bin/env python3
"""Add a Swift source file to MClean.xcodeproj without regenerating it.

Usage: add_to_pbxproj.py <FileName.swift> <GroupName>
GroupName is an existing PBXGroup (e.g. Services, Views, Models, App).
"""
import re
import sys
import uuid

PBXPROJ = "MClean.xcodeproj/project.pbxproj"


def make_id() -> str:
    return uuid.uuid4().hex[:24].upper()


def main() -> None:
    name, group = sys.argv[1], sys.argv[2]
    with open(PBXPROJ) as fh:
        text = fh.read()

    if f"/* {name} */ = {{isa = PBXFileReference" in text:
        print(f"{name} already present")
        return

    file_ref = make_id()
    build_file = make_id()

    build_entry = (
        f"\t\t{build_file} /* {name} in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {file_ref} /* {name} */; }};\n"
    )
    text = text.replace(
        "/* Begin PBXBuildFile section */\n",
        "/* Begin PBXBuildFile section */\n" + build_entry,
        1,
    )

    ref_entry = (
        f"\t\t{file_ref} /* {name} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = sourcecode.swift; path = {name}; "
        f'sourceTree = "<group>"; }};\n'
    )
    text = text.replace(
        "/* Begin PBXFileReference section */\n",
        "/* Begin PBXFileReference section */\n" + ref_entry,
        1,
    )

    group_pattern = re.compile(
        r"(/\* " + re.escape(group) + r" \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)"
    )
    if not group_pattern.search(text):
        sys.exit(f"group {group} not found")
    text = group_pattern.sub(
        lambda m: m.group(1) + f"\t\t\t\t{file_ref} /* {name} */,\n", text, count=1
    )

    sources_pattern = re.compile(
        r"(isa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = \d+;\n\t\t\tfiles = \(\n)"
    )
    if not sources_pattern.search(text):
        sys.exit("sources build phase not found")
    text = sources_pattern.sub(
        lambda m: m.group(1) + f"\t\t\t\t{build_file} /* {name} in Sources */,\n",
        text,
        count=1,
    )

    with open(PBXPROJ, "w") as fh:
        fh.write(text)
    print(f"added {name} to {group}")


if __name__ == "__main__":
    main()

import sys, re


def main():
    path = sys.argv[1]
    compiler_string = sys.argv[2] if len(sys.argv) > 2 else ""

    with open(path, "r") as f:
        content = f.read()

    # mkcompile_h is called by the kernel Makefile as:
    #   scripts/mkcompile_h "$(UTS_MACHINE)" "$(CONFIG_CC_VERSION_TEXT)" "$(LD)"
    #
    # CC_VERSION="$2" receives CONFIG_CC_VERSION_TEXT which is baked at defconfig
    # time from raw "clang --version" output — KBUILD_COMPILER_STRING is never
    # used here. We hardcode CC_VERSION to our clean string directly.
    #
    # LD_VERSION reads raw "ld.lld -v" output with full LLVM commit URL.
    # We replace it with a clean extraction that yields "LLD X.Y.Z" only.
    #
    # Result: LINUX_COMPILER = "Cirrus Clang 23.0.0, LLD 23.0.0"

    lines = content.split("\n")
    out = []
    i = 0
    cc_replaced = False
    ld_replaced = False

    clean_ld = (
        "LD_VERSION=$(LC_ALL=C $LD -v 2>/dev/null | head -n1 | "
        "grep -oP 'LLD\\s+\\K[0-9]+\\.[0-9]+\\.[0-9]+' | "
        "head -n1 | sed 's/^/LLD /')"
    )

    while i < len(lines):
        line = lines[i]

        if not cc_replaced and re.match(r'\s*CC_VERSION="\$2"', line):
            out.append(f'CC_VERSION="{compiler_string}"')
            i += 1
            cc_replaced = True
            continue

        if not ld_replaced and re.match(r"\s*LD_VERSION=\$\(", line):
            depth = 0
            j = i
            while j < len(lines):
                for ch in lines[j]:
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                if depth <= 0:
                    break
                j += 1
            out.append(clean_ld)
            i = j + 1
            ld_replaced = True
            continue

        out.append(line)
        i += 1

    if not cc_replaced:
        print("[warn] compiler_string_patch: CC_VERSION pattern not matched in mkcompile_h", flush=True)
    if not ld_replaced:
        print("[warn] compiler_string_patch: LD_VERSION pattern not matched in mkcompile_h", flush=True)

    if not cc_replaced and not ld_replaced:
        sys.exit(0)

    with open(path, "w") as f:
        f.write("\n".join(out))

    print(f"[info] mkcompile_h patched: CC='{compiler_string}', LD='LLD X.Y.Z' ✅", flush=True)


if __name__ == "__main__":
    main()

import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    # Fix 1: Move #include <linux/zeromount.h> from inside a function to top-level
    # The patch places it inside posix_acl_check() which is invalid C
    INCLUDE_INSIDE = (
        '#ifdef CONFIG_ZEROMOUNT\n'
        '#include <linux/zeromount.h>\n'
        '#endif\n'
    )

    if INCLUDE_INSIDE in content:
        count = content.count(INCLUDE_INSIDE)
        content = content.replace(INCLUDE_INSIDE, '')
        lines = content.split('\n')
        insert_after = 0
        # Scan all lines (not just first 60) to find last #include in header section.
        # Stop at first non-preprocessor, non-blank, non-comment line to avoid
        # inserting past the include block into function bodies.
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith('#include'):
                insert_after = i
            elif insert_after > 0 and stripped and not stripped.startswith('//') \
                    and not stripped.startswith('/*') and not stripped.startswith('*') \
                    and not stripped.startswith('#'):
                break
        lines.insert(insert_after + 1,
                     '#ifdef CONFIG_ZEROMOUNT\n'
                     '#include <linux/zeromount.h>\n'
                     '#endif')
        content = '\n'.join(lines)
        print(f"namei.c: removed {count} misplaced include(s), re-inserted at line {insert_after + 2}.")
    else:
        print("namei.c: include already in correct position or not found.")

    # Fix 2 (removed): this used to strip the zeromount permission-check
    # block wherever it appeared more than once, on the assumption the
    # patch had duplicated it by mistake. It hadn't — the patch inserts
    # the identical block into both generic_permission() and
    # inode_permission(), and content.replace() with no count limit
    # stripped every occurrence it found, deleting the enforcement from
    # BOTH functions rather than a genuine duplicate. Confirmed by
    # tracing real callers: generic_permission() is called directly by
    # several filesystems' own i_op->permission (overlayfs, fuse, btrfs,
    # kernfs, etc.), bypassing inode_permission() entirely, so a file
    # living on one of those needs the check in generic_permission()
    # too — losing either one is a real coverage gap, not cleanup.

    with open(path, 'w') as f:
        f.write(content)


if __name__ == "__main__":
    main()

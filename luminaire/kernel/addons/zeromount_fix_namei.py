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

    # Fix 2: Remove misplaced zeromount function call blocks
    ZM_BLOCK = (
        '\n#ifdef CONFIG_ZEROMOUNT\n'
        '\tif (zeromount_is_injected_file(inode)) {\n'
        '\t\tif (mask & MAY_WRITE)\n'
        '\t\t\treturn -EACCES;\n'
        '\t\treturn 0;\n'
        '\t}\n'
        '\n'
        '\tif (S_ISDIR(inode->i_mode) && zeromount_is_traversal_allowed(inode, mask)) {\n'
        '\t\treturn 0;\n'
        '\t}\n'
        '#endif\n'
    )
    count = content.count(ZM_BLOCK)
    if count:
        content = content.replace(ZM_BLOCK, '')
        print(f"namei.c: removed {count} misplaced zeromount call block(s).")

    with open(path, 'w') as f:
        f.write(content)


if __name__ == "__main__":
    main()

import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    # Case A: with SuSFS — zeromount call landed after SUS_KSTAT block
    # but still inside if(file){} scope
    broken_susfs = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )
    fixed_susfs = (
        '#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '\t\tsusfs_sus_kstat_spoof_show_map_vma(inode, &dev, &ino);\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_SUS_KSTAT\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        '\t}\n'
        '\n'
        '#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT\n'
        'orig_flow:\n'
        '#endif // #ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT'
    )

    # Case B: without SuSFS — zeromount call landed in wrong scope entirely
    # (inside if(!mm) block instead of if(file) block)
    broken_vanilla = (
        '\t\tif (!mm) {\n'
        '\t\t\tname = "[vdso]";\n'
        '\t\t\tgoto done;\n'
        '\t\t}\n'
        '\n'
        '#ifdef CONFIG_ZEROMOUNT\n'
        '\t\tzeromount_spoof_mmap_metadata(inode, &dev, &ino);\n'
        '#endif\n'
        '\t\tif (vma->vm_start <= mm->brk &&'
    )
    fixed_vanilla = (
        '\t\tif (!mm) {\n'
        '\t\t\tname = "[vdso]";\n'
        '\t\t\tgoto done;\n'
        '\t\t}\n'
        '\n'
        '\t\tif (vma->vm_start <= mm->brk &&'
    )

    if broken_susfs in content:
        content = content.replace(broken_susfs, fixed_susfs)
        print("task_mmu.c scope fix applied (with-SuSFS case).")
    elif broken_vanilla in content:
        # For vanilla: just remove the misplaced call entirely from wrong scope.
        # zeromount's show_map_vma hook in the patch already handles this
        # correctly via the other hook points (d_path.c, stat.c).
        content = content.replace(broken_vanilla, fixed_vanilla)
        print("task_mmu.c scope fix applied (vanilla/no-SuSFS case).")
    elif "zeromount_spoof_mmap_metadata" not in content:
        print("zeromount call not found, skipping.")
    else:
        print("Pattern already fixed or different, skipping.")

    with open(path, 'w') as f:
        f.write(content)


if __name__ == "__main__":
    main()

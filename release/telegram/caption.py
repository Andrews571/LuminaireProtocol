import os
import sys
import json
from datetime import datetime


CAPTION_LIMIT = 1024

KERNEL_VERSION_TO_ANDROID = {
    "5.10": "12",
    "5.15": "13",
    "6.1":  "14",
    "6.6":  "15",
    "6.12": "16",
}

VARIANT_DISPLAY = {
    "VANILLA":        "Vanilla",
    "RESUKISU":       "ReSukiSU",
    "RESUKISU_SUSFS": "ReSukiSU\\+SUSFS",
    "SUKISU":         "SukiSU\\-Ultra",
    "SUKISU_SUSFS":   "SukiSU\\-Ultra \\+SUSFS",
}


def mdv2_escape(s):
    special = r"\_*[]()~`>#+-=|{}.!"
    for ch in special:
        s = s.replace(ch, "\\" + ch)
    return s


def mdv2_escape_url(s):
    s = s.replace("\\", "\\\\")
    s = s.replace(")", "\\)")
    return s


def mdv2_code_escape(s):
    s = s.replace("\\", "\\\\")
    s = s.replace("`", "\\`")
    return s


def utf16_len(s):
    return sum(2 if ord(c) > 0xFFFF else 1 for c in s)


def truncate(caption, limit, suffix="\n\u2026\n```"):
    if utf16_len(caption) <= limit:
        return caption
    suffix_len = utf16_len(suffix)
    result = []
    current_len = 0
    for ch in caption:
        ch_len = 2 if ord(ch) > 0xFFFF else 1
        if current_len + ch_len + suffix_len > limit:
            break
        result.append(ch)
        current_len += ch_len
    return "".join(result) + suffix


def build_blocks(env):
    linux_ver       = mdv2_code_escape(env.get("LINUX_VER", "N/A"))
    kernel_branch   = mdv2_code_escape(env.get("KERNEL_BRANCH", "N/A"))
    build_system    = mdv2_code_escape(env.get("BUILD_SYSTEM_DISPLAY", "N/A"))
    compiler        = mdv2_code_escape(env.get("COMPILER_STRING", "N/A"))
    lto             = mdv2_code_escape(env.get("ENABLE_LTO", "NONE"))
    root_solution   = mdv2_code_escape(env.get("ROOT_SOLUTION_DISPLAY", "N/A"))
    susfs_ver       = mdv2_code_escape(env.get("SUSFS_VER", "N/A"))
    mountless       = mdv2_code_escape(env.get("MOUNTLESS_DISPLAY", "N/A"))
    rekernel        = mdv2_code_escape(env.get("REKERNEL_DISPLAY", "Disable"))
    bbrv3           = mdv2_code_escape(env.get("BBRV3_DISPLAY", "Disable"))
    bbg             = mdv2_code_escape(env.get("BBG_DISPLAY", "Disable"))
    droidspaces     = mdv2_code_escape(env.get("DROIDSPACES_DISPLAY", "Disable"))
    date_str        = mdv2_code_escape(datetime.now().strftime("%d %b %Y"))

    commit_short    = env.get("GITHUB_SHA", "")[:7]
    commit_url      = "{}/{}/commit/{}".format(
                        env.get("GITHUB_SERVER_URL", ""),
                        env.get("GITHUB_REPOSITORY", ""),
                        env.get("GITHUB_SHA", ""))
    run_url         = "{}/{}/actions/runs/{}".format(
                        env.get("GITHUB_SERVER_URL", ""),
                        env.get("GITHUB_REPOSITORY", ""),
                        env.get("GITHUB_RUN_ID", ""))
    run_id          = env.get("GITHUB_RUN_ID", "")

    block_luminaire = (
        "```Luminaire\n"
        f"Linux        : {linux_ver}\n"
        f"Build System : {build_system}\n"
        f"Compiler     : {compiler}\n"
        f"LTO          : {lto}\n"
        f"Date         : {date_str}```"
    )
    is_vanilla = env.get("ROOT_SOLUTION", "").upper() == "VANILLA"
    ksu_display = "N/A" if is_vanilla else root_solution
    root_lines = [f"KSU   : {ksu_display}", f"SuSFS : {susfs_ver}"]
    if is_vanilla:
        root_lines.append("Vanilla Build")
    block_root = "```Root-solution\n" + "\n".join(root_lines) + "```"
    block_addons = (
        "```Add-ons\n"
        f"Mountless Engine : {mountless}\n"
        f"Re:Kernel        : {rekernel}\n"
        f"BBRv3            : {bbrv3}\n"
        f"BBG              : {bbg}\n"
        f"Droidspaces      : {droidspaces}```"
    )
    footer = "[{}]({}) \\| [Run \\#{}]({})".format(
        mdv2_escape(commit_short),
        mdv2_escape_url(commit_url),
        mdv2_escape(run_id),
        mdv2_escape_url(run_url),
    )

    return block_luminaire, block_root, block_addons, footer


ADDON_DISPLAY_NAMES = {
    "bbrv3":       "BBRv3",
    "bbg":         "BBG",
    "rekernel":    "Re:Kernel",
    "droidspaces": "Droidspaces",
    "zeromount":   "ZeroMount",
    "nomount":     "NoMount",
}

CHANGELOG_MAX_LEN = 300


def build_channel_caption(env, variant_links):
    """
    variant_links: dict { "VANILLA": "https://t.me/c/...", "RESUKISU_SUSFS": "...", ... }
    Only variants present in the dict will be listed.
    """
    kernel_ver  = env.get("KERNEL_VERSION", "")
    linux_ver   = env.get("LINUX_VER", "N/A")
    android_ver = KERNEL_VERSION_TO_ANDROID.get(kernel_ver, "?")

    # e.g. "6.1.174" -> "6.1.x"
    major_minor = ".".join(linux_ver.split(".")[:2]) + ".x"

    sections = [
        f"*Luminaire \\| Protocol \\| {mdv2_escape(linux_ver)}*\n"
        f"*GKI Kernel \\| Android {mdv2_escape(android_ver)} \\| Linux {mdv2_escape(major_minor)}*"
    ]

    # Add-ons — only the ones actually enabled for this run
    addon_tokens = [t for t in env.get("ADDONS", "").split(",") if t]
    if addon_tokens:
        addon_lines = ["*Add\\-ons*"]
        for token in addon_tokens:
            name = ADDON_DISPLAY_NAMES.get(token, token)
            addon_lines.append(f"\\- {mdv2_escape(name)}")
        sections.append("\n".join(addon_lines))

    # Download links
    download_lines = ["*Download*"]
    for variant_key, link in variant_links.items():
        display = VARIANT_DISPLAY.get(variant_key, mdv2_escape(variant_key))
        safe_link = mdv2_escape_url(link)
        download_lines.append(f"• [{display}]({safe_link})")
    sections.append("\n".join(download_lines))

    # Changelog — manual input, optional, capped so it can't crowd out the
    # rest of the caption if someone pastes something huge
    changelog_raw = env.get("CHANGELOG", "").strip()
    if changelog_raw:
        entries = [e.strip() for e in changelog_raw.split(";") if e.strip()]
        changelog_lines = ["*Changelog*"]
        for entry in entries:
            changelog_lines.append(f"\\- {mdv2_escape(entry)}")
        changelog_block = "\n".join(changelog_lines)
        if utf16_len(changelog_block) > CHANGELOG_MAX_LEN:
            trimmed = []
            length = 0
            ellipsis = "\u2026"
            for ch in changelog_block:
                ch_len = 2 if ord(ch) > 0xFFFF else 1
                if length + ch_len + utf16_len(ellipsis) > CHANGELOG_MAX_LEN:
                    break
                trimmed.append(ch)
                length += ch_len
            changelog_block = "".join(trimmed) + ellipsis
        sections.append(changelog_block)

    # Traceability — commit + workflow run that produced this post
    commit_short = env.get("GITHUB_SHA", "")[:7]
    commit_url = "{}/{}/commit/{}".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""),
        env.get("GITHUB_SHA", ""))
    commits_url = "{}/{}/commits/main/".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""))
    run_url = "{}/{}/actions/runs/{}".format(
        env.get("GITHUB_SERVER_URL", ""),
        env.get("GITHUB_REPOSITORY", ""),
        env.get("GITHUB_RUN_ID", ""))
    trace_line = "[Commits]({}) \\| [Workflows]({})".format(
        mdv2_escape_url(commits_url), mdv2_escape_url(run_url))
    sections.append(trace_line)

    # Bug reports point to the community discussion group, not the CI group
    group_url = mdv2_escape_url("https://t.me/{}".format(env.get("TELEGRAM_GROUP", "")))
    sections.append(
        f"Found a bug? Let's discuss it in [Luminaire Lab]({group_url})"
    )

    date_str = mdv2_escape(datetime.now().strftime("%-d %b %Y"))
    donate_url = mdv2_escape_url("https://sociabuzz.com/chainonyourdoor")
    sections.append(f"{date_str} \u00b7 [Support]({donate_url})")

    sections.append("\\#GKI \\#Kernel \\#Luminaire")

    caption = "\n\n".join(sections)
    return truncate(caption, CAPTION_LIMIT, suffix="\n\u2026")



def main():
    out_group   = sys.argv[1]
    out_channel = sys.argv[2]

    env = os.environ

    block_luminaire, block_root, block_addons, footer = build_blocks(env)

    caption_group = "\n".join([block_luminaire, block_root, block_addons, footer])
    caption_group = truncate(caption_group, CAPTION_LIMIT)

    # Channel caption — built from VARIANT_LINKS_JSON (provided by channel_post.sh)
    variant_links_json = env.get("VARIANT_LINKS_JSON", "")
    try:
        variant_links = json.loads(variant_links_json) if variant_links_json else {}
    except Exception:
        variant_links = {}
    caption_channel = build_channel_caption(env, variant_links)

    with open(out_group, "w") as f:
        f.write(caption_group)

    with open(out_channel, "w") as f:
        f.write(caption_channel)

    print("[info] telegram_caption: captions written ✅", flush=True)


if __name__ == "__main__":
    main()

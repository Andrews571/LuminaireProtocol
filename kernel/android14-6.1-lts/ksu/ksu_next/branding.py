import sys


def main():
    path = sys.argv[1]

    with open(path) as f:
        content = f.read()

    # KernelSU-Next's Kbuild has no KSU_VERSION_FULL (unlike ReSukiSU/
    # SukiSU-Ultra) — it only builds KSU_VERSION_TAG from KSU_GIT_TAG (or a
    # hardcoded fallback when not a git repo), so that's the anchor here.
    old1 = '$(eval KSU_VERSION_TAG=$(KSU_GIT_TAG))'
    new1 = '$(eval KSU_VERSION_TAG=$(KSU_GIT_TAG) Luminaire)'

    old2 = 'KSU_VERSION_TAG_FALLBACK := v0.0.1'
    new2 = 'KSU_VERSION_TAG_FALLBACK := v0.0.1 Luminaire'

    if 'KSU_GIT_TAG) Luminaire' in content:
        print("Branding already applied, skipping.")
        sys.exit(0)

    if old1 not in content:
        print("ERROR: VERSION_TAG line not found!", file=sys.stderr)
        sys.exit(1)

    if old2 not in content:
        print("ERROR: VERSION_TAG fallback line not found!", file=sys.stderr)
        sys.exit(1)

    content = content.replace(old1, new1).replace(old2, new2)

    with open(path, 'w') as f:
        f.write(content)

    print("Branding injected successfully.")


if __name__ == "__main__":
    main()

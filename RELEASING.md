# Releasing Net Speed Bar

## Normal Release

1. Make sure `main` contains what you want to ship.
2. Update `CHANGELOG.md` with the new version summary.
3. Create and push a tag:

```bash
cd /path/to/net-speed-bar
git checkout main
git pull --ff-only
git tag v1.0.5          # replace with your version
git push origin v1.0.5
```

4. GitHub Actions automatically:
   - Builds the app
   - Signs it
   - Notarizes it
   - Publishes the GitHub release using the matching `CHANGELOG.md` entry as the release body
   - Uploads `.dmg` and `.zip`

5. After that, check:
   - [Releases page](https://github.com/mukhtharcm/net-speed-bar/releases)
   - [Actions run](https://github.com/mukhtharcm/net-speed-bar/actions)

## Patch Release Example

```bash
git checkout main
git pull --ff-only
git tag v1.0.4
git push origin v1.0.4
```

## Beta / Pre-release

If the version contains a suffix like `-beta.1`, the workflow marks it as a GitHub prerelease:

```bash
git checkout main
git pull --ff-only
git tag v1.1.0-beta.1
git push origin v1.1.0-beta.1
```

## Manual Trigger from GitHub

1. Go to **Actions**
2. Open the **Release** workflow
3. Click **Run workflow**
4. Enter a version like `1.0.5`

This uses the same packaging workflow, even without creating the tag first.

`CHANGELOG.md` is the source of truth for both the repo changelog and the GitHub release body, so make sure each version has an entry before tagging.

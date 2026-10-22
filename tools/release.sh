#!/usr/bin/env bash
# Packages LeanPad/ as LeanPad-v<version>.zip and publishes it to GitHub Releases and CurseForge.
# Run it from the repository root, with the commit to release checked out:
#   tools/release.sh 0.2.0            publish (needs GH_TOKEN and CF_API_TOKEN, run by .github/workflows/release.yml)
#   DRY_RUN=1 tools/release.sh 0.2.0  build the zip and print what would be sent, publish nothing
# The release notes are that version's section of CHANGELOG.md; the game version comes from the TOC's Interface line.
set -euo pipefail

version="${1:?usage: tools/release.sh <version>}"
root="$PWD"
toc="$root/LeanPad/LeanPad.toc"
out="$root/.release"
zip="LeanPad-v$version.zip"

# The zip holds only the addon, with the version stamped into the TOC.
rm -rf "$out"
mkdir -p "$out/LeanPad"
cp -r "$root/LeanPad/." "$out/LeanPad/"
sed -i "s/@project-version@/$version/" "$out/LeanPad/LeanPad.toc"
rm -f "$out/LeanPad/.pkgmeta" # older tags still carry the packager's config
(cd "$out" && zip -qr "$zip" LeanPad)

notes="$(awk -v v="$version" 'index($0, "## [" v "]") == 1 { on = 1; next } on && /^## \[/ { exit } on' "$root/CHANGELOG.md")"
if [ -z "$notes" ]; then
	echo "CHANGELOG.md has no section for $version" >&2
	exit 1
fi
printf '%s\n' "$notes" > "$out/notes.md"

# Interface 120105 is game version 12.1.5.
interface="$(grep -m1 '^## Interface:' "$toc" | tr -dc '0-9')"
game="$((interface / 10000)).$((interface / 100 % 100)).$((interface % 100))"
project="$(grep -m1 '^## X-Curse-Project-ID:' "$toc" | tr -dc '0-9')"

echo "LeanPad $version for WoW $game: $out/$zip, CurseForge project $project"
if [ -n "${DRY_RUN:-}" ]; then
	unzip -l "$out/$zip"
	cat "$out/notes.md"
	exit 0
fi

# GitHub: create the release for the tag, or replace its zip when re-releasing.
if gh release view "v$version" > /dev/null 2>&1; then
	gh release upload "v$version" "$out/$zip" --clobber
else
	gh release create "v$version" "$out/$zip" --title "LeanPad $version" --notes-file "$out/notes.md"
fi

# CurseForge: retail game versions are type 517; when the exact patch isn't listed yet, take the newest retail one.
cf="https://wow.curseforge.com"
versions="$(curl -fsS -H "X-Api-Token: $CF_API_TOKEN" "$cf/api/game/versions")"
game_id="$(jq -r --arg v "$game" '
	map(select(.gameVersionTypeID == 517)) as $retail
	| (($retail | map(select(.name == $v)) | first) // ($retail | max_by(.id))) | .id' <<< "$versions")"
jq -n --rawfile notes "$out/notes.md" --arg name "LeanPad $version" --argjson game "$game_id" \
	'{changelog: $notes, changelogType: "markdown", displayName: $name, gameVersions: [$game], releaseType: "release"}' \
	> "$out/metadata.json"
curl -fsS -H "X-Api-Token: $CF_API_TOKEN" -F "metadata=<$out/metadata.json" -F "file=@$out/$zip" \
	"$cf/api/projects/$project/upload-file"
echo
echo "Uploaded to CurseForge project $project for WoW $game (version id $game_id)"

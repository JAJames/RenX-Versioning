game_mirrors_file=game_mirrors
static_path="/home/renx/static.renegade-x.com/"
version_path="${static_path}/data/launcher_data/version"

update_mirrors() {
	game_mirrors=$(cat "${game_mirrors_file}")
	version_file=${version_path}/$1
	jq ".game.mirrors = ${game_mirrors}" "${version_file}" > "$version_file.tmp" && mv "${version_file}.tmp" "${version_file}"
}

# Release branches
update_mirrors release.json
update_mirrors server.json

# Staging branches
update_mirrors beta.json

# Temporary / Alpha testing branches
update_mirrors alpha.json
update_mirrors launcher.json

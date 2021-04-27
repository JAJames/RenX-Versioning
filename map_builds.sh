# Setup static paths
version_path="${version_data_path}"
patches_path="${patches_data_path}"

# Parse arguments
verbose=false

function print_help() {
	echo "Prints out a mapping of the current versions/builds."
	echo "Options:"
	echo "    --help, -h             | Displays this help message"
	echo "    --verbose, -v          | Enables verbose output, useful for debugging"
	echo "    --version-path <path>  | Explicitly override version data directory path with specified"
	echo "    --patches-path <path>  | Explicitly override patch data path with specified"
	echo ""
	echo "Example usage: ./map_builds --echo"
	exit 0
}

for arg in "$@"
do
	case $arg in
	--help|-h)
		print_help
		;;
	--verbose|-v)
		verbose=true
		shift
		;;
	--version-path)
		version_path="$2"
		shift
		shift
		;;
	--patches-path)
		patches_path="$2"
		shift
		shift
		;;
	esac
done

if $verbose
then
	echo "Values:"
	echo "    patches_path: $patches_path"
	echo "    version_path: $version_path"
	echo ""
fi

# Scans for unreferenced builds, and deletes them if necessary
#
# @param version_file Path to version files containing build information
# @param patches_path Path to the root patches directory on this filesystem
function map_builds() {
	version_path="$1"
	patches_path="$2"

	# Read in list of builds
	builds=()
	for item in $patches_path/*; do
		if [ -f "$item/instructions.json" ]; then
			builds+=("$item")
		fi
	done

	if $verbose; then
		echo "Builds available:"
		for build in "${builds[@]}"; do
			echo "$build"
		done
		echo ""
	fi

	# Read in referenced builds
	referenced_builds=()
	for version_file in $version_path/*; do
		version_data=$(cat "$version_file")

		# Read in game build
		build=$(echo "$version_data" | jq -r ".game.patch_path")
		build_path="$patches_path/$build"

		if [[ ! "${referenced_builds[@]}" =~ "$build_path" ]]; then
			referenced_builds+=("$build_path")
		fi

		# Read in SDK build
		sdk_build=$(echo "$version_data" | jq -r ".sdk.patch_path")
		sdk_build_path="$patches_path/$sdk_build"

		if [[ ! "${referenced_builds[@]}" =~ "$sdk_build_path" ]]; then
			referenced_builds+=("$sdk_build_path")
		fi

		echo "$(basename $version_file) -> Game: ${build}; SDK: ${sdk_build}"
	done

	if $verbose; then
		echo "Referenced builds:"
		for build in "${referenced_builds[@]}"; do
			echo $build
		done
		echo ""
	fi

	# Build list of unreferenced builds
	unreferenced_builds=()
	for build in "${builds[@]}"; do
		if [[ ! "${referenced_builds[@]}" =~ "$build" ]]; then
			unreferenced_builds+=("$build")
		fi
	done

	# Print out unreferenced builds
	echo "Unreferenced builds:"
	for build in "${unreferenced_builds[@]}"; do
		echo $build
	done
}

map_builds "${version_path}" "${patches_path}"

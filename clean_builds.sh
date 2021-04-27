# Setup static paths
version_path="${version_data_path}"
patches_path="${patches_data_path}"

# Parse arguments
echo_output=false
verbose=false

function print_help() {
	echo "Cleans up unreferenced builds."
	echo "Options:"
	echo "    --help, -h             | Displays this help message"
	echo "    --echo, -e, --dry-run  | Suppresses deleting the unreferenced builds"
	echo "    --verbose, -v          | Enables verbose output, useful for debugging"
	echo "    --version-path <path>  | Explicitly override version data directory path with specified"
	echo "    --patches-path <path>  | Explicitly override patch data path with specified"
	echo ""
	echo "Example usage: ./clean_builds --echo"
	exit 0
}

for arg in "$@"
do
	case $arg in
	--help|-h)
		print_help
		;;
	--echo|--dry-run|-e)
		echo_output=true
		shift
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
	echo "    echo_output: $echo_output"
	echo "    patches_path: $patches_path"
	echo "    version_path: $version_path"
	echo ""
fi

# Scans for unreferenced builds, and deletes them if necessary
#
# @param version_file Path to version files containing build information
# @param patches_path Path to the root patches directory on this filesystem
function clean_builds() {
	version_path="$1"
	patches_path="$2"

	# Read in list of builds
	builds=()
	for item in $patches_path/*; do
		if [ -f "$item/instructions.json" ]; then
			builds+=("$item")
			#echo "$item"
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
		build=$(echo "$version_data" | jq -r ".game.patch_path")
		build_path="$patches_path/$build"

		if [[ ! "${referenced_builds[@]}" =~ "$build_path" ]]; then
			referenced_builds+=("$build_path")
		fi
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

	if $verbose; then
		echo "Unreferenced builds:"
		for build in "${unreferenced_builds[@]}"; do
			echo $build
		done
		echo ""
	fi

	# Delete unreferenced builds
	for build in "${unreferenced_builds[@]}"; do
		echo "Removing $build..."
		if $echo_output; then
			echo rm -rf "$build"
		else
			rm -rf "$build"
		fi
	done
}

clean_builds "${version_path}" "${patches_path}"

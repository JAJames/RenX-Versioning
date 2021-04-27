# Setup static paths
version_path="${version_data_path}"
patches_path="${patches_data_path}"

# Parse arguments
echo_output=false
minify=false
verbose=false

function print_help() {
	echo "Sets the patch path for a given branch."
	echo "Options:"
	echo "    --help, -h             | Displays this help message"
	echo "    --echo, -e, --dry-run  | Prints the output to the console, instead of overwriting the file"
	echo "    --minify, -m           | Minifies the JSON result"
	echo "    --verbose, -v          | Enables verbose output, useful for debugging"
	echo "    --version-path <path>  | Explicitly override version data directory path with specified"
	echo "    --patches-path <path>  | Explicitly override patch data path with specified"
	echo ""
	echo "Example usage: ./set_game_branch --echo release PATCH5464C"
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
	--minify|-m)
		minify=true
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

# Sanity check parameter count
if [ "$#" -ne 2 ]
then
	echo "ERROR: insufficient parameters"
	print_help
fi

version_file="${version_path%/}/${1%.json}.json"
patch_path="${2%/}"

if $verbose
then
	echo "Values:"
	echo "    echo_output: $echo_output"
	echo "    minify: $minify"
	echo "    patches_path: $patches_path"
	echo "    version_path: $version_path"
	echo "    patch_path: $patch_path"
	echo "    version_file: $version_file"
	echo ""
fi

# Sets a Renegade X launcher version branch to point to a Renegade X game patch data package
#
# @param version_file Launcher version file to target/modify
# @param patch_path Relative path from patches_path to target game patch data
# @param patches_path Path to the root patches directory on this filesystem
function set_branch() {
	version_file="$1"
	patch_path="$2"
	patches_path="$3"
	metadata_file="${patches_path}/${patch_path}/metadata.json"

	# Verify version branch exists
	if ! [ -f "$version_file" ]
	then
		echo "ERROR: version file does not exist: $version_file"
		return 1
	fi

	# Verify patch data exists
	if ! [ -f "$metadata_file" ]
	then
		echo "ERROR: metadata file does not exist: $metadata_file"
		return 1
	fi

	# Get metadata hash
	patch_metadata=$(cat "${metadata_file}")
	metadata_hash=$(sha256sum ${metadata_file} | awk '{ print toupper($1) }')

	# Validate instructions_hash
	instructions_real_hash=$(sha256sum "${patches_path}/${patch_path}/instructions.json"| awk '{ print toupper($1) }')
	instructions_expected_hash=$(echo "$patch_metadata" | jq -r ".instructions_hash")
	if [ "$instructions_expected_hash" != "$instructions_real_hash" ]
	then
		echo "ERROR: Metadata hash does not match real instructions.json hash. Corrupt upload?"
		return 1
	fi

	# TODO: Verify contents of patch by parsing through instructions.json to check file hashes

	# Read in initial version data
	version_data=$(cat "${version_file}")

	# Set the patch_path
	version_data=$(echo "${version_data}" | jq ".game.patch_path = \"${patch_path}\"")

	# Set the metadata hash; this is unused for now
	version_data=$(echo "${version_data}" | jq ".game.metadata_hash = \"${metadata_hash}\"")

	# Merge in metadata into game
	game_version_data=$(echo "${version_data}" | jq ".game * ${patch_metadata}")
	version_data=$(echo "${version_data}" | jq ".game = ${game_version_data}")

	# Minify final JSON if specified
	if $minify
	then
		version_data=$(echo "${version_data}" | jq -c .)
	fi

	# Write version_data to destination
	if $echo_output
	then
		echo "${version_data}"
	else
		echo "${version_data}" > ${version_file}
	fi
}

set_branch "${version_file}" "${patch_path}" "${patches_path}"

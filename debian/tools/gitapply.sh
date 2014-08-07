tmpfile=""
# Show usage information about gitapply script
	echo "Usage: ./gitapply.sh [--nogit] [-d DIRECTORY]"
# Critical error, abort
abort()
{
	if [ ! -z "$tmpfile" ]; then
		rm "$tmpfile"
		tmpfile=""
	fi
	echo "[PATCH] ERR: $1" >&2
	exit 1
}

# Show a warning
warning()
{
	echo "[PATCH] WRN: $1" >&2
}

# Calculate git sha1 hash
	if [ -f "$1" ]; then
		echo -en "blob $(du -b "$1" | cut -f1)\x00" | cat - "$1" | sha1sum | cut -d' ' -f1
	else
		echo "0000000000000000000000000000000000000000"
	fi
}

# Determine size of a file (or zero, if it doesn't exist)
filesize()
{
	local size=$(du -b "$1" | cut -f1)
	if [ -z "$size" ]; then
		size="0"
	fi
	echo "$size"
			abort "Reverse applying patches not supported yet with this tool."
# Detect BSD - we check this first to error out as early as possible
if gzip -V 2>&1 | grep "BSD" &> /dev/null; then
	echo "This script is not compatible with *BSD utilities. Please install git," >&2
	echo "which provides the same functionality and will be used instead." >&2
	exit 1
fi

for dependency in awk cut dd du grep gzip hexdump patch sha1sum; do
awk_decode_b85='
    l = index(git, substr($0, 1, 1));
    if (l == 0){ exit 1; }
    p=2;
awk_decode_binarypatch='
      if (cp_size == 0){   cp_size  = 0x10000; }
# Find end of patch header
awk_eof_header='
BEGIN{
  ofs=1;
}
!/^(--- |\+\+\+ |old |new |copy |rename |similarity |index |GIT |literal |delta )/{
  ofs=0; exit 0;
}
END{
  print FNR+ofs;
}'
# Find end of text patch
awk_eof_textpatch='
BEGIN{
  ofs=1;
}
!/^(@| |+|-|\\)/{
  ofs=0; exit 0;
}
END{
  print FNR+ofs;
}'

# Find end of git binary patch
awk_eof_binarypatch='
BEGIN{
  ofs=1;
}
!/^[A-Za-z]/{
  ofs=0; exit 0;
}
END{
  print FNR+ofs;
}'


# Create a temporary file containing the patch - NOTE: even if the user
# provided a filename it still makes sense to work with a temporary file,
# to avoid changes of the content while this script is active.
tmpfile=$(mktemp)
if [ ! -f "$tmpfile" ]; then
	tmpfile=""
	abort "Unable to create temporary file for patch."
elif ! cat > "$tmpfile"; then
	abort "Patch truncated."
fi

# Go through the different patch sections
lastoffset=1
for offset in $(awk '/^diff --git /{ print FNR; }' "$tmpfile"); do

	# Check part between end of last patch and start of current patch
	if [ "$lastoffset" -gt "$offset" ]; then
		abort "Unable to split patch. Is this a proper git patch?"
	elif [ "$lastoffset" -lt "$offset" ]; then
		tmpoffset=$((offset - 1))
		if sed -n "$lastoffset,$tmpoffset p" "$tmpfile" | grep -q '^\(@@ -\|--- \|+++ \)'; then
			abort "Patch corrupted or not created with git."
		fi
	# Find out the size of the patch header
	tmpoffset=$((offset + 1))
	tmpoffset=$(sed -n "$tmpoffset,\$ p" "$tmpfile" | awk "$awk_eof_header")
	hdroffset=$((offset + tmpoffset))

	# Parse all important fields of the header
	patch_oldname=""
	patch_newname=""
	patch_oldsha1=""
	patch_newsha1=""
	patch_is_binary=0
	patch_binary_type=""
	patch_binary_size=""

	tmpoffset=$((hdroffset - 1))
	while IFS= read -r line; do
		if [ "$line" == "GIT binary patch" ]; then
			patch_is_binary=1

		elif [[ "$line" =~ ^diff\ --git\ ([^ ]*)\ ([^ ]*)$  ]]; then
			patch_oldname="${BASH_REMATCH[1]}"
			patch_newname="${BASH_REMATCH[2]}"

		elif [[ "$line" =~ ^---\ (.*)$ ]]; then

		elif [[ "$line" =~ ^(literal|delta)\ ([0-9]+)$ ]]; then
			patch_binary_type="${BASH_REMATCH[1]}"
			patch_binary_size="${BASH_REMATCH[2]}"

	done < <(sed -n "$offset,$tmpoffset p" "$tmpfile")
	# Remove first path components, which are always a/ and b/ for git patches
	if [[ "$patch_oldname" =~ ^a/(.*)$ ]]; then
		patch_oldname="${BASH_REMATCH[1]}"
	elif [ "$patch_oldname" != "/dev/null" ]; then
		abort "Old name doesn't start with a/."
	fi
	if [[ "$patch_newname" =~ ^b/(.*)$ ]]; then
		patch_newname="${BASH_REMATCH[1]}"
	elif [ "$patch_newname" != "/dev/null" ]; then
		abort "New name doesn't start with b/."
	fi
	# Short progress message
	echo "patching $patch_newname"
	# If its a textual patch, then use 'patch' to apply it.
	if [ "$patch_is_binary" -eq 0 ]; then
		# Find end of textual patch
		tmpoffset=$(sed -n "$hdroffset,\$ p" "$tmpfile" | awk "$awk_eof_textpatch")
		lastoffset=$((hdroffset + tmpoffset - 1))
		# Apply textual patch
		tmpoffset=$((lastoffset - 1))
		if ! sed -n "$offset,$tmpoffset p" "$tmpfile" | patch -p1 -s -f; then
			abort "Textual patch did not apply, aborting."
		fi
		continue
	fi
	# It is a binary patch - check that requirements are fulfilled
	if [ "$patch_binary_type" != "literal" ] && [ "$patch_binary_type" != "delta" ]; then
		abort "Unknown binary patch type."
	elif [ -z "$patch_oldsha1" ] || [ -z "$patch_newsha1" ]; then
		abort "Missing index header, sha1 sums required for binary patch."
	elif [ "$patch_oldname" != "$patch_newname" ]; then
		abort "Stripped old and new name doesn't match for binary patch."
	fi
	# Ensure that checksum of old file matches
	sha=$(gitsha1 "$patch_oldname")
	if [ "$patch_oldsha1" != "$sha" ]; then
		abort "Checksum mismatch for $patch_oldname (expected $patch_oldsha1, got $sha)."
	fi
	# Find end of binary patch
	tmpoffset=$(sed -n "$hdroffset,\$ p" "$tmpfile" | awk "$awk_eof_binarypatch")
	lastoffset=$((hdroffset + tmpoffset - 1))
	# Special case - deleting the whole file
	if [ "$patch_newsha1" == "0000000000000000000000000000000000000000" ] &&
			[ "$patch_binary_size" -eq 0 ] && [ "$patch_binary_type" == "literal" ]; then
		# Applying the patch just means deleting the file
		if [ -f "$patch_oldname" ] && ! rm "$patch_oldname"; then
			abort "Unable to delete file $patch_oldname."
		continue
	# Create temporary file for literal patch
	literal_tmpfile=$(mktemp)
	if [ ! -f "$literal_tmpfile" ]; then
		abort "Unable to create temporary file for binary patch."
	# Decode base85 and gzip compression
	tmpoffset=$((lastoffset - 1))
	sed -n "$hdroffset,$tmpoffset p" "$tmpfile" | awk "$awk_decode_b85" | gzip -dc > "$literal_tmpfile" 2>/dev/null
	if [ "$patch_binary_size" -ne "$(filesize "$literal_tmpfile")" ]; then
		rm "$literal_tmpfile"
		abort "Uncompressed binary patch has wrong size."
	# Convert delta to literal patch
	if [ "$patch_binary_type" == "delta" ]; then
		# Create new temporary file for literal patch
		delta_tmpfile="$literal_tmpfile"
		literal_tmpfile=$(mktemp)
		if [ ! -f "$literal_tmpfile" ]; then
			rm "$delta_tmpfile"
			abort "Unable to create temporary file for binary patch."
		patch_binary_complete=0
		patch_binary_destsize=0
		while read cmd arg1 arg2; do
			if [ "$cmd" == "S" ]; then
				[ "$arg1" -eq "$(filesize "$patch_oldname")" ] || break
				patch_binary_destsize="$arg2"
			elif [ "$cmd" == "1" ]; then
				dd if="$patch_oldname" bs=1 skip="$arg1" count="$arg2" >> "$literal_tmpfile" 2>/dev/null || break
			elif [ "$cmd" == "2" ]; then
				dd if="$delta_tmpfile" bs=1 skip="$arg1" count="$arg2" >> "$literal_tmpfile" 2>/dev/null || break
			elif [ "$cmd" == "E" ]; then
				patch_binary_complete=1
			else break; fi
		done < <(hexdump -v -e '32/1 "%02X" "\n"' "$delta_tmpfile" | awk "$awk_decode_binarypatch")
		rm "$delta_tmpfile"
		if [ "$patch_binary_complete" -eq 0 ]; then
			rm "$literal_tmpfile"
			abort "Unable to parse full patch."

		elif [ "$patch_binary_destsize" -ne "$(filesize "$literal_tmpfile")" ]; then
			rm "$literal_tmpfile"
			abort "Unpacked delta patch has wrong size."
	# Ensure that checksum of literal patch matches
	sha=$(gitsha1 "$literal_tmpfile")
	if [ "$patch_newsha1" != "$sha" ]; then
		rm "$literal_tmpfile"
		abort "Checksum mismatch for patched $patch_newname (expected $patch_newsha1, got $sha)."
	fi
	# Apply the patch - copy literal patch to destination path
	if ! cp "$literal_tmpfile" "$patch_newname"; then
		rm "$literal_tmpfile"
		abort "Unable to replace $patch_newname with patched file."
	rm "$literal_tmpfile"
done
# Check last remaining part for unparsed patches
if sed -n "$lastoffset,\$ p" "$tmpfile" | grep -q '^\(@@ -\|--- \|+++ \)'; then
	abort "Patch corrupted or not created with git."
# Delete temp file (if any)
if [ ! -z "$tmpfile" ]; then
	rm "$tmpfile"
	tmpfile=""
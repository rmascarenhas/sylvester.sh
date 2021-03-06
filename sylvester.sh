#!/usr/bin/env bash

set -e

gem="$1"
gem_basename="$(basename "$gem" .rb)"
gem_full_path="$(cd "$gem" && pwd)"

lib_file="$gem_full_path/lib/$gem_basename.rb"
bin_file="$gem_full_path/bin/$gem_basename"

git_ref="$2"

# All compiled files by silvester
declare -a compiled_files

# Prints error message on STDERR and exits with failure status.
#
#   $1 - the error message to be print.
abort() {
  echo "$1" >&2
  exit 1
}

# Check if a given file has already been compiled. The comparison is made against
# the files present in the `compiled_files` variable.
#
#   $1 - the name of the file that should be checked.
already_compiled() {
  local file

  for file in "${compiled_files[*]}"; do
    if [[ "$file" = "$1" ]]; then
      return 0
    fi
  done

  return 1
}

# Checks if the passed gem path is valid. It must have the following properties:
#
#   * Be an existing directory;
#   * Have a `lib` directory;
#   * Have a `lib/$gem.rb` file.
check_valid_structure() {
  if ! [[ -n "$gem" && -d "$gem" && -d "$gem/lib" && -f "$gem/lib/$gem_basename.rb" ]]; then
    abort "Invalid gem path: $gem"
  fi
}

# Checks if the script was given a specific git reference, passed as the second
# parameter on the script invokation.
has_git_ref() {
  [[ -n "$git_ref" ]]
}

# Checks out to a specific git reference in the gem repository.
#
#   $1 - the git reference to checkout to.
checkout_to() {
  pushd "$gem_full_path" &>/dev/null
  git checkout "$1" &>/dev/null
  popd >&/dev/null
}

# Reads the passed file and returns the path for all local files required.
#
#   $1 - the file to be scanned.
required_files() {
  local sed_script="
    s|require ['\"]$gem_basename/\([^'\"]*\)['\"]|$gem_full_path/lib/$gem_basename/\1.rb|g
    t print
    b end
    :print
    p

    :end
  "

  sed -ne "$sed_script" "$1"
}

# Removes comments, `require`s, and blank spaces from a file. 
#
#   $1 - the file to be cleaned.
clean() {
  local sed_script="
    /^[ \t]*$/d
    /^[ \t]*#.*$/d
    /^require ['\"]$gem_basename\/.*$/d
    /^require ['\"]$gem_basename['\"]$/d
  "

  sed -e "$sed_script" "$1"
}

# Returns the compiled version of a file, substituting `require` calls by the
# actual content of the file.
#
#   $1 - the file to be compiled.
compile() {
  local file

  for file in `required_files "$1"`; do
    if ! already_compiled "$file"; then
      compiled_files+=("$file")
      compile "$file"
    fi
  done

  clean "$1"
}

sylvester() {
  if has_git_ref; then
    checkout_to "$git_ref"
  fi

  echo "#!/usr/bin/env ruby"
  compile "$lib_file"
  compile "$bin_file"

  if has_git_ref; then
    checkout_to "-"
  fi
}

check_valid_structure
sylvester >"$gem_basename"

chmod +x "$gem_basename"

echo "Success! Compiled gem saved in '$gem_basename'"

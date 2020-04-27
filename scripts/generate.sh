#!/usr/bin/env bash
set -e
PROJECT_BASE_DIR=$(cd $"${BASH_SOURCE%/*}/../" && pwd)

SCRIPT_BASE_DIR="$PROJECT_BASE_DIR/scripts"
LOCAL_REPO_PATH="$PROJECT_BASE_DIR/../mvn-repo"
if [[ -d "$PROJECT_BASE_DIR/subprojects/mvn-repo" ]]
then
  LOCAL_REPO_PATH="$PROJECT_BASE_DIR/subprojects/mvn-repo"
fi

NEXT_CONTENT_DIR_NAME='.NEXT'
NEXT_CONTENT_DIR="$PROJECT_BASE_DIR/$NEXT_CONTENT_DIR_NAME"
PREV_CONTENT_DIR_NAME='.PREV'
PREV_CONTENT_DIR="$PROJECT_BASE_DIR/$PREV_CONTENT_DIR_NAME"
DEST_DIR_NAME='dest'
SRC_DIR_NAME='src'

HELP=
VERBOSE=
DRY_RUN=
MAXIMUM_RECURSION=5

main() {
  parse_args "$@"
  ! [ -z $VERBOSE ] && set -x
  ! [ -z $HELP ] && show_usage && exit 0
  init
  while ! has_settled
  do
    create_next_content_dir
    update_file_index
    generate
  done
  [ -z $DRY_RUN ] && apply_next_content
}

parse_args() {
  while getopts 'dhvr:-:' OPTION;
  do
    case $OPTION in
    -)
      case $OPTARG in
      dry-run)
        DRY_RUN='yes' ;;
      max-recursion)
        MAXIMUM_RECURSION=("${!OPTIND}"); OPTIND=$(($OPTIND+1)) ;;
      *)
        echo "ERROR: Unknown OPTION --$OPTARG" >&2
        exit 1
      esac
      ;;

    d) DRY_RUN='yes' ;;
    h) HELP='yes' ;;
    v) VERBOSE='yes' ;;
    r) MAXIMUM_RECURSION=("${!OPTIND}"); OPTIND=$(($OPTIND+1))
    esac
  done
}

show_usage () {
cat << END
Usage: $(basename "$0") [OPTION]...
  -d, --dry-run
    Generate files into a templatry dirctory preserving the existing content.

  -r, --max-recursion RECURSION_LIMIT
    The limit of how meny times the generator executed. (Default: 5)

  -h
    Display this help message.

  -v
    Verbose output
END
}

init() {
  rm -rf $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
}

create_next_content_dir() {
  mkdir -p $NEXT_CONTENT_DIR
  copy_content $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
  copy_content $PROJECT_BASE_DIR $NEXT_CONTENT_DIR

  local src_dir="$NEXT_CONTENT_DIR/$SRC_DIR_NAME"
  local dest_dir="$NEXT_CONTENT_DIR/$DEST_DIR_NAME"

  rm -rf $dest_dir
  if [ -d $src_dir ]
  then
    cp -rf $src_dir $dest_dir
  else
    mkdir -p $dest_dir
  fi
}

copy_content() {
  local src_dir=$1
  local dest_dir=$2
  [ -d $src_dir ] || return
  mkdir -p $dest_dir
  rm -rf $dest_dir/* || true
  rm -f $dest_dir/.[^.]* || true
  [ -z "$(ls -A $src_dir)" ] && return
  rsync -a${VERBOSE:+v} $src_dir/* $src_dir/.[^.]* $dest_dir \
             --exclude=.git \
             --exclude=.PREV \
             --exclude=.NEXT \
             --exclude=subprojects/mvn-repo/ \
             --exclude=tmp/
}

normalize_path() {
  local path=$1
  if [[ $path == ./* ]]
  then
    echo "${PROJECT_BASE_DIR}/$path"
  elif [[ $path == /* ]]
  then
    echo $path
  else
    echo "$NEXT_CONTENT_DIR/$path"
  fi
}

update_file_index() {
  local index_dir="$NEXT_CONTENT_DIR/model/project"
  mkdir -p $index_dir
  cat <<EOF > "$index_dir/sources.yaml"
project:
  sources:$(file_list | sort -d)
EOF
}

file_list() {
  (cd "$NEXT_CONTENT_DIR"
    local separator="\n  - "
    local dirs=
    [ -d ./model ] && dirs="$dirs ./model"
    [ -d ./template ] && dirs="$dirs ./template"
    [ -d ./src ] && dirs="$dirs ./src"
    find $dirs -type f | while read -r file
    do
      printf "$separator\"${file:2}\""
    done
    printf "\n"
  )
}

generate() {
  local generator_script="$PROJECT_BASE_DIR/scripts/laplacian-generate.sh"
  $generator_script \
    --plugin 'laplacian:laplacian.project.schema-plugin:1.0.0' \
    --template 'laplacian:laplacian.project.base-template:1.0.0' \
    --model 'laplacian:laplacian.project.project-types:1.0.0' \
    --model 'laplacian:laplacian.project.document-content:1.0.0' \
    --model-files $(normalize_path 'model/project.yaml') \
    --model-files $(normalize_path 'model/project/') \
    --template-files $(normalize_path 'template/') \
    --target-dir "$NEXT_CONTENT_DIR_NAME" \
    --local-repo "$LOCAL_REPO_PATH"
}

has_settled() {
  [ -d $NEXT_CONTENT_DIR ] || return 1
  [ -d $PREV_CONTENT_DIR ] || return 1
  diff -r -x 'build' $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
}

apply_next_content() {
  copy_content $PROJECT_BASE_DIR $PREV_CONTENT_DIR
  copy_content $NEXT_CONTENT_DIR $PROJECT_BASE_DIR
  rm -rf $NEXT_CONTENT_DIR $PREV_CONTENT_DIR
}

main "$@"
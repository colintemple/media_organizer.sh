#!/usr/bin/env bash
set -euo pipefail

show_help() {
  echo " media_organizer.sh - macOS media file organizer with date-based organization, dry-run, time preservation, parallelism, logging, input-directory pruning, and card/volume ejection."
  echo ""
  echo " Usage:"
  echo "   ./media_organizer.sh [options] <inputpath> <outputpath>"
  echo ""
  echo " Options:"
  echo "   -n, --dry-run               Show actions without performing them"
  echo "   -p, --preserve-times        Preserve modification times (uses rsync)"
  echo "   -j N, --jobs N              Run up to N move tasks in parallel (default: 1)"
  echo "   -l FILE, --log FILE         Enable logging and write the log to FILE"
  echo "   -v, --verbose               Verbose output"
  echo "   -r, --prune                 Remove empty directories under the input path after successful moves"
  echo "   -k, --keep-volume           Keep the input volume mounted, rather than ejecting it"
  echo "   -F FOLDER, --dcim FOLDER    The subfolder in the input path in which to find media (default: \"/DCIM\")"
  echo "   -P FOLDER, --photo FOLDER   The base folder into which image files should be stored (default: \"Photo/Raw\")"
  echo "   -V FOLDER, --video FOLDER   The base folder into which video files should be stored (default: \"Video/Raw\")"
  echo "   -A FOLDER, --audio FOLDER   The base folder into which audio files should be stored (default: \"Audio/Raw\")"
  echo "   -h, --help                  Show help and exit"
  echo ""
  echo " Notes:"
  echo " - Organizes by file Last Modified date, as /YYYY/YYYY-MM/YYYY-MM-DD, with folders created as needed."
  echo " - Video extensions (case-insensitive): 3g2 3gp amv ari asf avi cdng cine flv m4p m4v mkv mov mp4 mpeg mpg mpv mxf ogv ogx qt r3d vob webm wmv yuv"
  echo " - Audio extensions (case-insensitive): aa3 aac adif adts aea aif aifc aiff at3 at9 atp au flac hma l16 m4a m4b m4r m4r mogg mp3 mpc msv oga ogg oma omg opus pcm shn snd wav wma wv"
  echo " - Safe with filenames containing spaces/newlines (uses NUL separators)."
  echo " - You may test with --dry-run to view details of the operation without actually moving files."
  echo ""
  echo " Example:"
  echo "   Suppose you insert an SD card called \"Untitled\" from a Fujifilm digital camera with a file DSCF_1001.jpg, taken on September 5, 2022, and ran the command:"
  echo "     ./media_organizer.sh /Volumes/Untitled /Users/alice/Documents"
  echo ""
  echo "   ... you can expect that the file at:"
  echo "     /Volumes/Untitled/DCIM/FUJI_1000/DSCF_1001.jpg"
  echo ""
  echo "   ... will now be found at:"
  echo "     /Users/alice/Documents/Photo/Raw/2022/2022-09/2022-09-05/DSCF_1001.jpg"
  echo ""
  echo "   ... and that the SD card would then be ejected (unmounted) for quick removal."
  echo " "
}

# Defaults
DRY_RUN=0
PRESERVE_TIMES=0
JOBS=1
LOGFILE=""
KEEP_VOLUME=0
VERBOSE=0
PRUNE=0
FOLDER_DCIM="/DCIM"
FOLDER_PHOTO="Photo/Raw"
FOLDER_VIDEO="Video/Raw"
FOLDER_AUDIO="Audio/Raw"

# Parse args
ARGS=()
while (( "$#" )); do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; VERBOSE=1; shift ;;
    -p|--preserve-times) PRESERVE_TIMES=1; shift ;;
    -j|--jobs)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then JOBS="$2"; shift 2; else echo "Missing argument for --jobs" >&2; exit 2; fi ;;
    -l|--log)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then LOGFILE="$2"; shift 2; else echo "Missing argument for --log" >&2; exit 2; fi ;;
    -k|--keep-volume) KEEP_VOLUME=1; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -r|--prune) PRUNE=1; shift ;;
    -P|--photo)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then FOLDER_PHOTO="$2"; shift 2; else echo "Missing argument for --photo" >&2; exit 2; fi ;;
    -V|--video)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then FOLDER_VIDEO="$2"; shift 2; else echo "Missing argument for --video" >&2; exit 2; fi ;;
    -A|--audio)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then FOLDER_AUDIO="$2"; shift 2; else echo "Missing argument for --audio" >&2; exit 2; fi ;;
    -F|--dcim)
      if [[ -n "${2-}" && "${2:0:1}" != "-" ]]; then FOLDER_DCIM="$2"; shift 2; else echo "Missing argument for --dcim" >&2; exit 2; fi ;;
    -h|--help) show_help; exit 0 ;;
    --) shift; break ;;
    -*)
      echo "Unknown option: $1" >&2; show_help; exit 2 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]}"

if [ "$#" -ne 2 ]; then
  show_help
  exit 2
fi

VOLUME="$1"
INPUTPATH="$1$FOLDER_DCIM"
OUTPUTPATH="$2"

if [ ! -d "$INPUTPATH" ]; then
  echo "Error: input path '$INPUTPATH' does not exist or is not a directory." >&2
  exit 3
fi

mkdir -p "$OUTPUTPATH"

# Eject the volume
eject_volume() {
  if [ "$DRY_RUN" -ne 0 ]; then
    log "DRY-RUN $VOLUME would be ejected."
    echo "DRY-RUN $VOLUME would be ejected."
  else
    echo "$VOLUME will be ejected."
    diskutil unmount "$VOLUME"
  fi
}

# Log to a file
log() {
  if [ "$LOGFILE" -ne "" ];  then
    local ts msg
    ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    msg="$1"
    printf '%s %s\n' "$ts" "$msg" >> "$LOGFILE"
    if [ "$VERBOSE" -ne 0 ]; then
      printf '%s %s\n' "$ts" "$msg"
    fi
  fi
}

trap 'log "Interrupted. Exiting."; wait; exit 1' INT TERM

# Count files
total_files=$(find "$INPUTPATH" -type f -print0 | tr -cd '\0' | wc -c || true)
total_files=${total_files:-0}
if [ "$total_files" -eq 0 ]; then
  log "No files found under '$INPUTPATH'. Nothing to do."
  echo "No files found under '$INPUTPATH'. Nothing to do."

  if [ "$KEEP_VOLUME" -ne 1 ]; then
    eject_volume
  fi
  exit 0
fi

log "Starting media organizer: input='$INPUTPATH' output='$OUTPUTPATH' total_files=$total_files dry_run=$DRY_RUN preserve_times=$PRESERVE_TIMES jobs=$JOBS log='$LOGFILE' prune=$PRUNE"

TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/file_organizer.XXXXXX")"
status_dir="$TMPDIR/status"
mkdir -p "$status_dir"

# Remove the temporary directory
cleanup() {
  rm -rf -- "$TMPDIR"
}
trap cleanup EXIT

# Helper: get Year|Month|Day from file's modification time
get_date_parts() {
  local file="$1"
  stat -f "%Sm" -t "%Y|%m|%d" "$file"
}

# Move a file
move_one_file() {
  local src_file="$1"
  local dest_dir="$2"

  local fname base ext
  fname="$(basename -- "$src_file")"

  base="$fname"; ext=""
  if [[ "$fname" == *.* ]] && ([[ "$fname" != .* ]] || [[ "$fname" == *.*.* ]]); then
    base="${fname%.*}"
    ext="${fname##*.}"
  fi

  mkdir -p "$dest_dir" || { log "ERROR: failed to create dir '$dest_dir'"; return 1; }

  # choose unique name in dest_dir
  local newname="$fname"
  local count=1
  if [ -n "$ext" ]; then
    while [ -e "$dest_dir/$newname" ]; do
      newname="${base}(${count}).${ext}"
      count=$((count + 1))
    done
  else
    while [ -e "$dest_dir/$newname" ]; do
      newname="${base}(${count})"
      count=$((count + 1))
    done
  fi

  local dest_path="$dest_dir/$newname"

  if [ "$DRY_RUN" -ne 0 ]; then
    log "DRY-RUN: Would move '$src_file' -> '$dest_path' (method=$( [ "$PRESERVE_TIMES" -ne 0 ] && echo "rsync" || echo "mv" ))"
    return 0
  fi

  if [ "$PRESERVE_TIMES" -ne 0 ]; then
    rsync -a --no-perms --times -- "$src_file" "$dest_dir/" >> "$LOGFILE" 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
      log "ERROR: rsync failed ($rc) for '$src_file' -> '$dest_dir'"
      return 1
    fi
    # Ensure the copied file is named correctly (rsync uses original basename)
    local copied_path="$dest_dir/$(basename -- "$src_file")"
    if [ "$copied_path" != "$dest_path" ]; then
      mv -- "$copied_path" "$dest_path" >> "$LOGFILE" 2>&1 || { log "ERROR: failed to rename '$copied_path' -> '$dest_path'"; return 1; }
    fi
    rm -f -- "$src_file" >> "$LOGFILE" 2>&1 || log "WARNING: failed to remove source '$src_file' after rsync"
  else
    mv -- "$src_file" "$dest_path" >> "$LOGFILE" 2>&1 || { log "ERROR: mv failed for '$src_file' -> '$dest_path'"; return 1; }
  fi

  log "Moved: '$src_file' -> '$dest_path'"

  return 0
}

# Worker functions
current_jobs() {
  jobs -rp 2>/dev/null | wc -l
}

i=0
succeeded=0
failed=0

# For parallel mode (JOBS>1) we spawn background jobs but maintain a status file per task
bg_worker() {
  local src="$1"
  local dest="$2"
  local tag="$3"
  if move_one_file "$src" "$dest"; then
    echo "OK" > "$status_dir/$tag"
  else
    echo "ERR" > "$status_dir/$tag"
  fi
}

# Main loop
find "$INPUTPATH" -type f -print0 | while IFS= read -r -d '' file; do
  i=$((i + 1))
  IFS='|' read -r year month day <<< "$(get_date_parts "$file")"

  fname="$(basename -- "$file")"
  ext=""
  if [[ "$fname" == *.* ]] && ([[ "$fname" != .* ]] || [[ "$fname" == *.*.* ]]); then
    ext="${fname##*.}"
  fi
  lc_ext="$(printf '%s' "$ext" | awk '{print tolower($0)}')"

  dest_subdir="$FOLDER_PHOTO"
  case "$lc_ext" in
    mov|mp4|avi|mkv|flv|wmv|r3d|ari|cine|mxf|webm|vob|ogv|ogx|mpg|mpeg|mpv|qt|yuv|amv|m4p|m4v|asf|3gp|3g2|cdng) dest_subdir="$FOLDER_VIDEO" ;;
    wav|mp3|aac|m4a|flac|ogg|oga|mogg|wma|aiff|aif|aifc|au|snd|pcm|l16|msv|wv|aa3|aea|at3|at9|atp|hma|oma|omg|opus|shn|mpc|adif|adts|m4r|m4b|m4r) dest_subdir="$FOLDER_AUDIO" ;;
    *) ;;
  esac

  output_folder="$OUTPUTPATH/$dest_subdir/$year/$year-$month/$year-$month-$day"

  if [ "$JOBS" -gt 1 ]; then
    while [ "$(current_jobs)" -ge "$JOBS" ]; do sleep 0.1; done
    tag="task_$i"
    bg_worker "$file" "$output_folder" "$tag" &
  else
    if move_one_file "$file" "$output_folder"; then
      succeeded=$((succeeded + 1))
    else
      failed=$((failed + 1))
    fi
    percent=$(( (i * 100) / total_files ))
    printf "\r[%d/%d] %3d%%  %s" "$i" "$total_files" "$percent" "$file"
  fi
done

# If parallel, wait and collect statuses
if [ "$JOBS" -gt 1 ]; then
  wait
  if compgen -G "$status_dir/" > /dev/null; then
    for f in "$status_dir"/*; do
      [ -e "$f" ] || continue
      st="$(cat "$f" 2>/dev/null || echo "ERR")"
      if [ "$st" = "OK" ]; then
        succeeded=$((succeeded + 1))
      else
        failed=$((failed + 1))
      fi
    done
  fi
  printf "\rProcessed %d files. Success: %d  Failed: %d\n" "$total_files" "$succeeded" "$failed"
fi

log "Move pass complete. total=$total_files succeeded=$succeeded failed=$failed"

# Prune empty directories under INPUTPATH (optional)
if [ "$PRUNE" -ne 0 ]; then
  log "Prune enabled: removing empty directories under '$INPUTPATH' (excluding root)"
  if [ "$DRY_RUN" -ne 0 ]; then
    log "DRY-RUN prune: listing empty directories that would be removed:"
    find "$INPUTPATH" -type d -empty -not -path "$INPUTPATH" -print0 | while IFS= read -r -d '' d; do
      log "DRY-RUN PRUNE: would remove '$d'"
    done
  else
    # Remove empty directories bottom-up
    # Use rmdir which only removes empty dirs
    find "$INPUTPATH" -depth -type d -not -path "$INPUTPATH" -print0 | while IFS= read -r -d '' d; do
      # attempt rmdir; ignore failures
      if rmdir -- "$d" 2>/dev/null; then
        log "Pruned empty directory: '$d'"
      fi
    done
  fi
fi

if [ "$KEEP_VOLUME" -ne 1 ]; then
  eject_volume
fi

log "Completed. Total files: $total_files Succeeded: $succeeded Failed: $failed"
echo "Done!  Total files: $total_files Succeeded: $succeeded Failed: $failed"
exit 0


# media_organizer.sh
A shell script for organizing data from memory cards into storage locations on macOS.

## Usage
   `./media_organizer.sh [options] <inputpath> <outputpath>`

## Options

| Option Flag | Effect |
| ------ | ------ |
| `-n`, `--dry-run` | Show actions without performing them |
| `-p`, `--preserve-times` | Preserve modification times (uses `rsync`)  | 
| `-j N`, `--jobs N` | Run up to N move tasks in parallel (default: `1`)  | 
| `-v`, `--verbose` | Verbose output | 
| `-l FILE`, `--log FILE` | Enable logging and write the log to FILE  | 
| `-r`, `--prune` | Remove empty directories under the input path after successful moves  | 
| `-k`, `--keep-volume` | Keep the input volume mounted, rather than ejecting it  | 
| `-F FOLDER`, `--dcim FOLDER` | The subfolder in the input path in which to find media (default: "/DCIM")  | 
| `-P FOLDER`, `--photo FOLDER` | The base folder into which image files should be stored (default: "Photo/Raw")  | 
| `-V FOLDER`, `--video FOLDER` | The base folder into which video files should be stored (default: "Video/Raw")  | 
| `-A FOLDER`, `--audio FOLDER` | The base folder into which audio files should be stored (default: "Audio/Raw")  | 
| `-h`, `--help` | Show help and exit  | 

## Notes
- Organizes into nested folders based on the file's Last Modified date, in the format `/YYYY/YYYY-MM/YYYY-MM-DD`, with folders created as needed
- Video extensions (case-insensitive): `3g2`, `3gp`, `amv`, `ari`, `asf`, `avi`, `cdng`, `cine`, `flv`, `m4p`, `m4v`, `mkv`, `mov`, `mp4`, `mpeg`, `mpg`, `mpv`, `mxf`, `ogv`, `ogx`, `qt`, `r3d`, `vob`, `webm`, `wmv`, `yuv`
- Audio extensions (case-insensitive): `aa3`, `aac`, `adif`, `adts`, `aea`, `aif`, `aifc`, `aiff`, `at3`, `at9`, `atp`, `au`, `flac`, `hma`, `l16`, `m4a`, `m4b`, `m4r`, `m4r`, `mogg`, `mp3`, `mpc`, `msv`, `oga`, `ogg`, `oma`, `omg`, `opus`, `pcm`, `shn`, `snd`, `wav`, `wma`, `wv`
- Files not identified as audio or video are assumed to be photos and moved to the corresponding folder
- Safe with filenames containing spaces/newlines
- You may test with --dry-run to view details of the operation without actually moving files

## Example

Suppose you insert an SD card called "Untitled" from a Fujifilm digital camera with a file named `DSCF_1001.jpg`, taken on September 5, 2022, and ran the command:
 
   `./media_organizer.sh /Volumes/Untitled /Users/alice/Documents`

 ... you can expect that the file at:
 
**/Volumes/Untitled/DCIM/FUJI_1000/DSCF_1001.jpg**

... will now be found at:

**/Users/alice/Documents/Photo/Raw/2022/2022-09/2022-09-05/DSCF_1001.jpg**

 ... and that the SD card would then be ejected (unmounted) for quick removal.

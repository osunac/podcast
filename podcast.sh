#!/bin/bash
#
# podcast.sh: download files from podcasts
#
# The objective is to have a script that can be called from cron or udev to
# update feeds without any user interaction.
#
# Configuration is done with an INI file assumed to be self-descriptive for
# the most part (see example below). The only mandatory feed option is the
# url, the other options can be inferred from the name or the global options.
# A hook program can be called after each file download, in that case the
# following environment variables are set:
#  - PODCAST_FEED: feed identifier
#  - PODCAST_FILE: path to the file that has just been downloaded
#
# Dependencies:
#  - bash
#  - wget
#
# Copyright (C) 2015 Christophe Osuna, all rights reserved.
#
# This program is distributed free of charge under the therms of the WTFPL
# copy-pasted below.
#
# ----------------------------------------------------------------------------
# Sample configuration file
#
#  [global]
#  media = /home/user/media/podcast
#  default_max_size_mb = 100
#  feeds = feed1 feed2
#  hook = logger "podcast.sh: downloaded ${PODCAST_FILE}"
#
#  [feed1]
#  url  = http://example.org/feed1
#  name = Feed 1
#  dir  = feed_1
#  max_size_mb = 150
#
#  [feed2]
#  url = http://example.org/feed2
# 
# ----------------------------------------------------------------------------
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#                    Version 2, December 2004
#
# Copyright (C) 2004 Sam Hocevar <sam@hocevar.net>
#
# Everyone is permitted to copy and distribute verbatim or modified
# copies of this license document, and changing it is allowed as long
# as the name is changed.
#
#            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
#   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION
#
#  0. You just DO WHAT THE FUCK YOU WANT TO.
#
# ----------------------------------------------------------------------------

# Global variables
config=
media=
default_max_size=
hook=

# die MESSAGE
# Print error MESSAGE and exit with error code
function die() {
    echo "$1" 1>&2
    exit 1
}

# usage
# Print program usage
function usage() {
    echo "Usage: podcast.sh {--update}"
}

# find_configuration
# Look for configuration file in several locations and update the $config
# variable
function find_configuration()
{
    # Development location
    config=./config.ini
       
    # Freedesktop specification
    [ -r $config ] || config="$XDG_CONFIG_HOME/podcast.ini"
    [ -r $config ] || \
        for dir in $(echo $XDG_CONFIG_DIRS|tr ':' '\n'); do
            [ -r $config ] || config="$dir/podcast.ini"
        done

    # Default location
    [ -r $config ] || config=~/.podcast.ini

    # Not found: abort
    [ -r $config ] || die "Configuration file not found"
}

# read_ini INI
# Read configuration file INI and generate output that follow the pattern:
#   <section>|<key>|<value>
function read_ini()
{
    # http://unix-workstation.blogspot.de/2015/06/configuration-files-for-shell-scripts.html
    cat "$1" |sed '
1 {
  x
  s/^/default/
  x
}

/^#/n

/^\[/ {
  s/\[\(.*\)\]/\1/
  x
  b
}

/=/ {
  s/^[[:space:]]*//
  s/[[:space:]]*=[[:space:]]*/|/
  G
  s/\(.*\)\n\(.*\)/\2|\1/
  p
}
'
}

# read_ini_value INI SECTION KEY
# Return value for a given SECTION and KEY in an INI file
function read_ini_value()
{
    read_ini "$1" | awk -F\| -v section="$2" -v key="$3" '
($1 == section) && ($2 == key) { print $3; exit }
'
}

# read_global_config INI
# Read global configuration file INI
function read_global_config()
{
    media=$(read_ini_value $1 global media)
    default_max_size=$(read_ini_value $1 global default_max_size_mb)
    hook=$(read_ini_value $1 global hook)
}

# remove_excess_files DIRECTORY MAX_SIZE
# Remove all files in DIRECTORY so that its size remains below MAX_SIZE.
# If MAX_SIZE is empty, no files are removed.
function remove_excess_files() {
    [ -z "$2" ] && return

    while [ "$(du -m $1|awk '{print $1}')" -gt $2 ]; do
        file="$(ls -rt $1|head -1)"
        echo "  -$file"
        rm -f "$1/$file"
    done
}

# get_urls XML
# Extract the value of all attributes named "url" within XML file
function get_urls()
{
    wget --quiet -O - $url\
      | grep -o "url=\"[^\"]*"\
      | cut -d '"' -f 2
}

# filter_out_duplicates
# Make duplicate lines unique
function filter_out_duplicates()
{

    # From sed documentation
    sed '
h

:b
# On the last line, print and exit
$b
N
/^\(.*\)\n\1$/ {
    # The two lines are identical.  Undo the effect of
    # the n command.
    g
    bb
}

# If the N command had added the last line, print and exit
$b

# The lines are different; print the first and go
# back working on the second.
P
D
'
}

# filter_reverse
# Reverse all lines on stdin
function filter_reverse()
{
    sed '
1!G
h
$!d
'
}

# filter_audio
# Keep only audio files
function filter_audio()
{
    grep 'mp3$'
}

# filter_empty_list_when ITEM
# Empty begining of a list when ITEM is found
function filter_empty_list_when()
{
    awk -v magic="$1" '
$0 ~ magic { buffer = "" }
           { if (buffer != "") buffer = buffer "\n"
             buffer = buffer $0 }
END        { print buffer }
'
}

# download FEED DIRECTORY
# Download files from FEED to DIRECTORY if they do not already exist
function download()
{
    while read url; do
        file=$(basename $url)
        if [ ! -r "$2/$file" ]; then
            echo "  +$file"
            wget --quiet -O "$2/$file" $url
            [ -n "$hook" ] &&
                (
                    export PODCAST_FEED="$1"
                    export PODCAST_FILE="$2/file"
                    eval "$hook"
                )
        fi
    done
}

# update_feeds
# Update all the feeds
function update_feeds()
{
    while read feed; do

        # Values from feed section in INI file
        name=$(read_ini_value $config $feed name)
        dir=$(read_ini_value  $config $feed directory)
        url=$(read_ini_value  $config $feed url)
        max_size=$(read_ini_value $config $feed max_size_mb)

        # Values inherited from global values or guessed from feed name
        : ${name:=$feed}
        : ${dir:=$media/$feed}
        : ${max_size:=$default_max_size}

        mkdir -p $dir
        recent=$(ls -lt $dir|awk '(NR==2) {print $9}')
        echo "Updating feed $name..."
        get_urls $url\
          | filter_out_duplicates\
          | filter_reverse\
          | filter_audio\
          | filter_empty_list_when $recent\
          | download $feed "$dir"

        remove_excess_files "$dir" "$max_size"
    done
}

find_configuration
read_global_config $config

case $1 in
    -u|--update)
        read_ini_value $config global feeds\
          | tr ' ' '\n'\
          | update_feeds
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
esac

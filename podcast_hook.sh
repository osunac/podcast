#!/bin/bash
#
# podcast.sh hooks example file

die() {
    echo "$1" 1>&2
    exit 1
}

hook_pre() {
    case $PODCAST_FEED in
        feed1) [[ "$PODCAST_URL" =~ "morning" ]]; exit;;
        *)   exit 0;;
    esac
}

hook_post() {
    case $PODCAST_FEED in
        feed1)
            # Extract timestamp from filename
            name=$(basename $PODCAST_FILE)
            ts=${name:0:12}
            touch -t $ts $PODCAST_FILE
            ;;
        *)  ;;
    esac
}

case $1 in
    pre)
        [ -n "$PODCAST_FEED" ] || die "PODCAST_FEED not set"
        [ -n "$PODCAST_URL" ]  || die "PODCAST_URL not set"
        hook_pre
        ;;
    post)
        [ -n "$PODCAST_FEED" ] || die "PODCAST_FEED not set"
        [ -n "$PODCAST_FILE" ] || die "PODCAST_FILE not set"
        [ -r "$PODCAST_FILE" ] || die "PODCAST_FILE is not readable"
        hook_post
        ;;
    *)
        die "$0: missing action"
esac

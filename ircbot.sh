#!/usr/bin/env bash
# Copyright 2018 Anthony DeDominic <adedomin@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
VERSION="neo8ball: v2020.07.25"

echo1() {
    printf '%s\n' "$*"
}

echo2() {
    printf >&2 '%s\n' "$*"
}

# help info
usage() {
    echo2 \
'usage: '"$0"' [-c config] [-o logfile] [-t]

    -t --timestamp      Timestamp logs using iso-8601.
    -c --config=path    A neo8ball config.sh
    -o --log-out=file   A file to log to instead of stdout.
    -h --help           This message.

If no configuration path is found or CONFIG_PATH is not set,
ircbot will assume the configuration is in the same directory
as the script.

For testing, you can set MOCK_CONN_TEST=<anything>'
    exit 1
}


die() {
    echo2 "*** CRITICAL *** $1"
    exit 1
}

# parse args
while (( $# > 0 )); do
    case "$1" in
        -c|--config)
            CONFIG_PATH="$2"
            shift
        ;;
        --config=*)
            CONFIG_PATH="${1#*=}"
        ;;
        -o|--log-out)
            exec 1<>"$2"
            exec 2>&1
            shift
        ;;
        --log-out=*)
            exec 1<>"${1#*=}"
            exec 2>&1
        ;;
        -t|--timestamp)
            LOG_TSTAMP_FORMAT='%(%Y-%m-%dT%H:%M:%S%z)T '
            LOG_TSTAMP_ARG1=-1
        ;;
        -h|--help)
            usage
        ;;
        *)
            usage
        ;;
    esac
    shift
done

#################
# Configuration #
#################

# find default configuration path
# location script's directory
[[ -z "$CONFIG_PATH" ]] && {
    CONFIG_PATH="${BASH_SOURCE[0]%/*}/config.sh"
    [[ "$CONFIG_PATH" == "${BASH_SOURCE[0]}/config.sh" ]] &&
        CONFIG_PATH="./config.sh"
}

# load configuration
if [[ -f "$CONFIG_PATH" ]]; then
    # shellcheck disable=SC1090
    . "$CONFIG_PATH"
else
    echo2 '*** CRITICAL *** no configuration'
    usage
fi

# set default temp dir path if not set
# should consider using /dev/shm unless your /tmp is a tmpfs
[[ -z "$temp_dir" ]] && temp_dir=/tmp

#######################
# Configuration Tests #
#######################

# check for ncat, use bash tcp otherwise
# fail hard if user wanted tls and ncat not found
if ! type ncat >/dev/null 2>&1; then
    echo1 "*** NOTICE *** ncat not found; using bash tcp"
    [[ -n "$TLS" ]] &&
        die "TLS does not work with bash tcp"
    BASH_TCP=a
fi

# use default nick if not set, should be set
if [[ -z "$NICK" ]]; then
    echo1 "*** NOTICE *** nick was not specified; using ircbashbot"
    NICK="ircbashbot"
fi

# fail if no server
if [[ -z "$SERVER" ]]; then
    die "A server must be defined; check the configuration."
fi

###############
# Plugin Temp #
###############

# shellcheck disable=SC2154
APP_TMP="$temp_dir/bash-ircbot.$$"
mkdir -m 0770 "$APP_TMP" ||
    die "failed to make temp directory, check your config"

# add temp dir for plugins
PLUGIN_TEMP="$APP_TMP/plugin"
mkdir "$PLUGIN_TEMP" ||
    die "failed to create plugin temp dir"
# this is for plugins, so export it
export PLUGIN_TEMP

#########
# State #
#########

# TODO: soon
#declare -A user_modes

# populate invites array to prevent duplicate entries
declare -A invites
if [[ -f "$INVITE_FILE" ]]; then
    while read -r channel; do
        [[ -z "$channel" ]] && continue
        invites[$channel]=1
    done < "$INVITE_FILE"
fi

declare -Ag antispam_list

# IGNORE to a hash
declare -A ignore_hash
for ign in "${IGNORE[@]}"; do
    ignore_hash[$ign]=1
done

####################
# Signal Listeners #
####################

# handler to terminate bot
# can not trap SIGKILL
# make sure you kill with SIGTERM or SIGINT
exit_status=0
quit_prg() {
    exec 3<&-
    exec 4<&-
    [[ -n "$ncat_pid" ]] &&
        kill -- "$ncat_pid"
    [[ -n "$ping_child" ]] &&
        kill -- "$ping_child"
    rm -rf -- "$APP_TMP"
    exit "$exit_status"
}
trap 'quit_prg' SIGINT SIGTERM

# similar to above but with >0 exit code
exit_failure() {
    exit_status=1
    quit_prg
}
trap 'exit_failure' SIGUSR1

# helper for channel config reload
# determine if chan is in channel list
contains_chan() {
  for chan in "${@:2}"; do
      [[ "$chan" == "$1" ]] && return 0
  done
  return 1
}

# handle configuration reloading
# faster than restarting
# will: change nick (if applicable)
#       reauth with nickserv
#       join/part new or removed channels
#       reload all other variables, like COMMANDS, etc
reload_config() {
    send_log 'DEBUG' 'CONFIG RELOAD TRIGGERED'
    local _nick="$NICK"
    # shellcheck disable=SC2153
    local _nickserv="$NICKSERV"
    local _channels=("${CHANNELS[@]}")
    # shellcheck disable=SC1090
    . "$CONFIG_PATH"
    # NICK changed
    if [[ "$NICK" != "$_nick" ]]; then
        send_msg "NICK $NICK"
    fi
    # pass change for nickserv
    if [[ "$NICKSERV" != "$_nickserv" ]]; then
        printf '%s\r\n' "NICKSERV IDENTIFY $NICKSERV" >&3
    fi

    # persist channel invites
    # shellcheck disable=SC2207
    [[ -f "$INVITE_FILE" ]] &&
        CHANNELS+=($(< "$INVITE_FILE"))

    declare -A uniq_chans
    for chan in "${_channels[@]}" "${CHANNELS[@]}"; do
        uniq_chans[$chan]+=1
    done

    declare -a leave_list=()
    declare -a join_list=()
    local jlist='' llist=''
    for uniq_chan in "${!uniq_chans[@]}"; do
        (( ${#uniq_chans[$uniq_chan]} > 1 )) && continue
        if contains_chan "$uniq_chan" "${_channels[@]}"; then
            leave_list+=("$uniq_chan")
        else
            join_list+=("$uniq_chan")
        fi
    done

    if [[ "${#join_list[@]}" -gt 0 ]]; then
        printf -v jlist ',%s' "${join_list[@]}"
        send_cmd <<< ':j '"${jlist:1}"
    fi

    if [[ "${#leave_list[@]}" -gt 0 ]]; then
        printf -v llist ',%s' "${leave_list[@]}"
        send_cmd <<< ':l '"${llist:1}"
    fi
    

    unset ignore_hash
    declare -Ag ignore_hash
    for ign in "${IGNORE[@]}"; do
        ignore_hash[$ign]=1
    done
}
trap 'reload_config' SIGHUP SIGWINCH

####################
# Setup Connection #
####################

TLS_OPTS=()
[[ -n "$TLS"             ]] && TLS_OPTS+=(--ssl)
[[ -n "$VERIFY_TLS"      ]] && TLS_OPTS+=(--ssl-verify)
[[ -n "$VERIFY_TLS_FILE" ]] && TLS_OPTS+=("--ssl-trustfile=$VERIFY_TLS_FILE")

# this mode should be used for testing only
if [[ -n "$MOCK_CONN_TEST" ]]; then
    # send irc communication to
    exec 4>&0 # from server - stdin
    exec 3<&1 # to   server - stdout
    exec 1>&-
    exec 1<&2 # remap stdout to err for logs
    # disable ncat half close check
    BASH_TCP=1
# Connect to server otherwise
elif [[ -z "$BASH_TCP" ]]; then
    coproc {
        ncat "${TLS_OPTS[@]}" "$SERVER" "${PORT:-6667}"
        echo1 'ERROR :ncat has terminated'
    }
    ncat_pid="$COPROC_PID"
    # coprocs are a bit weird
    # subshells may not be able to r/w to these fd's normally
    # without reopening them
    exec 3<> "/dev/fd/${COPROC[1]}"
    exec 4<> "/dev/fd/${COPROC[0]}"
else
    exec 3<> "/dev/tcp/${SERVER}/${PORT}" ||
        die "Cannot connect to ($SERVER) on port ($PORT)"
    exec 4<&3 "/dev/fd/${COPROC[1]}"
fi

########################
# IRC Helper Functions #
########################

parse_irc() {
    local temp utemp
    # split by whitespace
    temp="$1"
    utemp="${temp%% *}"
    # clean and split out user information
    # e.g. :user!useless@host ...etc
    user="${utemp#:}" # : is multispace indicator,
                       # all line likely have it and we don't want it
    host="${user##*@}"
    user="${user%%'!'*}"

    temp="${temp#"$utemp"* }"
    # parse command
    # Command is one word string indicating what this
    # line does, e.g PRIVMSG, NOTICE, INVITE, etc.
    command="${temp%% *}"

    temp="${temp#"$command"* }"
    # parse channel
    # should be a one word string starting with a #
    # e.g. #channame
    channel="${temp%% *}"

    temp="${temp#"$channel"* }"
    # message parse
    # e.g. :a message here
    message="${temp#:}"  # remove optional multispace indicator
    message=${message%$'\r'} # irc lines are CRLF terminated
}

# After server "identifies" the bot
# joins all channels
# identifies with nickserv
# NOTE: ircd must implement NICKSERV command
#       This command is not technically a standard
post_ident() {
    # join chans
    local _channels
    # shellcheck disable=SC2207
    [[ -f "$INVITE_FILE" ]] &&
        CHANNELS+=($(< "$INVITE_FILE"))
    printf -v _channels ",%s" "${CHANNELS[@]}"
    # channels are repopulated on JOIN commands
    # to better reflect joined channel realities
    CHANNELS=()
    # list join channels
    send_cmd <<< ":j ${_channels:1}"
    # ident with nickserv
    if [[ -n "$NICKSERV" ]]; then
        # bypass logged send_cmd/send_msg
        printf '%s\r\n' "NICKSERV IDENTIFY $NICKSERV" >&3
    fi
}

# logger function that outputs to stdout
# checks log level to determine 
#
# if applicable to be written
# $1 - log level of message
# $2 - the message
send_log() {
    declare -i log_lvl
    case $1 in
        STDOUT)
            # shellcheck disable=2183
            [[ -n "$LOG_STDOUT" ]] &&
                printf '%(%Y-%m-%d %H:%M:%S%z)T %s\n' '-1' "${2//[$'\n'$'\r']/}"
            return
        ;;
        WARNING) log_lvl=3 ;;
        INFO)    log_lvl=2 ;;
        DEBUG)   log_lvl=1 ;;
        *)       log_lvl=4 ;;
    esac

    (( log_lvl >= LOG_LEVEL )) &&
        printf "$LOG_TSTAMP_FORMAT"'*** %s *** %s\n' $LOG_TSTAMP_ARG1 "$1" "$2"
}

# Send arguments to irc server.
# Most servers don't allow for string longer than 510+2 bytes
#
# $* - multiple strings to be sent.
send_msg() {
    printf '%s\r\n' "$*" >&3
    send_log "DEBUG" "SENT -> $*"
}

# function which converts sic/ircii-like
# commands to IRC messages.
# must be piped or heredoc; no arguments
#
# <STDIN> - valid bash-ircbot command string
# SEE     - README.md
send_cmd() {
    while read -r cmd arg other; do
        case $cmd in
            :j|:join)
                send_msg "JOIN $arg"
            ;;
            :jd|:delay-join)
                sleep "$arg"
                send_msg "JOIN $other"
            ;;
            :l|:leave)
                send_msg "PART $arg :$other"
            ;;
            :m|:message)
                send_msg "PRIVMSG $arg :$other"
            ;;
            :md|:delay-message)
                sleep "$arg"
                send_msg "PRIVMSG ${other% *} :${other#* }"
            ;;
            :mn|:notice)
                send_msg "NOTICE $arg :$other"
            ;;
            :nd|:delay-notice)
                sleep "$arg"
                send_msg "NOTICE ${other% *} :${other#* }"
            ;;
            :c|:ctcp)
                send_msg "PRIVMSG $arg :"$'\001'"$other"$'\001'
            ;;
            :n|:nick)
                send_msg "NICK $arg"
            ;;
            :q|:quit)
                send_msg "QUIT :$arg $other"
            ;;
            :r|:raw)
                send_msg "$arg $other"
            ;;
            :le|:loge)
                send_log "ERROR" "$arg $other"
            ;;
            :lw|:logw)
                send_log "WARNING" "$arg $other"
            ;;
            :li|:log)
                send_log "INFO" "$arg $other"
            ;;
            :ld|:logd)
                send_log "DEBUG" "$arg $other"
            ;;
            *)
                send_log "ERROR" "Invalid command: ($cmd) args: ($arg $other)"
            ;;
        esac
    done
}

# Match a string to the list of configured regexps to check
# $1       - string to try and match
# @return  - regex command that should be ran
# @exit    - zero for match, nonzero for no match
# @mutates - REPLY with matching regexp
check_regexp() {
    local regex

    for regex in "${!REGEX[@]}"; do
        if [[ "$1" =~ $regex ]]; then
            [[ -x "$LIB_PATH/${REGEX["$regex"]}" ]] || return 1
            REPLY="$regex"
            return 0
        fi
    done

    return 1
}

# stripped down version of privmsg checker
# determines if message qualifies for spam
# filtering
#
# $1 - username
check_spam() {
    [[ -z "$ANTISPAM" ]] && return 0
    # increment if command or hl event
    declare -i temp ttime
    temp="${antispam_list[$1]% *}"
    ttime="${antispam_list[$1]#* }"
    (( temp <= ${ANTISPAM_COUNT:-3} )) &&
        temp+=1

    declare -i counter current
    # shellcheck disable=SC2034
    current='SECONDS'

    (( ttime == 0 )) &&
        ttime='current'
    counter="( current - ttime ) / ${ANTISPAM_TIMEOUT:-10}"
    if (( counter > 0 )); then
        ttime='current'
        temp='temp - counter'
        (( temp < 0 )) &&
            temp=0
    fi

    antispam_list[$1]="$temp $ttime"

    if (( temp <= ${ANTISPAM_COUNT:-3} )); then
        return 0
    else
        send_log "DEBUG" "SPAMMER -> $1"
        return 1
    fi
}

# check if nick is in ignore list
#
# $1 - nick to check
# $2 - whole message to filter bots ?
check_ignore() {
    if [[ -n "${ignore_hash[$1]}" ]]; then
        send_log "DEBUG" "IGNORED -> $1"
        return 1
    fi
}

# check if nick is a "trusted gateway" as in a a nick 
# which is used by multiple individuals. 
# this checks a configurable list of nicks. 
#
# if the nick is not a trusted gateway, this function returns without
# doing anything
#
# Note that this function mutates message
# inputs such as user and message.
# gateway is assumed to prepend a nickname to the message
# like <the_gateway> <user1> msg
# if your gateway does not do this, please make an issue on github
# $1 - the nickname
irc_special_format=$'\x02\x03\x04\x0f\x11\x16\x1d\x1e\x1f'
trusted_gateway() {
    local trusted
    for nick in "${GATEWAY[@]}"; do
        if [[ "$1" == "$nick" ]]; then
            trusted=1
            break;
        fi
    done
    [[ -z "$trusted" ]] && return 1

    # is a gateway user
    # this a mutation
    newuser="${message%% *}"
    newmsg="${message#* }"
    # new msg without the gateway username
    # remove format reset some gateways add
    message="${newmsg#["$irc_special_format"]}"
    # delete any brackets and some special chars
    user=${newuser//[<>"$irc_special_format"]/}
    # delete mIRC color prepended numbers if applicable
    [[ "$user" =~ ^[0-9,]*(.*)$ ]] &&
        user="${BASH_REMATCH[1]}"

    # some plugins like vote use hostname instead of username
    # this tries to a create a new vhost, though
    # vhosts like these could be technically made
    host="${user}.trusted-gateway.${host}"
}

#######################
# Bot Message Handler #
#######################

# TODO: note addition of usermode when available
# handle PRIVMSGs and NOTICEs and
# determine if the bot needs to react to message
# $1: channel - the channel the string came from
# $2: vhost   - the vhost of the user
# $3: user    - the nickname of the user
# $4: msg     - message minus command
# $5: cmd     - command name
# $6: full    - full message
handle_privmsg() {
    # private message to us
    # 5th argument is the command name
    if [[ "$NICK" == "$1" ]]; then
        check_spam "$user" || return
        # most servers require this "in spirit"
        # tell them what we are
        if [[ "$6" = $'\001VERSION\001' ]]; then
            send_log "DEBUG" "CTCP VERSION -> $3 <$3>"
            send_msg "NOTICE $3 :"$'\001'"VERSION $VERSION"$'\001'
            return
        fi

        local cmd="$5"
        # if invalid command
        if [[ -z "${COMMANDS[$cmd]}" ]]; then
            echo1 ":m $3 --- Invalid Command ---"
            # basically your "help" command
            cmd="${PRIVMSG_DEFAULT_CMD:-help}"
        fi
        [[ -x "$LIB_PATH/${COMMANDS[$cmd]}" ]] || return
        send_log "DEBUG" "PRIVATE COMMAND EVENT -> $cmd: $3 <$3> $4"
        "$LIB_PATH/${COMMANDS[$cmd]}" \
            "$3" "$2" "$3" "$4" "$cmd" \
        | send_cmd &
        return
    fi

    # highlight event in message
    if [[ "$5" = ?(@)$NICK?(:|,) ]]; then
        check_spam "$user" || return
        # shellcheck disable=SC2153
        [[ -x "$LIB_PATH/$HIGHLIGHT" ]] || return
        send_log "DEBUG" "HIGHLIGHT EVENT -> $1 <$3>  $4"
        "$LIB_PATH/$HIGHLIGHT" \
            "$1" "$2" "$3" "$4" "$5" \
        | send_cmd &
        return
    fi

    # 5th argument is the command string that matched
    # may be useful for scripts that are linked
    # to multiple commands, allowing for different behavior
    # by command name
    case "${5:0:1}" in ["$CMD_PREFIX"])
        cmd="${5:1}"
        [[ -n "${COMMANDS[$cmd]}" &&
            -x "$LIB_PATH/${COMMANDS[$cmd]}" ]] || return
        check_spam "$user" || return
        send_log "DEBUG" "COMMAND EVENT -> $cmd: $1 <$3> $4"
        "$LIB_PATH/${COMMANDS[$cmd]}" \
            "$1" "$2" "$3" "$4" "$cmd" \
        | send_cmd &
        return
    esac

    # regexp check.
    if check_regexp "$6"; then
        check_spam "$user" || return
        local regex="$REPLY"
        send_log "DEBUG" "REGEX EVENT -> $regex: $1 <$3> $6 (${BASH_REMATCH[0]})"
        "$LIB_PATH/${REGEX["$regex"]}" \
            "$1" "$2" "$3" "$6" \
            "$regex" \
            "${BASH_REMATCH[0]}" \
        | send_cmd &
        return
    fi
}

#######################
# start communication #
#######################

[[ -z "$TIMEOUT_CHECK" ]] &&
    TIMEOUT_CHECK=300
# keeps the connection active.
# don't bother if we are in testing mode.
if [[ -z "$MOCK_CONN_TEST" ]]; then
    while sleep "$(( TIMEOUT_CHECK / 2 ))"; do
        send_msg "PING :$NICK"
    done &
    ping_child="$!"
fi

send_log "DEBUG" "COMMUNICATION START"
# pass if server is private
# this is likely not required
if [[ -n "$PASS" ]]; then
    send_msg "PASS $PASS"
elif [[ -n "$SASL_PASS" ]]; then
    send_msg "CAP REQ :sasl"
fi
# "Ident" information
send_msg "NICK $NICK"
send_msg "USER $NICK +i * :$NICK"
# IRC event loop
# note if the irc sends lines longer than
# 1024 bytes, it may fail to parse
while read -u 4 -r -n 1024 -t "$TIMEOUT_CHECK"; do
    # check for high level commands from the ircd
    case "$REPLY" in
        PING*) # have to reply
            send_msg "PONG ${REPLY#PING *}"
            continue
        ;;
        ERROR*) # banned?
            send_log "CRITICAL" "${REPLY#:}"
            break
        ;;
        AUTHENTICATE*) # SASL Auth
            # If your base64 encoded password is longer than
            # 400byes, I got bad news for you.
            send_msg "AUTHENTICATE $(
                printf '\0%s\0%s' \
                    "$NICK" "$SASL_PASS" \
                | base64 -w 0
            )"
        ;;
    esac

    parse_irc "$REPLY"

    # check if gateway nick
    trusted_gateway "$user"

    # other helpful variable
    ucmd="${message%% *}"
    umsg="${message#"$ucmd"}"
    # in case $ucmd is the only string in the message.
    # otherwise remove this argument
    umsg="${umsg# }"
    # the user who was kicked in a KICK command
    ukick="${message% :*}"
    # log message
    send_log "STDOUT" "$channel $command <$user> $message"

    # handle commands here
    case $command in
        # any channel message
        PRIVMSG)
            check_ignore "$user" || continue
            handle_privmsg \
                "$channel" \
                "$host" \
                "$user" \
                "$umsg" \
                "$ucmd" \
                "$message"
        ;;
        # bot ignores notices
        #NOTICE)
        #;;
        # bot was invited to channel
        # so join channel
        INVITE)
            [[ -n "$DISABLE_INVITES" ]] && continue
            # protect from potential bad index access
            [[ -z "$message" ]] && continue
            send_cmd <<< ":jd ${INVITE_DELAY:-2} $message"
            send_log "INVITE" "<$user> $message "
            if [[ -n "$INVITE_FILE" &&
                  "${invites[$message]}" != 1 ]]
            then
                echo1 "$message" >> "$INVITE_FILE"
                invites[$message]=1
            fi
        ;;
        # when the bot joins a channel
        JOIN)
            if [[ "$user" = "$NICK" ]]; then
                channel="${channel:1}"
                channel="${channel%$'\r'}"
                # channel joined add to list or channels
                CHANNELS+=("$channel")
                send_log "JOIN" "$channel"
            fi
        ;;
        # when the bot leaves a channel
        PART)
            # protect from potential bad index access
            [[ -z "$channel" ]] && continue
            if [[ "$user" = "$NICK" ]]; then
                for i in "${!CHANNELS[@]}"; do
                    if [[ "${CHANNELS[$i]}" = "$channel" ]]; then
                        unset CHANNELS["$i"]
                        if [[ -n "${invites[$channel]}" ]]; then
                            unset invites["$channel"]
                            printf '%s\n' "${!invites[@]}" \
                                > "$INVITE_FILE"
                        fi
                    fi
                done
                send_log "PART" "$channel"
            fi
        ;;
        # only way for the bot to be removed
        # from a channel, other than config reload
        KICK)
            # protect from potential bad index access
            [[ -z "$channel" ]] && continue
            if [[ "$ukick" = "$NICK" ]]; then
                for i in "${!CHANNELS[@]}"; do
                    if [[ "${CHANNELS[$i]}" = "$channel" ]]; then
                        unset CHANNELS["$i"]
                        if [[ -n "${invites[$channel]}" ]]; then
                            unset invites["$channel"]
                            printf '%s\n' "${!invites[@]}" \
                                > "$INVITE_FILE"
                        fi
                    fi
                done
                send_log "KICK" "<$user> $channel [Reason: ${message#*:}]"
            fi
        ;;
        NICK)
            if [[ "$user" = "$NICK" ]]; then
                channel="${channel:1}"
                [[ -z "$orig_nick" ]] && orig_nick="$NICK"
                NICK="${channel%$'\r'}"
                send_log "NICK" "NICK CHANGED TO $NICK"
            fi
        ;;
        # Server confirms we are "identified"
        # we are ready to join channels and start
        004)
            # this should only happen once?
            post_ident
            send_log "DEBUG" "POST-IDENT PHASE, BOT READY"
        ;;
        # PASS command failed
        464)
            send_log 'CRITICAL' 'INVALID PASSWORD'
            break
        ;;
        465)
            send_log 'CRITICAL' 'YOU ARE BANNED'
            break
        ;;
        # Nickname is already in use
        # add crap and try the new nick
        433|432)
            [[ -z "$orig_nick" ]] && orig_nick="$NICK"
            NICK="${NICK}_"
            case "$NICK" in
                # attempted to change nick 4 times
                "${orig_nick}"____)
                    send_log 'CRITICAL' 'FAILED TO CHANGE NICK THREE TIMES'
                    break
                ;;
            esac
            send_msg "NICK $NICK"
            send_log "NICK" "NICK CHANGED TO $NICK"
        ;;
        # SASL specific
        CAP)
            if [[ "$message" == 'ACK :sasl' ]]; then
                send_msg 'AUTHENTICATE PLAIN'
            fi
        ;;
        # SASL status commands
        903)
            send_msg "CAP END"
        ;;
        902|904|905|906)
            send_msg "CAP END"
            send_log 'CRITICAL' "$message"
            break
        ;;
        PONG)
            send_log 'DEBUG' 'RECV -> PONG'
        ;;
        # not an official command, this is for getting
        # key stateful variable from the bot for mock testing
        __DEBUG)
            # disable this if not in mock testing mode
            [[ -z "$MOCK_CONN_TEST" ]] && continue
            case $message in
                channels)  echo1 "${CHANNELS[*]}" >&3 ;;
                nickname)  echo1 "$NICK"    >&3 ;;
                nickparse) echo1 "$user"    >&3 ;;
                hostparse) echo1 "$host"    >&3 ;;
                chanparse) echo1 "$channel" >&3 ;;
                msgparse)  echo1 "$message" >&3 ;;
                *)         echo1 "$message" >&3 ;;
            esac
        ;;
    esac
done
send_msg "QUIT :bye"
send_log 'CRITICAL' 'Exited Event loop; timed out or disconnected.'
exit_failure

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

for arg; do
    case "$arg" in
        --nick=*)    nick="${arg#*=}" ;;
        --message=*) q="${arg#*=}" ;;
        --command=*) command="${arg#*=}" ;;
    esac
done

declare -i COUNT
COUNT=1

# parse args
while [[ -n "$q" ]]; do
    key="${q%% *}"

    case "$key" in
        -c|--count)
            LAST='c'
        ;;
        --count=*)
            [[ "${key#*=}" =~ ^[1-3]$ ]] &&
                COUNT="${key#*=}"
        ;;
        -d|--definition)
            LAST='d'
        ;;
        --definition=*)
            [[ "${key#*=}" =~ ^(1[0-9]|[1-9])$ ]] &&
                DEFINITION="${key#*=}"
        ;;
        -h|--help)
            echo ":r usage: $command [--count=#-to-ret|--definition=#] query"
            echo ":r find a defintion for a word using the urban dictionary."
            exit 0
        ;;
        '') ;;
        *)
            [ -z "$LAST" ] && break
            if [ "$LAST" = 'd' ]; then
                declare -i DEFINITION
                [[ "$key" =~ ^(1[0-9]|[1-9])$ ]] &&
                    DEFINITION="$key"
            else
                [[ "$key" =~ ^[1-3]$ ]] &&
                    COUNT="$key"
            fi
            LAST=
        ;;
    esac

    if [[ "${q#"$key" }" == "$q" ]]; then
        q=
    else
        q="${q#"$key" }"
    fi
done

if [[ -z "$q" ]]; then
    echo ":mn $nick This command requires a search query"
    exit 0
fi

# kept for advert
URBAN="http://www.urbandictionary.com/define.php?term=$(URI_ENCODE "$q")"
NEW_URBAN="http://api.urbandictionary.com/v0/define?term=$(URI_ENCODE "$q")"

# jq 1.5 (still common) has broken sub and gsub commands.
{
    curl \
        --silent \
        --fail \
        --location \
        "$NEW_URBAN" \
    || echo null
} | sed 's/\\[rn]\(\\[rn]\)*/ /g' \
    | jq \
       --arg COUNT "$COUNT" \
       --arg DEFNUM "$DEFINITION" \
       --arg WORD "$q" \
       -r '

    .list | length as $sizeof
    | if ($DEFNUM != "") then
        if (.[($DEFNUM | tonumber) - 1]) then
            [.[($DEFNUM | tonumber) - 1]]
        else
            [{ definition: "No Definition Found." }]
        end
    else
        if (.[0]) then
            .[0:($COUNT | tonumber)]
        else
            [{ definition: "No Definition Found." }]
        end
    end
    | to_entries
    | .[]
    | if ($DEFNUM != "") then
        .key = ($DEFNUM | tonumber) - 1
      else
        .
    end
    | ":r \u0002\($WORD)\u0002 " +
      "[\(.key + 1)/\($sizeof)] " +
      ":: \(.value.definition[0:400])"
'

printf '%s\n' ":mn $nick See More: $URBAN"

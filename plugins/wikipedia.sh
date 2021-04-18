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

# parse args
while [[ -n "$q" ]]; do
    key="${q%% *}"

    case "$key" in
        -h|--help)
            echo ":m $1 usage: $command query"
            echo ":m $1 find a wikipedia article."
            exit 0
        ;;
        '') ;;
        *)
            break
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

WIKI='https://en.wikipedia.org/api/rest_v1/page/summary/'"$(URI_ENCODE "$q")"

{
    curl --silent \
        --max-redirs 3 \
        --location \
        --fail "$WIKI" \
    || echo null
} | jq -r '
    if (. != null and .type != "disambiguation") then
        ":r \u0002\(.title)\u0002 :: \(.content_urls.desktop.page) :: " + 
        ( .extract[0:350] | gsub("\n"; " "))
    elif (. != null) then
        ":r \u0002\(.title)\u0002 :: \(.content_urls.desktop.page) :: " +
        "\u0002Ambiguous\u0002 \(.extract[0:339] | gsub("\n"; " "))"
    else
        ":r No Results."
    end
'

#!/usr/bin/bash
# Copyright 2020 Anthony DeDominic <adedomin@gmail.com>
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

args=()
for arg; do
    case "$arg" in
        --message=*)
            m="${arg#*=}"
            if [[ -n "$m" ]]; then
                args+=("--message=$m site:https://developer.mozilla.org/en-US")
            else
                args+=('')
            fi
        ;;
        *) args+=("$arg") ;;
    esac
done

if [[ -z "$PLUGIN_PATH" ]]; then
    echo ':loge mdn.sh: PLUGIN_PATH is unset'
    echo ':r Configuration Error.'
else
    "${PLUGIN_PATH}/duckduckgo.py" "${args[@]}"
fi

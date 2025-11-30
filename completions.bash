#!/usr/bin/env bash

_k8s_image_auditor_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # The flags our tool accepts
    opts="-a -p -r -o -s -h"

    case "${prev}" in
        -a)
            # Architecture suggestions
            local archs="amd64 arm64 arm v7 v8 ppc64le s390x"
            COMPREPLY=( $(compgen -W "${archs}" -- ${cur}) )
            return 0
            ;;
        -p)
            # AWS Profile suggestions: Scans ~/.aws/credentials for [profile names]
            if [[ -f ~/.aws/credentials ]]; then
                 # Extract names inside brackets [], remove brackets
                 local profiles=$(grep -oE '^\[([a-zA-Z0-9_-]+)\]' ~/.aws/credentials | tr -d '[]')
                 COMPREPLY=( $(compgen -W "${profiles}" -- ${cur}) )
            fi
            return 0
            ;;
        -r)
             # Common AWS regions
             local regions="us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 eu-central-1 eu-west-1 eu-west-2"
             COMPREPLY=( $(compgen -W "${regions}" -- ${cur}) )
             return 0
             ;;
        -o)
            # Standard file completion for output
            COMPREPLY=( $(compgen -f -- ${cur}) )
            return 0
            ;;
        *)
            ;;
    esac

    # If the user is typing a flag (starts with -), suggest the opts
    if [[ ${cur} == -* ]]; then
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi
}

# Register the function for our command
complete -F _k8s_image_auditor_completions k8s-image-auditor